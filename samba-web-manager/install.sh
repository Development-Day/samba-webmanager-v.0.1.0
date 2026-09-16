#!/bin/bash
# ============================================================
# Samba Web Manager - Установка "из коробки"
# ============================================================
# Поддерживаемые ОС: Debian 11+, Ubuntu 20.04+
# Запуск: sudo ./install.sh
# ============================================================

set -euo pipefail

# ============================================================
# ЦВЕТА
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}ℹ️  $*${NC}"; }
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}" >&2; }

# ============================================================
# ПРОВЕРКА ROOT
# ============================================================
if [ "$EUID" -ne 0 ]; then
    err "Запустите с sudo: sudo ./install.sh"
    exit 1
fi

# ============================================================
# ПРОВЕРКА ОС
# ============================================================
if [ ! -f /etc/debian_version ]; then
    err "Поддерживаются только Debian/Ubuntu. Обнаружено: $(uname -a)"
    exit 1
fi

# ============================================================
# ПЕРЕМЕННЫЕ
# ============================================================
APP_DIR="/opt/samba-web-manager"
SERVICE_NAME="samba-web"
SERVICE_USER="samba-web"
APP_PORT="${APP_PORT:-5000}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Проверка, что рядом лежит приложение
if [ ! -f "$SRC_DIR/app.py" ] && [ ! -f "$SRC_DIR/wsgi.py" ]; then
    err "Не найден app.py или wsgi.py рядом со скриптом установки."
    err "Убедитесь, что install.sh лежит в корне проекта."
    exit 1
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       🚀 Samba Web Manager - Установка                   ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# ============================================================
# 1. СИСТЕМНЫЕ ПАКЕТЫ
# ============================================================
log "[1/7] Установка системных пакетов..."
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    samba \
    samba-common-bin \
    smbclient \
    cifs-utils \
    acl \
    curl \
    rsync \
    gcc \
    > /dev/null 2>&1

ok "Пакеты установлены"

# ============================================================
# 2. ПОЛЬЗОВАТЕЛЬ И ПАПКИ
# ============================================================
log "[2/7] Создание пользователя и папок..."

if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
    useradd -r -s /bin/bash -m -d "$APP_DIR" "$SERVICE_USER"
    ok "Пользователь $SERVICE_USER создан"
else
    warn "Пользователь $SERVICE_USER уже существует"
fi

if ! id -u samba-user >/dev/null 2>&1; then
    useradd -r -s /bin/false samba-user
    ok "Пользователь samba-user создан"
fi

mkdir -p "$APP_DIR"
mkdir -p "$APP_DIR/logs"
mkdir -p "$APP_DIR/backups"
mkdir -p /srv/samba/public
chmod 2775 /srv/samba/public
chown -R samba-user:samba-user /srv/samba/public 2>/dev/null || true

ok "Папки созданы"

# ============================================================
# 3. КОПИРОВАНИЕ ФАЙЛОВ
# ============================================================
log "[3/7] Копирование файлов из $SRC_DIR в $APP_DIR..."

rsync -a \
    --exclude='venv' \
    --exclude='.venv' \
    --exclude='.env' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='logs/*' \
    --exclude='backups/*' \
    --exclude='.git' \
    --exclude='tests' \
    --exclude='deploy' \
    "$SRC_DIR/" "$APP_DIR/"

chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR"

ok "Файлы скопированы"

# ============================================================
# 4. PYTHON ОКРУЖЕНИЕ
# ============================================================
log "[4/7] Установка Python зависимостей..."

cd "$APP_DIR"
sudo -u "$SERVICE_USER" python3 -m venv venv
sudo -u "$SERVICE_USER" ./venv/bin/pip install -q --upgrade pip

if [ -f "$APP_DIR/requirements.txt" ]; then
    sudo -u "$SERVICE_USER" ./venv/bin/pip install -q -r "$APP_DIR/requirements.txt"
else
    warn "requirements.txt не найден, ставим стандартный набор"
    sudo -u "$SERVICE_USER" ./venv/bin/pip install -q \
        Flask==2.3.3 \
        python-dotenv==1.0.0 \
        psutil==5.9.5 \
        bcrypt==4.0.1 \
        gunicorn==21.2.0 \
        gevent==23.9.1
fi

ok "Python зависимости установлены"

# ============================================================
# 5. КОНФИГУРАЦИЯ .ENV
# ============================================================
log "[5/7] Настройка конфигурации..."

ENV_FILE="$APP_DIR/.env"
ADMIN_PASSWORD=""

if [ ! -f "$ENV_FILE" ]; then
    SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    ADMIN_PASSWORD=$(python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(16)))")

    cat > "$ENV_FILE" << EOF
# Samba Web Manager - Конфигурация
SECRET_KEY=$SECRET_KEY
FLASK_ENV=production
PORT=$APP_PORT

ADMIN_USERNAME=admin
ADMIN_PASSWORD=$ADMIN_PASSWORD

SAMBA_CONFIG=/etc/samba/smb.conf
SAMBA_PASSWD=/etc/samba/smbpasswd
WORKGROUP=WORKGROUP

ALLOWED_HOSTS=*
SESSION_COOKIE_SECURE=False
LOG_LEVEL=INFO
EOF

    chown "$SERVICE_USER:$SERVICE_USER" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    ok ".env создан"
else
    ADMIN_PASSWORD=$(grep '^ADMIN_PASSWORD=' "$ENV_FILE" | cut -d= -f2- || echo "(см. $ENV_FILE)")
    warn ".env уже существует, используем существующий пароль"
fi

# ============================================================
# 6. НАСТРОЙКА SAMBA + SUDO
# ============================================================
log "[6/7] Настройка Samba и прав..."

if ! grep -q "\[global\]" /etc/samba/smb.conf 2>/dev/null; then
    cat > /etc/samba/smb.conf << 'EOF'
[global]
   workgroup = WORKGROUP
   server string = Samba Web Manager
   netbios name = SAMBA
   security = user
   map to guest = Bad User
   guest account = nobody
   log file = /var/log/samba/log.%m
   max log size = 1000
   server role = standalone server
EOF
    ok "Базовый smb.conf создан"
fi

if ! grep -q "\[public\]" /etc/samba/smb.conf; then
    cat >> /etc/samba/smb.conf << 'EOF'

[public]
   path = /srv/samba/public
   browseable = yes
   read only = no
   guest ok = yes
   create mask = 0664
   directory mask = 2775
EOF
    ok "Шара [public] добавлена"
fi

# Sudo NOPASSWD
cat > /etc/sudoers.d/samba-web << SUDOEOF
# Samba Web Manager - NOPASSWD для команд Samba
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/sbin/smbpasswd
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/bin/smbpasswd
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/bin/pdbedit
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/sbin/useradd
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/sbin/userdel
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/sbin/usermod
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl
$SERVICE_USER ALL=(ALL) NOPASSWD: /bin/systemctl
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/sbin/service
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/bin/testparm
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/sbin/testparm
$SERVICE_USER ALL=(ALL) NOPASSWD: /bin/mount
$SERVICE_USER ALL=(ALL) NOPASSWD: /bin/umount
$SERVICE_USER ALL=(ALL) NOPASSWD: /sbin/mkfs.*
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/bin/lsblk
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/bin/blkid
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/sbin/smartctl
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/bin/getfacl
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/bin/setfacl
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/bin/chown
$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/bin/chmod
SUDOEOF

chmod 440 /etc/sudoers.d/samba-web

systemctl enable smbd nmbd 2>/dev/null || true
systemctl restart smbd nmbd 2>/dev/null || true

ok "Samba настроена, права выданы"

# ============================================================
# 7. SYSTEMD СЕРВИС
# ============================================================
log "[7/7] Настройка автозапуска..."

# Определяем точку входа
if [ -f "$APP_DIR/wsgi.py" ]; then
    ENTRYPOINT="wsgi:app"
elif [ -f "$APP_DIR/app.py" ]; then
    ENTRYPOINT="app:app"
else
    err "Не найден wsgi.py или app.py — сервис не запустится"
    exit 1
fi

cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Samba Web Manager
After=network.target smbd.service nmbd.service
Wants=smbd.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$APP_DIR

Environment="PYTHONUNBUFFERED=1"
EnvironmentFile=$APP_DIR/.env

ExecStart=$APP_DIR/venv/bin/gunicorn --worker-class gevent --workers 2 --bind 0.0.0.0:$APP_PORT --timeout 120 --access-logfile $APP_DIR/logs/access.log --error-logfile $APP_DIR/logs/error.log $ENTRYPOINT

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME" 2>/dev/null || true
systemctl start "$SERVICE_NAME" || true

# Ждём запуска
for i in $(seq 1 10); do
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        break
    fi
    sleep 1
done

# ============================================================
# ПРОВЕРКА
# ============================================================
if systemctl is-active --quiet "$SERVICE_NAME"; then
    IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    IP="${IP:-localhost}"

    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║        ✅  УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!                  ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "🌐 Веб-интерфейс:  http://$IP:$APP_PORT"
    echo "👤 Логин:          admin"
    echo "🔑 Пароль:         сохранён в $ENV_FILE (chmod 600)"
    echo ""
    echo "📁 Приложение:     $APP_DIR"
    echo "📊 Статус:         sudo systemctl status $SERVICE_NAME"
    echo "📋 Логи:           sudo journalctl -u $SERVICE_NAME -f"
    echo ""
    echo "🔑 Посмотреть пароль:"
    echo "   sudo grep ADMIN_PASSWORD $ENV_FILE"
    echo ""
else
    err "Сервис не запустился!"
    echo ""
    echo "Последние 30 строк лога:"
    journalctl -u "$SERVICE_NAME" -n 30 --no-pager || true
    exit 1
fi