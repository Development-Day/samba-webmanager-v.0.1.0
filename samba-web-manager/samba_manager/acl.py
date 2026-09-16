#!/usr/bin/env python3
"""
Модуль управления ACL (Access Control Lists) для Samba
Работает с правами доступа на уровне файловой системы
"""

import os
import subprocess
import pwd
import grp
from typing import List, Dict, Optional, Tuple


class ACLManager:
    """Управление правами доступа к папкам Samba"""
    
    def __init__(self):
        # Проверяем, поддерживается ли ACL в системе
        self.acl_supported = self._check_acl_support()
    
    def _check_acl_support(self) -> bool:
        """Проверить, поддерживается ли ACL"""
        try:
            result = subprocess.run(
                ['which', 'setfacl'],
                capture_output=True, text=True
            )
            return result.returncode == 0
        except:
            return False
    
    def get_acl(self, path: str) -> Dict:
        """
        Получить ACL для папки или файла
        
        Returns:
            {
                'path': '/srv/samba/public',
                'owner': 'samba-user',
                'group': 'users',
                'permissions': 'drwxrwxr-x',
                'acl_entries': [
                    {'type': 'user', 'name': 'john', 'perms': 'rwx'},
                    {'type': 'group', 'name': 'admins', 'perms': 'rwx'},
                    ...
                ]
            }
        """
        if not os.path.exists(path):
            raise FileNotFoundError(f'Путь {path} не существует')
        
        # Базовая информация
        stat_info = os.stat(path)
        owner = pwd.getpwuid(stat_info.st_uid).pw_name
        group = grp.getgrgid(stat_info.st_gid).gr_name
        
        result = {
            'path': path,
            'owner': owner,
            'group': group,
            'permissions': oct(stat_info.st_mode)[-4:],
            'acl_entries': []
        }
        
        # Получаем ACL если поддерживается
        if self.acl_supported:
            try:
                acl_result = subprocess.run(
                    ['getfacl', '-p', path],
                    capture_output=True, text=True, check=True
                )
                
                for line in acl_result.stdout.split('\n'):
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    
                    # Парсим строки вида: user:john:rwx
                    if ':' in line and not line.startswith('user::') and not line.startswith('group::'):
                        parts = line.split(':')
                        if len(parts) >= 3:
                            entry_type = parts[0]
                            entry_name = parts[1]
                            perms = parts[2]
                            
                            if entry_type in ['user', 'group'] and entry_name:
                                result['acl_entries'].append({
                                    'type': entry_type,
                                    'name': entry_name,
                                    'perms': perms
                                })
            except Exception as e:
                result['acl_error'] = str(e)
        
        return result
    
    def set_acl(self, path: str, entries: List[Dict], recursive: bool = False) -> bool:
        """
        Установить ACL для папки
        
        Args:
            path: путь к папке
            entries: список записей ACL
            recursive: применить рекурсивно
        """
        if not self.acl_supported:
            raise Exception('ACL не поддерживается. Установите: sudo apt install acl')
        
        if not os.path.exists(path):
            raise FileNotFoundError(f'Путь {path} не существует')
        
        try:
            # Формируем команду setfacl
            cmd = ['sudo', 'setfacl']
            if recursive:
                cmd.append('-R')
            cmd.append('-m')
            
            # Формируем строку с ACL
            acl_parts = []
            for entry in entries:
                entry_type = entry.get('type')
                name = entry.get('name', '')
                perms = entry.get('perms', '')
                
                if entry_type == 'user' and name:
                    acl_parts.append(f'u:{name}:{perms}')
                elif entry_type == 'group' and name:
                    acl_parts.append(f'g:{name}:{perms}')
                elif entry_type == 'other':
                    acl_parts.append(f'o:{perms}')
                elif entry_type == 'mask':
                    acl_parts.append(f'm:{perms}')
                elif entry_type == 'default':
                    acl_parts.append(f'd:{entry.get("default_type", "u")}:{name}:{perms}')
            
            if not acl_parts:
                return False
            
            cmd.append(','.join(acl_parts))
            cmd.append(path)
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                raise Exception(result.stderr)
            
            return True
        except Exception as e:
            print(f'Ошибка установки ACL: {e}')
            return False
    
    def remove_acl(self, path: str, name: str, entry_type: str = 'user') -> bool:
        """Удалить ACL запись"""
        if not self.acl_supported:
            return False
        
        try:
            cmd = ['sudo', 'setfacl', '-x', f'{entry_type}:{name}', path]
            result = subprocess.run(cmd, capture_output=True, text=True)
            return result.returncode == 0
        except:
            return False
    
    def set_owner(self, path: str, owner: str, group: str = None, recursive: bool = False) -> bool:
        """Сменить владельца папки"""
        try:
            cmd = ['sudo', 'chown']
            if recursive:
                cmd.append('-R')
            if group:
                cmd.append(f'{owner}:{group}')
            else:
                cmd.append(owner)
            cmd.append(path)
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            return result.returncode == 0
        except:
            return False
    
    def set_permissions(self, path: str, perms: str, recursive: bool = False) -> bool:
        """Установить базовые права доступа"""
        try:
            cmd = ['sudo', 'chmod']
            if recursive:
                cmd.append('-R')
            cmd.append(perms)
            cmd.append(path)
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            return result.returncode == 0
        except:
            return False
    
    def get_samba_acl(self, share_name: str) -> Dict:
        """
        Получить ACL для конкретной Samba-шары
        (парсит smb.conf и возвращает настройки доступа)
        """
        import configparser
        
        config = configparser.ConfigParser()
        config.read('/etc/samba/smb.conf')
        
        if not config.has_section(share_name):
            raise ValueError(f'Шара {share_name} не найдена')
        
        share = {
            'name': share_name,
            'path': config.get(share_name, 'path', fallback=''),
            'valid_users': config.get(share_name, 'valid users', fallback=''),
            'invalid_users': config.get(share_name, 'invalid users', fallback=''),
            'read_list': config.get(share_name, 'read list', fallback=''),
            'write_list': config.get(share_name, 'write list', fallback=''),
            'admin_users': config.get(share_name, 'admin users', fallback=''),
            'create_mask': config.get(share_name, 'create mask', fallback='0755'),
            'directory_mask': config.get(share_name, 'directory mask', fallback='0755'),
            'force_user': config.get(share_name, 'force user', fallback=''),
            'force_group': config.get(share_name, 'force group', fallback=''),
        }
        
        # Добавляем информацию файловой системы
        if share['path'] and os.path.exists(share['path']):
            try:
                share['fs_acl'] = self.get_acl(share['path'])
            except:
                pass
        
        return share
    
    def set_samba_acl(self, share_name: str, acl_data: Dict) -> bool:
        """
        Установить ACL для Samba-шары
        Изменяет параметры в smb.conf
        """
        import configparser
        
        config = configparser.ConfigParser()
        config.read('/etc/samba/smb.conf')
        
        if not config.has_section(share_name):
            raise ValueError(f'Шара {share_name} не найдена')
        
        # Обновляем параметры
        mapping = {
            'valid_users': 'valid users',
            'invalid_users': 'invalid users',
            'read_list': 'read list',
            'write_list': 'write list',
            'admin_users': 'admin users',
            'create_mask': 'create mask',
            'directory_mask': 'directory mask',
            'force_user': 'force user',
            'force_group': 'force group',
        }
        
        for key, config_key in mapping.items():
            if key in acl_data:
                value = acl_data[key]
                if value:
                    config.set(share_name, config_key, value)
                else:
                    # Удаляем параметр если пустое значение
                    if config.has_option(share_name, config_key):
                        config.remove_option(share_name, config_key)
        
        # Сохраняем
        with open('/etc/samba/smb.conf', 'w') as f:
            config.write(f)
        
        return True
    
    def apply_share_permissions(self, share_name: str) -> Dict:
        """
        Применить права файловой системы к папке шары
        с учетом настроек из smb.conf
        """
        share = self.get_samba_acl(share_name)
        result = {
            'share': share_name,
            'path': share['path'],
            'applied': False,
            'errors': []
        }
        
        if not share['path'] or not os.path.exists(share['path']):
            result['errors'].append('Путь не существует')
            return result
        
        try:
            # Устанавливаем владельца
            if share['force_user']:
                group = share['force_group'] if share['force_group'] else 'users'
                self.set_owner(share['path'], share['force_user'], group, recursive=True)
            
            # Устанавливаем маску создания
            if share['create_mask']:
                self.set_permissions(share['path'], share['create_mask'], recursive=True)
            
            # Устанавливаем ACL для valid users
            if share['valid_users']:
                users = [u.strip() for u in share['valid_users'].split(',') if u.strip()]
                entries = []
                for user in users:
                    perms = 'rwx'
                    # Проверяем, есть ли пользователь в read_list
                    if share['read_list'] and user in share['read_list']:
                        perms = 'r-x'
                    entries.append({
                        'type': 'user',
                        'name': user,
                        'perms': perms
                    })
                
                if entries:
                    self.set_acl(share['path'], entries, recursive=True)
            
            result['applied'] = True
        except Exception as e:
            result['errors'].append(str(e))
        
        return result


# ============ API для веб-интерфейса ============

class ACLAPI:
    """API для работы с ACL в веб-интерфейсе"""
    
    def __init__(self):
        self.manager = ACLManager()
    
    def get_share_acl(self, share_name: str) -> Dict:
        """Получить ACL шары"""
        try:
            return {
                'success': True,
                'data': self.manager.get_samba_acl(share_name)
            }
        except Exception as e:
            return {'success': False, 'error': str(e)}
    
    def update_share_acl(self, share_name: str, data: Dict) -> Dict:
        """Обновить ACL шары"""
        try:
            self.manager.set_samba_acl(share_name, data)
            return {
                'success': True,
                'message': f'ACL для {share_name} обновлен'
            }
        except Exception as e:
            return {'success': False, 'error': str(e)}
    
    def get_path_acl(self, path: str) -> Dict:
        """Получить ACL файлового пути"""
        try:
            return {
                'success': True,
                'data': self.manager.get_acl(path)
            }
        except Exception as e:
            return {'success': False, 'error': str(e)}
    
    def set_path_acl(self, path: str, entries: List[Dict], recursive: bool = False) -> Dict:
        """Установить ACL для пути"""
        try:
            self.manager.set_acl(path, entries, recursive)
            return {
                'success': True,
                'message': f'ACL для {path} установлен'
            }
        except Exception as e:
            return {'success': False, 'error': str(e)}