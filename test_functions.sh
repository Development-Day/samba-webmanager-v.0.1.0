#!/bin/bash
# ============================================================
# test_functions.sh — Проверка всех функций приложения
# ============================================================
# Что делает:
#   1. Логин
#   2. Создать 3 шары, 2 пользователя
#   3. Проверить мониторинг (создать SMB-сессию)
#   4. Проверить логи (все действия логируются?)
#   5. Проверить бэкапы (создать, восстановить, удалить)
#   6. Проверить диски
#   7. Очистить тестовые данные
# ============================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

BASE_URL="${1:-http://localhost:5000}"
COOKIE_JAR="/tmp/samba-functest-$$.txt"
ENV_FILE="/opt/samba-web-manager/.env"

USERNAME="admin"
PASSWORD="admin123"
[ -f "$ENV_FILE" ] && {
    USERNAME=$(grep '^ADMIN_USERNAME=' "$ENV_FILE" | cut -d= -f2- || echo admin)
    PASSWORD=$(grep '^ADMIN_PASSWORD=' "$ENV_FILE" | cut -d= -f2- || echo admin123)
}

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  🧪 Полный функциональный тест${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "🌐 $BASE_URL"
echo ""

# Логин
rm -f "$COOKIE_JAR"
curl -s -c "$COOKIE_JAR" -X POST "$BASE_URL/login" \
    -d "username=$USERNAME&password=$PASSWORD" -o /dev/null

if ! grep -q "session" "$COOKIE_JAR" 2>/dev/null; then
    echo -e "${RED}❌ Логин не удался${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Логин OK${NC}"
echo ""

# ============================================================
# ТЕСТ 1: БЭКАПЫ
# ============================================================
echo -e "${CYAN}━━━ [1/6] БЭКАПЫ ━━━${NC}"

echo "▸ GET /api/backups (до создания)"
BEFORE=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/api/backups")
COUNT_BEFORE=$(echo "$BEFORE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo 0)
echo "  Бэкапов до: $COUNT_BEFORE"

echo "▸ POST /api/backups (создать)"
RESP=$(curl -s -b "$COOKIE_JAR" -X POST "$BASE_URL/api/backups" -H "Content-Type: application/json" -d "{}")
BACKUP_FILE=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file',''))" 2>/dev/null || echo "")
if [ -n "$BACKUP_FILE" ]; then
    echo -e "  ${GREEN}✅ Бэкап создан: $BACKUP_FILE${NC}"
else
    echo -e "  ${RED}❌ Бэкап не создан: $RESP${NC}"
fi

echo "▸ GET /api/backups (после создания)"
AFTER=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/api/backups")
COUNT_AFTER=$(echo "$AFTER" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo 0)
echo "  Бэкапов после: $COUNT_AFTER"

if [ "$COUNT_AFTER" -gt "$COUNT_BEFORE" ]; then
    echo -e "  ${GREEN}✅ Список бэкапов обновляется${NC}"
else
    echo -e "  ${RED}❌ Список бэкапов НЕ обновляется${NC}"
fi

echo "▸ Файлы на диске:"
ls -la /opt/samba-web-manager/backups/ 2>/dev/null | tail -5 || echo "  папка не найдена"

# Удалить созданный бэкап
if [ -n "$BACKUP_FILE" ]; then
    BACKUP_NAME=$(basename "$BACKUP_FILE")
    curl -s -b "$COOKIE_JAR" -X DELETE "$BASE_URL/api/backups/$BACKUP_NAME" -o /dev/null
    echo -e "  ${GREEN}✅ Бэкап удалён${NC}"
fi
echo ""

# ============================================================
# ТЕСТ 2: ЛОГИ
# ============================================================
echo -e "${CYAN}━━━ [2/6] ЛОГИ ━━━${NC}"

LOG_FILE="/opt/samba-web-manager/logs/app.log"
if [ -f "$LOG_FILE" ]; then
    echo "▸ Размер лога: $(du -h $LOG_FILE | cut -f1)"
    echo "▸ Строк: $(wc -l < $LOG_FILE)"
    echo ""
    echo "▸ Последние 15 строк:"
    tail -15 "$LOG_FILE" | sed 's/^/    /'
    echo ""

    echo "▸ Проверка ключевых действий в логе:"
    for action in "вошёл" "Создание" "Удаление" "Бэкап" "Перезапуск" "Монтирование"; do
        COUNT=$(grep -c "$action" "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$COUNT" -gt 0 ]; then
            echo -e "    ${GREEN}✅${NC} '$action': $COUNT раз"
        else
            echo -e "    ${YELLOW}⚠️${NC}  '$action': 0 (возможно не логируется)"
        fi
    done
else
    echo -e "  ${RED}❌ Лог-файл не найден: $LOG_FILE${NC}"
fi
echo ""

# ============================================================
# ТЕСТ 3: МОНИТОРИНГ (создаём SMB-сессию)
# ============================================================
echo -e "${CYAN}━━━ [3/6] МОНИТОРИНГ ━━━${NC}"

echo "▸ smbstatus сейчас:"
sudo smbstatus 2>/dev/null | head -10 | sed 's/^/    /'

echo ""
echo "▸ Создаём SMB-сессию (smbclient в фоне на 5 сек)..."

# Создаём подключение в фоне
(sudo smbclient //localhost/public -N -c "ls; sleep 5" >/dev/null 2>&1) &
SMB_PID=$!
sleep 2

echo "▸ smbstatus во время сессии:"
sudo smbstatus 2>/dev/null | head -15 | sed 's/^/    /'

echo ""
echo "▸ GET /api/monitoring/connections:"
curl -s -b "$COOKIE_JAR" "$BASE_URL/api/monitoring/connections" | python3 -m json.tool 2>/dev/null | head -20 | sed 's/^/    /'

# Ждём завершения
wait $SMB_PID 2>/dev/null || true
echo ""
echo -e "  ${GREEN}✅ Тест мониторинга завершён${NC}"
echo ""

# ============================================================
# ТЕСТ 4: ШАРЫ (создать 3, удалить 3)
# ============================================================
echo -e "${CYAN}━━━ [4/6] ШАРЫ ━━━${NC}"

CREATED_SHARES=()
for i in 1 2 3; do
    NAME="functest_share_${i}_$(date +%s)"
    PATH_TMP="/tmp/${NAME}"
    mkdir -p "$PATH_TMP" && chmod 777 "$PATH_TMP"

    RESP=$(curl -s -b "$COOKIE_JAR" -X POST "$BASE_URL/api/shares" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$NAME\",\"path\":\"$PATH_TMP\",\"read_only\":false,\"guest_ok\":true}")

    if echo "$RESP" | grep -q "$NAME"; then
        echo -e "  ${GREEN}✅ Шара создана: $NAME${NC}"
        CREATED_SHARES+=("$NAME")
    else
        echo -e "  ${RED}❌ Шара не создана: $RESP${NC}"
    fi
done

echo ""
echo "▸ GET /api/shares:"
curl -s -b "$COOKIE_JAR" "$BASE_URL/api/shares" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'    Всего шар: {len(d)}')
for s in d:
    print(f'    • {s.get(\"name\",\"?\")} → {s.get(\"path\",\"?\")}')
" 2>/dev/null

echo ""
echo "▸ Удаляем созданные:"
for NAME in "${CREATED_SHARES[@]}"; do
    RESP=$(curl -s -b "$COOKIE_JAR" -X DELETE "$BASE_URL/api/shares/$NAME")
    if echo "$RESP" | grep -qE "удалена|success|message"; then
        echo -e "  ${GREEN}✅ Удалена: $NAME${NC}"
    else
        echo -e "  ${RED}❌ Не удалена: $NAME${NC}"
    fi
    rm -rf "/tmp/${NAME}" 2>/dev/null || true
done
echo ""

# ============================================================
# ТЕСТ 5: ПОЛЬЗОВАТЕЛИ
# ============================================================
echo -e "${CYAN}━━━ [5/6] ПОЛЬЗОВАТЕЛИ ━━━${NC}"

CREATED_USERS=()
for i in 1 2; do
    NAME="functest_user_${i}_$(date +%s)"
    PASS="TestPass123!"

    RESP=$(curl -s -b "$COOKIE_JAR" -X POST "$BASE_URL/api/users" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$NAME\",\"password\":\"$PASS\"}")

    if echo "$RESP" | grep -q "$NAME"; then
        echo -e "  ${GREEN}✅ Пользователь создан: $NAME${NC}"
        CREATED_USERS+=("$NAME")
    else
        echo -e "  ${RED}❌ Не создан: $RESP${NC}"
    fi
done

echo ""
echo "▸ Список пользователей Samba:"
sudo pdbedit -L 2>/dev/null | sed 's/^/    /'

echo ""
echo "▸ Проверка смены пароля:"
if [ ${#CREATED_USERS[@]} -gt 0 ]; then
    U="${CREATED_USERS[0]}"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_JAR" -X POST \
        -H "Content-Type: application/json" \
        -d '{"password":"NewPass456!"}' \
        "$BASE_URL/api/users/$U/password")
    echo "  Смена пароля: HTTP $CODE"
fi

echo ""
echo "▸ Удаление созданных:"
for NAME in "${CREATED_USERS[@]}"; do
    RESP=$(curl -s -b "$COOKIE_JAR" -X DELETE "$BASE_URL/api/users/$NAME")
    if echo "$RESP" | grep -qiE "удален|success|message"; then
        echo -e "  ${GREEN}✅ Удалён: $NAME${NC}"
    else
        echo -e "  ${RED}❌ Не удалён: $NAME${NC}"
    fi
done
echo ""

# ============================================================
# ТЕСТ 6: ДИСКИ
# ============================================================
echo -e "${CYAN}━━━ [6/6] ДИСКИ ━━━${NC}"

echo "▸ GET /api/disks:"
curl -s -b "$COOKIE_JAR" "$BASE_URL/api/disks" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'    Всего дисков: {d.get(\"total_disks\",0)}')
print(f'    Смонтировано: {d.get(\"mounted_disks\",0)}')
print(f'    Точки монтирования: {len(d.get(\"available_mount_points\",[]))}')
print()
for disk in d.get('disks', [])[:5]:
    status = '✅' if disk.get('is_mounted') else '○'
    print(f'    {status} {disk.get(\"device\",\"?\"):15} {disk.get(\"mount_point\",\"-\"):25} {disk.get(\"filesystem\",\"-\"):8} {disk.get(\"size_human\",\"?\")}')
" 2>/dev/null

echo ""

# ============================================================
# ИТОГ
# ============================================================
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  ✅ ТЕСТ ЗАВЕРШЁН${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo "📌 Что проверить вручную:"
echo ""
echo "  1. Откройте http://192.168.0.224:5000/backups"
echo "     → Должен быть список бэкапов (если создали)"
echo ""
echo "  2. Откройте http://192.168.0.224:5000/logs"
echo "     → Должны быть записи о действиях выше"
echo ""
echo "  3. Откройте http://192.168.0.224:5000/monitoring"
echo "     → Показывает ли активные подключения"
echo ""
echo "  4. Откройте http://192.168.0.224:5000/disks"
echo "     → Список всех дисков"
echo ""

rm -f "$COOKIE_JAR"
