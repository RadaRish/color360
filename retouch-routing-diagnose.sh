#!/usr/bin/env bash
# retouch-routing-diagnose.sh
# Полный автоматизированный скрипт диагностики и (частично) исправления цепочки ретуши:
# 1. Проверяет, какой nginx.conf реально активен и есть ли location для /api/retouch /api/retouch-json
# 2. Делает резервную копию nginx.conf при необходимости добавления блоков
# 3. (Опционально) вставляет недостающие точечные location = /api/retouch и /api/retouch-json
# 4. Тестирует прямой доступ к backend и через nginx
# 5. Выполняет пробный JSON fallback запрос с tiny 1x1 PNG
# 6. Даёт сводку статусов и рекомендации
#
# Запуск одной командой с обновлением из git (из корня проекта на сервере):
#   curl -s https://raw.githubusercontent.com/RadaRish/color360/main/retouch-routing-diagnose.sh | bash
# ИЛИ если скрипт уже в репо: (из /var/www/color360)
#   bash retouch-routing-diagnose.sh
#
# Переменные окружения (кастомизация):
#   DRY_RUN=1           Только показать, что было бы сделано
#   AUTO_FIX=1          Автоматически вставить отсутствующие location блоки
#   BACKEND_PORT=3001   Порт Node backend (если отличается)
#   DOMAIN=example.com  Явно указать домен для curl тестов
set -euo pipefail

COLOR_RESET='\033[0m'; COLOR_RED='\033[31m'; COLOR_GREEN='\033[32m'; COLOR_YELLOW='\033[33m'; COLOR_CYAN='\033[36m';
log(){ echo -e "${COLOR_CYAN}[INFO]${COLOR_RESET} $*"; }
warn(){ echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"; }
err(){ echo -e "${COLOR_RED}[ERR ]${COLOR_RESET} $*"; }
ok(){ echo -e "${COLOR_GREEN}[ OK ]${COLOR_RESET} $*"; }

BACKEND_PORT="${BACKEND_PORT:-3001}"
DOMAIN="${DOMAIN:-}" # если пусто — попробуем вытащить из server_name
NGINX_CONF_CANDIDATES=(/etc/nginx/nginx.conf /etc/nginx/conf.d/color360.conf /etc/nginx/sites-enabled/color360 /usr/local/nginx/conf/nginx.conf)
ACTIVE_CONF=""

step(){ echo -e "\n${COLOR_YELLOW}==== $* ====${COLOR_RESET}"; }

step "1. Поиск активного nginx.conf"
if nginx -T >/tmp/nginx_full_dump 2>&1; then
  ok "nginx -T выполнен"
else
  err "nginx -T не выполнился — необходимо root/правильный контейнер"; exit 1
fi

# Ищем путь include-ов и server_name
SERVER_NAMES=$(grep -E "server_name" /tmp/nginx_full_dump | awk '{for(i=1;i<=NF;i++){if($i!="server_name" && $i!="{" ){gsub(/;/,"");print $i}}}' | sort -u)
[[ -z "$DOMAIN" && -n "$SERVER_NAMES" ]] && DOMAIN=$(echo "$SERVER_NAMES" | head -n1)
[[ -z "$DOMAIN" ]] && DOMAIN="127.0.0.1"
ok "Используем DOMAIN=$DOMAIN"

for f in "${NGINX_CONF_CANDIDATES[@]}"; do
  if [[ -f $f ]]; then
    if grep -q "$f" /tmp/nginx_full_dump; then ACTIVE_CONF="$f"; break; fi
  fi
done
if [[ -z "$ACTIVE_CONF" ]]; then
  warn "Не удалось однозначно определить основной конфиг. Будем анализировать /etc/nginx/nginx.conf"
  ACTIVE_CONF="/etc/nginx/nginx.conf"
fi
ok "Основной конфиг (предположительно): $ACTIVE_CONF"

step "2. Проверка location для /api/retouch /api/retouch-json"
MATCH_RETOUCH=$(grep -n "location *= */api/retouch" /tmp/nginx_full_dump || true)
MATCH_JSON=$(grep -n "location *= */api/retouch-json" /tmp/nginx_full_dump || true)
if [[ -n "$MATCH_RETOUCH" ]]; then ok "Найден точечный location = /api/retouch"; else warn "Нет точечного location = /api/retouch"; fi
if [[ -n "$MATCH_JSON" ]]; then ok "Найден точечный location = /api/retouch-json"; else warn "Нет точечного location = /api/retouch-json"; fi

NEED_FIX=0
[[ -z "$MATCH_RETOUCH" || -z "$MATCH_JSON" ]] && NEED_FIX=1

if [[ $NEED_FIX -eq 1 ]]; then
  if [[ "${AUTO_FIX:-0}" == "1" ]]; then
    step "3. Автовставка недостающих location (AUTO_FIX=1)"
    BAK="$ACTIVE_CONF.$(date +%Y%m%d_%H%M%S).bak"
    cp "$ACTIVE_CONF" "$BAK"
    ok "Резервная копия: $BAK"

    if ! grep -q "location = /api/retouch-json" "$ACTIVE_CONF"; then
      echo -e '\n    # >>> AUTO INSERT retouch routing >>>\n    location = /api/retouch {\n        proxy_pass http://color360_backend/api/retouch;\n        proxy_set_header Host $host;\n        proxy_set_header X-Real-IP $remote_addr;\n        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto $scheme;\n    }\n    location = /api/retouch-json {\n        proxy_pass http://color360_backend/api/retouch-json;\n        proxy_set_header Host $host;\n        proxy_set_header X-Real-IP $remote_addr;\n        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto $scheme;\n    }\n    # <<< AUTO INSERT retouch routing <<<' >> "$ACTIVE_CONF"
      ok "Вставлены блоки"
    fi

    nginx -t && nginx -s reload && ok "Nginx перезагружен" || { err "Ошибка reload — откат"; cp "$BAK" "$ACTIVE_CONF"; exit 1; }
  else
    warn "Отсутствуют блоки — можно запустить с AUTO_FIX=1 или вставить вручную."
  fi
else
  ok "Оба блока присутствуют — правка не требуется"
fi

step "4. Тесты через Nginx"
for ep in /api/retouch /api/retouch-json; do
  code=$(curl -s -o /dev/null -w "%{http_code}" http://$DOMAIN$ep || true)
  echo "$ep -> HTTP $code"
  [[ "$code" == "404" ]] && warn "$ep возвращает 404 (маршрутизация не исправлена)"
  [[ "$code" != "404" ]] && ok "$ep не 404 (код=$code)"
done

step "5. Прямой тест backend (loopback)"
for ep in /api/retouch /api/retouch-json; do
  code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:${BACKEND_PORT}$ep || true)
  echo "127.0.0.1:${BACKEND_PORT}$ep -> HTTP $code"
  if [[ "$code" == "000" ]]; then warn "Нет соединения с backend портом ${BACKEND_PORT}"; fi
done

step "6. Пробный JSON fallback POST (минимальный)"
IMG_B64='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9YV7tV0AAAAASUVORK5CYII='
JSON_PAYLOAD=$(cat <<JSON
{ "imageData": "data:image/png;base64,$IMG_B64", "maskData": "data:image/png;base64,$IMG_B64", "prompt": "diag", "negative_prompt": "none" }
JSON
)
code=$(curl -s -o /tmp/retouch_json_test.out -w "%{http_code}" -H 'Content-Type: application/json' -X POST http://$DOMAIN/api/retouch-json -d "$JSON_PAYLOAD" || true)
echo "POST /api/retouch-json -> HTTP $code (body saved /tmp/retouch_json_test.out)"
[[ "$code" == "404" ]] && warn "JSON fallback маршрут всё ещё 404" || ok "JSON fallback маршрут отвечает (код=$code)"

step "7. Резюме"
cat <<EOF
====================================
РЕЗЮМЕ:
DOMAIN: $DOMAIN
Backend port: $BACKEND_PORT
retouch location: $( [[ -n "$MATCH_RETOUCH" ]] && echo PRESENT || echo MISSING )
retouch-json location: $( [[ -n "$MATCH_JSON" ]] && echo PRESENT || echo MISSING )
Последний HTTP /api/retouch-json: $code
Если /api/retouch-json не 200/400/500, а 404 — проверьте какой конфиг реально загружается (nginx -T) или внешний CDN.
Логи backend (pm2 logs backend) помогут если код 500.
====================================
EOF

ok "Диагностика завершена"
