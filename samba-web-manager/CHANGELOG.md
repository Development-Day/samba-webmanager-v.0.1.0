# Changelog

Все значимые изменения проекта.

Формат основан на [Keep a Changelog](https://keepachangelog.com/ru/1.0.0/),
версии следуют [Semantic Versioning](https://semver.org/lang/ru/).

---

## [1.0.0] - 2026-09-12

### Первый стабильный релиз

#### Добавлено

- **Веб-интерфейс** для управления Samba
  - Дашборд со статистикой
  - Управление общими папками (CRUD)
  - Управление пользователями Samba
  - Управление дисками (обнаружение, монтирование)
  - Бэкапы конфигурации
  - Мониторинг подключений
  - Логи действий
  - ACL права доступа

- **REST API** для всех операций
  - `/api/shares` — CRUD шар
  - `/api/users` — CRUD пользователей
  - `/api/disks` — обнаружение и монтирование
  - `/api/backups` — бэкапы
  - `/api/status` — статус Samba
  - `/api/system/info` — системная информация

- **Авторизация**
  - Логин/пароль администратора
  - Сессионные cookie
  - Защита API (401 для неавторизованных)
  - Logout с инвалидацией сессии

- **Автоматизация**
  - `install.sh` — установка из коробки
  - `uninstall.sh` — удаление
  - `update.sh` — обновление
  - `test_dashboard.sh` — 28 автотестов
  - `fix_all.sh` — автоисправление багов

- **DevOps**
  - Systemd сервис для автозапуска
  - Nginx конфиг (reverse proxy)
   - Docker-образ
    - Docker Compose
    - Makefile

#### Исправлено

- `'bytes' has no attribute 'encode'` в `users.py` — универсальная обработка str/bytes
- Шара не находилась в `smb.conf` — прямая запись + проверка через `configparser`
- Пользователь не создавался в Samba — `smbpasswd -a -s` + проверка через `pdbedit`
- Logout не убивал сессию — `set_cookie(expires=0)` + `delete_cookie`
- Sudo просил пароль — `NOPASSWD` в `/etc/sudoers.d/samba-web`

#### Ресурсы

- **RAM:** ~250 МБ
- **Диск:** ~250 МБ
- **Время установки:** ~2 минуты

---

## [Unreleased]

### Планируется

- [x] 2FA (двухфакторная аутентификация)
- [ ] Telegram/Email уведомления
- [ ] WebSocket для real-time мониторинга
- [ ] Интеграция с Active Directory
- [ ] Мобильное приложение
- [ ] Тёмная тема
- [x] Многоязычность (i18n)

