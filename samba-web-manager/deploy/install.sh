#!/bin/bash
set -e

echo "🚀 Samba Web Manager - Установка"

# Проверка прав
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Запустите с sudo: sudo ./deploy/install.sh"
    exit 1
fi

# Определение путей
APP_DIR="/opt/samba-web-manager"
USER="samba-web"

echo "📦 Установка системных зависимостей..."
apt update
apt install -y python3 python3-pip python3-venv samba smbclient cifs-utils nginx

echo "👤 Создание пользователя..."
if ! id -u $USER >/dev/null 2>&1; then
    useradd -r -s /bin/bash -m -d $APP_DIR $USER
fi

echo "📁 Копирование приложения..."
mkdir -p $APP_DIR
cp -r . $APP_DIR/
chown -R $USER:$USER $APP_DIR

echo "🐍 Настройка Python окружения..."
su - $USER -c "cd $APP_DIR && python3 -m venv venv"
su - $USER -c "cd $APP_DIR && source venv/bin/activate && pip install -r requirements.txt"

echo "🔒 Настройка прав sudo..."
cat > /etc/sudoers.d/samba-web << EOF
$USER ALL=(ALL) NOPASSWD: /usr/sbin/smbpasswd, /usr/bin/pdbedit, /usr/sbin/service smbd *, /bin/mount, /bin/umount, /sbin/mkfs.*
EOF
chmod 440 /etc/sudoers.d/samba-web

echo "⚙️ Настройка конфигурации..."
if [ ! -f $APP_DIR/.env ]; then
    cat > $APP_DIR/.env << EOF
SECRET_KEY=$(openssl rand -base64 32)
ADMIN_USERNAME=admin
ADMIN_PASSWORD=$(openssl rand -base64 12)
FLASK_ENV=production
EOF
    echo "✅ Сгенерирован пароль администратора:"
    grep ADMIN_PASSWORD $APP_DIR/.env
fi

echo "⚙️ Настройка systemd..."
cat > /etc/systemd/system/samba-web.service << EOF
[Unit]
Description=Samba Web Manager
After=network.target smbd.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$APP_DIR/venv/bin/gunicorn --worker-class gevent --workers 4 --bind 0.0.0.0:5000 wsgi:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable samba-web
systemctl start samba-web

echo "✅ Установка завершена!"
IP=$(hostname -I | awk '{print $1}')
echo "🌐 Откройте в браузере: http://$IP:5000"
echo "👤 Логин: admin"
echo "🔑 Пароль: $(grep ADMIN_PASSWORD $APP_DIR/.env | cut -d= -f2)"