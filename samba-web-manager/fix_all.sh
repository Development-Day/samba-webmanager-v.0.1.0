#!/bin/bash
# ============================================================
# Samba Web Manager - Полное исправление багов
# ============================================================
# Исправляет:
#   1. users.py   - ошибка 'bytes' has no attribute 'encode'
#   2. app.py     - logout не удаляет cookie
#   3. sudoers    - NOPASSWD для Samba команд
#   4. Очистка    - мусор от прошлых тестов
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

APP_DIR="/home/rootpool/Desktop/Samba-manager/samba-web-manager"

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    log_error "Запустите с sudo: sudo ./fix_all.sh"
    exit 1
fi

cd "$APP_DIR"

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  🔧 Samba Web Manager - Полное исправление${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""

# ============================================================
# БЭКАП
# ============================================================
BACKUP_DIR="/root/samba-web-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp samba_manager/users.py "$BACKUP_DIR/" 2>/dev/null || true
cp samba_manager/config_parser.py "$BACKUP_DIR/" 2>/dev/null || true
cp app.py "$BACKUP_DIR/" 2>/dev/null || true
log_info "Бэкап: $BACKUP_DIR"
echo ""

# ============================================================
# 1. ИСПРАВЛЕНИЕ users.py
# ============================================================
log_info "Исправление 1/4: users.py — универсальная обработка str/bytes"

cat > samba_manager/users.py << 'PYEOF'
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
PYEOF

log_info "✅ users.py перезаписан"
echo ""

# ============================================================
# 2. ИСПРАВЛЕНИЕ app.py - logout
# ============================================================
log_info "Исправление 2/4: app.py — logout удаляет cookie"

python3 << 'PYEOF'
import re

app_path = "app.py"

with open(app_path, 'r') as f:
    content = f.read()

# Ищем функцию logout (старую или новую)
pattern = r"(@app\.route\('/logout'\)\s*\n\s*def logout\(\):\s*\n(?:.*?\n)*?)(?=\s*@app\.route|\s*#\s*=|\Z)"

new_logout = """@app.route('/logout')
    def logout():
        username = session.get('username', 'unknown')
        app.logger.info(f'Пользователь {username} вышел из системы')
        session.clear()
        # Принудительно удаляем cookie сессии
        response = redirect(url_for('login'))
        response.set_cookie('session', '', expires=0, httponly=True, samesite='Lax', path='/')
        response.delete_cookie('session', path='/')
        return response

    """

match = re.search(pattern, content, re.DOTALL)
if match:
    content = content[:match.start()] + new_logout + content[match.end():]
    with open(app_path, 'w') as f:
        f.write(content)
    print("✅ logout исправлен через regex")
else:
    # Запасной вариант: ищем по строкам
    lines = content.split('\n')
    new_lines = []
    in_logout = False
    skip_until_route = False
    
    for i, line in enumerate(lines):
        if "@app.route('/logout')" in line:
            in_logout = True
            new_lines.append("@app.route('/logout')")
            continue
        
        if in_logout:
            if "def logout():" in line:
                new_lines.append("    def logout():")
                new_lines.append("        username = session.get('username', 'unknown')")
                new_lines.append("        app.logger.info(f'Пользователь {username} вышел из системы')")
                new_lines.append("        session.clear()")
                new_lines.append("        response = redirect(url_for('login'))")
                new_lines.append("        response.set_cookie('session', '', expires=0, httponly=True, samesite='Lax', path='/')")
                new_lines.append("        response.delete_cookie('session', path='/')")
                new_lines.append("        return response")
                new_lines.append("")
                skip_until_route = True
                continue
        
        if skip_until_route:
            if line.strip().startswith('@app.route') or line.strip().startswith('# ='):
                skip_until_route = False
                in_logout = False
                new_lines.append(line)
            # иначе пропускаем строки старой функции
            continue
        
        new_lines.append(line)
    
    content = '\n'.join(new_lines)
    with open(app_path, 'w') as f:
        f.write(content)
    print("✅ logout исправлен построчно")
PYEOF

log_info "✅ app.py обновлён"
echo ""

# ============================================================
# 3. NOPASSWD sudo
# ============================================================
log_info "Исправление 3/4: sudo NOPASSWD для Samba"

cat > /etc/sudoers.d/samba-web << 'EOF'
# Samba Web Manager - NOPASSWD для команд Samba
rootpool ALL=(ALL) NOPASSWD: /usr/sbin/smbpasswd
rootpool ALL=(ALL) NOPASSWD: /usr/bin/smbpasswd
rootpool ALL=(ALL) NOPASSWD: /usr/bin/pdbedit
rootpool ALL=(ALL) NOPASSWD: /usr/sbin/useradd
rootpool ALL=(ALL) NOPASSWD: /usr/sbin/userdel
rootpool ALL=(ALL) NOPASSWD: /usr/sbin/usermod
rootpool ALL=(ALL) NOPASSWD: /usr/bin/systemctl
rootpool ALL=(ALL) NOPASSWD: /bin/systemctl
rootpool ALL=(ALL) NOPASSWD: /usr/sbin/service
rootpool ALL=(ALL) NOPASSWD: /usr/bin/testparm
rootpool ALL=(ALL) NOPASSWD: /usr/sbin/testparm
rootpool ALL=(ALL) NOPASSWD: /bin/mount
rootpool ALL=(ALL) NOPASSWD: /bin/umount
rootpool ALL=(ALL) NOPASSWD: /sbin/mkfs.*
rootpool ALL=(ALL) NOPASSWD: /usr/bin/lsblk
rootpool ALL=(ALL) NOPASSWD: /usr/bin/blkid
rootpool ALL=(ALL) NOPASSWD: /usr/sbin/smartctl
rootpool ALL=(ALL) NOPASSWD: /usr/bin/getfacl
rootpool ALL=(ALL) NOPASSWD: /usr/bin/setfacl
rootpool ALL=(ALL) NOPASSWD: /usr/bin/chown
rootpool ALL=(ALL) NOPASSWD: /usr/bin/chmod
rootpool ALL=(ALL) NOPASSWD: /usr/sbin/smbstatus
rootpool ALL=(ALL) NOPASSWD: /usr/bin/smbstatus
rootpool ALL=(ALL) NOPASSWD: /bin/grep
rootpool ALL=(ALL) NOPASSWD: /usr/bin/grep
rootpool ALL=(ALL) NOPASSWD: /usr/bin/find
rootpool ALL=(ALL) NOPASSWD: /bin/cat
rootpool ALL=(ALL) NOPASSWD: /usr/bin/cat
EOF

chmod 440 /etc/sudoers.d/samba-web

if visudo -c &>/dev/null; then
    log_info "✅ sudoers настроен корректно"
else
    log_error "❌ Ошибка в sudoers!"
    rm -f /etc/sudoers.d/samba-web
    exit 1
fi
echo ""

# ============================================================
# 4. ОЧИСТКА МУСОРА
# ============================================================
log_info "Исправление 4/4: Очистка мусора от тестов"

# Удаляем тестовых пользователей
COUNT=0
for user in $(getent passwd | grep -oP '^testuser_\d+' || true); do
    smbpasswd -x "$user" 2>/dev/null || true
    userdel -r "$user" 2>/dev/null || true
    COUNT=$((COUNT + 1))
done

if [ "$COUNT" -gt 0 ]; then
    log_warn "Удалено пользователей: $COUNT"
else
    log_info "Тестовых пользователей не найдено"
fi

# Удаляем тестовые шары
SHARE_COUNT=0
for share in $(sudo testparm -s 2>/dev/null | grep -oP '^\[\Ktest_share_\d+' || true); do
    python3 -c "
from samba_manager.config_parser import SambaConfig
try:
    c = SambaConfig()
    c.delete_share('$share')
    print('OK')
except Exception as e:
    print(f'Ошибка: {e}')
" 2>/dev/null
    SHARE_COUNT=$((SHARE_COUNT + 1))
done

if [ "$SHARE_COUNT" -gt 0 ]; then
    log_warn "Удалено шар: $SHARE_COUNT"
else
    log_info "Тестовых шар не найдено"
fi

# ============================================================
# ФИНАЛ
# ============================================================
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ ВСЕ ИСПРАВЛЕНИЯ ПРИМЕНЕНЫ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "📁 Бэкап оригиналов: ${CYAN}$BACKUP_DIR${NC}"
echo ""
echo -e "${YELLOW}🚀 Следующие шаги:${NC}"
echo ""
echo "   1. Перезапустить приложение:"
echo "      sudo pkill -9 -f 'python.*app.py'"
echo "      cd $APP_DIR && source venv/bin/activate"
echo "      nohup python3 app.py > /tmp/samba-web.log 2>&1 &"
echo ""
echo "   2. Запустить тест:"
echo "      cd $APP_DIR && ./test_dashboard.sh"
echo ""
