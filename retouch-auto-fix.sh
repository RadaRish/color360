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
SERVER_NAME_CANDIDATES=$(grep -E "server_name" "$TMP_NGX_DUMP" | sed -E 's/.*server_name\s+([^;]+);.*/\1/' | tr ' ' '\n' | tr -d '\r' | grep -v '^_$' || true)
# Попытка достать домен из сертификата, если server_name не найден
if [[ -z "$SERVER_NAME_CANDIDATES" ]]; then
  CERT_DOMAIN=$(grep -E "ssl_certificate " "$TMP_NGX_DUMP" | sed -E 's/.*live\/([^/]+)\/fullchain.pem.*/\1/' | head -n1 || true)
  if [[ -n "$CERT_DOMAIN" && "$CERT_DOMAIN" =~ \.[a-zA-Z]{2,}$ ]]; then
    SERVER_NAME_CANDIDATES="$CERT_DOMAIN"
  fi
fi
if [[ -z "$DOMAIN" ]]; then
  DOMAIN=$(echo "$SERVER_NAME_CANDIDATES" | grep -E '\.' | head -n1 || true)
fi
if [[ -z "$DOMAIN" ]]; then
  warn "Автоопределение домена не удалось (нет server_name с точкой). Fallback 127.0.0.1"; DOMAIN="127.0.0.1";
fi
ok "Используем DOMAIN=$DOMAIN"
add_summary "DOMAIN=$DOMAIN"
if [[ -n "$SERVER_NAME_CANDIDATES" ]]; then
  echo "[diag] server_name кандидаты: $(echo $SERVER_NAME_CANDIDATES | tr '\n' ' ')" | sed 's/  */ /g'
else
  echo "[diag] server_name кандидаты: (пусто)"
fi

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
    log "Попытка безопасной вставки внутрь server{}"

    # Определяем proxy_pass цель: пытаемся найти upstream color360_backend
    UPSTREAM_NAME="color360_backend"
    if ! grep -q "upstream[[:space:]]\+$UPSTREAM_NAME" "$TMP_NGX_DUMP2" 2>/dev/null; then
      # fallback на прямой localhost:BACKEND_PORT
      PROXY_TARGET_RETOUCH="http://127.0.0.1:${BACKEND_PORT}/api/retouch"
      PROXY_TARGET_JSON="http://127.0.0.1:${BACKEND_PORT}/api/retouch-json"
    else
      PROXY_TARGET_RETOUCH="http://${UPSTREAM_NAME}/api/retouch"
      PROXY_TARGET_JSON="http://${UPSTREAM_NAME}/api/retouch-json"
    fi

    INSERT_PAYLOAD() {
      cat <<'EOF'
    # >>> AUTO RETOUCH ROUTING >>>
    location = /api/retouch {
        proxy_pass ${PROXY_TARGET_RETOUCH};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 250M;
    }
    location = /api/retouch-json {
        proxy_pass ${PROXY_TARGET_JSON};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 250M;
    }
    # <<< AUTO RETOUCH ROUTING <<<
EOF
    }

    # Функция поиска server{} содержащего server_name с доменом или listen 80/443
    select_server_block() {
      local file="$1" domain_pat="$2"; awk -v dom="$domain_pat" '
        BEGIN{in_srv=0;lvl=0;keep=0;buf=""}
        function flush(){if(keep){print buf}; buf=""; keep=0}
        /server\s*{/ { if(!in_srv){in_srv=1;lvl=0}; }
        { if(in_srv){ buf = buf $0 ORS } }
        /{/ { if(in_srv){ lvl++ } }
        /}/ { if(in_srv){ lvl--; if(lvl==0){
              # Решение о выборе
              if(buf ~ /server_name/ && buf ~ dom){ keep=1 }
              else if(!keep && dom=="FALLBACK" && buf ~ /listen[^;]*80/){ keep=1 }
              if(keep){ print buf > "/dev/stderr"; print "__SELECTED__"; };
              in_srv=0; buf=""; keep=0;
            }} }
      ' "$file" 2>"$file.selected.tmp" | grep -q '__SELECTED__'; local rc=$?; if [[ $rc -eq 0 ]]; then echo "$file.selected.tmp"; else rm -f "$file.selected.tmp"; return 1; fi
    }

    # Собираем кандидаты файлов
    TARGET_FILE=""
    for f in /etc/nginx/nginx.conf /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/*.conf; do
      [[ -f "$f" ]] || continue
      if grep -q "server_name" "$f"; then
        if grep -q "$DOMAIN" "$f"; then TARGET_FILE="$f"; break; fi
      fi
    done
    if [[ -z "$TARGET_FILE" ]]; then
      # fallback берём nginx.conf
      TARGET_FILE="/etc/nginx/nginx.conf"
    fi
    log "Файлы-конфиги проверены (pattern: nginx.conf conf.d/*.conf sites-enabled/*.conf). Итоговый выбор: $TARGET_FILE"

    BACKUP_NAME="${TARGET_FILE}.$(date +%Y%m%d_%H%M%S).bak"
    log "Выбран файл для модификации: $TARGET_FILE (backup: $BACKUP_NAME)"

    # Определим файл во вложении контейнера или хоста
    if [[ $DOCKER_HAS_NGINX -eq 1 ]]; then
      docker exec -i "$NGINX_CONTAINER_ID" cp "$TARGET_FILE" "$BACKUP_NAME" || warn "Не удалось backup внутри контейнера"
      # Извлекаем файл локально
      docker cp "$NGINX_CONTAINER_ID:$TARGET_FILE" /tmp/ngx_target_work.$$ || { err "Не удалось извлечь $TARGET_FILE"; }
      WORK_FILE="/tmp/ngx_target_work.$$"
    else
      cp "$TARGET_FILE" "$BACKUP_NAME" || warn "Не удалось сделать backup"
      WORK_FILE="$TARGET_FILE"
    fi

    # Пытаемся найти серверный блок для домена
    if ! grep -q "server_name" "$WORK_FILE"; then
      warn "В файле нет server_name — вставка будет сделана в конец первого server{}"
    fi

  # Используем awk для вставки перед завершающей скобкой выбранного блока
    DOMAIN_REGEX="$DOMAIN"
    [[ "$DOMAIN" == "127.0.0.1" || "$DOMAIN" == "localhost" ]] && DOMAIN_REGEX="FALLBACK"

    # Создаём файл с меткой блока (stderr от awk выше)
    # В случае сложности используем простую вставку: ищем строку server_name с доменом и ближайшую закрывающую }
  RAW_INSERT=$(INSERT_PAYLOAD)
  # Подставляем цели proxy_pass (т.к. внутри <<'EOF' переменные не разворачиваются)
  RAW_INSERT=${RAW_INSERT//\$\{PROXY_TARGET_RETOUCH\}/${PROXY_TARGET_RETOUCH}}
  RAW_INSERT=${RAW_INSERT//\$\{PROXY_TARGET_JSON\}/${PROXY_TARGET_JSON}}
  INSERT_TMP_ESCAPED=$(printf '%s' "$RAW_INSERT" | sed 's/\\/\\\\/g' | sed ':a;N;$!ba;s/\n/\\n/g')

    if grep -q "$DOMAIN" "$WORK_FILE"; then
      # Вставка по домену
      awk -v dom="$DOMAIN" -v insert="$INSERT_TMP_ESCAPED" '
        BEGIN{srv=0;lvl=0}
        /server[[:space:]]*{/ { if(!srv){srv=1;lvl=0} }
        { if(srv){ if($0 ~ dom){mark=1} } }
        /{/ { if(srv){lvl++} }
        /}/ { if(srv){lvl--; if(lvl==0){ if(mark){ print insert } srv=0; mark=0 } } }
        { print $0 }
      ' "$WORK_FILE" > "$WORK_FILE.new" && mv "$WORK_FILE.new" "$WORK_FILE"
    else
      # fallback: первая server{} со слушающим 80
      awk -v insert="$INSERT_TMP_ESCAPED" '
        BEGIN{srv=0;lvl=0;done=0}
        /server[[:space:]]*{/ { if(!srv){srv=1;lvl=0} }
        /listen[^;]*80/ { if(srv){cand=1} }
        /{/ { if(srv){lvl++} }
        /}/ { if(srv){lvl--; if(lvl==0){ if(cand && !done){ print insert; done=1 } srv=0; cand=0 } } }
        { print $0 }
      ' "$WORK_FILE" > "$WORK_FILE.new" && mv "$WORK_FILE.new" "$WORK_FILE"
    fi

    # Быстрая проверка: убедимся что каждая вставленная location внутри server{}
    if grep -n "AUTO RETOUCH ROUTING" "$WORK_FILE" >/dev/null 2>&1; then
      LOC_LINE=$(grep -n "AUTO RETOUCH ROUTING" "$WORK_FILE" | head -n1 | cut -d: -f1)
      # Считаем количество 'server' до строки и баланс фигурных скобок
      if [[ -n "$LOC_LINE" ]]; then
        # Проверяем, что между началом файла и строкой вставки есть хотя бы одно 'server {' и что количество '{' превышает '}' (внутри блока)
        BEFORE_CONTENT=$(sed -n "1,${LOC_LINE}p" "$WORK_FILE")
        OPEN_COUNT=$(echo "$BEFORE_CONTENT" | grep -o '{' | wc -l | tr -d ' ')
        CLOSE_COUNT=$(echo "$BEFORE_CONTENT" | grep -o '}' | wc -l | tr -d ' ')
        if (( OPEN_COUNT <= CLOSE_COUNT )); then
          warn "Детектор: вставка может быть вне server{} (OPEN=$OPEN_COUNT CLOSE=$CLOSE_COUNT). Откатываем изменения."
          if [[ -f "$BACKUP_NAME" ]]; then cp "$BACKUP_NAME" "$WORK_FILE"; fi
        fi
      fi
    fi

    # Возвращаем файл в контейнер (если docker)
    if [[ $DOCKER_HAS_NGINX -eq 1 ]]; then
      docker cp "$WORK_FILE" "$NGINX_CONTAINER_ID:$TARGET_FILE" || err "Не удалось вернуть изменённый файл"
    fi

    # Тест и reload
    if [[ $DOCKER_HAS_NGINX -eq 1 ]]; then
      docker exec -i "$NGINX_CONTAINER_ID" nginx -t && docker exec -i "$NGINX_CONTAINER_ID" nginx -s reload && ok "Nginx reloaded (safe insert)" || warn "Reload провалился (docker)"
    else
      nginx -t && nginx -s reload && ok "Nginx reloaded (safe insert)" || warn "Reload провалился"
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
