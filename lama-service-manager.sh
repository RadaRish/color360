#!/bin/bash

# Скрипт проверки и запуска LaMa сервиса для Color360

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
log_info() { echo -e "ℹ️  $1"; }
log_success() { echo -e "✅ $1"; }
log_warning() { echo -e "⚠️  $1"; }
log_error() { echo -e "❌ $1"; }
log_fix() { echo -e "🔧 $1"; }

# Поиск LaMa директории
find_lama_directory() {
    local paths=(
        "/var/www/color360/lama"
        "/var/www/html/color360/lama" 
        "/var/www/html/lama"
        "/opt/color360/lama"
        "/home/$(whoami)/color360/lama"
        "./lama"
        "../lama"
        "lama"
    )
    
    for path in "${paths[@]}"; do
        if [ -d "$path" ] && [ -f "$path/service.py" ]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# Проверка запущенных процессов LaMa
check_lama_processes() {
    log_info "Проверка запущенных LaMa процессов..."
    
    local processes=$(ps aux | grep -E "(service\.py|lama|uvicorn.*8080)" | grep -v grep || true)
    if [ ! -z "$processes" ]; then
        log_info "Найдены процессы LaMa:"
        echo "$processes"
        return 0
    else
        log_warning "LaMa процессы не найдены"
        return 1
    fi
}

# Проверка доступности LaMa API
check_lama_api() {
    log_info "Проверка доступности LaMa API..."
    
    local urls=(
        "http://localhost:8080/health"
        "http://127.0.0.1:8080/health"
        "http://localhost:8080/"
        "http://127.0.0.1:8080/"
    )
    
    for url in "${urls[@]}"; do
        log_info "Проверяем $url..."
        if curl -s --connect-timeout 5 "$url" > /dev/null 2>&1; then
            local response=$(curl -s "$url" 2>/dev/null || echo "")
            log_success "LaMa API доступен: $url"
            if [ ! -z "$response" ]; then
                echo "Ответ: $response"
            fi
            return 0
        fi
    done
    
    log_error "LaMa API недоступен на всех портах"
    return 1
}

# Запуск LaMa сервиса
start_lama_service() {
    log_fix "Запуск LaMa сервиса..."
    
    local lama_dir=$(find_lama_directory)
    if [ $? -ne 0 ]; then
        log_error "LaMa директория не найдена! Установите LaMa сначала."
        log_info "Используйте: bash fix-lama-compatibility-v3.sh"
        return 1
    fi
    
    log_info "Найдена LaMa директория: $lama_dir"
    cd "$lama_dir"
    
    # Проверяем виртуальное окружение
    if [ ! -d "lama_env" ]; then
        log_error "Виртуальное окружение lama_env не найдено!"
        log_info "Используйте: bash fix-lama-compatibility-v3.sh"
        return 1
    fi
    
    # Проверяем service.py
    if [ ! -f "service.py" ]; then
        log_error "service.py не найден!"
        log_info "Используйте: bash fix-lama-compatibility-v3.sh"
        return 1
    fi
    
    # Активируем окружение и запускаем
    log_info "Активация окружения и запуск сервиса..."
    source lama_env/bin/activate
    
    # Проверяем зависимости
    if ! python -c "import uvicorn, fastapi" 2>/dev/null; then
        log_error "Отсутствуют зависимости! Переустановите LaMa."
        log_info "Используйте: bash fix-lama-compatibility-v3.sh"
        return 1
    fi
    
    # Запускаем в фоне
    log_success "Запуск LaMa сервиса на порту 8080..."
    nohup python service.py > lama_service.log 2>&1 &
    local pid=$!
    
    echo $pid > lama_service.pid
    log_success "LaMa сервис запущен с PID: $pid"
    log_info "Лог файл: $lama_dir/lama_service.log"
    
    # Ждем запуска
    log_info "Ожидание инициализации сервиса..."
    sleep 5
    
    if check_lama_api; then
        log_success "LaMa сервис успешно запущен и доступен!"
        return 0
    else
        log_error "LaMa сервис запущен, но API недоступен"
        log_info "Проверьте лог: tail -f $lama_dir/lama_service.log"
        return 1
    fi
}

# Остановка LaMa сервиса
stop_lama_service() {
    log_info "Остановка LaMa сервиса..."
    
    # Останавливаем по PID файлу
    local lama_dir=$(find_lama_directory)
    if [ $? -eq 0 ] && [ -f "$lama_dir/lama_service.pid" ]; then
        local pid=$(cat "$lama_dir/lama_service.pid")
        if kill -0 $pid 2>/dev/null; then
            log_info "Остановка процесса с PID: $pid"
            kill $pid
            rm -f "$lama_dir/lama_service.pid"
        fi
    fi
    
    # Принудительно убиваем все процессы
    local processes=$(ps aux | grep -E "(service\.py|uvicorn.*8080)" | grep -v grep | awk '{print $2}' || true)
    if [ ! -z "$processes" ]; then
        log_info "Принудительная остановка процессов: $processes"
        echo "$processes" | xargs kill -9 2>/dev/null || true
    fi
    
    log_success "LaMa сервис остановлен"
}

# Перезапуск LaMa сервиса
restart_lama_service() {
    log_fix "Перезапуск LaMa сервиса..."
    stop_lama_service
    sleep 2
    start_lama_service
}

# Показ статуса
show_status() {
    echo
    echo "🔧 СТАТУС LAMA СЕРВИСА"
    echo "======================"
    
    check_lama_processes || true
    echo
    check_lama_api || true
    echo
    
    local lama_dir=$(find_lama_directory)
    if [ $? -eq 0 ]; then
        log_info "LaMa директория: $lama_dir"
        if [ -f "$lama_dir/lama_service.log" ]; then
            log_info "Последние строки лога:"
            tail -n 5 "$lama_dir/lama_service.log" 2>/dev/null || echo "Лог пуст"
        fi
    fi
}

# Главная функция
main() {
    case "${1:-status}" in
        "start")
            start_lama_service
            ;;
        "stop")
            stop_lama_service
            ;;
        "restart")
            restart_lama_service
            ;;
        "status")
            show_status
            ;;
        "check")
            if check_lama_api; then
                log_success "LaMa API работает корректно"
                exit 0
            else
                log_error "LaMa API недоступен"
                exit 1
            fi
            ;;
        *)
            echo "Использование: $0 {start|stop|restart|status|check}"
            echo
            echo "Команды:"
            echo "  start   - Запустить LaMa сервис"
            echo "  stop    - Остановить LaMa сервис"
            echo "  restart - Перезапустить LaMa сервис"
            echo "  status  - Показать статус сервиса"
            echo "  check   - Проверить доступность API"
            exit 1
            ;;
    esac
}

echo
echo "🎨 УПРАВЛЕНИЕ LAMA СЕРВИСОМ"
echo "==========================="
main "$@"