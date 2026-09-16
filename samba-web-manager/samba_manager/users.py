#!/usr/bin/env python3
"""
Модуль управления пользователями Samba
ИСПРАВЛЕНО: универсальная обработка str/bytes в _run
"""

import subprocess
import os
import pwd
from typing import List, Dict, Union


def _run(cmd: list, input_data: Union[str, bytes, None] = None) -> tuple:
    """
    Вспомогательная функция запуска команд
    ИСПРАВЛЕНО: принимает и str, и bytes без ошибок
    """
    # Нормализуем input_data в bytes
    if input_data is None:
        input_bytes = None
    elif isinstance(input_data, bytes):
        input_bytes = input_data
    else:
        input_bytes = str(input_data).encode('utf-8')
    
    try:
        result = subprocess.run(
            cmd,
            input=input_bytes,
            capture_output=True,
            text=False,
            timeout=30
        )
        
        # Декодируем stdout/stderr с игнорированием ошибок
        stdout = result.stdout.decode('utf-8', errors='replace') if result.stdout else ''
        stderr = result.stderr.decode('utf-8', errors='replace') if result.stderr else ''
        
        return result.returncode, stdout, stderr
        
    except subprocess.TimeoutExpired:
        return -1, '', 'Timeout'
    except Exception as e:
        return -1, '', str(e)


def get_samba_users() -> List[Dict]:
    """Получить список пользователей Samba через pdbedit"""
    code, stdout, stderr = _run(['sudo', '-n', 'pdbedit', '-L'])
    
    if code != 0:
        code, stdout, stderr = _run(['pdbedit', '-L'])
    
    users = []
    if code == 0:
        for line in stdout.strip().split('\n'):
            if line and ':' in line:
                parts = line.split(':')
                if len(parts) >= 2:
                    users.append({
                        'username': parts[0],
                        'uid': parts[1] if len(parts) > 1 else '',
                        'nt_username': parts[2] if len(parts) > 2 else '',
                        'full_name': parts[3] if len(parts) > 3 else ''
                    })
    return users


def system_user_exists(username: str) -> bool:
    """Проверить существование системного пользователя"""
    try:
        pwd.getpwnam(username)
        return True
    except KeyError:
        return False


def add_user(username: str, password: str) -> bool:
    """
    Добавить пользователя Samba
    ИСПРАВЛЕНО: корректная передача пароля в smbpasswd
    """
    username = username.strip()
    
    if not username or not password:
        raise ValueError("Имя и пароль обязательны")
    
    if len(password) < 6:
        raise ValueError("Пароль должен быть минимум 6 символов")
    
    # Шаг 1: системный пользователь
    if not system_user_exists(username):
        code, _, err = _run(['sudo', '-n', 'useradd', '-m', '-s', '/bin/bash', username])
        if code != 0:
            raise Exception(f"Не удалось создать системного пользователя: {err}")
    
    # Шаг 2: пароль Samba
    input_data = f"{password}\n{password}\n"
    code, stdout, stderr = _run(
        ['sudo', '-n', 'smbpasswd', '-a', '-s', username],
        input_data=input_data
    )
    
    if code != 0:
        raise Exception(f"smbpasswd вернул ошибку: {stderr or stdout}")
    
    # Шаг 3: проверка
    code, stdout, _ = _run(['sudo', '-n', 'pdbedit', '-L', username])
    if username not in stdout:
        code2, stdout2, _ = _run(['sudo', '-n', 'pdbedit', '-L'])
        if username not in stdout2:
            raise Exception(f"Пользователь {username} не найден в Samba после создания")
    
    return True


def delete_user(username: str) -> bool:
    """Удалить пользователя Samba (из Samba + из системы)"""
    username = username.strip()
    
    _run(['sudo', '-n', 'smbpasswd', '-x', username])
    
    if system_user_exists(username):
        _run(['sudo', '-n', 'userdel', '-r', username])
    
    return True


def set_password(username: str, password: str) -> bool:
    """Сменить пароль пользователя Samba"""
    username = username.strip()
    
    if len(password) < 6:
        raise ValueError("Пароль должен быть минимум 6 символов")
    
    input_data = f"{password}\n{password}\n"
    code, stdout, stderr = _run(
        ['sudo', '-n', 'smbpasswd', '-s', username],
        input_data=input_data
    )
    
    if code != 0:
        raise Exception(f"Не удалось сменить пароль: {stderr or stdout}")
    
    return True


def enable_user(username: str) -> bool:
    """Включить пользователя Samba"""
    code, _, err = _run(['sudo', '-n', 'smbpasswd', '-e', username])
    if code != 0:
        raise Exception(f"Не удалось включить: {err}")
    return True


def disable_user(username: str) -> bool:
    """Отключить пользователя Samba"""
    code, _, err = _run(['sudo', '-n', 'smbpasswd', '-d', username])
    if code != 0:
        raise Exception(f"Не удалось отключить: {err}")
    return True
