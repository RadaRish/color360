#!/bin/bash
# Комплексная диагностика Color360 системы
# Основан на monitor-vps.sh с дополнительными проверками
# Версия: 1.0

set -euo pipefail

# Конфигурация
PROJECT_DIR="${PROJECT_DIR:-/var/www/color360}"
SERVICES="${SERVICES:-color360-app color360-sd nginx}"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_section() { echo -e "${CYAN}📋 === $1 ===${NC}"; }

clear
echo "🔍 Color360 System Diagnostics"
echo "=============================="
echo "Время: $(date)"
echo "Проект: $PROJECT_DIR"
echo ""

# Функция проверки системных ресурсов
check_system_resources() {
    log_section "Системные ресурсы"
    
    # Информация о системе
    local os_info
    os_info=$(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown Linux")
    log_info "ОС: $os_info"
    
    # Память
    local mem_info
    mem_info=$(free -h | awk 'NR==2{printf "%s используется из %s (%.1f%%)", $3, $2, $3*100/$2}')
    log_info "Память: $mem_info"
    
    # Диск
    local disk_info
    disk_info=$(df -h "$PROJECT_DIR" | awk 'NR==2{printf "%s используется из %s (%s)", $3, $2, $5}')
    log_info "Диск: $disk_info"
    
    # Загрузка CPU
    local cpu_load
    cpu_load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    log_info "Загрузка CPU: $cpu_load"
    
    echo ""
}

# Функция проверки Git репозитория
check_git_status() {
    log_section "Git репозиторий"
    
    if [[ ! -d "$PROJECT_DIR/.git" ]]; then
        log_error "Git репозиторий не найден в $PROJECT_DIR"
        return 1
    fi
    
    cd "$PROJECT_DIR"
    
    # Текущий коммит
    local current_commit
    current_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local commit_msg
    commit_msg=$(git log -1 --pretty=format:"%s" 2>/dev/null || echo "")
    log_info "Текущий коммит: $current_commit"
    log_info "Сообщение: $commit_msg"
    
    # Статус репозитория
    if git diff --quiet 2>/dev/null; then
        log_success "Нет локальных изменений"
    else
        log_warning "Есть локальные изменения"
        git status --porcelain | head -5
    fi
    
    # Проверка обновлений
    log_info "Проверка обновлений на GitHub..."
    if git fetch origin 2>/dev/null; then
        local remote_commit
        remote_commit=$(git rev-parse --short origin/main 2>/dev/null || echo "unknown")
        if [[ "$current_commit" == "$remote_commit" ]]; then
            log_success "Код актуален"
        else
            log_warning "Доступны обновления: $current_commit -> $remote_commit"
        fi
    else
        log_warning "Не удалось проверить обновления"
    fi
    
    echo ""
}

# Функция проверки systemd сервисов
check_systemd_services() {
    log_section "Systemd сервисы"
    
    for service in $SERVICES; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            if systemctl is-active --quiet "$service"; then
                local uptime_info
                uptime_info=$(systemctl show "$service" --property=ActiveEnterTimestamp --value 2>/dev/null | cut -d' ' -f1-2 || echo "неизвестно")
                log_success "$service: активен (запущен: $uptime_info)"
            else
                log_error "$service: неактивен"
                
                # Показываем причину сбоя
                local failed_reason
                failed_reason=$(systemctl show "$service" --property=Result --value 2>/dev/null || echo "неизвестно")
                if [[ "$failed_reason" != "success" && "$failed_reason" != "" ]]; then
                    log_warning "Причина: $failed_reason"
                fi
            fi
            
            # Показываем статус
            if systemctl is-enabled --quiet "$service" 2>/dev/null; then
                log_info "$service: включен автозапуск"
            else
                log_warning "$service: автозапуск отключен"
            fi
        else
            log_warning "$service: сервис не установлен"
        fi
    done
    
    echo ""
}

# Функция проверки процессов и портов
check_processes_and_ports() {
    log_section "Процессы и порты"
    
    # Node.js процессы
    local node_count
    node_count=$(ps aux | grep -c "[n]ode.*server.js" || echo "0")
    if [[ "$node_count" -gt 0 ]]; then
        log_success "Node.js процессов: $node_count"
        ps aux | grep "[n]ode.*server.js" | awk '{print "   PID:", $2, "CPU:", $3"%", "MEM:", $4"%", "CMD:", $11, $12, $13}' | head -3
    else
        log_warning "Node.js процессы не найдены"
    fi
    
    # Python процессы
    local python_count
    python_count=$(ps aux | grep -c "[p]ython.*lama" || echo "0")
    if [[ "$python_count" -gt 0 ]]; then
        log_success "Python AI процессов: $python_count"
        ps aux | grep "[p]ython.*lama" | awk '{print "   PID:", $2, "CPU:", $3"%", "MEM:", $4"%"}' | head -3
    else
        log_info "Python AI процессы не найдены"
    fi
    
    # Проверка портов
    log_info "Проверка портов:"
    
    # Порт 3000
    if netstat -tlnp 2>/dev/null | grep -q ":3000 "; then
        local port_3000_process
        port_3000_process=$(netstat -tlnp 2>/dev/null | grep ":3000 " | awk '{print $7}' | head -1)
        log_success "Порт 3000: прослушивается ($port_3000_process)"
    else
        log_error "Порт 3000: не прослушивается"
    fi
    
    # Порт 5002
    if netstat -tlnp 2>/dev/null | grep -q ":5002 "; then
        local port_5002_process
        port_5002_process=$(netstat -tlnp 2>/dev/null | grep ":5002 " | awk '{print $7}' | head -1)
        log_success "Порт 5002: прослушивается ($port_5002_process)"
    else
        log_info "Порт 5002: не прослушивается (AI сервис может быть отключен)"
    fi
    
    # Порт 80/443 (nginx)
    if netstat -tlnp 2>/dev/null | grep -q ":80 "; then
        log_success "Порт 80: прослушивается (nginx)"
    else
        log_warning "Порт 80: не прослушивается"
    fi
    
    echo ""
}

# Функция проверки HTTP endpoints
check_http_endpoints() {
    log_section "HTTP доступность"
    
    # Основное приложение
    local main_response
    main_response=$(curl -s -o /dev/null -w "%{http_code}:%{time_total}" --connect-timeout 10 --max-time 30 "http://localhost:3000/" 2>/dev/null || echo "000:timeout")
    local http_code_main=${main_response%%:*}
    local response_time_main=${main_response##*:}
    
    if [[ "$http_code_main" == "200" ]]; then
        log_success "Основное приложение: HTTP $http_code_main (${response_time_main}s)"
    else
        log_error "Основное приложение: HTTP $http_code_main"
    fi
    
    # AI сервис
    if systemctl list-unit-files | grep -q "color360-sd.service"; then
        local ai_response
        ai_response=$(curl -s -o /dev/null -w "%{http_code}:%{time_total}" --connect-timeout 5 --max-time 15 "http://localhost:5002/health" 2>/dev/null || echo "000:timeout")
        local http_code_ai=${ai_response%%:*}
        local response_time_ai=${ai_response##*:}
        
        if [[ "$http_code_ai" == "200" ]]; then
            log_success "AI сервис: HTTP $http_code_ai (${response_time_ai}s)"
        else
            log_warning "AI сервис: HTTP $http_code_ai (может запускаться)"
        fi
    else
        log_info "AI сервис: не установлен"
    fi
    
    echo ""
}

# Функция проверки зависимостей
check_dependencies() {
    log_section "Зависимости"
    
    cd "$PROJECT_DIR"
    
    # Node.js зависимости
    if [[ -f "package.json" ]]; then
        if [[ -d "node_modules" ]]; then
            local npm_packages
            npm_packages=$(find node_modules -maxdepth 1 -type d | wc -l)
            log_success "Node.js: установлено $npm_packages пакетов"
        else
            log_error "Node.js: node_modules не найден"
        fi
    else
        log_warning "package.json не найден"
    fi
    
    # Python зависимости
    if [[ -f "sd/requirements.txt" ]]; then
        if [[ -d "sd_env" ]]; then
            local python_version
            python_version=$(sd_env/bin/python --version 2>&1 || echo "неизвестно")
            log_success "Python: окружение активно ($python_version)"
            
            local pip_packages
            pip_packages=$(sd_env/bin/pip list 2>/dev/null | wc -l || echo "0")
            log_info "Python: установлено $pip_packages пакетов"
        else
            log_error "Python: виртуальное окружение не найдено"
        fi
    else
        log_info "Python: AI зависимости не требуются"
    fi
    
    echo ""
}

# Функция проверки логов на ошибки
check_recent_logs() {
    log_section "Анализ логов (последние 10 минут)"
    
    for service in color360-app color360-sd; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            log_info "Проверка логов $service..."
            
            # Ищем ошибки в логах за последние 10 минут
            local error_count
            error_count=$(journalctl -u "$service" --since="10 minutes ago" --no-pager | grep -ci "error\|exception\|fatal" || echo "0")
            
            if [[ "$error_count" -eq 0 ]]; then
                log_success "$service: ошибок не найдено"
            else
                log_warning "$service: найдено $error_count ошибок"
                journalctl -u "$service" --since="10 minutes ago" --no-pager | grep -i "error\|exception\|fatal" | tail -3 | sed 's/^/   /'
            fi
        fi
    done
    
    echo ""
}

# Функция рекомендаций
show_recommendations() {
    log_section "Рекомендации по обслуживанию"
    
    # Проверка места на диске
    local disk_usage
    disk_usage=$(df "$PROJECT_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ -n "$disk_usage" && "$disk_usage" -gt 80 ]]; then
        log_warning "Диск заполнен на ${disk_usage}%. Рекомендуется очистка:"
        echo "   curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/clean-vps-disk.sh | sudo bash"
    fi
    
    # Проверка обновлений
    log_info "Для обновления системы используйте:"
    echo "   # Полное обновление"
    echo "   curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/update-vps-root.sh | sudo bash"
    echo ""
    echo "   # Быстрое обновление кода"
    echo "   curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/quick-update.sh | sudo bash"
    
    echo ""
    log_info "Полезные команды:"
    echo "   # Перезапуск сервисов"
    echo "   sudo systemctl restart color360-app color360-sd"
    echo ""
    echo "   # Просмотр логов"
    echo "   sudo journalctl -u color360-app -f"
    echo "   sudo journalctl -u color360-sd -f"
    echo ""
    echo "   # Мониторинг в реальном времени"
    echo "   watch 'systemctl status color360-app color360-sd'"
}

# Основная логика
main() {
    check_system_resources
    check_git_status
    check_systemd_services
    check_processes_and_ports
    check_http_endpoints
    check_dependencies
    check_recent_logs
    show_recommendations
    
    echo ""
    log_success "🎉 Диагностика завершена!"
    log_info "Для непрерывного мониторинга запустите: watch -n 5 'bash <(curl -s https://raw.githubusercontent.com/RadaRish/color360/main/diagnostic-system.sh)'"
}

# Запуск
main