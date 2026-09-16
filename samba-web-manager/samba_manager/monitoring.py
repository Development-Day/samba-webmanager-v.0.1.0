#!/usr/bin/env python3
"""
Модуль мониторинга Samba
"""

import subprocess
import os
from typing import List, Dict


def _run(cmd: List[str], timeout: int = 10) -> str:
    """Запускает команду и возвращает stdout или пустую строку."""
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return result.stdout or ''
    except (subprocess.TimeoutExpired, FileNotFoundError, Exception):
        return ''


def get_active_connections() -> List[Dict]:
    """
    Возвращает список активных SMB-подключений.

    Использует `smbstatus -p` (parsable format).

    Формат:
        PID  Username  Group  Machine  Protocol  Encryption  Signing
        24827  nobody  nogroup  ::1 (ipv6:::1:49446)  SMB3_00  -  -
    """
    # Пробуем сначала без sudo, потом с sudo -n (non-interactive)
    output = _run(['smbstatus', '-p'])
    if not output.strip():
        output = _run(['sudo', '-n', 'smbstatus', '-p'])
    if not output.strip():
        output = _run(['sudo', 'smbstatus', '-p'])

    if not output.strip():
        return []

    connections = []
    services = []

    # Разбираем по секциям (между --- разделителями)
    lines = output.split('\n')
    current_section = None
    in_data = False

    for line in lines:
        line = line.rstrip()

        # Разделитель
        if line.startswith('---'):
            if in_data:
                in_data = False
                current_section = None
            else:
                in_data = True
            continue

        # Заголовок секции
        if not in_data:
            low = line.lower()
            if 'pid' in low and 'username' in low and 'machine' in low:
                current_section = 'connections'
            elif 'service' in low and 'pid' in low and 'machine' in low:
                current_section = 'services'
            elif 'locked' in low:
                current_section = 'locked'
            continue

        # Данные
        if not current_section or not line.strip():
            continue

        parts = line.split()
        if not parts:
            continue

        if current_section == 'connections':
            # Формат: PID Username Group Machine Protocol Encryption Signing
            # Machine содержит пробел: "::1 (ipv6:::1:49446)"
            if len(parts) >= 6:
                # Последние 3 поля — protocol, encryption, signing
                signing = parts[-1]
                encryption = parts[-2]
                protocol = parts[-3]

                # Machine — всё между group и protocol
                machine = ' '.join(parts[3:-3])

                connections.append({
                    'pid': parts[0],
                    'user': parts[1] or 'anonymous',
                    'group': parts[2],
                    'machine': machine,
                    'protocol': protocol,
                })

        elif current_section == 'services':
            # Формат: Service pid Machine Connected at Encryption Signing
            # Machine может содержать пробел
            if len(parts) >= 4:
                service_name = parts[0]
                pid = parts[1]

                # Последние 2 поля — encryption, signing
                # Между machine и encryption — "connected at" (несколько полей)
                signing = parts[-1]
                encryption = parts[-2]

                # Machine — parts[2] (обычно одно слово)
                machine = parts[2]

                # "Connected at" — всё между machine и encryption
                time_str = ' '.join(parts[3:-2]) if len(parts) > 5 else ''

                services.append({
                    'service': service_name,
                    'pid': pid,
                    'machine': machine,
                    'time': time_str,
                })

    # Объединяем: к каждой сессии привязываем сервис
    result = []
    for conn in connections:
        # Ищем сервис по PID
        service_name = '—'
        time_str = '—'

        for svc in services:
            if svc['pid'] == conn['pid']:
                if svc['service'] not in ('IPC$',):
                    service_name = svc['service']
                    time_str = svc['time']
                    break

        # Извлекаем IP из machine (первое слово)
        machine = conn.get('machine', '')
        ip = machine.split()[0] if machine else '—'

        result.append({
            'pid': conn['pid'],
            'user': conn['user'] or 'anonymous',
            'service': service_name,
            'ip': ip,
            'protocol': conn.get('protocol', '—'),
            'time': time_str,
        })

    return result


def check_samba_health() -> Dict:
    """Проверка здоровья Samba."""
    status = {
        'smbd': False,
        'nmbd': False,
        'config_valid': False,
        'port_445': False,
        'port_139': False,
        'healthy': False,
    }

    # smbd
    out = _run(['systemctl', 'is-active', 'smbd'])
    status['smbd'] = out.strip() == 'active'

    # nmbd
    out = _run(['systemctl', 'is-active', 'nmbd'])
    status['nmbd'] = out.strip() == 'active'

    # testparm (проверка конфига)
    try:
        result = subprocess.run(
            ['testparm', '-s', '--suppress-prompt'],
            capture_output=True, text=True, timeout=10, check=False,
        )
        status['config_valid'] = result.returncode == 0
    except Exception:
        pass

    # Порты
    out = _run(['ss', '-tln'])
    status['port_445'] = ':445' in out
    status['port_139'] = ':139' in out

    # Итог
    status['healthy'] = all([
        status['smbd'],
        status['config_valid'],
        status['port_445'],
    ])

    return status
