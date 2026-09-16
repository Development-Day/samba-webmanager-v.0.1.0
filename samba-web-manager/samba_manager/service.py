import subprocess
import os
import time

def get_status() -> dict:
    """Получить статус службы Samba"""
    status = {
        'smbd': False,
        'nmbd': False,
        'active': False,
        'status': 'stopped'
    }
    
    try:
        result = subprocess.run(['systemctl', 'is-active', 'smbd'], 
                              capture_output=True, text=True)
        status['smbd'] = result.stdout.strip() == 'active'
    except:
        pass
    
    try:
        result = subprocess.run(['systemctl', 'is-active', 'nmbd'], 
                              capture_output=True, text=True)
        status['nmbd'] = result.stdout.strip() == 'active'
    except:
        pass
    
    status['active'] = status['smbd'] and status['nmbd']
    status['status'] = 'running' if status['active'] else 'stopped'
    
    return status

def restart():
    """Перезапустить Samba"""
    subprocess.run(['sudo', 'systemctl', 'restart', 'smbd'], check=True)
    subprocess.run(['sudo', 'systemctl', 'restart', 'nmbd'], check=True)

def reload():
    """Перезагрузить конфигурацию"""
    subprocess.run(['sudo', 'systemctl', 'reload', 'smbd'], check=True)

def get_uptime() -> str:
    """Получить время работы"""
    try:
        result = subprocess.run(['systemctl', 'status', 'smbd'], 
                              capture_output=True, text=True)
        for line in result.stdout.split('\n'):
            if 'Active:' in line and 'since' in line:
                return line.strip()
    except:
        pass
    return 'unknown'