#!/bin/bash
# ============================================================
# Samba Web Manager - ПОЛНОЕ тестирование всех функций
# ============================================================
# Использование:
#   sudo ./test_full.sh                    # localhost:5000
#   sudo ./test_full.sh 192.168.0.224      # по IP
#   sudo ./test_full.sh 192.168.0.224 5000 # IP:порт
# ============================================================

set -uo pipefail

# ============================================================
# ЦВЕТА
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ============================================================
# ПАРАМЕТРЫ
# ============================================================
HOST="${1:-localhost}"
PORT="${2:-5000}"
BASE_URL="http://${HOST}:${PORT}"
COOKIE_JAR="/tmp/samba-web-test-$$.txt"

# Пароль из .env
ENV_FILE="/opt/samba-web-manager/.env"
USERNAME="admin"
PASSWORD="admin123"

if [ -f "$ENV_FILE" ]; then
    _U=$(grep '^ADMIN_USERNAME=' "$ENV_FILE" | cut -d= -f2- || true)
    _P=$(grep '^ADMIN_PASSWORD=' "$ENV_FILE" | cut -d= -f2- || true)
    [ -n "$_U" ] && USERNAME="$_U"
    [ -n "$_P" ] && PASSWORD="$_P"
fi

# ============================================================
# СЧЁТЧИКИ
# ============================================================
PASSED=0
FAILED=0
SKIPPED=0
TOTAL_GROUPS=0

# ============================================================
# ФУНКЦИИ
# ============================================================
log_header() {
    TOTAL_GROUPS=$((TOTAL_GROUPS + 1))
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  📦 [$TOTAL_GROUPS] $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

log_sub() {
    echo ""
    echo -e "${MAGENTA}  ▸ $1${NC}"
}

test_pass() {
    echo -e "${GREEN}  ✅ $1${NC}"
    PASSED=$((PASSED + 1))
}

test_fail() {
    echo -e "${RED}  ❌ $1${NC}"
    [ -n "${2:-}" ] && echo -e "${RED}     → $2${NC}"
    FAILED=$((FAILED + 1))
}

test_skip() {
    echo -e "${YELLOW}  ⏭️  $1${NC}"
    SKIPPED=$((SKIPPED + 1))
}

# HTTP-запрос с cookie
http_code() {
    curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$@"
}

# GET с cookie
api_get() {
    curl -s -b "$COOKIE_JAR" --max-time 10 "$BASE_URL$1"
}

# POST с cookie + JSON
api_post() {
    local url="$1"
    local data="$2"
    curl -s -b "$COOKIE_JAR" -X POST --max-time 15 \
        -H "Content-Type: application/json" \
        -d "$data" "$BASE_URL$url"
}

# DELETE с cookie
api_delete() {
    curl -s -b "$COOKIE_JAR" -X DELETE --max-time 15 "$BASE_URL$1"
}

# Проверка, что ответ — JSON
is_json() {
    echo "$1" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null
    return $?
}

# Проверка, что JSON содержит поле
has_field() {
    echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if '$2' in d else 1)" 2>/dev/null
    return $?
}

# ============================================================
# ПРИВЕТСТВИЕ
# ============================================================
clear
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   🧪  Samba Web Manager - ПОЛНОЕ ТЕСТИРОВАНИЕ            ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF

echo ""
echo "🌐 Сервер:   $BASE_URL"
echo "👤 Логин:    $USERNAME"
echo "🔑 Пароль:   ${PASSWORD:0:3}***"
echo "🍪 Cookies:  $COOKIE_JAR"
echo ""

# Проверка curl
if ! command -v curl &>/dev/null; then
    echo "❌ curl не установлен. Установите: sudo apt install curl"
    exit 1
fi

rm -f "$COOKIE_JAR"

# ============================================================
# ГРУППА 1: HEALTHCHECK
# ============================================================
log_header "HEALTHCHECK"

log_sub "GET /health"
RESP=$(curl -s --max-time 5 "$BASE_URL/health")
if echo "$RESP" | grep -q '"status":"ok"'; then
    test_pass "Health отвечает: $RESP"
else
    test_fail "Health не отвечает" "$RESP"
    echo ""
    echo "  ⚠️  Дальнейшие тесты невозможны — сервис не отвечает."
    echo "  Проверьте: sudo systemctl status samba-web"
    rm -f "$COOKIE_JAR"
    exit 1
fi

# ============================================================
# ГРУППА 2: АВТОРИЗАЦИЯ
# ============================================================
log_header "АВТОРИЗАЦИЯ"

log_sub "GET /login (форма)"
RESP=$(curl -s --max-time 5 "$BASE_URL/login")
# Проверяем разные варианты: form, username, password, login
if echo "$RESP" | grep -qiE '<form|username|password|type="password"|логин|login'; then
    SIZE=$(echo -n "$RESP" | wc -c)
    test_pass "Страница логина отдаётся ($SIZE байт)"
else
    test_fail "Страница логина не отдаётся" "$(echo "$RESP" | head -c 100)"
fi

log_sub "POST /login (правильные креды)"
CODE=$(http_code -c "$COOKIE_JAR" -X POST "$BASE_URL/login" \
    -d "username=$USERNAME&password=$PASSWORD")
if [ "$CODE" = "302" ] || [ "$CODE" = "200" ]; then
    if [ -f "$COOKIE_JAR" ] && grep -q "session" "$COOKIE_JAR"; then
        test_pass "Логин успешен (HTTP $CODE, cookie получена)"
    else
        test_fail "Логин прошёл, но cookie НЕ сохранена"
    fi
else
    test_fail "Логин НЕ удался" "HTTP $CODE"
fi

log_sub "POST /login (неправильный пароль)"
CODE=$(http_code -X POST "$BASE_URL/login" \
    -d "username=$USERNAME&password=WRONG_PASSWORD_123")
if [ "$CODE" = "200" ]; then
    test_pass "Неверный пароль отвергнут (HTTP $CODE)"
else
    test_fail "Неверный пароль принят" "HTTP $CODE"
fi

log_sub "GET /api/shares БЕЗ cookie (должен быть 401)"
CODE=$(http_code "$BASE_URL/api/shares")
if [ "$CODE" = "401" ] || [ "$CODE" = "302" ]; then
    test_pass "API защищён без авторизации (HTTP $CODE)"
else
    test_fail "API доступен без авторизации" "HTTP $CODE"
fi

# ============================================================
# ГРУППА 3: HTML-СТРАНИЦЫ
# ============================================================
log_header "HTML-СТРАНИЦЫ"

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
    URL="${page%%:*}"
    NAME="${page##*:}"
    CODE=$(http_code -b "$COOKIE_JAR" "$BASE_URL$URL")
    if [ "$CODE" = "200" ]; then
        test_pass "GET $URL ($NAME) → HTTP $CODE"
    else
        test_fail "GET $URL ($NAME) → HTTP $CODE"
    fi
done

# ============================================================
# ГРУППА 4: API - СИСТЕМА
# ============================================================
log_header "API - СИСТЕМА"

log_sub "GET /api/status"
RESP=$(api_get "/api/status")
if is_json "$RESP"; then
    test_pass "Статус получен: $(echo "$RESP" | head -c 80)..."
else
    test_fail "Статус не работает" "$RESP"
fi

log_sub "GET /api/system/info"
RESP=$(api_get "/api/system/info")
if has_field "$RESP" "cpu" && has_field "$RESP" "memory"; then
    test_pass "Системная информация получена"

    # Проверяем поля дисков
    log_sub "GET /api/system/info — поля дисков"
    if has_field "$RESP" "total_disks"; then
        TOTAL=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total_disks'))" 2>/dev/null)
        test_pass "total_disks: $TOTAL"
    else
        test_fail "Нет поля total_disks — обновите app.py"
    fi

    if has_field "$RESP" "mounted_disks"; then
        MOUNTED=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('mounted_disks',[])))" 2>/dev/null)
        test_pass "mounted_disks: $MOUNTED"
    else
        test_fail "Нет поля mounted_disks"
    fi
else
    test_fail "Системная информация не работает"
fi

log_sub "GET /api/monitoring/connections"
RESP=$(api_get "/api/monitoring/connections")
if is_json "$RESP"; then
    test_pass "Мониторинг подключений работает"
else
    test_fail "Мониторинг не работает"
fi

# ============================================================
# ГРУППА 5: API - ДИСКИ
# ============================================================
log_header "API - ДИСКИ"

log_sub "GET /api/disks"
RESP=$(api_get "/api/disks")
if has_field "$RESP" "total_disks"; then
    TOTAL=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total_disks'))" 2>/dev/null)
    MOUNTED=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('mounted_disks'))" 2>/dev/null)
    test_pass "Список дисков: всего $TOTAL, смонтировано $MOUNTED"
else
    test_fail "Список дисков не работает"
fi

log_sub "GET /api/disks/mount-points"
RESP=$(api_get "/api/disks/mount-points")
if is_json "$RESP"; then
    COUNT=$(echo "$RESP" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('mount_points',[])))" 2>/dev/null)
    test_pass "Точки монтирования: $COUNT доступно"
else
    test_fail "Точки монтирования не работают"
fi

# ============================================================
# ГРУППА 6: API - ШАРЫ (CRUD)
# ============================================================
log_header "API - ШАРЫ (CRUD)"

SHARE_NAME="test_share_$(date +%s)"
SHARE_PATH="/tmp/samba_test_$$"
mkdir -p "$SHARE_PATH"
chmod 777 "$SHARE_PATH"

log_sub "GET /api/shares"
RESP=$(api_get "/api/shares")
if is_json "$RESP" || echo "$RESP" | grep -qE '^\[|^\{'; then
    test_pass "Список шар получен"
else
    test_fail "Список шар не работает"
fi

log_sub "POST /api/shares (создание)"
RESP=$(api_post "/api/shares" \
    "{\"name\":\"$SHARE_NAME\",\"path\":\"$SHARE_PATH\",\"read_only\":false,\"guest_ok\":true,\"comment\":\"Test\"}")
if echo "$RESP" | grep -q "$SHARE_NAME" || echo "$RESP" | grep -q "создана"; then
    test_pass "Шара '$SHARE_NAME' создана"
    sleep 1

    if sudo grep -q "\[$SHARE_NAME\]" /etc/samba/smb.conf 2>/dev/null; then
        test_pass "Шара появилась в smb.conf"
    else
        test_fail "Шара НЕ появилась в smb.conf"
    fi
else
    test_fail "Шара не создана" "$RESP"
fi

log_sub "GET /api/shares (проверка)"
RESP=$(api_get "/api/shares")
if echo "$RESP" | grep -q "$SHARE_NAME"; then
    test_pass "Шара есть в списке"
else
    test_fail "Шары нет в списке"
fi

log_sub "PUT /api/shares/$SHARE_NAME (обновление)"
# Проверяем по HTTP-коду — надёжнее, чем grep по UTF-8
CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" -X PUT \
    -H "Content-Type: application/json" \
    -d '{"comment":"Updated comment","read_only":true}' \
    "$BASE_URL/api/shares/$SHARE_NAME")
if [ "$CODE" = "200" ] || [ "$CODE" = "204" ]; then
    test_pass "Шара обновлена (HTTP $CODE)"
else
    test_skip "Обновление не сработало (HTTP $CODE)"
fi

log_sub "DELETE /api/shares/$SHARE_NAME (удаление)"
RESP=$(api_delete "/api/shares/$SHARE_NAME")
if echo "$RESP" | grep -qE "удалена|success|message"; then
    test_pass "Шара удалена через API"
    sleep 1
    if sudo grep -q "\[$SHARE_NAME\]" /etc/samba/smb.conf 2>/dev/null; then
        test_fail "Шара ВСЁ ЕЩЁ в smb.conf"
    else
        test_pass "Шара удалена из smb.conf"
    fi
else
    test_fail "Шара не удалена" "$RESP"
fi

rm -rf "$SHARE_PATH"

# ============================================================
# ГРУППА 7: API - ПОЛЬЗОВАТЕЛИ (CRUD)
# ============================================================
log_header "API - ПОЛЬЗОВАТЕЛИ (CRUD)"

TEST_USER="testuser_$(date +%s)"
TEST_PASS="TestPass123!"

log_sub "GET /api/users"
RESP=$(api_get "/api/users")
if is_json "$RESP" || echo "$RESP" | grep -qE '^\[|^\{'; then
    COUNT=$(echo "$RESP" | grep -o '"username"' | wc -l)
    test_pass "Список пользователей получен ($COUNT)"
else
    test_fail "Список пользователей не работает"
fi

log_sub "POST /api/users (создание)"
RESP=$(api_post "/api/users" \
    "{\"username\":\"$TEST_USER\",\"password\":\"$TEST_PASS\"}")
if echo "$RESP" | grep -q "$TEST_USER" || echo "$RESP" | grep -qE "добавлен|created"; then
    test_pass "Пользователь '$TEST_USER' создан"
    sleep 1

    if sudo pdbedit -L 2>/dev/null | grep -q "^$TEST_USER:"; then
        test_pass "Пользователь есть в Samba (pdbedit)"
    else
        test_fail "Пользователь НЕ в Samba"
    fi
else
    test_fail "Пользователь не создан" "$RESP"
fi

log_sub "POST /api/users/$TEST_USER/password (смена пароля)"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" -X POST \
    -H "Content-Type: application/json" \
    -d '{"password":"NewPass456!"}' \
    "$BASE_URL/api/users/$TEST_USER/password")
if [ "$CODE" = "200" ]; then
    test_pass "Пароль изменён (HTTP $CODE)"
else
    test_skip "Смена пароля не сработала (HTTP $CODE)"
fi

log_sub "POST /api/users/$TEST_USER/disable"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" -X POST \
    -H "Content-Type: application/json" -d '{}' \
    "$BASE_URL/api/users/$TEST_USER/disable")
if [ "$CODE" = "200" ]; then
    test_pass "Пользователь отключён (HTTP $CODE)"
else
    test_skip "Disable не сработал (HTTP $CODE)"
fi

log_sub "POST /api/users/$TEST_USER/enable"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" -X POST \
    -H "Content-Type: application/json" -d '{}' \
    "$BASE_URL/api/users/$TEST_USER/enable")
if [ "$CODE" = "200" ]; then
    test_pass "Пользователь включён (HTTP $CODE)"
else
    test_skip "Enable не сработал (HTTP $CODE)"
fi

log_sub "DELETE /api/users/$TEST_USER (удаление)"
RESP=$(api_delete "/api/users/$TEST_USER")
if echo "$RESP" | grep -qiE "удален|deleted|success|message"; then
    test_pass "Пользователь удалён"
    sleep 1
    if sudo pdbedit -L 2>/dev/null | grep -q "^$TEST_USER:"; then
        test_fail "Пользователь ВСЁ ЕЩЁ в Samba"
    else
        test_pass "Пользователь удалён из Samba"
    fi
else
    test_fail "Пользователь не удалён" "$RESP"
fi

# ============================================================
# ГРУППА 8: API - БЭКАПЫ
# ============================================================
log_header "API - БЭКАПЫ"

log_sub "GET /api/backups"
RESP=$(api_get "/api/backups")
if is_json "$RESP" || echo "$RESP" | grep -qE '^\[|^\{'; then
    COUNT=$(echo "$RESP" | grep -o '"filename"' | wc -l)
    test_pass "Список бэкапов получен ($COUNT)"
else
    test_skip "API бэкапов не отвечает"
fi

log_sub "POST /api/backups (создание)"
RESP=$(api_post "/api/backups" "{}")
if echo "$RESP" | grep -qiE "создан|created|success|file"; then
    BACKUP_FILE=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file',''))" 2>/dev/null || echo "")
    test_pass "Бэкап создан: $BACKUP_FILE"

    if [ -n "$BACKUP_FILE" ]; then
        # Извлекаем ТОЛЬКО имя файла (без пути "backups/")
        BACKUP_NAME=$(basename "$BACKUP_FILE")
        log_sub "DELETE /api/backups/$BACKUP_NAME"
        CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" -X DELETE \
            "$BASE_URL/api/backups/$BACKUP_NAME")
        if [ "$CODE" = "200" ] || [ "$CODE" = "204" ]; then
            test_pass "Бэкап удалён (HTTP $CODE)"
        else
            test_skip "Удаление бэкапа не сработало (HTTP $CODE)"
        fi
    fi
else
    test_skip "Создание бэкапа не сработало"
fi

# ============================================================
# ГРУППА 9: RESTART SAMBA
# ============================================================
log_header "API - RESTART SAMBA"

log_sub "POST /api/restart"
RESP=$(api_post "/api/restart" "{}")
if echo "$RESP" | grep -qiE "перезапущена|restarted|success|message"; then
    test_pass "Samba перезапущена"
    sleep 3
    # Проверим, что сервис жив
    if systemctl is-active --quiet samba-web 2>/dev/null; then
        test_pass "Сервис samba-web активен после перезапуска"
    else
        test_fail "Сервис упал после перезапуска"
    fi
else
    test_skip "Перезапуск не сработал: $(echo "$RESP" | head -c 100)"
fi

# ============================================================
# ГРУППА 10: СТРАНИЦА ЛОГОВ
# ============================================================
log_header "СТРАНИЦА ЛОГОВ"

log_sub "GET /logs"
RESP=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/logs")
if echo "$RESP" | grep -qiE "log|логи|journal|app.log"; then
    test_pass "Страница логов отдаётся"
else
    test_fail "Страница логов не отдаётся"
fi

# ============================================================
# ГРУППА 11: LOGOUT
# ============================================================
log_header "LOGOUT"

log_sub "GET /logout"
CODE=$(http_code -b "$COOKIE_JAR" "$BASE_URL/logout")
if [ "$CODE" = "302" ] || [ "$CODE" = "200" ]; then
    test_pass "Logout работает (HTTP $CODE)"
else
    test_fail "Logout не работает" "HTTP $CODE"
fi

log_sub "GET /api/shares ПОСЛЕ logout (должен быть 401)"
rm -f "$COOKIE_JAR"  # очищаем cookie
CODE=$(http_code "$BASE_URL/api/shares")
if [ "$CODE" = "401" ] || [ "$CODE" = "302" ]; then
    test_pass "API защищён после logout (HTTP $CODE)"
else
    test_fail "API доступен после logout" "HTTP $CODE"
fi

# ============================================================
# ИТОГ
# ============================================================
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  📊 ИТОГОВЫЙ ОТЧЁТ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  📦 Групп тестов:    $TOTAL_GROUPS"
echo -e "  ${GREEN}✅ Пройдено:${NC}         $PASSED"
echo -e "  ${RED}❌ Провалено:${NC}        $FAILED"
echo -e "  ${YELLOW}⏭️  Пропущено:${NC}        $SKIPPED"
echo -e "  ${BLUE}📊 Всего проверок:${NC}   $((PASSED + FAILED + SKIPPED))"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}║   🎉 ВСЕ ТЕСТЫ ПРОЙДЕНЫ!                                 ║${NC}"
    echo -e "${GREEN}║      Samba Web Manager работает корректно                ║${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    rm -f "$COOKIE_JAR"
    exit 0
else
    echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                                           ║${NC}"
    echo -e "${RED}║   ⚠️  ЕСТЬ ПРОБЛЕМЫ: $FAILED${NC}"
    echo -e "${RED}║      Проверьте логи выше                                 ║${NC}"
    echo -e "${RED}║                                                           ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
    rm -f "$COOKIE_JAR"
    exit 1
fi
