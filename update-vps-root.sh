#!/bin/bash
# Скрипт обновления Color360 для VPS (упрощенная версия для root)
# Работает полностью от пользователя root без создания отдельного пользователя
# Версия: 2.0 - Улучшен на основе существующих скриптов из репозитория

set -euo pipefail

# Конфигурация
PROJECT_DIR="${PROJECT_DIR:-/var/www/color360}"
GIT_REPO="${GIT_REPO:-https://github.com/RadaRish/color360.git}"
BRANCH="${BRANCH:-main}"
SERVICES="${SERVICES:-color360-app color360-sd nginx}"
FORCE_UPDATE="${FORCE_UPDATE:-false}"
APP_USER="${APP_USER:-color360}"

# Цвета для логов
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Функции логирования
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_debug() { echo -e "${PURPLE}🐛 DEBUG: $1${NC}"; }
log_step() { echo -e "${CYAN}🔄 $1${NC}"; }

echo "🔥 Color360 Root Update Script v2.0"
echo "===================================="
log_info "Запуск упрощенного обновления Color360 (от root)"
log_info "Проект: $PROJECT_DIR | Ветка: $BRANCH"

# Проверка что скрипт запущен от root
if [[ $EUID -ne 0 ]]; then
    log_error "Этот скрипт должен запускаться от root. Используйте: sudo $0"
    exit 1
fi

# Функция диагностики системы
system_diagnostics() {
    log_step "Диагностика системы"
    
    # Информация о системе
    log_info "ОС: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")"
    log_info "Ядро: $(uname -r)"
    log_info "Архитектура: $(uname -m)"
    
    # Проверка памяти
    local mem_info
    mem_info=$(free -m | awk 'NR==2{printf "%.1fGB используется из %.1fGB", $3/1024, $2/1024}')
    log_info "Память: $mem_info"
    
    # Проверка загрузки процессора
    local cpu_load
    cpu_load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    log_info "Загрузка CPU: $cpu_load"
}

# Функция проверки портов
check_ports() {
    log_step "Проверка занятых портов"
    
    # Порт 3000 (основное приложение)
    if netstat -tlnp 2>/dev/null | grep -q ":3000 "; then
        local port_3000_process
        port_3000_process=$(netstat -tlnp 2>/dev/null | grep ":3000 " | awk '{print $7}' | head -1)
        log_info "Порт 3000 занят процессом: $port_3000_process"
    else
        log_warning "Порт 3000 свободен"
    fi
    
    # Порт 5002 (AI сервис)
    if netstat -tlnp 2>/dev/null | grep -q ":5002 "; then
        local port_5002_process
        port_5002_process=$(netstat -tlnp 2>/dev/null | grep ":5002 " | awk '{print $7}' | head -1)
        log_info "Порт 5002 занят процессом: $port_5002_process"
    else
        log_warning "Порт 5002 свободен"
    fi
}

system_diagnostics
check_ports

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

# Функция остановки сервисов с принудительным завершением процессов
stop_services() {
    log_step "Остановка сервисов: $SERVICES"
    
    for service in $SERVICES; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                log_info "Остановка $service"
                systemctl stop "$service" || log_warning "Не удалось корректно остановить $service"
                
                # Ждем немного
                sleep 2
                
                # Проверяем что остановился
                if systemctl is-active --quiet "$service" 2>/dev/null; then
                    log_warning "Принудительная остановка $service"
                    systemctl kill "$service" 2>/dev/null || true
                fi
            else
                log_info "Сервис $service уже остановлен"
            fi
        else
            log_warning "Сервис $service не найден в systemd"
        fi
    done
    
    # Принудительная остановка процессов color360
    log_info "Принудительная остановка процессов color360..."
    pkill -9 -f "color360\|server.js" 2>/dev/null || true
    
    # Освобождение портов
    log_info "Освобождение портов 3000 и 5002..."
    fuser -k 3000/tcp 2>/dev/null || true
    fuser -k 5002/tcp 2>/dev/null || true
    
    sleep 3
    log_success "Все сервисы остановлены"
}

stop_services

# Функция обновления Git репозитория
update_git_repository() {
    log_step "Обновление Git репозитория"
    
    if [[ ! -d "$PROJECT_DIR/.git" ]]; then
        log_info "Git репозиторий не найден. Клонирование..."
        rm -rf "$PROJECT_DIR"
        git clone "$GIT_REPO" "$PROJECT_DIR"
        log_success "Репозиторий клонирован"
    else
        cd "$PROJECT_DIR"
        
        # Настройка безопасности Git
        git config --global --add safe.directory "$PROJECT_DIR"
        
        # Проверяем текущее состояние
        local current_commit
        current_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        log_info "Текущий коммит: $current_commit"
        
        # Получение изменений
        log_info "Загрузка изменений с GitHub..."
        git fetch origin
        
        # Проверяем есть ли обновления
        local remote_commit
        remote_commit=$(git rev-parse --short origin/$BRANCH)
        
        if [[ "$current_commit" == "$remote_commit" ]]; then
            log_success "Код уже актуален (коммит: $current_commit)"
            return 0
        fi
        
        log_info "Найдены обновления: $current_commit -> $remote_commit"
        
        # Сохранение локальных изменений
        if ! git diff --quiet || ! git diff --cached --quiet; then
            log_info "Сохранение локальных изменений в stash..."
            git stash push -m "Auto-stash before update $(date '+%Y-%m-%d_%H-%M-%S')"
        fi
        
        # Обновление до последней версии
        log_info "Применение обновлений..."
        git reset --hard origin/$BRANCH
        git clean -fd
        
        commit_hash=$(git rev-parse --short HEAD)
        commit_msg=$(git log -1 --pretty=format:"%s")
        log_success "Обновлён до коммита $commit_hash: $commit_msg"
    fi
}

update_git_repository

cd "$PROJECT_DIR"

# Функция умного обновления зависимостей
update_dependencies() {
    log_step "Проверка и обновление зависимостей"
    
    # Node.js зависимости
    if [[ -f "package.json" ]]; then
        # Проверяем нужно ли обновлять Node.js зависимости
        local need_npm_update=false
        
        if [[ ! -d "node_modules" ]]; then
            need_npm_update=true
            log_info "Директория node_modules не найдена"
        elif git diff --name-only HEAD~1 2>/dev/null | grep -q "package.*\.json"; then
            need_npm_update=true
            log_info "Файлы package.json изменились"
        fi
        
        if [[ "$need_npm_update" == "true" ]]; then
            log_info "Обновление Node.js зависимостей..."
            
            # Очищаем npm кэш для избежания проблем
            npm cache clean --force 2>/dev/null || true
            
            if [[ -f "package-lock.json" ]]; then
                npm ci --production
            else
                npm install --production
            fi
            log_success "Node.js зависимости обновлены"
        else
            log_info "Node.js зависимости актуальны, пропускаем обновление"
        fi
    else
        log_warning "package.json не найден - пропускаем npm install"
    fi
    
    # Python зависимости
    if [[ -f "sd/requirements.txt" ]]; then
        local need_python_update=false
        
        if [[ ! -d "sd_env" ]]; then
            need_python_update=true
            log_info "Python окружение не найдено"
        elif git diff --name-only HEAD~1 2>/dev/null | grep -q "sd/requirements.txt"; then
            need_python_update=true
            log_info "Файл sd/requirements.txt изменился"
        fi
        
        if [[ "$need_python_update" == "true" ]]; then
            log_info "Обновление Python зависимостей..."
            
            if [[ ! -d "sd_env" ]]; then
                log_info "Создание Python виртуального окружения..."
                python3 -m venv sd_env
            fi
            
            log_info "Установка/обновление пакетов..."
            source sd_env/bin/activate
            pip install --upgrade pip --quiet
            pip install --upgrade -r sd/requirements.txt --quiet
            deactivate
            
            log_success "Python зависимости обновлены"
        else
            log_info "Python зависимости актуальны, пропускаем обновление"
        fi
    else
        log_info "sd/requirements.txt не найден - пропускаем Python зависимости"
    fi
    
    # Установка прав доступа
    log_info "Установка прав доступа..."
    if id "$APP_USER" &>/dev/null; then
        chown -R "$APP_USER":"$APP_USER" "$PROJECT_DIR"
        log_info "Права установлены для пользователя: $APP_USER"
    else
        log_warning "Пользователь $APP_USER не найден, оставляем права для root"
    fi
    
    # Делаем скрипты исполняемыми
    chmod +x "$PROJECT_DIR"/*.sh 2>/dev/null || true
}

update_dependencies

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

# Функция комплексной проверки здоровья системы
health_check() {
    log_step "Комплексная проверка работоспособности"
    
    # Даем время на запуск
    log_info "Ожидание запуска сервисов (15 секунд)..."
    sleep 15
    
    local all_ok=true
    local health_report=()
    
    # Проверка статуса systemd сервисов
    for service in $SERVICES; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            if systemctl is-active --quiet "$service"; then
                log_success "Сервис $service активен"
                health_report+=("✅ $service: активен")
            else
                log_error "Сервис $service неактивен"
                health_report+=("❌ $service: неактивен")
                
                # Показываем последние 5 строк логов
                log_warning "Последние логи $service:"
                journalctl -u "$service" --no-pager -n 5 || true
                all_ok=false
            fi
        else
            log_warning "Сервис $service не установлен"
            health_report+=("⚠️ $service: не установлен")
        fi
    done
    
    # Проверка процессов
    log_info "Проверка процессов..."
    local node_processes
    node_processes=$(ps aux | grep -c "[n]ode.*server.js" || echo "0")
    if [[ "$node_processes" -gt 0 ]]; then
        log_success "Node.js процессов найдено: $node_processes"
        health_report+=("✅ Node.js процессы: $node_processes")
    else
        log_warning "Node.js процессы не найдены"
        health_report+=("⚠️ Node.js процессы: не найдены")
    fi
    
    # Проверка портов
    log_info "Проверка портов..."
    if netstat -tlnp 2>/dev/null | grep -q ":3000 "; then
        log_success "Порт 3000 прослушивается"
        health_report+=("✅ Порт 3000: прослушивается")
    else
        log_warning "Порт 3000 не прослушивается"
        health_report+=("⚠️ Порт 3000: не прослушивается")
        all_ok=false
    fi
    
    if netstat -tlnp 2>/dev/null | grep -q ":5002 "; then
        log_success "Порт 5002 прослушивается"
        health_report+=("✅ Порт 5002: прослушивается")
    else
        log_info "Порт 5002 не прослушивается (возможно AI сервис не установлен)"
        health_report+=("ℹ️ Порт 5002: не прослушивается")
    fi
    
    # HTTP тестирование
    log_info "Тестирование HTTP endpoints..."
    
    # Основное приложение
    local http_code_main
    http_code_main=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 "http://localhost:3000/" 2>/dev/null || echo "000")
    if [[ "$http_code_main" == "200" ]]; then
        log_success "Основное приложение доступно (HTTP $http_code_main)"
        health_report+=("✅ HTTP основное приложение: $http_code_main")
    else
        log_warning "Основное приложение недоступно (HTTP $http_code_main)"
        health_report+=("⚠️ HTTP основное приложение: $http_code_main")
        all_ok=false
    fi
    
    # AI сервис (если установлен)
    if systemctl list-unit-files | grep -q "color360-sd.service"; then
        local http_code_ai
        http_code_ai=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 15 "http://localhost:5002/health" 2>/dev/null || echo "000")
        if [[ "$http_code_ai" == "200" ]]; then
            log_success "AI сервис доступен (HTTP $http_code_ai)"
            health_report+=("✅ HTTP AI сервис: $http_code_ai")
        else
            log_warning "AI сервис недоступен (HTTP $http_code_ai) - возможно еще запускается"
            health_report+=("⚠️ HTTP AI сервис: $http_code_ai")
        fi
    fi
    
    # Проверка дискового пространства
    local disk_usage
    disk_usage=$(df "$PROJECT_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ -n "$disk_usage" && "$disk_usage" -lt 90 ]]; then
        log_success "Диск: свободно $((100-disk_usage))%"
        health_report+=("✅ Диск: $((100-disk_usage))% свободно")
    else
        log_warning "Диск заполнен на ${disk_usage}%"
        health_report+=("⚠️ Диск: ${disk_usage}% заполнен")
    fi
    
    # Итоговый отчет
    echo ""
    log_info "📊 Отчет о состоянии системы:"
    for report_line in "${health_report[@]}"; do
        echo "   $report_line"
    done
    
    return $([ "$all_ok" = true ])
}

# Вызываем проверку здоровья
if health_check; then
    health_status="✅ Все системы работают нормально"
    exit_code=0
else
    health_status="⚠️ Обнаружены проблемы с некоторыми компонентами"
    exit_code=1
fi

# Финальный отчёт
generate_final_report() {
    local commit_hash
    commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local commit_msg
    commit_msg=$(git log -1 --pretty=format:"%s" 2>/dev/null || echo "")
    local update_time
    update_time=$(date)
    
    echo ""
    echo "🎉======================================🎉"
    log_success "Color360 Root Update завершено!"
    echo "🎉======================================🎉"
    echo ""
    log_info "📋 Сводная информация об обновлении:"
    echo "   📅 Время завершения: $update_time"
    echo "   🌿 Ветка: $BRANCH"
    echo "   📝 Текущий коммит: $commit_hash"
    echo "   💬 Последнее изменение: $commit_msg"
    echo "   📂 Директория проекта: $PROJECT_DIR"
    echo "   👤 Выполнено пользователем: root"
    echo "   🏥 Статус здоровья: $health_status"
    echo ""
    log_info "� Управление сервисами:"
    echo "   # Статус всех сервисов"
    echo "   systemctl status $SERVICES"
    echo ""
    echo "   # Просмотр логов в реальном времени"
    echo "   journalctl -u color360-app -f"
    echo "   journalctl -u color360-sd -f"
    echo ""
    echo "   # Перезапуск сервисов при необходимости"
    echo "   systemctl restart color360-app color360-sd"
    echo ""
    log_info "🌐 Проверка доступности:"
    echo "   # Основное приложение"
    echo "   curl http://localhost:3000/"
    echo ""
    echo "   # AI сервис (если установлен)"
    echo "   curl http://localhost:5002/health"
    echo ""
    log_info "📚 Документация и помощь:"
    echo "   # GitHub репозиторий"
    echo "   https://github.com/RadaRish/color360"
    echo ""
    echo "   # Мониторинг системы"
    echo "   bash <(curl -s https://raw.githubusercontent.com/RadaRish/color360/main/monitor-vps.sh)"
    echo ""
}

generate_final_report

if [[ $exit_code -ne 0 ]]; then
    echo ""
    log_error "⚠️ Обновление завершено с предупреждениями. Проверьте логи выше."
    echo ""
    log_info "💡 Для диагностики используйте:"
    echo "   journalctl -u color360-app --no-pager -n 20"
    echo "   journalctl -u color360-sd --no-pager -n 20"
fi

exit $exit_code