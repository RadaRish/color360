#!/usr/bin/env bash
# update-retouch-fallback.sh
# Автоматизация: гарантировать наличие расширенного fallback (400/404/405 -> JSON) в pano/ui/retouch_manager.js
# Возможности:
#  1. Если git-репозиторий доступен — сделает fetch/pull main.
#  2. Если нужные строки не появились, применит встроенный patch (idempotent, --forward).
#  3. Создаст резервную копию исходного файла.
#  4. Перезапустит PM2 (ecosystem*.config.*) если найден pm2.
#  5. Выведет рекомендации при systemd.

set -euo pipefail
IFS=$'\n\t'

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_RESET='\033[0m'

log() { echo -e "${COLOR_GREEN}[retouch-update]${COLOR_RESET} $*"; }
warn() { echo -e "${COLOR_YELLOW}[retouch-update] WARN:${COLOR_RESET} $*" >&2; }
err() { echo -e "${COLOR_RED}[retouch-update] ERROR:${COLOR_RESET} $*" >&2; }

ROOT="${1:-$(pwd)}"
cd "$ROOT" || { err "Не удалось перейти в каталог $ROOT"; exit 1; }

FILE="pano/ui/retouch_manager.js"
if [[ ! -f "$FILE" ]]; then
  err "Файл $FILE не найден. Запусти скрипт из корня проекта или передай путь к корню как аргумент."; exit 1;
fi

# Проверим репозиторий
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  log "Определён git репозиторий (ветка: $CURRENT_BRANCH)"
  # Сохраним локальные правки (если есть unstaged) через stash (опционально)
  if ! git diff --quiet || ! git diff --cached --quiet; then
    warn "Обнаружены несохранённые изменения — временно stash";
    git stash push -u -m "auto-retouch-fallback-before-update" || warn "Stash не выполнен";
    STASHED=1
  fi
  log "Выполняю fetch/pull origin/main"
  git fetch --all --prune || warn "git fetch завершился с предупреждением"
  if git show-ref --verify --quiet refs/heads/main; then
    git checkout main || warn "Не удалось переключиться на main (возможно уже на ней)"
  fi
  git pull --ff-only || warn "git pull не fast-forward. Возможно локальные дивергенции — будет попытка применить patch напрямую"
else
  warn "Каталог не является git репозиторием. Будет использован только встроенный patch."
fi

# Создадим резервную копию
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="${FILE}.bak.${TS}"
cp -p "$FILE" "$BACKUP"
log "Создан backup: $BACKUP"

NEEDED_PATTERN='originalRespStatus'
JSON_FALLBACK_PATTERN='JSON fallback /api/retouch-json'

if grep -q "$NEEDED_PATTERN" "$FILE" && grep -q '404 || resp.status === 405' "$FILE" ; then
  log "Похоже обновление уже присутствует (найдены сигнатуры). Patch не требуется."
  APPLY_PATCH=0
else
  APPLY_PATCH=1
  warn "Сигнатуры не найдены — будет применён встроенный patch.";
fi

read -r -d '' PATCH <<'PATCH_EOF'
*** Begin Patch
*** Update File: pano/ui/retouch_manager.js
@@
-      const loaded = new Promise((res, rej) => {
-        img.onload = () => res(true);
-        img.onerror = (e) => rej(e);
-      });
+      const loaded = new Promise((res) => { img.onload = () => res(true); });
@@
-      const originalRotation = camera.rotation.clone();
+          console.warn(`⚠️ RetouchManager: статус ${resp.status} (original=${originalRespStatus}) от ${endpointUsed}, пробуем JSON fallback /api/retouch-json`);
@@
-        normalVector.copy(intersectionPoint).normalize();
-        
+          const loaded = new Promise((res) => { img.onload = () => res(true); });
@@
-      let resp = await fetch(endpointUsed, { 
-        method: 'POST', 
-        body: fd,
-        timeout: 300000 // 5 минут
-      });
+      let originalRespStatus = null;
+      let resp = await fetch(endpointUsed, { method: 'POST', body: fd, timeout: 300000 });
+      originalRespStatus = resp.status;
@@
-        } else if (resp.status === 400) {
+        } else if (resp.status === 400 || resp.status === 404 || resp.status === 405 || (originalRespStatus === 400 && !resp.ok)) {
           let details = '';
           try { details = await resp.text(); } catch(_){}
-          console.warn('⚠️ RetouchManager: 400 от /api/retouch, пробуем JSON fallback /api/retouch-json');
+          console.warn(`⚠️ RetouchManager: статус ${resp.status} (original=${originalRespStatus}) - пробуем JSON fallback /api/retouch-json`);
*** End Patch
PATCH_EOF

if (( APPLY_PATCH )); then
  # Применяем patch через встроенный мини-патчер (sed/grep) или utility 'apply_patch' если присутствует
  if command -v apply_patch >/dev/null 2>&1; then
    echo "$PATCH" | apply_patch || warn "apply_patch не применил diff — возможно уже применён";
  else
    # Используем patch(1)
    if command -v patch >/dev/null 2>&1; then
      echo "$PATCH" | patch --forward -p0 || warn "patch сообщил об ошибке (вероятно уже применено)";
    else
      warn "Не найден 'patch' — выполняю упрощённые правки через sed (последовательно).";
      # Минимальный набор sed-замен как fallback
      sed -i "s/const loaded = new Promise((res, rej).*/const loaded = new Promise((res) => { img.onload = () => res(true); });/" "$FILE" || true
      grep -q 'originalRespStatus' "$FILE" || sed -i "s/fetch(endpointUsed, {/let originalRespStatus = null;\n      let resp = await fetch(endpointUsed, {/" "$FILE" || true
      grep -q 'originalRespStatus = resp.status' "$FILE" || sed -i "s/let resp = await fetch(endpointUsed, { method: 'POST', body: fd,/let resp = await fetch(endpointUsed, { method: 'POST', body: fd, timeout: 300000 });\n      originalRespStatus = resp.status;/'" "$FILE" || true
      sed -i "s/else if (resp.status === 400) {/else if (resp.status === 400 || resp.status === 404 || resp.status === 405 || (originalRespStatus === 400 && !resp.ok)) {/'" "$FILE" || true
    fi
  fi
else
  log "Пропускаем применение patch — не требуется."
fi

# Быстрая валидация наличия ключевых строк
if grep -q 'originalRespStatus' "$FILE" && grep -q '404 || resp.status === 405' "$FILE"; then
  log "Валидация: расширенный fallback обнаружен ✅"
else
  err "Валидация НЕ прошла — fallback строки не найдены. Проверьте файл вручную: $FILE"; exit 2;
fi

# Commit локально (если внутри git и были изменения)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if ! git diff --quiet "$FILE"; then
    git add "$FILE"
    git commit -m "feat(retouch): ensure extended fallback (auto script)" || warn "commit не выполнен"
    # Пытаемся push (игнорируем ошибку если нет прав)
    git push || warn "git push не выполнен (нет прав или offline)"
  else
    log "Файл не изменился — commit не требуется."
  fi
fi

# Перезапуск сервиса
RESTART_DONE=0
if command -v pm2 >/dev/null 2>&1; then
  if [[ -f ecosystem.config.js || -f ecosystem.config.cjs || -f ecosystem.separate.config.js ]]; then
    log "Перезапуск PM2"
    (pm2 reload ecosystem.config.js 2>/dev/null || pm2 restart ecosystem.config.js 2>/dev/null || pm2 reload ecosystem.separate.config.js 2>/dev/null || pm2 restart ecosystem.separate.config.js 2>/dev/null || true)
    RESTART_DONE=1
  fi
fi

if (( ! RESTART_DONE )); then
  warn "Автоперезапуск не выполнен. Если используется systemd, выполните: systemctl restart color360.service (или другое имя)"
fi

log "Готово."
