#!/bin/bash
# ============================================================
# Samba Web Manager - Удаление
# ============================================================
# Использование:
#   ./uninstall.sh            — мягкое удаление (интерактивно)
#   ./uninstall.sh --full     — полное удаление (интерактивно)
#   ./uninstall.sh --yes      — без подтверждений
#   ./uninstall.sh --full --yes
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}" >&2; }

if [ "$EUID" -ne 0 ]; then
    err "Запустите с sudo"
    exit 1
fi

APP_DIR="/opt/samba-web-manager"
SERVICE_NAME="samba-web"
SERVICE_USER="samba-web"

FULL_MODE=false
AUTO_YES=false

for arg in "$@"; do
    case $arg in
        --full) FULL_MODE=true ;;
        --yes|-y) AUTO_YES=true ;;
        *) err "Неизвестный аргумент: $arg"; exit 1 ;;
    esac
done

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       🗑️  Удаление Samba Web Manager                     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

if [ "$FULL_MODE" = true ]; then
    echo "⚠️  РЕЖИМ: ПОЛНОЕ УДАЛЕНИЕ"
    echo "   Будут удалены: приложение, Samba, конфиги, файлы"
    echo ""
    if [ "$AUTO_YES" = false ]; then
        read -p "Введите 'DELETE' для подтверждения: " confirm
        if [ "$confirm" != "DELETE" ]; then
            echo "Отменено"
            exit 0
        fi
    fi
else
    echo "ℹ️  РЕЖИМ: МЯГКОЕ УДАЛЕНИЕ"
    echo "   Сохранятся: /etc/samba/smb.conf, /srv/samba"
    echo ""
    if [ "$AUTO_YES" = false ]; then
        read -p "Продолжить? [y/N]: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Отменено"
            exit 0
        fi
    fi
fi

echo ""
echo "🛑 [1/5] Остановка сервиса..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true
systemctl disable "$SERVICE_NAME" 2>/dev/null || true
ok

echo "🗑️  [2/5] Удаление systemd сервиса..."
rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true
ok

echo "📁 [3/5] Удаление приложения..."
rm -rf "$APP_DIR"
rm -rf /var/log/samba-web-manager 2>/dev/null || true
rm -rf /var/backups/samba-web-manager 2>/dev/null || true
ok

echo "👤 [4/5] Удаление пользователя..."
userdel "$SERVICE_USER" 2>/dev/null || true
ok

echo "🔒 [5/5] Удаление sudo-правил..."
rm -f /etc/sudoers.d/samba-web
ok

if [ "$FULL_MODE" = true ]; then
    echo ""
    echo "⚠️  Удаление Samba..."
    systemctl stop smbd nmbd 2>/dev/null || true
    systemctl disable smbd nmbd 2>/dev/null || true

    apt-get remove --purge -y samba samba-common-bin smbclient cifs-utils 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true

    echo "📁 Удаление данных..."
    rm -rf /etc/samba
    rm -rf /srv/samba
    rm -rf /var/log/samba
    ok
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       ✅ Удаление завершено                              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

if [ "$FULL_MODE" = false ]; then
    echo "💡 Сохранены:"
    echo "   - /etc/samba/smb.conf"
    echo "   - /srv/samba/"
    echo ""
    echo "Для полного удаления: sudo ./uninstall.sh --full"
fi