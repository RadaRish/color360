#!/bin/bash
# Скрипт обновления Color360 для VPS (упрощенная версия для root)
# Работает полностью от пользователя root без создания отдельного пользователя
# Версия: 1.0

set -euo pipefail

# Конфигурация
PROJECT_DIR="${PROJECT_DIR:-/var/www/color360}"
GIT_REPO="${GIT_REPO:-https://github.com/RadaRish/color360.git}"
BRANCH="${BRANCH:-main}"
SERVICES="${SERVICES:-color360-app color360-sd nginx}"
FORCE_UPDATE="${FORCE_UPDATE:-false}"

# Цвета для логов
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

log_info "Запуск упрощенного обновления Color360 (от root)"
log_info "Проект: $PROJECT_DIR | Ветка: $BRANCH"

# Проверка что скрипт запущен от root
if [[ $EUID -ne 0 ]]; then
    log_error "Этот скрипт должен запускаться от root. Используйте: sudo $0"
    exit 1
fi

# Проверка команд
for cmd in git npm curl systemctl; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Команда '$cmd' не найдена. Установите её перед запуском."
        exit 1
    fi
done

# Проверка места на диске
check_disk_space() {
    local disk_usage
    disk_usage=$(df "$(dirname "$PROJECT_DIR")" | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [[ -n "$disk_usage" && "$disk_usage" -ge 95 ]]; then
        log_error "Критически мало места на диске (${disk_usage}%)."
        exit 1
    elif [[ -n "$disk_usage" && "$disk_usage" -ge 85 ]]; then
        log_warning "Диск заполнен на ${disk_usage}%. Рекомендуется очистка."
    else
        log_success "Свободное место на диске: $((100-disk_usage))%"
    fi
}

check_disk_space

# Создание директории проекта
if [[ ! -d "$PROJECT_DIR" ]]; then
    log_info "Создание директории проекта: $PROJECT_DIR"
    mkdir -p "$PROJECT_DIR"
fi

# Остановка сервисов
log_info "Остановка сервисов: $SERVICES"
for service in $SERVICES; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        log_info "Остановка $service"
        systemctl stop "$service" || log_warning "Не удалось остановить $service"
    fi
done

# Обновление Git репозитория
log_info "Обновление репозитория"
if [[ ! -d "$PROJECT_DIR/.git" ]]; then
    log_info "Клонирование репозитория..."
    rm -rf "$PROJECT_DIR"
    git clone "$GIT_REPO" "$PROJECT_DIR"
else
    cd "$PROJECT_DIR"
    
    # Настройка безопасности Git
    git config --global --add safe.directory "$PROJECT_DIR"
    
    # Получение изменений
    git fetch origin
    
    # Сохранение локальных изменений
    if ! git diff --quiet; then
        log_info "Сохранение локальных изменений"
        git stash push -m "Auto-stash before update $(date '+%Y-%m-%d_%H-%M-%S')"
    fi
    
    # Обновление до последней версии
    git reset --hard origin/$BRANCH
    git clean -fd
    
    local commit_hash
    commit_hash=$(git rev-parse --short HEAD)
    local commit_msg
    commit_msg=$(git log -1 --pretty=format:"%s")
    log_success "Обновлён до коммита $commit_hash: $commit_msg"
fi

cd "$PROJECT_DIR"

# Обновление зависимостей
if [[ -f "package.json" ]]; then
    log_info "Обновление Node.js зависимостей"
    
    # Очищаем npm кэш для избежания проблем
    npm cache clean --force 2>/dev/null || true
    
    if [[ -f "package-lock.json" ]]; then
        npm ci --production
    else
        npm install --production
    fi
    log_success "Node.js зависимости обновлены"
fi

# Python зависимости
if [[ -f "sd/requirements.txt" ]]; then
    log_info "Обновление Python зависимостей"
    
    if [[ ! -d "sd_env" ]]; then
        log_info "Создание Python окружения"
        python3 -m venv sd_env
    fi
    
    source sd_env/bin/activate
    pip install --upgrade pip
    pip install --upgrade -r sd/requirements.txt
    deactivate
    
    log_success "Python зависимости обновлены"
fi

# Настройка сервисов
log_info "Настройка systemd сервисов"

# Создание основного сервиса
cat > /etc/systemd/system/color360-app.service << EOF
[Unit]
Description=Color360 Main Application
After=network.target
Wants=color360-sd.service

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5
StartLimitInterval=60s
StartLimitBurst=3

Environment=NODE_ENV=production
Environment=PORT=3000
Environment=SD_PORT=5002
Environment=SD_HOST=127.0.0.1

[Install]
WantedBy=multi-user.target
EOF

# Создание AI сервиса (если есть)
if [[ -f "sd/requirements.txt" ]]; then
cat > /etc/systemd/system/color360-sd.service << EOF
[Unit]
Description=Color360 Stable Diffusion Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_DIR/sd
Environment=PATH=$PROJECT_DIR/sd_env/bin
ExecStart=$PROJECT_DIR/sd_env/bin/python lama_service.py
Restart=always
RestartSec=10
StartLimitInterval=60s
StartLimitBurst=3

Environment=PORT=5002
Environment=HOST=127.0.0.1
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF
fi

# Перезагрузка systemd и включение сервисов
systemctl daemon-reload
systemctl enable color360-app
if [[ -f "sd/requirements.txt" ]]; then
    systemctl enable color360-sd
fi

# Запуск сервисов
log_info "Запуск сервисов"
systemctl start color360-app
sleep 3

if systemctl list-unit-files | grep -q "color360-sd.service"; then
    systemctl start color360-sd
    sleep 5
fi

if systemctl list-unit-files | grep -q "nginx.service"; then
    # Проверка конфигурации nginx
    if nginx -t 2>/dev/null; then
        systemctl start nginx
    else
        log_warning "Проблемы с конфигурацией nginx"
    fi
fi

# Проверка статуса
log_info "Проверка статуса сервисов"
sleep 10

all_ok=true
for service in $SERVICES; do
    if systemctl list-unit-files | grep -q "^${service}.service"; then
        if systemctl is-active --quiet "$service"; then
            log_success "Сервис $service активен"
        else
            log_error "Сервис $service неактивен"
            journalctl -u "$service" --no-pager -n 5 || true
            all_ok=false
        fi
    fi
done

# Тестирование endpoint'ов
log_info "Тестирование доступности"
if curl -fsS --connect-timeout 10 "http://localhost:3000/" >/dev/null 2>&1; then
    log_success "Основное приложение доступно"
else
    log_warning "Основное приложение недоступно"
fi

if systemctl list-unit-files | grep -q "color360-sd.service"; then
    if curl -fsS --connect-timeout 5 "http://localhost:5002/health" >/dev/null 2>&1; then
        log_success "AI сервис доступен"
    else
        log_warning "AI сервис недоступен"
    fi
fi

# Финальный отчёт
commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
commit_msg=$(git log -1 --pretty=format:"%s" 2>/dev/null || echo "")

echo ""
log_success "🎉 Упрощенное обновление Color360 завершено!"
echo ""
log_info "📋 Информация:"
echo "   📅 Время: $(date)"
echo "   🌿 Ветка: $BRANCH"
echo "   📝 Коммит: $commit_hash"
echo "   💬 Сообщение: $commit_msg"
echo "   📂 Директория: $PROJECT_DIR"
echo "   👤 Пользователь: root"
echo ""
log_info "🔍 Полезные команды:"
echo "   systemctl status $SERVICES"
echo "   journalctl -u color360-app -f"
echo "   journalctl -u color360-sd -f"

if [[ "$all_ok" != "true" ]]; then
    echo ""
    log_warning "⚠️  Некоторые сервисы работают некорректно. Проверьте логи выше."
    exit 1
fi