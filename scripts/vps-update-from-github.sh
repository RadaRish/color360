#!/bin/bash
# Lightweight updater for deploying the latest Color360 build from GitHub onto a VPS
# Usage (defaults are suitable for production host):
#   ./vps-update-from-github.sh
# Environment / CLI overrides:
#   PROJECT_DIR=/var/www/color360 BRANCH=main ./vps-update-from-github.sh
#   ./vps-update-from-github.sh --project /opt/color360 --branch develop --skip-backup

set -euo pipefail

# --- Defaults ---------------------------------------------------------------
PROJECT_DIR=${PROJECT_DIR:-/var/www/color360}
BACKUP_DIR=${BACKUP_DIR:-/var/www/color360-backups}
REPO_URL=${REPO_URL:-https://github.com/RadaRish/color360.git}
BRANCH=${BRANCH:-main}
APP_USER=${APP_USER:-color360}
SERVICES=${SERVICES:-"color360-app color360-sd nginx"}
SKIP_BACKUP=0
HEALTHCHECK=${HEALTHCHECK:-1}
NODE_ENV_INSTALL_FLAGS=${NODE_ENV_INSTALL_FLAGS:---production}
PYTHON_ENV_DIR=${PYTHON_ENV_DIR:-sd_env}
PYTHON_REQUIREMENTS=${PYTHON_REQUIREMENTS:-sd/requirements.txt}

# --- Helpers ----------------------------------------------------------------
log()  { printf '\n%s %s\n' "[$(date +%H:%M:%S)]" "$*"; }
warn() { printf '\n%s %s\n' "[$(date +%H:%M:%S)]" "⚠️  $*" >&2; }
die()  { printf '\n%s %s\n' "[$(date +%H:%M:%S)]" "❌ $*" >&2; exit 1; }

run_root() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

run_as_app() {
  if [[ $EUID -eq 0 ]]; then
    sudo -u "$APP_USER" -H -- "$@"
  else
    "$@"
  fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

print_usage() {
  cat <<EOF
Usage: ${0##*/} [options]

Options:
  -p, --project DIR      Путь до каталога проекта (default: $PROJECT_DIR)
  -b, --branch  NAME     Ветка Git для деплоя (default: $BRANCH)
  -r, --repo    URL      Git-репозиторий (default: $REPO_URL)
  -u, --user    NAME     Системный пользователь приложения (default: $APP_USER)
  -s, --services LIST    Сервисы systemd через пробел (default: "$SERVICES")
  --skip-backup          Пропустить создание tar-бэкапа перед обновлением
  --no-healthcheck       Не выполнять curl-проверки после рестарта
  -h, --help             Показать помощь
EOF
}

# --- CLI parsing ------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)
      PROJECT_DIR=$2; shift 2;;
    -b|--branch)
      BRANCH=$2; shift 2;;
    -r|--repo)
      REPO_URL=$2; shift 2;;
    -u|--user)
      APP_USER=$2; shift 2;;
    -s|--services)
      SERVICES=$2; shift 2;;
    --skip-backup)
      SKIP_BACKUP=1; shift;;
    --no-healthcheck)
      HEALTHCHECK=0; shift;;
    -h|--help)
      print_usage; exit 0;;
    *)
      die "Неизвестный параметр: $1";;
  esac
done

# --- Preconditions ----------------------------------------------------------
[[ -d $(dirname "$PROJECT_DIR") || $EUID -eq 0 ]] || die "Каталог $(dirname "$PROJECT_DIR") недоступен. Запустите скрипт через sudo."

for bin in git npm curl; do
  command_exists "$bin" || die "Требуется установить '$bin' перед запуском."
done

if [[ -f "$PYTHON_REQUIREMENTS" || -d "$PYTHON_ENV_DIR" ]]; then
  command_exists python3 || warn "python3 не найден — пропускаю python зависимости"
fi

# Создаём системного пользователя при необходимости
if [[ $EUID -eq 0 ]] && ! id "$APP_USER" &>/dev/null; then
  log "Создаём пользователя $APP_USER"
  useradd -r -s /bin/bash -d "$PROJECT_DIR" "$APP_USER" || true
fi

# --- Состояние диска --------------------------------------------------------
DISK_USAGE=$(df "$(dirname "$PROJECT_DIR")" | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ -n "$DISK_USAGE" && "$DISK_USAGE" -ge 95 ]]; then
  die "На диске занято ${DISK_USAGE}%. Освободите место прежде чем продолжить."
elif [[ -n "$DISK_USAGE" && "$DISK_USAGE" -ge 85 ]]; then
  warn "На диске занято ${DISK_USAGE}%. Рекомендуется очистка."
fi

# --- Получение исходников ---------------------------------------------------
if [[ ! -d "$PROJECT_DIR/.git" ]]; then
  log "Каталог проекта не найден или не инициализирован. Подготавливаю..."
  run_root mkdir -p "$(dirname "$PROJECT_DIR")"

  if [[ -d "$PROJECT_DIR" ]] && [[ -n "$(ls -A "$PROJECT_DIR" 2>/dev/null)" ]]; then
    die "Каталог $PROJECT_DIR уже существует и не пуст. Переместите его или укажите --project для другого пути."
  fi

  run_root rm -rf "$PROJECT_DIR"
  run_root git clone "$REPO_URL" "$PROJECT_DIR"
fi

if [[ ! -d "$PROJECT_DIR/.git" ]]; then
  die "Каталог $PROJECT_DIR не является Git-репозиторием"
fi

# Убеждаемся, что origin указывает на нужный URL
cd "$PROJECT_DIR"
CURRENT_REMOTE=$(git remote get-url origin)
if [[ "$CURRENT_REMOTE" != "$REPO_URL" ]]; then
  log "Обновляю origin URL ($CURRENT_REMOTE -> $REPO_URL)"
  git remote set-url origin "$REPO_URL"
fi

git fetch origin "$BRANCH"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
  log "Переключаюсь на ветку $BRANCH"
  git checkout "$BRANCH"
fi

# --- Резервная копия --------------------------------------------------------
if [[ $SKIP_BACKUP -eq 0 ]]; then
  log "Создание резервной копии в $BACKUP_DIR"
  run_root mkdir -p "$BACKUP_DIR"
  BACKUP_FILE="${BACKUP_DIR}/color360-$(date +%Y%m%d-%H%M%S).tar.gz"
  run_root tar -czf "$BACKUP_FILE" --exclude='.git' -C "$(dirname "$PROJECT_DIR")" "$(basename "$PROJECT_DIR")"
  log "Бэкап сохранён: $BACKUP_FILE"
else
  warn "Создание бэкапа отключено"
fi

# --- Обновление репозитория -------------------------------------------------
if ! git diff --quiet || ! git diff --cached --quiet; then
  warn "Обнаружены локальные изменения. Сохраняю их в stash."
  git stash push -m "pre-update $(date +%Y-%m-%d_%H-%M-%S)"
fi

log "Синхронизация с origin/$BRANCH"
git reset --hard "origin/$BRANCH"
git clean -fd

# --- Права ------------------------------------------------------------------
if [[ $EUID -eq 0 ]]; then
  run_root chown -R "$APP_USER":"$APP_USER" "$PROJECT_DIR"
fi

# --- Node.js зависимости ----------------------------------------------------
if [[ -f package.json ]]; then
  log "Обновление Node.js зависимостей"
  if [[ -f package-lock.json ]]; then
    run_as_app npm ci $NODE_ENV_INSTALL_FLAGS
  else
    run_as_app npm install $NODE_ENV_INSTALL_FLAGS
  fi
else
  warn "package.json не найден — пропускаю npm install"
fi

# --- Python зависимости -----------------------------------------------------
if [[ -f "$PYTHON_REQUIREMENTS" ]]; then
  if ! command_exists python3 || ! command_exists pip; then
    warn "python3/pip отсутствуют — пропускаю обновление Python окружения"
  else
  log "Обновление Python окружения"
  run_as_app mkdir -p "$PROJECT_DIR/$PYTHON_ENV_DIR"
    if [[ ! -d "$PROJECT_DIR/$PYTHON_ENV_DIR/bin" ]]; then
      log "Создаю виртуальное окружение $PYTHON_ENV_DIR"
      run_as_app python3 -m venv "$PROJECT_DIR/$PYTHON_ENV_DIR"
    fi
    run_as_app "$PROJECT_DIR/$PYTHON_ENV_DIR/bin/pip" install --upgrade pip
    run_as_app "$PROJECT_DIR/$PYTHON_ENV_DIR/bin/pip" install --upgrade -r "$PYTHON_REQUIREMENTS"
  fi
else
  log "Python зависимости отсутствуют — шаг пропущен"
fi

# --- Сборка фронтенда при необходимости -------------------------------------
if [[ -f package.json && -f scripts/build-frontend.sh ]]; then
  log "Запуск дополнительных build-скриптов"
  run_as_app bash scripts/build-frontend.sh
fi

# --- Рестарт сервисов -------------------------------------------------------
log "Перезапуск сервисов: $SERVICES"
for svc in $SERVICES; do
  if run_root systemctl list-unit-files | awk '{print $1}' | grep -qx "${svc}.service"; then
    run_root systemctl restart "$svc" || warn "Не удалось перезапустить $svc"
  else
    warn "Сервис $svc не найден в systemd — пропускаю"
  fi
done

# --- Проверка состояния -----------------------------------------------------
if [[ $HEALTHCHECK -eq 1 ]]; then
  log "Health-check основных endpoint'ов"
  if curl -fsS "http://localhost:3000/" >/dev/null; then
    log "Main app OK (http://localhost:3000/)"
  else
    warn "Главное приложение не ответило на http://localhost:3000/"
  fi

  if curl -fsS "http://localhost:5002/health" >/dev/null; then
    log "Stable Diffusion OK (http://localhost:5002/health)"
  else
    warn "AI сервис не ответил на http://localhost:5002/health"
  fi
fi

log "Готово! Коммит: $(git rev-parse --short HEAD)"
log "Использовано репо: $REPO_URL (ветка $BRANCH)"
log "Следите за логами: journalctl -u ${SERVICES// / -u } -f"
