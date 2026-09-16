#!/bin/bash
# ============================================================
# Samba Web Manager - Проверка установки
# ============================================================
# Использование: sudo ./check_installation.sh
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   🔍 Проверка установки Samba Web Manager               ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

errors=0
warnings=0

check() {
    local label="$1"
    local result="$2"
    local extra="${3:-}"
    if [ "$result" = "ok" ]; then
        echo -e "${GREEN}✅${NC} $label ${extra}"
    elif [ "$result" = "warn" ]; then
        echo -e "${YELLOW}⚠️ ${NC} $label ${extra}"
        warnings=$((warnings + 1))
    else
        echo -e "${RED}❌${NC} $label ${extra}"
        errors=$((errors + 1))
    fi
}

# 1. Python
if command -v python3 &>/dev/null; then
    check "Python3" ok "$(python3 --version)"
else
    check "Python3" err "не установлен"
fi

# 2. Samba
if command -v smbd &>/dev/null; then
    check "Samba" ok "$(smbd --version 2>&1 | head -1)"
else
    check "Samba" err "не установлена"
fi

# 3. smb.conf
if [ -f /etc/samba/smb.conf ]; then
    check "/etc/samba/smb.conf" ok "существует"
else
    check "/etc/samba/smb.conf" err "отсутствует"
fi

# 4. Права на smb.conf
if [ -w /etc/samba/smb.conf ] 2>/dev/null; then
    check "Права на smb.conf" ok
else
    check "Права на smb.conf" warn "нет прав на запись"
fi

# 5. venv
if [ -d /opt/samba-web-manager/venv ]; then
    check "venv" ok "/opt/samba-web-manager/venv"
else
    check "venv" err "не создан"
fi

# 6. Зависимости в venv
if [ -f /opt/samba-web-manager/venv/bin/python ]; then
    for pkg in Flask gunicorn gevent psutil bcrypt python-dotenv; do
        if /opt/samba-web-manager/venv/bin/pip show "$pkg" >/dev/null 2>&1; then
            check "  $pkg" ok
        else
            check "  $pkg" err "не установлен"
        fi
    done
fi

# 7. Сервис
if systemctl is-active --quiet samba-web 2>/dev/null; then
    check "Сервис samba-web" ok "запущен"
else
    check "Сервис samba-web" err "не запущен"
fi

# 8. Порт (из .env)
PORT=5000
if [ -f /opt/samba-web-manager/.env ]; then
    PORT_FROM_ENV=$(grep '^PORT=' /opt/samba-web-manager/.env | cut -d= -f2- || echo "5000")
    PORT="${PORT_FROM_ENV:-5000}"
fi
if ss -tln 2>/dev/null | grep -q ":${PORT}"; then
    check "Порт $PORT" ok "слушается"
else
    check "Порт $PORT" err "не слушается"
fi

# 9. Health
if command -v curl &>/dev/null; then
    if curl -s --max-time 3 "http://localhost:${PORT}/health" | grep -q '"status":"ok"'; then
        check "Healthcheck /health" ok
    else
        check "Healthcheck /health" err
    fi
fi

# 10. .env
if [ -f /opt/samba-web-manager/.env ]; then
    if grep -q '^SECRET_KEY=' /opt/samba-web-manager/.env; then
        check ".env SECRET_KEY" ok
    else
        check ".env SECRET_KEY" err "не задан"
    fi
    if grep -q '^ADMIN_PASSWORD=' /opt/samba-web-manager/.env; then
        check ".env ADMIN_PASSWORD" ok
    else
        check ".env ADMIN_PASSWORD" warn "не задан"
    fi
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
    echo -e "${GREEN}🎉 Все проверки пройдены!${NC}"
    exit 0
elif [ $errors -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Есть предупреждения: $warnings${NC}"
    exit 0
else
    echo -e "${RED}❌ Ошибок: $errors, предупреждений: $warnings${NC}"
    echo ""
    echo "Рекомендации:"
    echo "  - Проверьте: sudo journalctl -u samba-web -n 30"
    echo "  - Переустановите: sudo ./install.sh"
    exit 1
fi