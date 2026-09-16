#!/bin/bash
# ============================================================
# full-cleanup.sh — Полное удаление Samba Web Manager
# ============================================================
# Что удаляет:
#   1. systemd-сервис samba-web
#   2. Приложение /opt/samba-web-manager
#   3. Пользователей samba-web, samba-user
#   4. Sudo-правила /etc/sudoers.d/samba-web
#   5. Конфиг Samba /etc/samba/smb.conf
#   6. Шары /srv/samba
#   7. Логи /var/log/samba*
#   8. Остатки Samba (по умолчанию — всё, включая пакеты)
#
# Использование:
#   sudo bash full-cleanup.sh              # ПОЛНАЯ очистка (по умолчанию)
#   sudo bash full-cleanup.sh --soft       # мягкая (без apt purge)
#   sudo bash full-cleanup.sh --yes        # без подтверждений
#   sudo bash full-cleanup.sh --soft --yes # мягкая + без подтверждений
# ============================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}ℹ️  $*${NC}"; }
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}" >&2; }

PURGE=true          # по умолчанию — полная очистка
AUTO_YES=false

for arg in "$@"; do
    case "$arg" in
        --soft)   PURGE=false ;;
        --purge)  PURGE=true  ;;
        --yes|-y) AUTO_YES=true ;;
        *) err "Неизвестный аргумент: $arg"; exit 1 ;;
    esac
done

# ============================================================
# ПРОВЕРКА ROOT
# ============================================================
if [ "$EUID" -ne 0 ]; then
    err "Запустите с sudo: sudo bash full-cleanup.sh"
    exit 1
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║   🗑️  ПОЛНОЕ УДАЛЕНИЕ Samba Web Manager                  ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

if [ "$PURGE" = true ]; then
    echo -e "${RED}⚠️  РЕЖИМ: ПОЛНАЯ ОЧИСТКА${NC}"
    echo "   Будут удалены:"
    echo "     • приложение /opt/samba-web-manager"
    echo "     • Samba-пакеты (apt purge)"
    echo "     • конфиги /etc/samba, /srv/samba"
    echo "     • пользователи samba-web, samba-user"
    echo "     • systemd-юнит, sudo-правила"
    echo "     • логи, бэкапы, /var/lib/samba"
    echo ""
else
    echo -e "${YELLOW}ℹ️  РЕЖИМ: МЯГКОЕ УДАЛЕНИЕ${NC}"
    echo "   Будут удалены:"
    echo "     • приложение /opt/samba-web-manager"
    echo "     • systemd-юнит, sudo-правила"
    echo "     • пользователи samba-web, samba-user"
    echo "     • конфиг /etc/samba/smb.conf"
    echo "     • шары /srv/samba"
    echo "   Samba-пакеты (apt) НЕ удаляются."
    echo ""
fi

if [ "$AUTO_YES" = false ]; then
    read -p "Продолжить? [y/N]: " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Отменено"
        exit 0
    fi
fi

echo ""
log "Начинаю удаление..."
echo ""

# ============================================================
# 1. ОСТАНОВКА ВСЕХ ПРОЦЕССОВ И СЕРВИСОВ
# ============================================================
echo "🛑 [1/9] Остановка сервисов и процессов..."

# systemd — все связанные сервисы
systemctl stop samba-web 2>/dev/null || true
systemctl disable samba-web 2>/dev/null || true
systemctl reset-failed samba-web 2>/dev/null || true

systemctl stop smbd 2>/dev/null || true
systemctl stop nmbd 2>/dev/null || true
systemctl stop winbind 2>/dev/null || true

# Отключаем автозапуск Samba
systemctl disable smbd 2>/dev/null || true
systemctl disable nmbd 2>/dev/null || true
systemctl disable winbind 2>/dev/null || true

# Все процессы, связанные с Samba
pkill -f "smbd" 2>/dev/null || true
pkill -f "nmbd" 2>/dev/null || true
pkill -f "winbindd" 2>/dev/null || true

# Наши процессы
pkill -f "gunicorn.*samba" 2>/dev/null || true
pkill -f "installer_app.py" 2>/dev/null || true
pkill -f "samba-web-manager" 2>/dev/null || true

# Освобождаем порты
fuser -k 5000/tcp 2>/dev/null || true
fuser -k 5001/tcp 2>/dev/null || true

sleep 2
ok "Сервисы остановлены, порты освобождены"

# ============================================================
# 2. УДАЛЕНИЕ SYSTEMD-ЮНИТА
# ============================================================
echo ""
echo "🗑️  [2/9] Удаление systemd-юнита..."
rm -f /etc/systemd/system/samba-web.service
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true
ok "systemd-юнит удалён"

# ============================================================
# 3. УДАЛЕНИЕ ПРИЛОЖЕНИЯ
# ============================================================
echo ""
echo "📁 [3/9] Удаление приложения..."
if [ -d /opt/samba-web-manager ]; then
    du -sh /opt/samba-web-manager 2>/dev/null || true
    rm -rf /opt/samba-web-manager
    ok "/opt/samba-web-manager удалён"
else
    warn "/opt/samba-web-manager не найден"
fi

# ============================================================
# 4. УДАЛЕНИЕ ПОЛЬЗОВАТЕЛЕЙ
# ============================================================
echo ""
echo "👤 [4/9] Удаление пользователей..."

for user in samba-web samba-user; do
    if id "$user" >/dev/null 2>&1; then
        pkill -u "$user" 2>/dev/null || true
        sleep 1
        userdel "$user" 2>/dev/null && ok "Пользователь $user удалён" || warn "Не удалось удалить $user"
    else
        warn "Пользователь $user не найден"
    fi
done

# ============================================================
# 5. УДАЛЕНИЕ SUDO-ПРАВИЛ
# ============================================================
echo ""
echo "🔒 [5/9] Удаление sudo-правил..."
rm -f /etc/sudoers.d/samba-web
ok "sudo-правила удалены"

# ============================================================
# 6. ОЧИСТКА SAMBA (конфиг + шары + БД)
# ============================================================
echo ""
echo "⚙️  [6/9] Очистка Samba-конфига, шар и баз..."

# Бэкап smb.conf (на всякий случай)
if [ -f /etc/samba/smb.conf ]; then
    mkdir -p /tmp/samba-backup-cleanup 2>/dev/null || true
    cp /etc/samba/smb.conf "/tmp/samba-backup-cleanup/smb.conf.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    ok "Бэкап smb.conf сохранён в /tmp/samba-backup-cleanup/"
fi

# Конфиги Samba
rm -f /etc/samba/smb.conf 2>/dev/null || true
rm -f /etc/samba/smbpasswd 2>/dev/null || true
rm -f /etc/samba/smbusers 2>/dev/null || true
rm -f /etc/samba/lmhosts 2>/dev/null || true

# База пользователей Samba
rm -f /var/lib/samba/private/passdb.tdb 2>/dev/null || true
rm -f /var/lib/samba/private/secrets.tdb 2>/dev/null || true
rm -f /var/lib/samba/private/schannel_store.tdb 2>/dev/null || true
rm -f /var/lib/samba/registry.tdb 2>/dev/null || true
rm -f /var/lib/samba/account_policy.tdb 2>/dev/null || true
rm -f /var/lib/samba/group_mapping.tdb 2>/dev/null || true
rm -f /var/lib/samba/share_info.tdb 2>/dev/null || true

ok "Samba-конфиги и БД очищены"

# Шары
if [ -d /srv/samba ]; then
    du -sh /srv/samba 2>/dev/null || true
    rm -rf /srv/samba
    ok "/srv/samba удалён"
else
    warn "/srv/samba не найден"
fi

# ============================================================
# 7. ОЧИСТКА ЛОГОВ И БЭКАПОВ
# ============================================================
echo ""
echo "🧹 [7/9] Очистка логов и бэкапов..."

rm -rf /var/log/samba-web-manager 2>/dev/null || true
rm -rf /var/backups/samba-web-manager 2>/dev/null || true
rm -rf /var/log/samba 2>/dev/null || true

ok "Логи и бэкапы очищены"

# ============================================================
# 8. SAMBA-ПАКЕТЫ И ОСТАТКИ
# ============================================================
echo ""
if [ "$PURGE" = true ]; then
    echo "📦 [8/9] Полное удаление Samba (пакеты + остатки)..."

    export DEBIAN_FRONTEND=noninteractive

    # Удаляем пакеты
    apt-get remove --purge -y -qq \
        samba samba-common samba-common-bin samba-libs samba-vfs-modules \
        smbclient cifs-utils libsmbclient libwbclient0 \
        winbind 2>/dev/null || true

    apt-get autoremove -y -qq 2>/dev/null || true
    apt-get autoclean -y -qq 2>/dev/null || true

    # Остатки от Samba (не удаляются apt purge)
    rm -rf /var/lib/samba 2>/dev/null || true
    rm -rf /var/cache/samba 2>/dev/null || true
    rm -rf /var/spool/samba 2>/dev/null || true
    rm -rf /etc/samba 2>/dev/null || true
    rm -rf /usr/lib/x86_64-linux-gnu/samba 2>/dev/null || true
    rm -rf /usr/lib/samba 2>/dev/null || true

    # systemd-юниты от Samba
    rm -f /lib/systemd/system/smbd.service 2>/dev/null || true
    rm -f /lib/systemd/system/nmbd.service 2>/dev/null || true
    rm -f /lib/systemd/system/winbind.service 2>/dev/null || true

    systemctl daemon-reload

    ok "Samba полностью удалена (пакеты + остатки)"
else
    echo "ℹ️  [8/9] Samba-пакеты НЕ удалены (используйте --soft)"
fi

# ============================================================
# 9. ФИНАЛЬНАЯ ПРОВЕРКА
# ============================================================
echo ""
echo "🔍 [9/9] Проверка чистоты системы..."
echo ""

FOUND=0

echo "  📌 Файлы и папки:"
for path in \
    /opt/samba-web-manager \
    /etc/systemd/system/samba-web.service \
    /etc/sudoers.d/samba-web \
    /etc/samba \
    /srv/samba \
    /var/lib/samba \
    /var/cache/samba \
    /var/log/samba-web-manager \
    /var/log/samba
do
    if [ -e "$path" ]; then
        echo -e "    ${RED}❌ $path${NC}"
        FOUND=$((FOUND + 1))
    else
        echo -e "    ${GREEN}✅ $path${NC}"
    fi
done

echo ""
echo "  📌 Пользователи:"
for user in samba-web samba-user; do
    if id "$user" >/dev/null 2>&1; then
        echo -e "    ${RED}❌ $user${NC}"
        FOUND=$((FOUND + 1))
    else
        echo -e "    ${GREEN}✅ $user — нет${NC}"
    fi
done

echo ""
echo "  📌 Порты:"
for port in 5000 5001; do
    if ss -tln 2>/dev/null | grep -q ":${port}"; then
        echo -e "    ${RED}❌ $port занят${NC}"
        FOUND=$((FOUND + 1))
    else
        echo -e "    ${GREEN}✅ $port свободен${NC}"
    fi
done

echo ""
echo "  📌 Сервисы:"
for svc in samba-web smbd nmbd winbind; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "    ${YELLOW}⚠️  $svc активен${NC}"
    else
        echo -e "    ${GREEN}✅ $svc неактивен${NC}"
    fi
done

echo ""
echo "  📌 Пакеты Samba:"
for pkg in samba samba-common-bin smbclient cifs-utils; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
        if [ "$PURGE" = true ]; then
            echo -e "    ${RED}❌ $pkg всё ещё установлен${NC}"
            FOUND=$((FOUND + 1))
        else
            echo -e "    ${YELLOW}⚠️  $pkg установлен (нормально без --purge)${NC}"
        fi
    else
        echo -e "    ${GREEN}✅ $pkg не установлен${NC}"
    fi
done

# ============================================================
# ИТОГ
# ============================================================
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
if [ $FOUND -eq 0 ]; then
    echo "║   ✅ СИСТЕМА ПОЛНОСТЬЮ ОЧИЩЕНА                           ║"
else
    printf "║   ⚠️  ОСТАЛОСЬ АРТЕФАКТОВ: %-3d                          ║\n" "$FOUND"
fi
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "📌 Что дальше:"
echo ""
echo "  1. Проверить чистоту:"
echo "     sudo bash check-clean.sh"
echo ""
echo "  2. Переустановить через веб-установщик:"
echo "     cd /path/to/samba-webmanager-install"
echo "     sudo python3 installer_app.py"
echo ""
echo "  3. Или bash-установщиком:"
echo "     cd /path/to/samba-web-manager"
echo "     sudo ./install.sh"
echo ""

if [ -d /tmp/samba-backup-cleanup ]; then
    echo "💾 Бэкапы smb.conf:"
    ls -la /tmp/samba-backup-cleanup/ 2>/dev/null | tail -n +2
    echo ""
fi
