#!/bin/bash
# ============================================================================
#  Color360 – Автоматическое исправление бага ретуши (RetouchManager / LaMa)
# ----------------------------------------------------------------------------
#  Что делает скрипт:
#   1. Находит активные файлы retouch_manager.js в проде
#   2. Делает резервные копии
#   3. Скачивает последнюю версию из репозитория (ветка main)
#   4. Проверяет, что файл содержит новую логику (FastMask / lama endpoint)
#   5. Заменяет все целевые копии (или только основную) — опционально
#   6. Принудительно обновляет HTML (кеш-бамп ?v=TIMESTAMP)
#   7. (Опционально) добавляет принудительную инъекцию force-retouch если файл не подключён
#   8. Выполняет диагностику после замены (curl + grep FastMask)
#   9. Даёт инструкции по проверке в браузере
#
#  Запуск (от root):
#     sudo bash fix-retouch-auto.sh
#  Неинтерактивно (автоматически заменить все найденные):
#     sudo AUTO_Y=1 bash fix-retouch-auto.sh
#  С указанием веб-корня вручную:
#     sudo WEB_ROOT=/var/www/html bash fix-retouch-auto.sh
# ============================================================================

set -euo pipefail

BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
NC='\033[0m'

log() { echo -e "${BLUE}ℹ️  $*${NC}"; }
ok() { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
err() { echo -e "${RED}❌ $*${NC}"; }
step() { echo -e "\n${MAGENTA}🔧 $*${NC}"; }

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  err "Запустите от root: sudo bash $0"; exit 1;
fi

REPO_OWNER="RadaRish"
REPO_NAME="color360"
BRANCH="main"
REMOTE_PATH="pano/ui/retouch_manager.js"
RAW_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/${REMOTE_PATH}"
TS=$(date +%Y%m%d-%H%M%S)

# Определение WEB_ROOT
if [[ -z "${WEB_ROOT:-}" ]]; then
  for c in /var/www/html /usr/share/nginx/html /srv/www/html; do
    if [[ -d $c ]]; then WEB_ROOT="$c"; break; fi
  done
fi
WEB_ROOT=${WEB_ROOT:-/var/www/html}

if [[ ! -d "$WEB_ROOT" ]]; then
  err "WEB_ROOT не существует: $WEB_ROOT (укажите WEB_ROOT=/path)"; exit 1;
fi

OUTPUT_DIR="$PWD"

step "Параметры"
log "WEB_ROOT: $WEB_ROOT"
log "RAW_URL:  $RAW_URL"
log "Timestamp: $TS"

TMP_DIR=$(mktemp -d -t retouch-fix-XXXX)
cleanup() { rm -rf "$TMP_DIR" 2>/dev/null || true; }
trap cleanup EXIT

step "Скачиваем актуальную версию"
curl -fsSL "$RAW_URL" -o "$TMP_DIR/new.js" || { err "Не удалось скачать файл"; exit 1; }

if ! grep -q 'FastMask' "$TMP_DIR/new.js"; then
  warn "Скачанный файл не содержит маркер FastMask — возможно не та версия. Прерывание."
  exit 1
fi
ok "Файл скачан и прошёл первичную проверку (найдено FastMask)"

step "Поиск существующих retouch_manager.js"
mapfile -t FOUND < <(grep -RIl --exclude-dir=node_modules --exclude-dir=.git 'export default class RetouchManager' "$WEB_ROOT" 2>/dev/null | grep 'retouch_manager.js' || true)

if [[ ${#FOUND[@]} -eq 0 ]]; then
  warn "Активные файлы retouch_manager.js не найдены через сигнатуру класса. Ищем по имени..."
  mapfile -t FOUND < <(find "$WEB_ROOT" -type f -name 'retouch_manager.js' 2>/dev/null || true)
fi

if [[ ${#FOUND[@]} -eq 0 ]]; then
  err "Не найден ни один файл retouch_manager.js. Требуется ручная проверка структуры."; exit 1;
fi

echo "Найдено файлов: ${#FOUND[@]}"
idx=0
for f in "${FOUND[@]}"; do
  ((idx++)) || true
  SIZE=$(stat -c %s "$f" 2>/dev/null || echo '?')
  SHA=$(sha1sum "$f" 2>/dev/null | awk '{print $1}')
  echo "  [$idx] $f (size=$SIZE sha1=$SHA)"
done

TARGETS=("${FOUND[@]}")

if [[ -z "${AUTO_Y:-}" ]]; then
  echo
  read -r -p "Заменить ВСЕ найденные файлы? [y/N]: " ans
  if [[ ! $ans =~ ^[Yy]$ ]]; then
    read -r -p "Введите номера через запятую (например 1,3) или 'q' для выхода: " sel
    if [[ $sel == 'q' ]]; then err "Отменено пользователем"; exit 1; fi
    IFS=',' read -r -a nums <<< "$sel"
    NEW_TARGETS=()
    for n in "${nums[@]}"; do
      ntrim=$(echo "$n" | tr -d ' ')
      [[ $ntrim =~ ^[0-9]+$ ]] || continue
      ((ntrim>=1 && ntrim<=${#FOUND[@]})) || continue
      NEW_TARGETS+=("${FOUND[$((ntrim-1))]}")
    done
    if [[ ${#NEW_TARGETS[@]} -eq 0 ]]; then err "Не выбраны цели"; exit 1; fi
    TARGETS=("${NEW_TARGETS[@]}")
  fi
else
  log "AUTO_Y=1 — заменяем все без вопросов"
fi

step "Резервное копирование целей"
BACKUP_ROOT="$OUTPUT_DIR/retouch_backup_$TS"
mkdir -p "$BACKUP_ROOT"
for t in "${TARGETS[@]}"; do
  rel="${t#/}"
  mkdir -p "$BACKUP_ROOT/$(dirname "$rel")"
  cp -a "$t" "$BACKUP_ROOT/$rel"
  ok "Backup: $t -> $BACKUP_ROOT/$rel"
done

step "Замена файлов"
for t in "${TARGETS[@]}"; do
  cp "$TMP_DIR/new.js" "$t"
  chmod 644 "$t" || true
  ok "Обновлён: $t"
done

step "Поиск HTML для обновления cache-bust"
mapfile -t HTMLS < <(grep -RIl '</head>' "$WEB_ROOT" 2>/dev/null | grep -E '\.(html|htm)$' | head -n 200 || true)
if [[ ${#HTMLS[@]} -eq 0 ]]; then
  warn "HTML файлы не найдены (возможно SPA bundling). Пропуск.";
else
  BUST="v=$(date +%s)"
  changed=0
  for h in "${HTMLS[@]}"; do
    if grep -q 'retouch_manager.js' "$h"; then
      if grep -q 'retouch_manager.js?v=' "$h"; then
        # обновим существующий параметр
        sed -i -E "s#(retouch_manager.js\?v=)[0-9A-Za-z_-]+#\\1$BUST#g" "$h" && ((changed++)) || true
      else
        sed -i "s#retouch_manager.js#retouch_manager.js?$BUST#g" "$h" && ((changed++)) || true
      fi
    fi
  done
  ok "Обновлено HTML с cache-bust: $changed шт."
fi

step "Принудительная инъекция (если файл нигде не подключён явно)"
if ! grep -RIl 'retouch_manager.js' "$WEB_ROOT" 2>/dev/null | grep -qE '\.(html|htm)$'; then
  warn "Не нашли прямого подключения retouch_manager.js в HTML. Добавляем force-retouch.js"
  FORCE_JS="$WEB_ROOT/force-retouch.js"
  cat > "$FORCE_JS" <<'EOF'
console.log('🛠 force-retouch bootstrap (auto)');
(function(){
  try {
    const s = document.createElement('script');
    s.src = '/pano/ui/retouch_manager.js?v=' + Date.now();
    document.documentElement.appendChild(s);
  } catch(e) { console.error('force-retouch error', e); }
})();
EOF
  chmod 644 "$FORCE_JS" || true
  # Вставим в первый найденный HTML (если есть вообще какой-то)
  FIRST_HTML=$(find "$WEB_ROOT" -maxdepth 2 -type f -name 'index.html' | head -n1 || true)
  if [[ -n "$FIRST_HTML" ]]; then
    if ! grep -q 'force-retouch.js' "$FIRST_HTML"; then
      sed -i "0,/<\/head>/s//<script src=\"\/force-retouch.js\?v=$TS\"><\/script>\n<\/head>/" "$FIRST_HTML"
      ok "Инжектирован force-retouch.js в $FIRST_HTML"
    fi
  fi
fi

step "Диагностика обновления"
PRIMARY_FETCH="/pano/ui/retouch_manager.js"
if [[ -f "$WEB_ROOT$PRIMARY_FETCH" ]]; then
  if command -v curl >/dev/null 2>&1; then
    STATUS=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost$PRIMARY_FETCH?test=$TS" || true)
    log "HTTP локальный статус: $STATUS (http://localhost$PRIMARY_FETCH)"
    BODY=$(curl -s "http://localhost$PRIMARY_FETCH?test=$TS" | head -n 50)
    if echo "$BODY" | grep -q 'FastMask'; then
      ok "Локальный HTTP отдаёт обновлённый файл (обнаружен FastMask)"
    else
      warn "Локальный HTTP НЕ содержит маркер FastMask — возможен кеш или другой путь."
    fi
  else
    warn "curl не установлен — пропущена HTTP-проверка"
  fi
else
  warn "Ожидаемый путь $WEB_ROOT$PRIMARY_FETCH отсутствует."
fi

step "Итог"
ok "Готово. Проверьте в браузере: откройте /pano/ с Ctrl+F5 и запустите ретушь."
echo -e "${CYAN}Проверьте в консоли браузера наличие логов: '⚡ FastMask:' и запрос на /api/lama/inpaint${NC}"
echo -e "${CYAN}При проблемах: tail -n 200 -f /var/log/nginx/access.log | grep retouch_manager.js${NC}"

exit 0
