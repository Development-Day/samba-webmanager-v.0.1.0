# 🐛 Решение проблем

Частые проблемы и их решения.

---

## 🔴 Сервис не запускается

### Симптом

```bash
$ sudo systemctl status samba-web
● samba-web.service - Samba Web Manager
     Active: failed (Result: exit-code)
```

### Диагностика

```bash
# Смотрим логи
sudo journalctl -u samba-web -n 50 --no-pager

# Проверяем конфиг
sudo -u samba-web /opt/samba-web-manager/venv/bin/python -c "from wsgi import app; print('OK')"

# Проверяем .env
sudo cat /opt/samba-web-manager/.env
```

### Частые причины

| Симптом в логах | Причина | Решение |
|---|---|---|
| `SECRET_KEY не задан` | Нет `SECRET_KEY` в `.env` | Добавить в `.env`, перезапустить |
| `Address already in use` | Порт 5000 занят | Сменить `PORT` в `.env` |
| `ModuleNotFoundError` | Нет зависимостей | `cd /opt/samba-web-manager && sudo -u samba-web venv/bin/pip install -r requirements.txt` |
| `Permission denied` | Неверные права | `sudo chown -R samba-web:samba-web /opt/samba-web-manager` |
| `No such file: wsgi.py` | Не скопировался | `ls /opt/samba-web-manager/wsgi.py` |

---

## 🔴 Не открывается веб-интерфейс

### Симптом

Браузер: «Не удаётся открыть эту страницу».

### Диагностика

```bash
# 1. Слушает ли порт?
sudo ss -tlnp | grep 5000

# 2. Локально работает?
curl -s http://localhost:5000/health

# 3. Firewall?
sudo ufw status
```

### Решения

**Порт не слушается:**

```bash
sudo systemctl status samba-web
sudo journalctl -u samba-web -n 20 --no-pager
```

**Порт слушается, локально работает, извне — нет:**

```bash
# Открыть порт
sudo ufw allow 5000/tcp

# Проверить
sudo ufw status
```

**Порт занят другим процессом:**

```bash
# Кто слушает?
sudo ss -tlnp | grep 5000

# Убить
sudo fuser -k 5000/tcp

# Или сменить порт
sudo nano /opt/samba-web-manager/.env
# PORT=8080
sudo systemctl restart samba-web
```

---

## 🔴 Не логинится

### Симптом

Вводите пароль, но возвращает «Неверное имя пользователя или пароль».

### Диагностика

```bash
# 1. Проверить пароль
sudo grep ADMIN_PASSWORD /opt/samba-web-manager/.env

# 2. Проверить, что SESSION_COOKIE_SECURE=False
sudo grep SESSION_COOKIE_SECURE /opt/samba-web-manager/.env

# 3. Логи попытки входа
sudo journalctl -u samba-web -f
# Вводите логин/пароль, смотрите лог
```

### Решения

**Пароль не тот:**

```bash
sudo nano /opt/samba-web-manager/.env
# Сменить ADMIN_PASSWORD=...
sudo systemctl restart samba-web
```

**`SESSION_COOKIE_SECURE=True` без HTTPS:**

```bash
sudo nano /opt/samba-web-manager/.env
# SESSION_COOKIE_SECURE=False
sudo systemctl restart samba-web
```

**`ADMIN_PASSWORD_HASH` задан, но не тот:**

```bash
# Убрать хеш
sudo sed -i '/^ADMIN_PASSWORD_HASH=/d' /opt/samba-web-manager/.env
sudo systemctl restart samba-web
```

---

## 🔴 Дашборд показывает 0 дисков

### Симптом

В карточке «ДИСКИ» стоит 0, хотя диски есть.

### Диагностика

```bash
# Что отдаёт API?
PASS=$(sudo grep -E '^ADMIN_PASSWORD=' /opt/samba-web-manager/.env \
        | head -n1 | cut -d= -f2-)
COOKIE=$(mktemp)
trap 'rm -f "$COOKIE"' EXIT

curl -s -c "$COOKIE" -X POST http://localhost:5000/login \
    --data-urlencode "username=admin" \
    --data-urlencode "password=$PASS" > /dev/null

curl -s -b "$COOKIE" http://localhost:5000/api/system/info | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print('total:', d.get('total_disks'), 'mounted:', d.get('mounted_disks'))"
```

- Если `None` — `app.py` старый, без поля `disks`.
- Если `8` — проблема в шаблоне `index.html` (старый).

### Решение

Обновить `app.py` и `templates/index.html` (см. актуальные версии в проекте).

---

## 🔴 Samba не работает

### Симптом

`smbd` не запускается, шары недоступны.

### Диагностика

```bash
# Статус
sudo systemctl status smbd nmbd

# Проверить конфиг
sudo testparm -s

# Активные подключения
sudo smbstatus
```

### Решения

**Ошибка в `smb.conf`:**

```bash
# Тест конфига
sudo testparm

# Создать бэкап и заменить
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
sudo nano /etc/samba/smb.conf
```

**Пользователь Samba не создан:**

```bash
# Список
sudo pdbedit -L

# Создать
sudo smbpasswd -a username
```

**Права на папку шары:**

```bash
sudo chown -R samba-user:samba-user /srv/samba/public
sudo chmod 2775 /srv/samba/public
```

---

## 🔴 Логин не работает после смены SECRET_KEY

### Симптом

После смены `SECRET_KEY` в `.env` и перезапуска — существующие сессии сбрасываются, но новые должны работать.

Если не работает — проверьте:

```bash
sudo journalctl -u samba-web -n 30 --no-pager
```

Ищите `SECRET_KEY не задан` или `RuntimeError`.

---

## 🔴 Установщик не запускается

### Симптом

```bash
$ sudo python3 installer_app.py
ModuleNotFoundError: No module named 'flask'
```

### Решение

**Способ 1.** Установить Flask вручную:

```bash
sudo apt install python3-flask
sudo python3 installer_app.py
```

**Способ 2.** Проверить, что bootstrap сработал — в `installer_app.py` должна быть функция `_ensure_flask()`. Если её нет — обновите `installer_app.py`.

---

## 🔴 Установщик: «Не выбраны компоненты»

### Симптом

Установщик возвращает `❌ Ошибка: Не выбраны компоненты` при переустановке.

### Причина

Все компоненты уже установлены, JS снял выделение → `selectedComponents=[]`.

### Решение

Обновить `installer_app.py` и `templates/installer/index.html` (см. актуальные версии).

**Проверьте:**

```bash
# app.py
grep -n "force_reinstall" /path/to/installer_app.py

# index.html
grep -n "onForceReinstallChange" /path/to/templates/installer/index.html
```

Должны быть обе строки.

---

## 🔴 CSS отображается как текст

### Симптом

Открываете установщик — CSS/JS отображаются как текст с фигурными скобками.

### Причина

Flask использует Jinja2, который ломает CSS/JS.

### Решение

В `installer_app.py` замените:

```python
from flask import Flask, render_template, ...
```

на:

```python
from flask import Flask, send_from_directory, ...
```

И роут `/`:

```python
@app.route('/')
def index():
    return send_from_directory(
        os.path.join(TEMPLATES_DIR, 'installer'),
        'index.html',
        mimetype='text/html',
    )
```

---

## 🔴 Порт 5000 занят

### Симптом

```bash
Address already in use
Port 5000 is in use by another program.
```

### Решение

**Узнать, кто:**

```bash
sudo ss -tlnp | grep 5000
sudo lsof -i :5000
```

**Убить:**

```bash
sudo fuser -k 5000/tcp
sudo pkill -f installer_app.py
```

**Сменить порт:**

```bash
sudo nano /opt/samba-web-manager/.env
# PORT=8080
sudo systemctl restart samba-web
```

---

## 🔴 Медленная работа

### Симптом

Страницы грузятся долго.

### Диагностика

```bash
# Замер API
time curl -s -b "$COOKIE" http://localhost:5000/api/system/info -o /dev/null

# Замер dpkg-query
time dpkg-query -W -f='${Package}\t${Status}\n' samba python3 python3-pip
```

### Решение

Обновить `check_packages` в `installer_app.py` — использовать один вызов `dpkg-query` вместо N вызовов `dpkg -l`.

---

## 🔴 Диск не монтируется

### Симптом

`POST /api/disks/mount` возвращает ошибку.

### Диагностика

```bash
# Что в логах?
sudo journalctl -u samba-web -n 20 --no-pager

# Попробовать вручную
sudo mount /dev/sdc1 /mnt/disk_sdc
```

### Решения

**NTFS без `ntfs-3g`:**

```bash
sudo apt install ntfs-3g
```

**exFAT без `exfat-fuse`:**

```bash
sudo apt install exfat-fuse exfatprogs
```

**Точка монтирования не существует:**

```bash
sudo mkdir -p /mnt/disk_sdc
```

---

## 📞 Где получить помощь

- **Логи:** `sudo journalctl -u samba-web -n 50 --no-pager`
- **Проверка:** `sudo ./check_installation.sh`
- **Тесты:** `sudo ./test_dashboard.sh`
- **Issues:** [github.com/Development-Day/samba-web-manager/issues](https://github.com/Development-Day/samba-web-manager/issues)

**При создании Issue прикладывайте:**

    - ОС и версия
    - Python версия
    - Полные логи
    - Что делали
    - Что ожидали / что получили