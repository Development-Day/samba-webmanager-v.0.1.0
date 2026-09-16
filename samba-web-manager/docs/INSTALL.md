# 📥 Установка Samba Web Manager

Подробное руководство по установке на Debian 11+ / Ubuntu 20.04+.

---

## 📋 Требования

| Компонент | Минимум | Рекомендуется |
|---|---|---|
| **ОС** | Debian 11 / Ubuntu 20.04 | Debian 12 / Ubuntu 22.04 |
| **RAM** | 256 МБ | 512 МБ |
| **Диск** | 300 МБ | 1 ГБ |
| **Python** | 3.8 | 3.11 |
| **Права** | root / sudo | root / sudo |
| **Интернет** | Да (для apt) | Да |

---

## 🔌 Порты

| Порт | Что | Когда работает |
|---|---|---|
| **5001** | Веб-установщик | Только во время установки |
| **5000** | Samba Web Manager | После установки |
| **445** | Samba (SMB) | Всегда |
| **137/udp, 138/udp** | NetBIOS | Для «Сетевого окружения» (опционально) |

**Firewall:** после установки откройте `5000/tcp` и `445/tcp`:

```bash
sudo ufw allow 5000/tcp
sudo ufw allow 445/tcp
sudo ufw reload
```

---

## 🚀 Способы установки

### Способ 1: Bash-установщик (быстрый)

```bash
git clone https://github.com/Development-Day/samba-web-manager.git
cd samba-web-manager
sudo ./install.sh
```

**Что делает `install.sh`:**

- Устанавливает системные пакеты (samba, python3, python3-venv, ...).
- Создаёт пользователей `samba-web` и `samba-user`.
- Копирует файлы в `/opt/samba-web-manager/`.
- Создаёт Python venv и ставит зависимости.
- Генерирует `.env` с `SECRET_KEY` и паролем админа.
- Настраивает `/etc/samba/smb.conf`.
- Настраивает sudo-правила.
- Создаёт systemd-сервис и запускает его.

**Время:** 1–3 минуты.

### Способ 2: Веб-установщик (пошаговый мастер)

```bash
cd samba-web-manager-install
sudo python3 installer_app.py
```

Откройте `http://IP-сервера:5001` — мастер проведёт по шагам:

1. **Проверка системы** — что установлено, что нет.
2. **Выбор компонентов** — Samba, Python, Web, диски.
3. **Настройка** — логин/пароль админа, порт.
4. **Установка** — с прогресс-баром и логами.
5. **Готово** — данные для входа.

**Преимущества:**

- Не требует Flask (сам установит).
- Показывает, что уже установлено.
- Позволяет переустановить отдельные компоненты.

**Время:** 2–5 минут.

---

## 🔧 Ручная установка (для отладки)

### 1. Установить зависимости

```bash
sudo apt-get update
sudo apt-get install -y \
    python3 python3-pip python3-venv \
    samba samba-common-bin smbclient cifs-utils \
    acl curl rsync gcc
```

### 2. Создать пользователя и папки

```bash
sudo useradd -r -s /bin/bash -m -d /opt/samba-web-manager samba-web
sudo useradd -r -s /bin/false samba-user
sudo mkdir -p /opt/samba-web-manager
sudo mkdir -p /srv/samba/public
sudo chmod 2775 /srv/samba/public
```

### 3. Скопировать файлы

```bash
sudo rsync -a --exclude='venv' --exclude='.env' \
    ./ /opt/samba-web-manager/
sudo chown -R samba-web:samba-web /opt/samba-web-manager
```

### 4. Создать venv

```bash
cd /opt/samba-web-manager
sudo -u samba-web python3 -m venv venv
sudo -u samba-web ./venv/bin/pip install --upgrade pip
sudo -u samba-web ./venv/bin/pip install -r requirements.txt
```

### 5. Создать `.env`

```bash
cd /opt/samba-web-manager
sudo -u samba-web cp .env.example .env
SK=$(python3 -c "import secrets; print(secrets.token_hex(32))")
sudo -u samba-web sed -i "s|^SECRET_KEY=.*|SECRET_KEY=$SK|" .env
sudo chmod 600 .env
```

### 6. Настроить systemd

```bash
sudo tee /etc/systemd/system/samba-web.service << 'EOF'
[Unit]
Description=Samba Web Manager
After=network.target smbd.service

[Service]
Type=simple
User=samba-web
Group=samba-web
WorkingDirectory=/opt/samba-web-manager
EnvironmentFile=/opt/samba-web-manager/.env
ExecStart=/opt/samba-web-manager/venv/bin/gunicorn --worker-class gevent --workers 2 --bind 0.0.0.0:5000 --access-logfile /opt/samba-web-manager/logs/access.log --error-logfile /opt/samba-web-manager/logs/error.log wsgi:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now samba-web
```

### 7. Проверить

```bash
curl -s http://localhost:5000/health
sudo systemctl status samba-web
```

---

## ✅ После установки

### 1. Открыть веб-интерфейс

Перейдите по адресу `http://IP-сервера:5000`.

- **Логин:** `admin`
- **Пароль:** сохранён в `/opt/samba-web-manager/.env`

```bash
sudo grep ADMIN_PASSWORD /opt/samba-web-manager/.env
```

### 2. Сменить пароль

```bash
sudo nano /opt/samba-web-manager/.env
# Изменить ADMIN_PASSWORD=...
sudo systemctl restart samba-web
```

### 3. Открыть порт в firewall (если нужно)

```bash
sudo ufw allow 5000/tcp
sudo ufw allow Samba
```

### 4. Проверить Samba

```bash
sudo testparm -s
sudo smbstatus
```

---

## 🔍 Проверка установки

```bash
sudo /opt/samba-web-manager/check_installation.sh
```

**Ожидаемо:**

```
✅ Python3: Python 3.11.2
✅ Samba: Version 4.17.12
✅ /etc/samba/smb.conf существует
✅ venv
✅ Flask, gunicorn, gevent, psutil, bcrypt, python-dotenv
✅ Сервис samba-web запущен
✅ Порт 5000 слушается
✅ Healthcheck /health
✅ .env SECRET_KEY
✅ .env ADMIN_PASSWORD

🎉 Все проверки пройдены!
```

---

## 🐛 Проблемы при установке

### `apt-get update` падает

```bash
# Проверить интернет
ping -c 3 1.1.1.1

# Проверить DNS
cat /etc/resolv.conf
# Добавить nameserver 1.1.1.1
```

### `Permission denied` при venv

```bash
sudo chown -R samba-web:samba-web /opt/samba-web-manager
```

### Сервис не запускается

```bash
sudo journalctl -u samba-web -n 50 --no-pager
```

Смотрите «Решение проблем» в основном `README.md`.

---

## 🗑️ Удаление

```bash
cd /opt/samba-web-manager
sudo ./uninstall.sh          # мягкое
sudo ./uninstall.sh --full   # полное
```

См. подробнее в `README.md`.