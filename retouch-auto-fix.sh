#!/usr/bin/env bash
# retouch-auto-fix.sh
# =============================================================
# Комплексная диагностика и авто-устранение проблем цепочки ретуши
# Охват:
#  - Определение среды (bare metal / docker)
#  - Поиск и правка Nginx routing для /api/retouch и /api/retouch-json
#  - Проверка доступности backend (порт, PM2, docker container)
#  - Автозапуск backend через PM2 (если найден server.js / ecosystem.config.json)
#  - Проверка доступности LaMa (LAMA_URL, docker сервис lama, порт 5000/5002)
#  - Тест multipart и JSON fallback запросов
#  - Доп.проверка версии retouch_manager.js (наличие _exportMaskEquirect без артефактов)
#  - Формирование отчёта и подсказок
#  - НЕ вносит правки в JS (только Nginx + запуск процессов)
#
# Запуск одной командой c GitHub:
#   curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/retouch-auto-fix.sh | bash
#
# Переменные окружения / флаги:
#   AUTO_FIX=1            Включить правку Nginx и автозапуск backend
#   FORCE_PM2_SETUP=1     Установить pm2 глобально если отсутствует
#   BACKEND_PORT=3001     Порт backend
#   LAMA_PORT=5000        Порт LaMa (или 5002 для docker-nginx.conf маршрута /lama/)
#   DOMAIN=example.com    Домен для curl тестов (иначе авто)
#   DRY_RUN=1             Ничего не менять, только отчёт
# =============================================================
set -euo pipefail

COLOR_RESET='\033[0m'; COLOR_RED='\033[31m'; COLOR_GREEN='\033[32m'; COLOR_YELLOW='\033[33m'; COLOR_CYAN='\033[36m';
log(){ echo -e "${COLOR_CYAN}[INFO]${COLOR_RESET} $*"; }
warn(){ echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"; }
err(){ echo -e "${COLOR_RED}[ERR ]${COLOR_RESET} $*"; }
ok(){ echo -e "${COLOR_GREEN}[ OK ]${COLOR_RESET} $*"; }
section(){ echo -e "\n${COLOR_YELLOW}==== $* ====${COLOR_RESET}"; }

AUTO_FIX="${AUTO_FIX:-0}"
FORCE_PM2_SETUP="${FORCE_PM2_SETUP:-0}"
BACKEND_PORT="${BACKEND_PORT:-3001}"
LAMA_PORT="${LAMA_PORT:-5000}"
DOMAIN="${DOMAIN:-}"
# Если пользователь оставил плейсхолдер — считаем, что домен не задан и пытаемся автоопределить
if [[ "$DOMAIN" =~ ^(your-domain\.tld|example\.com)$ ]]; then
  DOMAIN=""
fi
DRY_RUN="${DRY_RUN:-0}"

SUMMARY=()
add_summary(){ SUMMARY+=("$1") ; }

SCRIPT_START_TS=$(date +%s)
WORKDIR=$(pwd)

# -------------------------------------------------------------
section "1. Определение Docker / bare metal"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  DOCKER_AVAILABLE=1
  DOCKER_PS=$(docker ps --format '{{.Names}}' || true)
  if echo "$DOCKER_PS" | grep -qi nginx; then
    DOCKER_HAS_NGINX=1
  else
    DOCKER_HAS_NGINX=0
  fi
  if echo "$DOCKER_PS" | grep -qi backend; then
    DOCKER_HAS_BACKEND=1
  else
    DOCKER_HAS_BACKEND=0
  fi
  if echo "$DOCKER_PS" | grep -qi lama; then
    DOCKER_HAS_LAMA=1
  else
    DOCKER_HAS_LAMA=0
  fi
  ok "Docker доступен (nginx=$DOCKER_HAS_NGINX backend=$DOCKER_HAS_BACKEND lama=$DOCKER_HAS_LAMA)"
else
  DOCKER_AVAILABLE=0; DOCKER_HAS_NGINX=0; DOCKER_HAS_BACKEND=0; DOCKER_HAS_LAMA=0
  warn "Docker не обнаружен — предполагаем bare metal"
fi
add_summary "Docker: ${DOCKER_AVAILABLE} (nginx: $DOCKER_HAS_NGINX, backend: $DOCKER_HAS_BACKEND, lama: $DOCKER_HAS_LAMA)"

# -------------------------------------------------------------
section "2. Определение домена"
TMP_NGX_DUMP=$(mktemp)
if DOCKER_NGX_CID=$(docker ps --filter 'name=nginx' --format '{{.ID}}' 2>/dev/null | head -n1) && [[ -n "$DOCKER_NGX_CID" ]]; then
  docker exec -i "$DOCKER_NGX_CID" nginx -T > "$TMP_NGX_DUMP" 2>/dev/null || true
fi
if [[ ! -s "$TMP_NGX_DUMP" ]]; then
  nginx -T > "$TMP_NGX_DUMP" 2>/dev/null || true
fi
if [[ -z "$DOMAIN" ]]; then
  # выбираем первый осмысленный server_name не '_'
  DOMAIN=$(grep -E "server_name" "$TMP_NGX_DUMP" | sed -E 's/.*server_name\s+([^;]+);.*/\1/' | tr ' ' '\n' | grep -v '^_$' | grep -E '\.' | head -n1 || true)
fi
[[ -z "$DOMAIN" ]] && DOMAIN="127.0.0.1"
ok "Используем DOMAIN=$DOMAIN"
add_summary "DOMAIN=$DOMAIN"

# -------------------------------------------------------------
section "3. Проверка backend процесса"
BACKEND_LISTENING=0
if ss -tln 2>/dev/null | grep -q ":${BACKEND_PORT} "; then BACKEND_LISTENING=1; ok "Порт ${BACKEND_PORT} слушается (host)"; fi
if [[ $BACKEND_LISTENING -eq 0 && $DOCKER_AVAILABLE -eq 1 && $DOCKER_HAS_BACKEND -eq 1 ]]; then
  docker exec -i $(docker ps --filter 'name=backend' --format '{{.ID}}' | head -n1) bash -lc "ss -tln | grep ':${BACKEND_PORT} '" >/dev/null 2>&1 && BACKEND_LISTENING=2
  [[ $BACKEND_LISTENING -eq 2 ]] && ok "Порт ${BACKEND_PORT} слушается внутри backend контейнера"
fi
if [[ $BACKEND_LISTENING -eq 0 ]]; then warn "Backend порт ${BACKEND_PORT} не слушается"; add_summary "Backend port ${BACKEND_PORT}: NOT LISTENING"; else add_summary "Backend port ${BACKEND_PORT}: LISTENING ($BACKEND_LISTENING)"; fi

# Попытка найти backend файл
BACKEND_ENTRY=""
if [[ -f ecosystem.config.json ]]; then
  BACKEND_ENTRY=$(grep -E 'script.*server\.js' ecosystem.config.json | head -n1 | sed -E 's/.*"script"\s*:\s*"([^"]+)".*/\1/' || true)
fi
[[ -z "$BACKEND_ENTRY" && -f server.js ]] && BACKEND_ENTRY="server.js"
[[ -z "$BACKEND_ENTRY" && -f server-fixed.js ]] && BACKEND_ENTRY="server-fixed.js"

if [[ $BACKEND_LISTENING -eq 0 && -n "$BACKEND_ENTRY" && $AUTO_FIX -eq 1 && $DRY_RUN -eq 0 ]]; then
  section "3a. Автозапуск backend через PM2"
  if ! command -v pm2 >/dev/null 2>&1; then
    if [[ $FORCE_PM2_SETUP -eq 1 ]]; then
      log "Устанавливаю pm2 (npm i -g pm2)"; npm i -g pm2 || { err "Не удалось установить pm2"; };
    else
      warn "pm2 не установлен. Добавьте FORCE_PM2_SETUP=1 для авто установки"; 
    fi
  fi
  if command -v pm2 >/dev/null 2>&1; then
    if [[ -f ecosystem.config.json ]]; then
      pm2 start ecosystem.config.json --only backend || pm2 start "$BACKEND_ENTRY" --name backend
    else
      pm2 start "$BACKEND_ENTRY" --name backend
    fi
    sleep 2
    if ss -tln 2>/dev/null | grep -q ":${BACKEND_PORT} "; then ok "Backend поднят (порт ${BACKEND_PORT})"; BACKEND_LISTENING=1; else warn "Backend всё ещё не слушает порт"; fi
  fi
fi

# -------------------------------------------------------------
section "4. Проверка LaMa"
LAMA_HEALTH=0
# Проверка через известные порты
for LP in "$LAMA_PORT" 8080 5000 5002; do
  if curl -s -m 3 http://127.0.0.1:${LP}/inpaint >/dev/null 2>&1; then LAMA_HEALTH=1; LAMA_PORT_ACTUAL=$LP; break; fi
  if [[ $DOCKER_AVAILABLE -eq 1 && $DOCKER_HAS_LAMA -eq 1 ]]; then
    if docker exec -i $(docker ps --filter 'name=lama' --format '{{.ID}}' | head -n1) bash -lc "curl -s -m 3 http://127.0.0.1:${LP}/inpaint >/dev/null"; then LAMA_HEALTH=2; LAMA_PORT_ACTUAL=$LP; break; fi
  fi
done
if [[ ${LAMA_HEALTH} -eq 0 ]]; then warn "LaMa endpoint /inpaint не отвечает"; add_summary "LaMa: NOT REACHABLE"; else ok "LaMa доступна (mode=${LAMA_HEALTH}, port=${LAMA_PORT_ACTUAL})"; add_summary "LaMa: OK (port=${LAMA_PORT_ACTUAL}, mode=${LAMA_HEALTH})"; fi

# -------------------------------------------------------------
section "5. Проверка и правка Nginx routing"
NGX_EDIT=0
TMP_NGX_DUMP2=$(mktemp)
if [[ $DOCKER_HAS_NGINX -eq 1 ]]; then
  NGINX_CONTAINER_ID=$(docker ps --filter 'name=nginx' --format '{{.ID}}' | head -n1)
  docker exec -i "$NGINX_CONTAINER_ID" nginx -T > "$TMP_NGX_DUMP2" 2>/dev/null || true
else
  nginx -T > "$TMP_NGX_DUMP2" 2>/dev/null || true
fi
HAS_RETOUCH=$(grep -E "location *= */api/retouch( |$)" "$TMP_NGX_DUMP2" || true)
HAS_JSON=$(grep -E "location *= */api/retouch-json( |$)" "$TMP_NGX_DUMP2" || true)
if [[ -z "$HAS_RETOUCH" || -z "$HAS_JSON" ]]; then
  warn "Точечные location отсутствуют"
  add_summary "Nginx retouch locations: MISSING"
  if [[ $AUTO_FIX -eq 1 && $DRY_RUN -eq 0 ]]; then
    NGX_EDIT=1
    log "Попытка вставки блоков"
    TARGET_CONF="/etc/nginx/nginx.conf"
    # Если docker — попробуем найти conf.d файл
    if [[ $DOCKER_HAS_NGINX -eq 1 ]]; then
      # Пробуем default.conf
      if docker exec -i "$NGINX_CONTAINER_ID" test -f /etc/nginx/conf.d/default.conf; then
        TARGET_CONF="/etc/nginx/conf.d/default.conf"
      fi
    else
      # Если есть conf.d/color360.conf — предпочтём его
      if [[ -f /etc/nginx/conf.d/color360.conf ]]; then TARGET_CONF="/etc/nginx/conf.d/color360.conf"; fi
    fi
    BACKUP_NAME="${TARGET_CONF}.$(date +%Y%m%d_%H%M%S).bak"
    INSERT_BLOCK=$'\n    # >>> AUTO RETOUCH ROUTING >>>\n    location = /api/retouch {\n        proxy_pass http://color360_backend/api/retouch;\n        proxy_set_header Host $host;\n        proxy_set_header X-Real-IP $remote_addr;\n        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto $scheme;\n    }\n    location = /api/retouch-json {\n        proxy_pass http://color360_backend/api/retouch-json;\n        proxy_set_header Host $host;\n        proxy_set_header X-Real-IP $remote_addr;\n        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto $scheme;\n    }\n    # <<< AUTO RETOUCH ROUTING <<<'
    if [[ $DOCKER_HAS_NGINX -eq 1 ]]; then
      docker exec -i "$NGINX_CONTAINER_ID" cp "$TARGET_CONF" "$BACKUP_NAME" || warn "Не удалось сделать backup внутри контейнера"
      docker exec -i "$NGINX_CONTAINER_ID" /bin/sh -c "printf '%s' \"$INSERT_BLOCK\" >> $TARGET_CONF" || err "Не удалось вставить блоки"
      docker exec -i "$NGINX_CONTAINER_ID" nginx -t && docker exec -i "$NGINX_CONTAINER_ID" nginx -s reload && ok "Nginx reloaded (docker)" || warn "Проблема reload"
    else
      cp "$TARGET_CONF" "$BACKUP_NAME" || warn "Не удалось сделать backup"
      printf '%s' "${INSERT_BLOCK}" >> "$TARGET_CONF" || err "Не удалось изменить $TARGET_CONF"
      nginx -t && nginx -s reload && ok "Nginx reloaded" || warn "Проблема reload"
    fi
  fi
else
  ok "Точечные location присутствуют"
  add_summary "Nginx retouch locations: OK"
fi

# -------------------------------------------------------------
section "6. Сетевые тесты HTTP через домен"
for ep in /api/retouch /api/retouch-json; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 http://$DOMAIN$ep || true)
  followNote=""
  if [[ "$code" == "301" || "$code" == "308" ]]; then
    code_tls=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 https://$DOMAIN$ep || true)
    followNote=" (redirect->$code_tls via https)"
    if [[ -n "$code_tls" ]]; then code=$code_tls; fi
  fi
  echo "$ep -> HTTP $code$followNote"
  [[ "$code" == "000" ]] && warn "$ep: соединение не установлено" && add_summary "$ep HTTP=000" || add_summary "$ep HTTP=$code"
  if [[ "$code" == "404" ]]; then warn "$ep: 404 (маршрутизация не исправлена)"; fi
  if [[ "$code" == "405" ]]; then warn "$ep: 405 (возможно не тот upstream)"; fi
 done

# -------------------------------------------------------------
section "7. JSON fallback POST тест"
IMG_B64='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9YV7tV0AAAAASUVORK5CYII='
JSON_PAYLOAD="{ \"imageData\": \"data:image/png;base64,$IMG_B64\", \"maskData\": \"data:image/png;base64,$IMG_B64\", \"prompt\": \"diag\" }"
JF_CODE=$(curl -s -o /tmp/retouch_json_fullfix.out -w "%{http_code}" -H 'Content-Type: application/json' -X POST --max-time 25 http://$DOMAIN/api/retouch-json -d "$JSON_PAYLOAD" || true)
if [[ "$JF_CODE" == "301" || "$JF_CODE" == "308" ]]; then
  JF_CODE=$(curl -s -o /tmp/retouch_json_fullfix.out -w "%{http_code}" -H 'Content-Type: application/json' -X POST --max-time 25 https://$DOMAIN/api/retouch-json -d "$JSON_PAYLOAD" || true)
  echo "POST /api/retouch-json (follow https) -> HTTP $JF_CODE"
else
  echo "POST /api/retouch-json -> HTTP $JF_CODE"
fi
add_summary "JSON fallback POST: $JF_CODE"

# -------------------------------------------------------------
section "8. Проверка retouch_manager.js версии"
# Пытаемся скачать файл напрямую
RTM_URL_BASE="http://$DOMAIN/pano/ui/retouch_manager.js"
HTTP_RTM=$(curl -s -o /tmp/retouch_manager_remote.js -w "%{http_code}" --max-time 15 "$RTM_URL_BASE" || true)
if [[ "$HTTP_RTM" == "301" || "$HTTP_RTM" == "308" ]]; then
  RTM_URL_BASE="https://$DOMAIN/pano/ui/retouch_manager.js"
  HTTP_RTM=$(curl -s -o /tmp/retouch_manager_remote.js -w "%{http_code}" --max-time 15 "$RTM_URL_BASE" || true)
fi
if [[ "$HTTP_RTM" != "200" ]]; then
  warn "Не удалось получить retouch_manager.js (код=$HTTP_RTM)"
  add_summary "retouch_manager.js fetch: $HTTP_RTM"
else
  if grep -q "_exportMaskEquirect" /tmp/retouch_manager_remote.js && ! grep -q "resp.status" /tmp/retouch_manager_remote.js; then
    ok "retouch_manager.js версия выглядит корректно"
    add_summary "retouch_manager.js: OK"
  else
    warn "Подозрительная версия retouch_manager.js (возможно старая/кэш)"
    add_summary "retouch_manager.js: SUSPECT"
  fi
fi

# -------------------------------------------------------------
section "9. PM2 состояние (если установлен)"
if command -v pm2 >/dev/null 2>&1; then
  pm2 jlist > /tmp/pm2_jlist.json 2>/dev/null || true
  BACKEND_PM2=$(grep -Ei '"name"\s*:\s*"(backend|color360-app)"' /tmp/pm2_jlist.json || true)
  if [[ -z "$BACKEND_PM2" ]]; then BACKEND_PM2=$(grep -Ei '"script"\s*:\s*"server\.js"' /tmp/pm2_jlist.json || true); fi
  if [[ -n "$BACKEND_PM2" ]]; then ok "PM2 backend процесс(ы) обнаружены"; add_summary "PM2 backend: PRESENT"; else warn "PM2 backend процесс не найден"; add_summary "PM2 backend: MISSING"; fi
else
  warn "PM2 не установлен"
  add_summary "PM2: NOT INSTALLED"
fi

# -------------------------------------------------------------
section "10. Итоговый отчёт"
{
  echo "====================================";
  echo "RET, AUTO-FIX SUMMARY";
  for line in "${SUMMARY[@]}"; do echo " - $line"; done
  echo "Runtime: $(( $(date +%s) - SCRIPT_START_TS ))s";
  echo "AUTO_FIX=$AUTO_FIX DRY_RUN=$DRY_RUN FORCE_PM2_SETUP=$FORCE_PM2_SETUP";
  echo "====================================";
} | tee /tmp/retouch_auto_fix_summary.txt

# -------------------------------------------------------------
section "11. Рекомендации"
cat <<'EOT'
1) Если /api/retouch-json даёт 404 / 000 — проверьте:
   - Правка Nginx внутри нужного окружения (docker vs host)
   - Правильный upstream color360_backend
  - При 301/308: добавьте блоки и в HTTPS server { listen 443 ssl; }
2) Если backend порт не слушает — поднять через PM2 или docker compose.
3) Если JSON POST => 500 — смотреть pm2 logs backend (причина в Node/LaMa).
4) Если LaMa недоступна — проверить сервис lama / контейнер, переменные LAMA_URL.
5) Если retouch_manager.js подозрителен — очистить кэш браузера / CDN.
6) Повторить тесты после исправлений:
   DOMAIN=your-domain AUTO_FIX=1 bash retouch-auto-fix.sh
7) Если nginx пишет "location directive is not allowed here" — вставьте блоки внутрь server { } (а не в http{} или вне блока).
EOT

ok "Готово. Итог: /tmp/retouch_auto_fix_summary.txt"

exit 0
