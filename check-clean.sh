#!/bin/bash
# ============================================================
# check-clean.sh — проверка, что всё удалено
# ============================================================
# Запуск: sudo bash check-clean.sh
# ============================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║   🔍 ПРОВЕРКА ЧИСТОТЫ СИСТЕМЫ                            ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# ============================================================
# 1. ФАЙЛЫ И ПАПКИ
# ============================================================
echo -e "${CYAN}📌 [1/7] Файлы и папки${NC}"
echo ""

check_path() {
    local path="$1"
    local label="$2"
    if [ -e "$path" ]; then
        echo -e "  ${RED}❌ $label${NC}"
        echo -e "     $path — существует"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "  ${GREEN}✅ $label${NC}"
    fi
}

check_path "/opt/samba-web-manager"                    "Приложение"
check_path "/etc/systemd/system/samba-web.service"      "systemd-юнит"
check_path "/etc/sudoers.d/samba-web"                   "Sudo-правила"
check_path "/etc/samba/smb.conf"                        "Конфиг Samba"
check_path "/etc/samba/smbpasswd"                       "Samba-пароли"
check_path "/srv/samba"                                 "Общие папки"
check_path "/var/log/samba-web-manager"                 "Логи приложения"
check_path "/var/backups/samba-web-manager"             "Бэкапы приложения"

echo ""

# ============================================================
# 2. ПОЛЬЗОВАТЕЛИ
# ============================================================
echo -e "${CYAN}📌 [2/7] Пользователи${NC}"
echo ""

for user in samba-web samba-user; do
    if id "$user" >/dev/null 2>&1; then
        echo -e "  ${RED}❌ Пользователь $user${NC}"
        id "$user"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "  ${GREEN}✅ Пользователь $user — нет${NC}"
    fi
done

echo ""

# ============================================================
# 3. ПРОЦЕССЫ
# ============================================================
echo -e "${CYAN}📌 [3/7] Процессы${NC}"
echo ""

PROC_FOUND=0
for pattern in "gunicorn" "installer_app" "samba-web-manager" "samba_manager"; do
    PIDS=$(pgrep -f "$pattern" 2>/dev/null | tr '\n' ' ' || true)
    if [ -n "$PIDS" ]; then
        echo -e "  ${RED}❌ Процессы '$pattern': $PIDS${NC}"
        PROC_FOUND=$((PROC_FOUND + 1))
        ERRORS=$((ERRORS + 1))
    else
        echo -e "  ${GREEN}✅ Процессы '$pattern' — нет${NC}"
    fi
done

# Python-процессы
PY_PROC=$(pgrep -u samba-web 2>/dev/null | wc -l || echo 0)
if [ "$PY_PROC" -gt 0 ]; then
    echo -e "  ${YELLOW}⚠️  Процессы пользователя samba-web: $PY_PROC${NC}"
fi

echo ""

# ============================================================
# 4. ПОРТЫ
# ============================================================
echo -e "${CYAN}📌 [4/7] Порты${NC}"
echo ""

for port in 5000 5001; do
    LISTEN=$(ss -tln 2>/dev/null | grep -c ":${port}" || echo 0)
    if [ "$LISTEN" -gt 0 ]; then
        echo -e "  ${RED}❌ Порт $port — занят${NC}"
        ss -tlnp 2>/dev/null | grep ":${port}" | head -3
        ERRORS=$((ERRORS + 1))
    else
        echo -e "  ${GREEN}✅ Порт $port — свободен${NC}"
    fi
done

echo ""

# ============================================================
# 5. СЕРВИСЫ
# ============================================================
echo -e "${CYAN}📌 [5/7] Сервисы${NC}"
echo ""

for svc in samba-web smbd nmbd; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  ${YELLOW}⚠️  Сервис $svc — активен${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "  ${GREEN}✅ Сервис $svc — неактивен${NC}"
    fi
done

# Проверка, что юнит не зарегистрирован
if systemctl list-unit-files 2>/dev/null | grep -q "samba-web"; then
    echo -e "  ${RED}❌ Юнит samba-web всё ещё зарегистрирован${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "  ${GREEN}✅ Юнит samba-web — не зарегистрирован${NC}"
fi

echo ""

# ============================================================
# 6. ПАКЕТЫ
# ============================================================
echo -e "${CYAN}📌 [6/7] Пакеты${NC}"
echo ""

for pkg in samba samba-common-bin smbclient cifs-utils; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
        VERSION=$(dpkg -l "$pkg" 2>/dev/null | awk '/^ii/ {print $3}')
        echo -e "  ${YELLOW}⚠️  $pkg установлен ($VERSION)${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "  ${GREEN}✅ $pkg — не установлен${NC}"
    fi
done

echo ""

# ============================================================
# 7. ОСТАТКИ SAMBA
# ============================================================
echo -e "${CYAN}📌 [7/7] Остатки Samba${NC}"
echo ""

for path in \
    "/var/lib/samba" \
    "/var/cache/samba" \
    "/var/log/samba" \
    "/etc/samba" \
    "/var/spool/samba" \
    "/usr/lib/x86_64-linux-gnu/samba"
do
    if [ -e "$path" ]; then
        echo -e "  ${YELLOW}⚠️  $path — существует${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "  ${GREEN}✅ $path — нет${NC}"
    fi
done

# Пользователи Samba в pdbedit
if command -v pdbedit >/dev/null 2>&1; then
    SAMBA_USERS=$(pdbedit -L 2>/dev/null | wc -l || echo 0)
    if [ "$SAMBA_USERS" -gt 0 ]; then
        echo -e "  ${YELLOW}⚠️  Пользователей Samba: $SAMBA_USERS${NC}"
        pdbedit -L 2>/dev/null | head -5
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "  ${GREEN}✅ Пользователей Samba нет${NC}"
    fi
fi

echo ""

# ============================================================
# ИТОГ
# ============================================================
echo "═══════════════════════════════════════════════════════════"
echo -e "${CYAN}  📊 ИТОГОВЫЙ ОТЧЁТ${NC}"
echo "═══════════════════════════════════════════════════════════"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}║   ✅ СИСТЕМА ПОЛНОСТЬЮ ЧИСТА                             ║${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}║   Можно переустанавливать!                               ║${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                                                           ║${NC}"
    echo -e "${YELLOW}║   ⚠️  ЕСТЬ ПРЕДУПРЕЖДЕНИЯ: $WARNINGS${NC}"
    echo -e "${YELLOW}║                                                           ║${NC}"
    echo -e "${YELLOW}║   Можно переустанавливать, но проверьте пакеты.          ║${NC}"
    echo -e "${YELLOW}║                                                           ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
    exit 0
else
    echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                                           ║${NC}"
    echo -e "${RED}║   ❌ ОСТАЛИСЬ АРТЕФАКТЫ: $ERRORS${NC}"
    echo -e "${RED}║                                                           ║${NC}"
    echo -e "${RED}║   Переустановка может конфликтовать!                     ║${NC}"
    echo -e "${RED}║                                                           ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Что делать:"
    echo "  1. Запустите ещё раз: sudo bash full-cleanup.sh --purge --yes"
    echo "  2. Или удалите вручную найденные артефакты"
    echo ""
    exit 1
fi
