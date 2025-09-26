#!/bin/bash
# Легковесный скрипт быстрого обновления Color360
# Загружает изменения с GitHub без создания резервных копий
# Версия: 1.0

set -euo pipefail

# Конфигурация
PROJECT_DIR="${PROJECT_DIR:-/var/www/color360}"
BRANCH="${BRANCH:-main}"
APP_USER="${APP_USER:-color360}"

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

log_info "Запуск быстрого обновления Color360..."

# Проверяем существование проекта
if [[ ! -d "$PROJECT_DIR" ]]; then
    log_error "Проект не найден в $PROJECT_DIR"
    log_info "Используйте полный скрипт установки: curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/update-vps.sh | sudo bash"
    exit 1
fi

cd "$PROJECT_DIR"

# Функция для выполнения команд от имени пользователя
run_as_user() {
    if [[ $EUID -eq 0 ]]; then
        if id "$APP_USER" &>/dev/null; then
            su - "$APP_USER" -c "cd '$PROJECT_DIR' && $*"
        else
            log_warning "Пользователь $APP_USER не найден, выполняем от root"
            cd "$PROJECT_DIR" && "$@"
        fi
    else
        "$@"
    fi
}

# Функция для npm команд
run_npm_as_user() {
    local npm_cmd="$*"
    
    if [[ $EUID -eq 0 ]]; then
        if id "$APP_USER" &>/dev/null; then
            if su - "$APP_USER" -c "cd '$PROJECT_DIR' && $npm_cmd" 2>/dev/null; then
                return 0
            fi
            log_warning "Выполнение npm от root..."
            cd "$PROJECT_DIR" && $npm_cmd
            chown -R "$APP_USER":"$APP_USER" "$PROJECT_DIR"
        else
            cd "$PROJECT_DIR" && $npm_cmd
        fi
    else
        cd "$PROJECT_DIR" && $npm_cmd
    fi
}

# Остановка сервисов
log_info "Остановка сервисов..."
sudo systemctl stop color360-app color360-sd 2>/dev/null || true

# Обновление кода
log_info "Получение изменений с GitHub..."
run_as_user git fetch origin

# Проверка наличия изменений
LOCAL_COMMIT=$(git rev-parse HEAD)
REMOTE_COMMIT=$(git rev-parse origin/$BRANCH)

if [[ "$LOCAL_COMMIT" == "$REMOTE_COMMIT" ]]; then
    log_success "Код уже актуален (коммит: ${LOCAL_COMMIT:0:8})"
else
    log_info "Обнаружены изменения. Обновление..."
    
    # Сохранение локальных изменений (если есть)
    if ! run_as_user git diff --quiet; then
        log_warning "Обнаружены локальные изменения. Сохранение в stash..."
        run_as_user git stash push -m "Auto-stash before update $(date)"
    fi
    
    # Применение изменений
    run_as_user git reset --hard origin/$BRANCH
    log_success "Код обновлён (${REMOTE_COMMIT:0:8})"
fi

# Проверка зависимостей
if [[ -f "package.json" ]]; then
    log_info "Проверка Node.js зависимостей..."
    if [[ -f "package-lock.json" ]]; then
        run_npm_as_user npm ci --production --silent
    else
        run_npm_as_user npm install --production --silent
    fi
    log_success "Зависимости проверены"
fi

# Запуск сервисов
log_info "Запуск сервисов..."
sudo systemctl start color360-app
sleep 3
sudo systemctl start color360-sd 2>/dev/null || true
sleep 2

# Проверка статуса
if systemctl is-active --quiet color360-app; then
    log_success "Основное приложение запущено"
else
    log_error "Ошибка запуска основного приложения"
    sudo journalctl -u color360-app --no-pager -n 5
    exit 1
fi

# Тест доступности
if curl -fsS --connect-timeout 5 "http://localhost:3000/" >/dev/null 2>&1; then
    log_success "Приложение доступно на http://localhost:3000/"
else
    log_warning "Приложение может еще запускаться..."
fi

# Итоговая информация
CURRENT_COMMIT=$(git rev-parse --short HEAD)
COMMIT_MSG=$(git log -1 --pretty=format:"%s" 2>/dev/null || echo "")

echo ""
log_success "🎉 Быстрое обновление завершено!"
echo ""
log_info "📝 Текущий коммит: $CURRENT_COMMIT"
log_info "💬 Сообщение: $COMMIT_MSG"
log_info "🕒 Время: $(date)"
echo ""
log_info "🔍 Для проверки статуса:"
echo "   systemctl status color360-app color360-sd"
echo ""
log_info "📖 Полная документация:"
echo "   https://github.com/RadaRish/color360/blob/main/INSTALL-UPDATE-GUIDE.md"