# 🌐 REST API Samba Web Manager

Все эндпоинты, кроме `/health` и `/login`, требуют авторизации (cookie сессии).

Базовый URL: `http://localhost:5000`

---

## 🔐 Авторизация

### `POST /login`

Логин в веб-интерфейс.

**Параметры (form-data):**

| Поле | Тип | Обязательно |
|---|---|---|
| `username` | string | Да |
| `password` | string | Да |

**Ответ:**

- `302 FOUND` → `Location: /` (успех)
- `200 OK` → HTML логина (ошибка)

**Пример:**

```bash
curl -s -c /tmp/cookies.txt -X POST http://localhost:5000/login \
    --data-urlencode "username=samba-admin" \
    --data-urlencode "password=YourPassword"
```

> `--data-urlencode` корректно закодирует спецсимволы в пароле (`&`, `%`, `+`).
> Пароль всё равно попадёт в `~/.bash_history` — для отладки используйте `HISTCONTROL=ignorespace` или читайте из переменной окружения.

### `GET /logout`

Выход. Очищает сессию.

```bash
curl -s -b /tmp/cookies.txt http://localhost:5000/logout
```

---

## 💚 Healthcheck

### `GET /health`

Без авторизации.

**Ответ:**

```json
{
  "status": "ok",
  "name": "Samba Web Manager",
  "version": "1.0.0"
}
```

```bash
curl -s http://localhost:5000/health
```

---

## 📊 Система

### `GET /api/status`

Статус Samba.

**Ответ:**

```json
{
  "active": true,
  "status": "active",
  "smbd": true,
  "nmbd": true,
  "uptime": "Active: ... 2h ago"
}
```

### `GET /api/system/info`

Системная информация + список дисков.

**Ответ:**

```json
{
  "hostname": "samba-host",
  "os": "Linux-6.1.0...",
  "python": "3.11.2",
  "cpu": {
    "cores": 2,
    "usage": 11.5,
    "load_avg": [0.38, 0.61, 0.82]
  },
  "memory": {
    "total": 4083351552,
    "used": 2224742400,
    "percent": 69.3
  },
  "disk": { },
  "disks": [ ],
  "mounted_disks": [ ],
  "total_disks": 10,
  "uptime": "..."
}
```

### `POST /api/restart`

Перезапуск Samba. Автоматически создаёт бэкап `smb.conf`.

```bash
curl -s -b /tmp/cookies.txt -X POST http://localhost:5000/api/restart
```

---

## 📂 Шары

### `GET /api/shares`

Список всех шар.

**Ответ:**

```json
[
  {
    "name": "public",
    "path": "/srv/samba/public",
    "read_only": false,
    "guest_ok": true,
    "comment": ""
  }
]
```

### `POST /api/shares`

Создание шары.

**Body (JSON):**

```json
{
  "name": "documents",
  "path": "/srv/samba/documents",
  "read_only": false,
  "guest_ok": false,
  "valid_users": "user1,user2",
  "comment": "Documents"
}
```

**Ответ:** `201 Created`

```bash
curl -s -b /tmp/cookies.txt -X POST http://localhost:5000/api/shares \
    -H "Content-Type: application/json" \
    -d '{"name":"test","path":"/tmp/test","read_only":false}'
```

### `PUT /api/shares/<name>`

Обновление шары.

**Body (JSON):** те же поля, что и при создании. Достаточно передать только изменяемые.

### `DELETE /api/shares/<name>`

Удаление шары. Создаёт бэкап `smb.conf` перед удалением.

```bash
curl -s -b /tmp/cookies.txt -X DELETE http://localhost:5000/api/shares/test
```

---

## 👥 Пользователи

### `GET /api/users`

Список Samba-пользователей.

**Ответ:**

```json
[
  {"username": "admin", "enabled": true},
  {"username": "user1", "enabled": true}
]
```

### `POST /api/users`

Создание пользователя.

**Body:**

```json
{
  "username": "user1",
  "password": "StrongPass123"
}
```

**Требования:**

- `username` ≥ 3 символа
- `password` ≥ 8 символов
- Пользователь не должен существовать в системе

### `DELETE /api/users/<username>`

Удаление пользователя (из Samba + из системы).

### `POST /api/users/<username>/password`

Смена пароля.

**Body:**

```json
{"password": "NewPass456"}
```

### `POST /api/users/<username>/enable`

Включение аккаунта.

### `POST /api/users/<username>/disable`

Отключение аккаунта.

---

## 💾 Диски

### `GET /api/disks`

Полный список дисков.

**Ответ:**

```json
{
  "disks": [
    {
  "device": "/dev/sda1",
  "mount_point": "/mnt/disk_sda",
  "size": 1000000000000,
  "size_human": "1.0 TB",
  "used": 250000000000,
  "used_human": "250.0 GB",
  "free": 750000000000,
  "free_human": "750.0 GB",
  "usage_percent": 25,
  "filesystem": "ext4",
  "label": null,
  "uuid": "0000-0000",
  "is_mounted": true,
  "is_auto_mount": false,
  "type": "SATA"
}
  ],
  "total_disks": 10,
  "mounted_disks": 8,
  "available_mount_points": ["/mnt/disk_a", "/mnt/disk_b"]
}
```

### `POST /api/disks/mount`

Монтирование диска.

**Body:**

```json
{
  "device": "/dev/sdc1",
  "mount_point": "/mnt/disk_sdc",
  "options": {
    "filesystem": "auto",
    "options": ["rw"],
    "fstab": true
  },
  "create_share": true
}
```

### `POST /api/disks/unmount`

Отмонтирование.

**Body:**

```json
{
  "mount_point": "/mnt/disk_sdc",
  "remove_fstab": true,
  "remove_share": true
}
```

### `GET /api/disks/mount-points`

Список доступных точек монтирования.

### `POST /api/disks/mount-points`

Создание новой точки.

**Body:**

```json
{"name": "my_disk"}
```

### `POST /api/disks/auto-mount`

Автомонтирование всех обнаруженных дисков.

---

## 📦 Бэкапы

### `GET /api/backups`

Список бэкапов.

**Ответ:**

```json
[
  {
  "filename": "smb.conf_20250101_000000.gz",
  "date": "2025-01-01T00:00:00",
  "size": 1234,
  "size_human": "1.2 KB"
  }
]
```

### `POST /api/backups`

Создание бэкапа.

### `POST /api/backups/<filename>`

Восстановление из бэкапа. Автоматически перезапускает Samba.

### `DELETE /api/backups/<filename>`

Удаление бэкапа.

---

## 📡 Мониторинг

### `GET /api/monitoring/connections`

Активные SMB-подключения.

**Ответ:**

```json
[
  {
    "user": "admin",
    "service": "public",
    "ip": "192.0.2.100",
    "time": "..."
  }
]
```

---

## 🐛 Обработка ошибок

Все эндпоинты возвращают JSON с полем `error` при ошибке.

**Примеры:**

```json
{"error": "Не авторизован"}       // 401
{"error": "Ресурс не найден"}     // 404
{"error": "Неверный формат"}      // 400
{"error": "Внутренняя ошибка"}    // 500
```

**HTTP-коды:**

| Код | Значение |
|---|---|
| 200 | OK |
| 201 | Created |
| 302 | Redirect (для `/login`) |
| 400 | Bad Request |
| 401 | Unauthorized |
| 403 | Forbidden |
| 404 | Not Found |
| 500 | Internal Server Error |

---

## 🔧 Примеры использования

### Полный workflow: создание шары

```bash
BASE="http://localhost:5000"
COOKIE=$(mktemp)
trap 'rm -f "$COOKIE"' EXIT

# 1. Логин
PASS="${ADMIN_PASSWORD:?Установите ADMIN_PASSWORD в окружении}"
curl -s -c "$COOKIE" -X POST "$BASE/login" \
    --data-urlencode "username=samba-admin" \
    --data-urlencode "password=$PASS"

# 2. Создать папку
sudo mkdir -p /srv/samba/documents

# 3. Создать шару
curl -s -b "$COOKIE" -X POST "$BASE/api/shares" \
    -H "Content-Type: application/json" \
    -d '{"name":"documents","path":"/srv/samba/documents","read_only":false,"guest_ok":true}'

# 4. Проверить
curl -s -b "$COOKIE" "$BASE/api/shares" | python3 -m json.tool
```

### Мониторинг через cron

```bash
# Каждую минуту проверять health, писать в лог при падении
* * * * * curl -sf http://localhost:5000/health > /dev/null \
          || echo "$(date -Is) Samba Web Manager down" >> /var/log/samba-web-alert.log
```

> Не используйте `mail` без настроенного MTA — письма будут молча теряться. Логируйте в файл и настройте `logrotate`, либо используйте `systemd`-таймер с `OnFailure=`.

### Скрипт для автоматической установки

```bash
#!/bin/bash
set -euo pipefail

BASE="http://localhost:5000"
PASS="${ADMIN_PASSWORD:?Установите ADMIN_PASSWORD в окружении}"

COOKIE=$(mktemp)
trap 'rm -f "$COOKIE"' EXIT

# Логин
curl -sf -c "$COOKIE" -X POST "$BASE/login" \
    --data-urlencode "username=samba-admin" \
    --data-urlencode "password=$PASS" > /dev/null

# Создать три шары
for share in public documents media; do
    sudo mkdir -p "/srv/samba/$share"
    curl -sf -b "$COOKIE" -X POST "$BASE/api/shares" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$share\",\"path\":\"/srv/samba/$share\",\"read_only\":false,\"guest_ok\":true}"
    echo "Создана шара: $share"
done
```

---

## 📖 Дополнительно

- [Установка](INSTALL.md)
- [Конфигурация](CONFIGURATION.md)
- [Решение проблем](TROUBLESHOOTING.md)