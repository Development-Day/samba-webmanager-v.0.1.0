#!/usr/bin/env python3
"""
Модуль парсинга и записи smb.conf
ИСПРАВЛЕНО: правильная запись секций, сохранение форматирования
"""

import os
import re
import configparser
from typing import List, Dict


class SambaConfig:
    """Расширенный класс для работы с smb.conf"""
    
    def __init__(self, config_path='/etc/samba/smb.conf'):
        self.config_path = config_path
        self.config = configparser.ConfigParser()
        if os.path.exists(config_path):
            self.config.read(config_path)
    
    def get_shares(self) -> List[Dict]:
        """Получить все общие папки"""
        shares = []
        for section in self.config.sections():
            if section not in ['global', 'printers', 'print$']:
                share = {
                    'name': section,
                    'path': self._get(section, 'path', ''),
                    'read_only': self._get_bool(section, 'read only', True),
                    'guest_ok': self._get_bool(section, 'guest ok', False),
                    'browseable': self._get_bool(section, 'browseable', True),
                    'valid_users': self._get(section, 'valid users', ''),
                    'invalid_users': self._get(section, 'invalid users', ''),
                    'comment': self._get(section, 'comment', ''),
                    'create_mask': self._get(section, 'create mask', '0755'),
                    'directory_mask': self._get(section, 'directory mask', '0755')
                }
                shares.append(share)
        return shares
    
    def add_share(self, name: str, path: str, **kwargs):
        """
        Добавить новую шару
        ИСПРАВЛЕНО: пишет корректно, с отступами, в конец файла
        """
        # Валидация имени
        name = name.strip()
        if not re.match(r'^[a-zA-Z0-9_\-.]+$', name):
            raise ValueError(f'Недопустимое имя шары: {name}')
        
        # Проверка пути
        if not os.path.exists(path):
            raise FileNotFoundError(f'Папка {path} не существует')
        
        # Проверка существования секции
        if self.config.has_section(name):
            raise ValueError(f'Шара {name} уже существует')
        
        # Читаем текущий файл
        with open(self.config_path, 'r') as f:
            content = f.read()
        
        # Формируем новую секцию
        read_only = 'yes' if kwargs.get('read_only', True) else 'no'
        guest_ok = 'yes' if kwargs.get('guest_ok', False) else 'no'
        
        section = f"\n[{name}]\n"
        section += f"   path = {path}\n"
        section += f"   read only = {read_only}\n"
        section += f"   guest ok = {guest_ok}\n"
        section += f"   browseable = yes\n"
        
        if kwargs.get('valid_users'):
            section += f"   valid users = {kwargs['valid_users']}\n"
        if kwargs.get('comment'):
            section += f"   comment = {kwargs['comment']}\n"
        if kwargs.get('create_mask'):
            section += f"   create mask = {kwargs['create_mask']}\n"
        if kwargs.get('directory_mask'):
            section += f"   directory mask = {kwargs['directory_mask']}\n"
        
        # Дописываем в конец файла
        with open(self.config_path, 'a') as f:
            f.write(section)
        
        # Перечитываем конфиг
        self.config.read(self.config_path)
        
        # Проверяем, что записалось
        if not self.config.has_section(name):
            raise Exception(f'Не удалось записать секцию [{name}] в {self.config_path}')
    
    def update_share(self, name: str, data: Dict):
        """Обновить параметры шары"""
        if not self.config.has_section(name):
            raise ValueError(f'Шара {name} не найдена')
        
        for key, value in data.items():
            if key in ['name', 'path']:
                continue
            if isinstance(value, bool):
                self.config.set(name, key, 'yes' if value else 'no')
            elif value:
                self.config.set(name, key, str(value))
            else:
                if self.config.has_option(name, key):
                    self.config.remove_option(name, key)
        
        self._save()
    
    def delete_share(self, name: str):
        """
        Удалить шару
        ИСПРАВЛЕНО: корректное удаление секции с сохранением остальных
        """
        if not self.config.has_section(name):
            raise ValueError(f'Шара {name} не найдена')
        
        # Удаляем из configparser
        self.config.remove_section(name)
        
        # Перезаписываем файл (но сохраняем комментарии и форматирование)
        with open(self.config_path, 'r') as f:
            lines = f.readlines()
        
        new_lines = []
        in_section = False
        
        for line in lines:
            stripped = line.strip()
            
            # Начало другой секции
            if stripped.startswith('[') and stripped.endswith(']'):
                section_name = stripped[1:-1]
                if section_name == name:
                    in_section = True
                    continue
                else:
                    in_section = False
            
            if not in_section:
                new_lines.append(line)
        
        with open(self.config_path, 'w') as f:
            f.writelines(new_lines)
        
        # Перечитываем
        self.config.read(self.config_path)
    
    def _get(self, section, key, default=''):
        try:
            return self.config.get(section, key)
        except:
            return default
    
    def _get_bool(self, section, key, default=False):
        try:
            return self.config.getboolean(section, key)
        except:
            return default
    
    def _save(self):
        """Сохранить конфигурацию"""
        with open(self.config_path, 'w') as f:
            self.config.write(f)
    
    def reload(self):
        """Перечитать конфиг"""
        self.config = configparser.ConfigParser()
        self.config.read(self.config_path)
