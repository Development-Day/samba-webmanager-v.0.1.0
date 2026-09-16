import subprocess

def validate_config() -> tuple:
    """Проверить конфигурацию через testparm"""
    try:
        result = subprocess.run(['testparm', '-s', '--suppress-prompt'], 
                              capture_output=True, text=True)
        return result.returncode == 0, result.stdout + result.stderr
    except:
        return False, 'testparm not found'

def validate_share_name(name: str) -> bool:
    """Проверить имя шары на допустимые символы"""
    import re
    return bool(re.match(r'^[a-zA-Z0-9_\-.]+$', name))

def validate_path(path: str) -> bool:
    """Проверить существование пути"""
    import os
    return os.path.exists(path)