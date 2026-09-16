# 🤝 Contributing to Samba Web Manager

Спасибо за интерес к проекту! Будем рады любому вкладу — от исправления опечаток до новых модулей.

---

## 📋 Как помочь

### 🐛 Если нашли баг

1. Проверьте [Issues](https://github.com/Development-Day/samba-web-manager/issues) — возможно, уже обсуждается.
2. Если нет — создайте новый Issue с:
   - **ОС и версия**: `cat /etc/debian_version`
   - **Python**: `python3 --version`
   - **Версия Samba Web Manager**: из `health`-эндпоинта
   - **Что делали**: пошагово
   - **Что ожидали**
   - **Что получили**: включая логи `sudo journalctl -u samba-web -n 50 --no-pager`
   - **Скриншоты**: если применимо

### 💡 Есть идея?

Откройте Issue с меткой `enhancement`:

- **Что хотите**: краткое описание
- **Зачем**: какую задачу решает
- **Как видите**: возможная реализация

### 🔧 Хотите исправить?

1. Форкните репозиторий.
2. Создайте ветку: `git checkout -b fix/краткое-название`
3. Внесите изменения.
4. Убедитесь, что тесты проходят: `sudo ./test_dashboard.sh`
5. Сделайте коммит: `git commit -m "fix: что исправлено"`
6. Запушьте: `git push origin fix/краткое-название`
7. Откройте Pull Request.

---

## 🎨 Стиль кода

### Python

- **PEP 8** — стандарт.
- **Отступы**: 4 пробела.
- **Длина строки**: до 88 символов (как в Black).
- **Docstrings**: для всех функций.
- **Type hints**: желательно.
- **Импорты**: сортированы (stdlib → 3rd-party → local).

**Пример:**

```python
def get_disk_status(self) -> Dict:
    """Возвращает статус всех дисков системы."""
    disks = self.manager.detect_disks()
    return {
        'disks': [asdict(d) for d in disks],
        'total_disks': len(disks),
    }
```

### Shell

- `#!/bin/bash` в начале.
- `set -euo pipefail` — обязательно.
- Проверка root: `if [ "$EUID" -ne 0 ]; then ...`
- Цвета: через переменные (`RED`, `GREEN`).
- Функции: `log()`, `ok()`, `warn()`, `err()`.

**Шаблон:**

```bash
#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Запустите от root" >&2
    exit 1
fi
```

### HTML / CSS / JS

- Cyberpunk-тема — основной стиль (`#0a0a0a` фон, `#00ffff` акцент).
- Без фреймворков — чистый CSS + Vanilla JS.
- Иконки: Bootstrap Icons.
- Отступы: 4 пробела.
- Классы: kebab-case (`.component-card`).
- ID: camelCase (`#disksCount`).

### Комментарии

```python
# ============================================================
# СЕКЦИЯ (для больших блоков)
# ============================================================

# Обычный комментарий
```

---

## 🧪 Тестирование

### Перед PR — обязательно

```bash
# 1. Установка
sudo ./install.sh

# 2. Проверка
sudo ./check_installation.sh

# 3. Тесты
sudo ./test_dashboard.sh    # быстрые (16 тестов)
sudo ./test_full.sh         # полные (42 теста)
```

Затем откройте http://localhost:5000 и проверьте вручную.

`test_dashboard.sh` проверяет:

- 16 сценариев, ~40 проверок.
- Healthcheck, логин, CRUD, API, дашборд.
- Logout + защита API.

Все тесты должны пройти перед PR.

---

## 📝 Формат коммитов

Используем [Conventional Commits](https://www.conventionalcommits.org/):

```
<тип>: <краткое описание>

[опционально: подробное описание]
```

### Типы

| Тип | Когда |
|---|---|
| `feat` | Новая функция |
| `fix` | Исправление бага |
| `docs` | Только документация |
| `style` | Форматирование, пробелы |
| `refactor` | Рефакторинг без изменения поведения |
| `test` | Тесты |
| `chore` | Сборка, зависимости, конфиги |

### Примеры

```
feat: добавить экспорт шар в JSON
fix: логин не работал в production без ADMIN_PASSWORD_HASH
docs: обновить README с новыми портами
refactor: разделить disks.py на модули
```

---

## 🎯 Что приветствуется

### 🟢 Хорошо

- Новые функции с тестами.
- Улучшение документации.
- Оптимизация производительности.
- Безопасность (XSS, CSRF, SQL-injection).
- Совместимость с новыми ОС / версиями.

### 🔴 Не приветствуется

- Ломающие изменения без обсуждения.
- Зависимости «на всякий случай».
- Отключение тестов.
- Игнорирование code review.
- Коммиты `fix`, `update`, `wtf`.

---

## 🐛 Полезные команды для разработки

### Запуск в dev-режиме

```bash
cd /opt/samba-web-manager
sudo systemctl stop samba-web
trap 'sudo systemctl start samba-web' EXIT   # вернёт сервис при выходе
./venv/bin/python app.py
```

### Отладка API

```bash
# Логин
PASS=$(sudo cat /opt/samba-web-manager/.env \
        | grep -E '^ADMIN_PASSWORD=' \
        | head -n1 \
        | cut -d= -f2-)
[ -n "$PASS" ] || { echo "ADMIN_PASSWORD не найден в .env"; exit 1; }

COOKIE=$(mktemp)
trap 'rm -f "$COOKIE"' EXIT

curl -s -c "$COOKIE" -X POST http://localhost:5000/login \
    --data-urlencode "username=admin" \
    --data-urlencode "password=$PASS" > /dev/null

# Запросы
curl -s -b "$COOKIE" http://localhost:5000/api/status | python3 -m json.tool
curl -s -b "$COOKIE" http://localhost:5000/api/disks  | python3 -m json.tool
```

### Просмотр логов

```bash
# systemd
sudo journalctl -u samba-web -f

# Flask + gunicorn access (одновременно)
sudo tail -f /opt/samba-web-manager/logs/app.log \
             /opt/samba-web-manager/logs/access.log
```

### Переустановка зависимостей

```bash
cd /opt/samba-web-manager
sudo -u samba-web venv/bin/pip install -r requirements.txt
```

> Если venv принадлежит пользователю `samba-web`, устанавливайте pip-пакеты **от его имени**, а не от root — иначе файлы в `site-packages` получат владельца root и сервис не сможет их прочитать.

---

## 📜 Лицензия

Внося вклад, вы соглашаетесь, что ваш код распространяется под MIT License.

---

## 🙏 Спасибо!

Каждый PR, Issue и Star — вклад в развитие проекта. Спасибо, что вы с нами! ❤️