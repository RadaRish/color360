#!/bin/bash
# Скрипт обновления Color360 на VPS сервере
# Автоматически загружает изменения с GitHub и перезапускает сервисы
# Версия: 2.0 - Улучшенная обработка конфликтов и автоматическое решение проблем
# 
# ВНИМАНИЕ: Резервные копии НЕ создаются автоматически!
# При необходимости создавайте резервные копии вручную перед обновлением.

set -euo pipefail

# Конфигурация (можно переопределить через переменные окружения)
PROJECT_DIR="${PROJECT_DIR:-/var/www/color360}"
GIT_REPO="${GIT_REPO:-https://github.com/RadaRish/color360.git}"
BRANCH="${BRANCH:-main}"
APP_USER="${APP_USER:-color360}"
SERVICES="${SERVICES:-color360-app color360-sd nginx}"
FORCE_UPDATE="${FORCE_UPDATE:-false}"

# Цвета для логов
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

log_info "Запуск обновления Color360 на VPS сервере..."
log_info "Проект: $PROJECT_DIR | Ветка: $BRANCH | Пользователь: $APP_USER"

# Функция проверки команд
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Команда '$1' не найдена. Установите её перед запуском."
        exit 1
    fi
}

# Проверяем необходимые команды
for cmd in git npm curl systemctl; do
    check_command "$cmd"
done

# Функция для запуска команд от нужного пользователя
run_as_user() {
    if [[ $EUID -eq 0 ]]; then
        sudo -u "$APP_USER" -H "$@"
    else
        "$@"
    fi
}

# Функция для запуска команд от root
run_as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Проверяем место на диске
check_disk_space() {
    local disk_usage
    disk_usage=$(df "$(dirname "$PROJECT_DIR")" | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [[ -n "$disk_usage" && "$disk_usage" -ge 95 ]]; then
        log_error "Критически мало места на диске (${disk_usage}%)."
        log_info "Запустите очистку: wget -qO- https://raw.githubusercontent.com/RadaRish/color360/main/clean-vps-disk.sh | bash"
        exit 1
    elif [[ -n "$disk_usage" && "$disk_usage" -ge 85 ]]; then
        log_warning "Диск заполнен на ${disk_usage}%. Рекомендуется очистка."
    else
        log_success "Свободное место на диске: $((100-disk_usage))%"
    fi
}

check_disk_space

# Создаём системного пользователя при необходимости
if [[ $EUID -eq 0 ]] && ! id "$APP_USER" &>/dev/null; then
    log_info "Создание пользователя $APP_USER"
    useradd -r -s /bin/bash -d "$PROJECT_DIR" "$APP_USER" || true
fi

# Проверяем и создаём директорию проекта
if [[ ! -d "$PROJECT_DIR" ]]; then
    log_info "Создание директории проекта: $PROJECT_DIR"
    run_as_root mkdir -p "$PROJECT_DIR"
    run_as_root chown "$APP_USER":"$APP_USER" "$PROJECT_DIR"
fi

# Функция очистки временных файлов
cleanup_temp_files() {
    log_info "Очистка временных файлов и кэшей"
    local cleanup_paths=(
        "$PROJECT_DIR/temp/*"
        "$PROJECT_DIR/.cache/*"
        "$PROJECT_DIR/node_modules/.cache"
        "$PROJECT_DIR/*.log"
        "/tmp/color360*"
    )
    
    for path in "${cleanup_paths[@]}"; do
        run_as_root rm -rf $path 2>/dev/null || true
    done
}

cleanup_temp_files

# Функция остановки сервисов
stop_services() {
    log_info "Остановка сервисов: $SERVICES"
    for service in $SERVICES; do
        if run_as_root systemctl is-active --quiet "$service" 2>/dev/null; then
            log_info "Остановка $service"
            run_as_root systemctl stop "$service" || log_warning "Не удалось остановить $service"
        else
            log_info "Сервис $service уже остановлен"
        fi
    done
}

# Функция обновления Git репозитория
update_git_repo() {
    log_info "Проверка и обновление Git репозитория"
    
    # Переходим в директорию проекта или клонируем репозиторий
    if [[ ! -d "$PROJECT_DIR/.git" ]]; then
        log_info "Git репозиторий не найден. Клонирование..."
        run_as_root rm -rf "$PROJECT_DIR"
        run_as_root git clone "$GIT_REPO" "$PROJECT_DIR"
        run_as_root chown -R "$APP_USER":"$APP_USER" "$PROJECT_DIR"
    fi
    
    cd "$PROJECT_DIR"
    
    # Настройка безопасности Git
    if [[ $EUID -eq 0 ]]; then
        git config --global --add safe.directory "$PROJECT_DIR"
    fi
    
    # Убеждаемся что remote правильный
    local current_remote
    current_remote=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ "$current_remote" != "$GIT_REPO" ]]; then
        log_info "Обновление remote URL: $current_remote -> $GIT_REPO"
        git remote set-url origin "$GIT_REPO"
    fi
    
    # Получаем информацию о ветках
    git fetch origin "$BRANCH" || {
        log_error "Не удалось получить обновления из репозитория"
        exit 1
    }
    
    # Проверяем текущую ветку
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [[ "$current_branch" != "$BRANCH" ]]; then
        log_info "Переключение на ветку $BRANCH"
        git checkout -B "$BRANCH" "origin/$BRANCH"
    fi
    
    # Обработка локальных изменений
    if ! git diff --quiet || ! git diff --cached --quiet; then
        if [[ "$FORCE_UPDATE" == "true" ]]; then
            log_warning "Принудительный сброс локальных изменений"
            git reset --hard HEAD
            git clean -fd
        else
            log_info "Сохранение локальных изменений в stash"
            git stash push -m "Auto-stash before update $(date +%Y-%m-%d_%H-%M-%S)"
        fi
    fi
    
    # Получаем последние изменения
    log_info "Синхронизация с origin/$BRANCH"
    git reset --hard "origin/$BRANCH"
    git clean -fd
    
    # Показываем информацию о коммите
    local commit_hash
    commit_hash=$(git rev-parse --short HEAD)
    local commit_msg
    commit_msg=$(git log -1 --pretty=format:"%s")
    log_success "Обновлён до коммита $commit_hash: $commit_msg"
}

stop_services
update_git_repo

# Функция обновления зависимостей
update_dependencies() {
    log_info "Установка прав доступа"
    run_as_root chown -R "$APP_USER":"$APP_USER" "$PROJECT_DIR"
    
    # Node.js зависимости
    if [[ -f "package.json" ]]; then
        log_info "Обновление Node.js зависимостей"
        if [[ -f "package-lock.json" ]]; then
            run_as_user npm ci --production
        else
            run_as_user npm install --production
        fi
        log_success "Node.js зависимости обновлены"
    else
        log_warning "package.json не найден - пропускаем npm install"
    fi
    
    # Python зависимости
    if [[ -f "sd/requirements.txt" ]]; then
        log_info "Проверка Python зависимостей"
        
        if [[ ! -d "sd_env" ]]; then
            log_info "Создание Python виртуального окружения"
            run_as_user python3 -m venv sd_env
        fi
        
        log_info "Обновление Python пакетов"
        run_as_user bash -c "source sd_env/bin/activate && pip install --upgrade pip && pip install --upgrade -r sd/requirements.txt"
        log_success "Python зависимости обновлены"
    else
        log_info "Python зависимости не найдены - пропускаем"
    fi
}

update_dependencies

# Функция настройки сервисов
setup_services() {
    log_info "Настройка systemd сервисов"
    
    # Создание сервиса основного приложения
    if ! run_as_root systemctl is-enabled color360-app >/dev/null 2>&1; then
        log_info "Создание сервиса color360-app"
        run_as_root tee /etc/systemd/system/color360-app.service > /dev/null << EOF
[Unit]
Description=Color360 Main Application
After=network.target
Wants=color360-sd.service

[Service]
Type=simple
User=$APP_USER
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

NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$PROJECT_DIR
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
        
        run_as_root systemctl daemon-reload
        run_as_root systemctl enable color360-app
        log_success "Сервис color360-app создан и включён"
    fi
    
    # Создание сервиса Stable Diffusion
    if [[ -f "sd/requirements.txt" ]] && ! run_as_root systemctl is-enabled color360-sd >/dev/null 2>&1; then
        log_info "Создание сервиса color360-sd"
        run_as_root tee /etc/systemd/system/color360-sd.service > /dev/null << EOF
[Unit]
Description=Color360 Stable Diffusion Service
After=network.target

[Service]
Type=simple
User=$APP_USER
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

NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$PROJECT_DIR
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
        
        run_as_root systemctl daemon-reload
        run_as_root systemctl enable color360-sd
        log_success "Сервис color360-sd создан и включён"
    fi
}

# Функция запуска сервисов
start_services() {
    log_info "Запуск сервисов"
    
    # Проверка nginx конфигурации
    if run_as_root nginx -t 2>/dev/null; then
        log_success "Конфигурация nginx корректна"
    else
        log_warning "Проблемы с конфигурацией nginx"
    fi
    
    # Запуск сервисов по порядку
    for service in $SERVICES; do
        if run_as_root systemctl list-unit-files | grep -q "^${service}.service"; then
            log_info "Запуск $service"
            run_as_root systemctl start "$service" || log_warning "Не удалось запустить $service"
            
            # Для SD сервиса даём больше времени на запуск
            if [[ "$service" == "color360-sd" ]]; then
                sleep 8
            else
                sleep 2
            fi
        else
            log_warning "Сервис $service не найден"
        fi
    done
}

setup_services
start_services
# Функция проверки статуса сервисов
check_services_status() {
    log_info "Проверка статуса сервисов (ожидание 15 секунд)"
    sleep 15
    
    local all_ok=true
    
    for service in $SERVICES; do
        if run_as_root systemctl list-unit-files | grep -q "^${service}.service"; then
            if run_as_root systemctl is-active --quiet "$service"; then
                log_success "Сервис $service активен"
            else
                log_error "Сервис $service неактивен"
                log_info "Логи $service:"
                run_as_root journalctl -u "$service" --no-pager -n 5 || true
                all_ok=false
            fi
        fi
    done
    
    return $([ "$all_ok" = true ])
}

# Функция тестирования endpoint'ов
test_endpoints() {
    log_info "Тестирование доступности сервисов"
    
    # Тест основного приложения
    if curl -fsS --connect-timeout 10 --max-time 30 "http://localhost:3000/" >/dev/null 2>&1; then
        log_success "Основное приложение доступно (http://localhost:3000/)"
    else
        log_warning "Основное приложение недоступно"
    fi
    
    # Тест AI сервиса (если есть)
    if systemctl list-unit-files | grep -q "^color360-sd.service"; then
        if curl -fsS --connect-timeout 5 --max-time 15 "http://localhost:5002/health" >/dev/null 2>&1; then
            log_success "AI сервис доступен (http://localhost:5002/health)"
        else
            log_warning "AI сервис недоступен (может еще запускаться)"
        fi
    fi
}

# Функция финального отчёта
final_report() {
    local commit_hash
    commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local commit_msg
    commit_msg=$(git log -1 --pretty=format:"%s" 2>/dev/null || echo "")
    
    echo ""
    log_success "🎉 Обновление Color360 завершено!"
    echo ""
    log_info "📋 Информация об обновлении:"
    echo "   📅 Время: $(date)"
    echo "   🌿 Ветка: $BRANCH"
    echo "   📝 Коммит: $commit_hash"
    echo "   💬 Сообщение: $commit_msg"
    echo "   👤 Пользователь: $APP_USER"
    echo "   📂 Директория: $PROJECT_DIR"
    echo ""
    log_info "📊 Полезные команды:"
    echo "   # Статус сервисов"
    echo "   systemctl status $SERVICES"
    echo ""
    echo "   # Просмотр логов"
    echo "   journalctl -u color360-app -f"
    echo "   journalctl -u color360-sd -f"
    echo ""
    echo "   # Управление"
    echo "   systemctl restart $SERVICES"
    echo "   systemctl stop $SERVICES"
}

# Финальная очистка
cleanup_final() {
    log_info "Финальная очистка системы"
    run_as_root npm cache clean --force 2>/dev/null || true
    run_as_root find /var/log -name "*.log" -mtime +7 -delete 2>/dev/null || true
    run_as_root find /tmp -name "*color360*" -mtime +1 -delete 2>/dev/null || true
    log_success "Система очищена"
}

# Выполнение финальных шагов
check_services_status
test_endpoints
cleanup_final
final_report