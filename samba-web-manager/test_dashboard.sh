#!/bin/bash
# ============================================================
# Samba Web Manager - Полный тест дашборда
# ============================================================
# Использование:
#   ./test_dashboard.sh                    # Тест localhost:5000
#   ./test_dashboard.sh 192.168.0.224      # Тест по IP
#   ./test_dashboard.sh 192.168.0.224 5000 # Тест IP:порт
# ============================================================

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

HOST="${1:-localhost}"
PORT="${2:-5000}"
BASE_URL="http://${HOST}:${PORT}"
COOKIE_JAR="/tmp/samba-web-cookies.txt"

# Читаем пароль из .env (если доступен)
USERNAME="admin"
PASSWORD="admin123"
ENV_FILE="/opt/samba-web-manager/.env"
if [ -f "$ENV_FILE" ]; then
    _U=$(grep '^ADMIN_USERNAME=' "$ENV_FILE" | cut -d= -f2- || true)
    _P=$(grep '^ADMIN_PASSWORD=' "$ENV_FILE" | cut -d= -f2- || true)
    [ -n "$_U" ] && USERNAME="$_U"
    [ -n "$_P" ] && PASSWORD="$_P"
fi

PASSED=0
FAILED=0
SKIPPED=0

log_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

test_pass() { echo -e "${GREEN}  ✅ $1${NC}"; PASSED=$((PASSED + 1)); }
test_fail() { echo -e "${RED}  ❌ $1${NC}"; [ -n "${2:-}" ] && echo -e "${RED}     → $2${NC}"; FAILED=$((FAILED + 1)); }
test_skip() { echo -e "${YELLOW}  ⏭️  $1${NC}"; SKIPPED=$((SKIPPED + 1)); }

check_response() {
    echo "$1" | grep -q "$2"
}

clear
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     🧪  Samba Web Manager - Тест дашборда                ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF

echo ""
echo "🌐 Целевой сервер: $BASE_URL"
echo "👤 Логин: $USERNAME"
echo "🔑 Пароль: ${PASSWORD:0:3}***"
echo ""

if ! command -v curl &>/dev/null; then
    echo "❌ curl не установлен. Установите: sudo apt install curl"
    exit 1
fi

rm -f "$COOKIE_JAR"

# ============================================================
# ТЕСТ 1: Health
# ============================================================
log_header "ТЕСТ 1: Healthcheck"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health" 2>/dev/null || echo "000")
if [ "$RESPONSE" = "200" ]; then
    test_pass "Health отвечает (HTTP $RESPONSE)"
else
    test_fail "Health не отвечает" "HTTP $RESPONSE"
    echo ""
    echo "Проверьте: sudo systemctl status samba-web"
    exit 1
fi

# ============================================================
# ТЕСТ 2: Страница логина
# ============================================================
log_header "ТЕСТ 2: Страница логина"
RESPONSE=$(curl -s "$BASE_URL/login")
if check_response "$RESPONSE" "login" || check_response "$RESPONSE" "form"; then
    test_pass "Страница /login отдаётся"
else
    test_fail "Страница /login не отдаётся"
fi

# ============================================================
# ТЕСТ 3: Логин
# ============================================================
log_header "ТЕСТ 3: Авторизация"
RESPONSE=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -X POST "$BASE_URL/login" \
    -d "username=$USERNAME&password=$PASSWORD" \
    -w "\n%{http_code}" --max-time 10)

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "200" ]; then
    if [ -f "$COOKIE_JAR" ] && grep -q "session" "$COOKIE_JAR"; then
        test_pass "Логин успешен (HTTP $HTTP_CODE, cookie получена)"
    else
        test_fail "Логин прошёл, но cookie НЕ сохранена" "SESSION_COOKIE_SECURE?"
    fi
else
    test_fail "Логин НЕ удался (HTTP $HTTP_CODE)" "Пароль из $ENV_FILE?"
fi

# ============================================================
# ТЕСТ 4: Дашборд
# ============================================================
log_header "ТЕСТ 4: Главная страница"
RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/")
if check_response "$RESPONSE" "Samba" || check_response "$RESPONSE" "ДАШБОРД"; then
    test_pass "Дашборд загружается"
else
    test_fail "Дашборд не загружается"
fi

# ============================================================
# ТЕСТ 5: API /api/status
# ============================================================
log_header "ТЕСТ 5: API - статус Samba"
RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/api/status")
if check_response "$RESPONSE" "active" || check_response "$RESPONSE" "status"; then
    test_pass "Статус получен"
else
    test_fail "API статуса не работает"
fi

# ============================================================
# ТЕСТ 6: API /api/shares
# ============================================================
log_header "ТЕСТ 6: API - список шар"
RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/api/shares")
if echo "$RESPONSE" | grep -qE "^\[|^\{"; then
    COUNT=$(echo "$RESPONSE" | grep -o '"name"' | wc -l)
    test_pass "Список шар получен ($COUNT)"
else
    test_fail "API шар не работает" "$RESPONSE"
fi

# ============================================================
# ТЕСТ 7: API /api/users
# ============================================================
log_header "ТЕСТ 7: API - список пользователей"
RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/api/users")
if echo "$RESPONSE" | grep -qE "^\[|^\{"; then
    COUNT=$(echo "$RESPONSE" | grep -o '"username"' | wc -l)
    test_pass "Список пользователей получен ($COUNT)"
else
    test_fail "API пользователей не работает"
fi

# ============================================================
# ТЕСТ 8: API /api/system/info + disks
# ============================================================
log_header "ТЕСТ 8: API - системная информация + диски"
RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/api/system/info")
if check_response "$RESPONSE" "cpu" && check_response "$RESPONSE" "memory"; then
    test_pass "Системная информация получена"
    if check_response "$RESPONSE" "total_disks"; then
        COUNT=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('mounted_disks', [])))" 2>/dev/null || echo "?")
        test_pass "Диски в /api/system/info ($COUNT смонтировано)"
    else
        test_fail "Поле total_disks отсутствует" "Обновите app.py"
    fi
else
    test_skip "API системной информации недоступен"
fi

# ============================================================
# ТЕСТ 9: API /api/disks
# ============================================================
log_header "ТЕСТ 9: API - диски"
RESPONSE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/api/disks")
if check_response "$RESPONSE" "total_disks"; then
    test_pass "API дисков работает"
else
    test_fail "API дисков не работает"
fi

# ============================================================
# ТЕСТ 10: Создание шары
# ============================================================
log_header "ТЕСТ 10: Создание тестовой шары"
SHARE_NAME="test_share_$(date +%s)"
SHARE_PATH="/tmp/samba_test_$$"
mkdir -p "$SHARE_PATH"
chmod 777 "$SHARE_PATH"

RESPONSE=$(curl -s -b "$COOKIE_JAR" -X POST "$BASE_URL/api/shares" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$SHARE_NAME\",\"path\":\"$SHARE_PATH\",\"read_only\":false,\"guest_ok\":true,\"comment\":\"Test\"}" \
    --max-time 15)

if check_response "$RESPONSE" "$SHARE_NAME" || check_response "$RESPONSE" "создана"; then
    test_pass "Шара '$SHARE_NAME' создана"
    sleep 1
    if sudo grep -q "\[$SHARE_NAME\]" /etc/samba/smb.conf 2>/dev/null; then
        test_pass "Шара в /etc/samba/smb.conf"
    else
        test_fail "Шара НЕ в /etc/samba/smb.conf"
    fi
else
    test_fail "Шара не создана" "$RESPONSE"
fi

# ============================================================
# ТЕСТ 11: Удаление шары
# ============================================================
log_header "ТЕСТ 11: Удаление шары"
RESPONSE=$(curl -s -b "$COOKIE_JAR" -X DELETE "$BASE_URL/api/shares/$SHARE_NAME" --max-time 15)
if check_response "$RESPONSE" "удалена" || check_response "$RESPONSE" "message"; then
    test_pass "Шара удалена"
    sleep 1
    if sudo grep -q "\[$SHARE_NAME\]" /etc/samba/smb.conf 2>/dev/null; then
        test_fail "Шара ВСЁ ЕЩЁ в smb.conf"
    else
        test_pass "Шара удалена из smb.conf"
    fi
else
    test_fail "Шара не удалена"
fi
rm -rf "$SHARE_PATH"

# ============================================================
# ТЕСТ 12: Создание пользователя
# ============================================================
log_header "ТЕСТ 12: Создание тестового пользователя"
TEST_USER="testuser_$(date +%s)"
TEST_PASS="TestPass123"

RESPONSE=$(curl -s -b "$COOKIE_JAR" -X POST "$BASE_URL/api/users" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$TEST_USER\",\"password\":\"$TEST_PASS\"}" --max-time 15)

if check_response "$RESPONSE" "$TEST_USER" || check_response "$RESPONSE" "добавлен"; then
    test_pass "Пользователь '$TEST_USER' создан"
    sleep 1
    if sudo pdbedit -L 2>/dev/null | grep -q "^$TEST_USER:"; then
        test_pass "Пользователь в Samba (pdbedit)"
    else
        test_fail "Пользователь НЕ в Samba"
    fi
else
    test_fail "Пользователь не создан"
fi

# ============================================================
# ТЕСТ 13: Смена пароля
# ============================================================
log_header "ТЕСТ 13: Смена пароля"
RESPONSE=$(curl -s -b "$COOKIE_JAR" -X POST "$BASE_URL/api/users/$TEST_USER/password" \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"NewPass456\"}" --max-time 15)

if check_response "$RESPONSE" "изменен" || check_response "$RESPONSE" "message"; then
    test_pass "Пароль изменён"
else
    test_fail "Пароль не изменён"
fi

# ============================================================
# ТЕСТ 14: Удаление пользователя
# ============================================================
log_header "ТЕСТ 14: Удаление пользователя"
RESPONSE=$(curl -s -b "$COOKIE_JAR" -X DELETE "$BASE_URL/api/users/$TEST_USER" --max-time 15)
if check_response "$RESPONSE" "удален" || check_response "$RESPONSE" "message"; then
    test_pass "Пользователь удалён"
    sleep 1
    if sudo pdbedit -L 2>/dev/null | grep -q "^$TEST_USER:"; then
        test_fail "Пользователь ВСЁ ЕЩЁ в Samba"
    else
        test_pass "Пользователь удалён из Samba"
    fi
else
    test_fail "Пользователь не удалён"
fi

# ============================================================
# ТЕСТ 15: Все HTML-страницы
# ============================================================
log_header "ТЕСТ 15: HTML страницы"
PAGES=(
    "/:Дашборд"
    "/shares:Шары"
    "/users:Пользователи"
    "/disks:Диски"
    "/backups:Бэкапы"
    "/logs:Логи"
    "/monitoring:Мониторинг"
)

for page in "${PAGES[@]}"; do
    URL=$(echo "$page" | cut -d: -f1)
    NAME=$(echo "$page" | cut -d: -f2)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" "$BASE_URL$URL")

    if [ "$HTTP_CODE" = "200" ]; then
        test_pass "Страница $NAME ($URL) → HTTP $HTTP_CODE"
    elif [ "$HTTP_CODE" = "302" ]; then
        test_skip "Страница $NAME ($URL) → редирект"
    else
        test_fail "Страница $NAME ($URL) → HTTP $HTTP_CODE"
    fi
done

# ============================================================
# ТЕСТ 16: Выход и защита API
# ============================================================
log_header "ТЕСТ 16: Logout + защита API"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" "$BASE_URL/logout")
if [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "200" ]; then
    test_pass "Выход работает (HTTP $HTTP_CODE)"
else
    test_fail "Выход не работает"
fi

rm -f "$COOKIE_JAR"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/shares")

if [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
    test_pass "После выхода API защищён (HTTP $HTTP_CODE)"
else
    test_fail "После выхода API доступен (HTTP $HTTP_CODE)"
fi

# ============================================================
# ИТОГ
# ============================================================
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  📊 ИТОГОВЫЙ ОТЧЁТ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}✅ Пройдено:${NC}   $PASSED"
echo -e "  ${RED}❌ Провалено:${NC}  $FAILED"
echo -e "  ${YELLOW}⏭️  Пропущено:${NC}  $SKIPPED"
echo -e "  ${BLUE}📊 Всего:${NC}      $((PASSED + FAILED + SKIPPED))"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}🎉 Все тесты пройдены!${NC}"
    exit 0
else
    echo -e "${RED}⚠️  Есть проблемы! Проверьте логи выше.${NC}"
    exit 1
fi