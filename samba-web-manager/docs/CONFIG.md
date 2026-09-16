# ⚙️ Конфигурация Samba Web Manager

Все параметры приложения задаются в файле `/opt/samba-web-manager/.env`.

---

## 📝 Формат `.env`

```bash
# Комментарии — со знаком #
KEY=value
```

**Правила:**

- Пробелы вокруг `=` допустимы: `KEY = value` → `value`.
- Кавычки не нужны: `KEY=value` (не `KEY="value"`).
- Пустые строки игнорируются.
- Значения после `#` не обрезаются.

---

## 🔑 Переменные

### Flask

| Переменная | По умолчанию | Описание |
|---|---|---|
| `SECRET_KEY` | (генерируется) | Ключ для подписи сессий. Обязательно сменить! |
| `FLASK_ENV` | `production` | Окружение: `production` / `development` / `testing` |
| `PORT` | `5000` | Порт веб-интерфейса |

**Сгенерировать `SECRET_KEY`:**

```bash
python3 -c "import secrets; print(secrets.token_hex(32))"
```

### Администратор

| Переменная | По умолчанию | Описание |
|---|---|---|
| `ADMIN_USERNAME` | `admin` | Логин админа |
| `ADMIN_PASSWORD` | (генерируется) | Пароль (plaintext) |
| `ADMIN_PASSWORD_HASH` | — | bcrypt-хеш (приоритет над plaintext) |

**Сгенерировать bcrypt-хеш:**

```bash
python3 -c "import bcrypt; print(bcrypt.hashpw(b'your_password', bcrypt.gensalt()).decode())"
```

> ⚠️ Если задан `ADMIN_PASSWORD_HASH` — `ADMIN_PASSWORD` игнорируется.

### Samba

| Переменная | По умолчанию | Описание |
|---|---|---|
| `SAMBA_CONFIG` | `/etc/samba/smb.conf` | Путь к конфигу Samba |
| `SAMBA_PASSWD` | `/etc/samba/smbpasswd` | Путь к базе паролей Samba |
| `WORKGROUP` | `WORKGROUP` | Рабочая группа |

### Безопасность

| Переменная | По умолчанию | Описание |
|---|---|---|
| `SESSION_COOKIE_SECURE` | `False` | Cookie только через HTTPS |
| `ALLOWED_HOSTS` | `*` | Разрешённые Host (для reverse proxy) |

**`SESSION_COOKIE_SECURE`:**

- `False` — прямое подключение `http://IP:5000` (по умолчанию).
- `True` — только если настроен HTTPS (nginx + Let's Encrypt).

> ⚠️ Если `True`, но HTTPS нет — логин работать не будет.

**`ALLOWED_HOSTS`:**

- `*` — все хосты (рекомендуется для LAN).
- `localhost,192.0.2.50` — список через запятую.

### Логи

| Переменная | По умолчанию | Описание |
|---|---|---|
| `LOG_LEVEL` | `INFO` | Уровень: `DEBUG` / `INFO` / `WARNING` / `ERROR` |

---

## 🎯 Полный пример `.env`

```bash
# ============================================================
# Samba Web Manager - Конфигурация
# ============================================================

# Flask
SECRET_KEY=0000000000000000000000000000000000000000000000000000000000000000
FLASK_ENV=production
PORT=5000

# Администратор
ADMIN_USERNAME=admin
ADMIN_PASSWORD=ChangeMeBeforeUse

# Samba
SAMBA_CONFIG=/etc/samba/smb.conf
SAMBA_PASSWD=/etc/samba/smbpasswd
WORKGROUP=WORKGROUP

# Безопасность
ALLOWED_HOSTS=*
SESSION_COOKIE_SECURE=False

# Логи
LOG_LEVEL=INFO
```

> ⚠️ Значения `SECRET_KEY` и `ADMIN_PASSWORD` в примере — **плейсхолдеры**. Сгенерируйте свои командами выше.

---

## 🚀 Применение изменений

После правки `.env`:

```bash
sudo systemctl restart samba-web
```

**Проверка:**

```bash
sudo systemctl status samba-web
curl -s http://localhost:5000/health
```

---

## 🔍 Проверка значений

```bash
sudo /opt/samba-web-manager/venv/bin/python -c "
import sys
sys.path.insert(0, '/opt/samba-web-manager')
from config import config
c = config['production']
print('ADMIN_USERNAME:', c.ADMIN_USERNAME)
print('ALLOWED_HOSTS:', c.ALLOWED_HOSTS)
print('SESSION_COOKIE_SECURE:', c.SESSION_COOKIE_SECURE)
print('SECRET_KEY length:', len(c.SECRET_KEY))
"
```

> `sudo` без `-u root` — избыточно, так как `sudo` и так запускает от root. Если venv принадлежит пользователю `samba-web`, используйте `sudo -u samba-web`.

---

## 💡 Частые задачи

### Сменить пароль админа

```bash
sudo nano /opt/samba-web-manager/.env
# Изменить ADMIN_PASSWORD=...
sudo systemctl restart samba-web
```

### Сменить порт

```bash
sudo nano /opt/samba-web-manager/.env
# PORT=8080
sudo systemctl restart samba-web
```

### Включить HTTPS-cookie

```bash
sudo nano /opt/samba-web-manager/.env
# SESSION_COOKIE_SECURE=True
sudo systemctl restart samba-web
```

> ⚠️ Только если настроен HTTPS (nginx + Let's Encrypt).

### Изменить уровень логов

```bash
sudo nano /opt/samba-web-manager/.env
# LOG_LEVEL=DEBUG
sudo systemctl restart samba-web
sudo journalctl -u samba-web -f
```