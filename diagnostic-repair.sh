#!/bin/bash
# Quick Diagnostic and Repair Script for Color360 LaMa
# Быстрая диагностика и восстановление

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Проверка и диагностика
diagnose_system() {
    log_info "🔍 Диагностика Color360 системы..."
    
    # Проверка процессов
    echo "🔄 Активные процессы:"
    ps aux | grep -E "(color360|lama|server\.js|node.*server)" | grep -v grep || log_warning "Нет активных процессов"
    
    # Проверка портов
    echo ""
    log_info "🔌 Занятые порты:"
    netstat -tlnp | grep -E ":3000|:5002" || log_warning "Порты свободны"
    
    # Проверка сервисов systemd
    echo ""
    log_info "⚙️ Статус systemd сервисов:"
    for service in color360-app color360-lama nginx; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            status=$(systemctl is-active $service 2>/dev/null)
            if [ "$status" = "active" ]; then
                log_success "$service: активен"
            else
                log_error "$service: не активен ($status)"
            fi
        else
            log_warning "$service: не найден"
        fi
    done
    
    # Проверка директорий
    echo ""
    log_info "📁 Структура проекта:"
    if [ -d "/var/www/color360" ]; then
        echo "   ✅ /var/www/color360 существует"
        if [ -d "/var/www/color360/lama" ]; then
            echo "   ✅ /var/www/color360/lama существует"
            if [ -f "/var/www/color360/lama/service.py" ]; then
                echo "   ✅ service.py найден"
            else
                echo "   ❌ service.py отсутствует"
            fi
            if [ -d "/var/www/color360/lama/lama_env" ]; then
                echo "   ✅ Python окружение есть"
            else
                echo "   ❌ Python окружение отсутствует"
            fi
        else
            echo "   ❌ директория lama отсутствует"
        fi
    else
        echo "   ❌ Основная директория проекта не найдена"
    fi
    
    # Проверка API
    echo ""
    log_info "🌐 Проверка API:"
    if curl -s --connect-timeout 3 http://localhost:5002/health > /dev/null 2>&1; then
        log_success "LaMa API отвечает на :5002"
    else
        log_error "LaMa API не отвечает на :5002"
    fi
    
    if curl -s --connect-timeout 3 http://localhost:3000 > /dev/null 2>&1; then
        log_success "Основное приложение отвечает на :3000"
    else
        log_error "Основное приложение не отвечает на :3000"
    fi
}

# Быстрое восстановление
quick_fix() {
    log_info "🔧 Быстрое восстановление..."
    
    # Остановка всех процессов
    log_info "🛑 Остановка процессов..."
    systemctl stop color360-app color360-lama 2>/dev/null || true
    pkill -9 -f "color360\|lama.*service\|server\.js" 2>/dev/null || true
    
    # Освобождение портов
    log_info "🔓 Освобождение портов..."
    fuser -k 3000/tcp 2>/dev/null || true
    fuser -k 5002/tcp 2>/dev/null || true
    
    sleep 3
    
    # Запуск LaMa отдельно для тестирования
    if [ -f "/var/www/color360/lama/service.py" ] && [ -d "/var/www/color360/lama/lama_env" ]; then
        log_info "🎯 Тест LaMa сервиса..."
        cd /var/www/color360/lama
        
        # Запуск в фоне
        source lama_env/bin/activate
        nohup python service.py > /tmp/lama_test.log 2>&1 &
        lama_pid=$!
        
        sleep 10
        
        if kill -0 $lama_pid 2>/dev/null; then
            log_success "LaMa сервис запустился (PID: $lama_pid)"
            
            # Тест API
            if curl -s --connect-timeout 5 http://localhost:5002/health > /dev/null; then
                log_success "LaMa API работает"
                kill $lama_pid 2>/dev/null || true
            else
                log_error "LaMa API не отвечает"
                log_info "Логи LaMa:"
                tail -10 /tmp/lama_test.log
                kill $lama_pid 2>/dev/null || true
                return 1
            fi
        else
            log_error "LaMa сервис не запустился"
            log_info "Логи LaMa:"
            cat /tmp/lama_test.log
            return 1
        fi
    else
        log_error "Файлы LaMa не найдены"
        return 1
    fi
    
    # Запуск через systemd
    log_info "⚙️ Запуск через systemd..."
    systemctl daemon-reload
    systemctl start color360-lama
    sleep 5
    systemctl start color360-app
    sleep 3
    
    log_success "Сервисы перезапущены"
}

# Показать логи
show_logs() {
    log_info "📋 Последние логи:"
    
    echo ""
    echo "🎯 LaMa сервис:"
    journalctl -u color360-lama --no-pager -n 10 || echo "Нет логов"
    
    echo ""
    echo "🌐 Основное приложение:"
    journalctl -u color360-app --no-pager -n 10 || echo "Нет логов"
    
    if [ -f "/tmp/lama_test.log" ]; then
        echo ""
        echo "🔍 Тест LaMa:"
        tail -10 /tmp/lama_test.log
    fi
}

# Полная переустановка только LaMa
reinstall_lama_only() {
    log_info "🎯 Переустановка только LaMa сервиса..."
    
    # Остановка
    systemctl stop color360-lama 2>/dev/null || true
    pkill -9 -f "lama.*service" 2>/dev/null || true
    fuser -k 5002/tcp 2>/dev/null || true
    
    cd /var/www/color360
    
    # Удаление старого окружения
    rm -rf lama/lama_env
    
    # Создание нового
    python3 -m venv lama/lama_env
    source lama/lama_env/bin/activate
    
    log_info "📦 Установка зависимостей..."
    pip install --upgrade pip
    pip install --extra-index-url https://download.pytorch.org/whl/cpu \
        torch==2.1.0+cpu torchvision==0.16.0+cpu torchaudio==2.1.0+cpu
    pip install fastapi==0.104.1 uvicorn[standard]==0.24.0
    pip install python-multipart==0.0.6
    pip install pillow==10.1.0 opencv-python-headless==4.8.1.78 numpy==1.24.3
    pip install lama-cleaner==1.2.2
    pip install psutil==5.9.6 requests==2.31.0
    
    deactivate
    
    # Запуск
    systemctl start color360-lama
    sleep 10
    
    if systemctl is-active --quiet color360-lama; then
        log_success "LaMa переустановлен успешно"
    else
        log_error "Ошибка переустановки LaMa"
        show_logs
    fi
}

# Интерактивное меню
show_menu() {
    echo ""
    echo "🛠️  Color360 Diagnostic & Repair Tool"
    echo "===================================="
    echo ""
    echo "1) 🔍 Полная диагностика"
    echo "2) 🔧 Быстрое восстановление"
    echo "3) 📋 Показать логи"
    echo "4) 🎯 Переустановить только LaMa"
    echo "5) 🚪 Выход"
    echo ""
}

# Основная функция
main() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Запустите с правами root: sudo bash $0"
        exit 1
    fi
    
    # Быстрая диагностика при запуске
    diagnose_system
    
    while true; do
        show_menu
        echo -n "Выберите действие (1-5): "
        read -r choice
        
        case $choice in
            1) diagnose_system ;;
            2) quick_fix ;;
            3) show_logs ;;
            4) reinstall_lama_only ;;
            5) log_info "До свидания!"; break ;;
            *) log_warning "Неверный выбор. Попробуйте еще раз." ;;
        esac
    done
}

# Запуск
main "$@"