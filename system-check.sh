#!/bin/bash

# Скрипт полной диагностики Color360 системы

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "ℹ️  $1"; }
log_success() { echo -e "✅ $1"; }
log_warning() { echo -e "⚠️  $1"; }
log_error() { echo -e "❌ $1"; }

echo
echo "🔍 ДИАГНОСТИКА COLOR360 СИСТЕМЫ"
echo "================================"

# Проверка основного сервера
echo
echo "🌐 ОСНОВНОЙ СЕРВЕР (порт 3000)"
echo "==============================="

if curl -s --connect-timeout 5 http://localhost:3000 > /dev/null; then
    log_success "Основной сервер доступен"
    
    # Проверяем заголовки
    status_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)
    log_info "HTTP статус: $status_code"
    
    if [ "$status_code" = "200" ]; then
        log_success "Сервер работает корректно"
    else
        log_warning "Сервер доступен, но HTTP статус: $status_code"
    fi
else
    log_error "Основной сервер недоступен"
    
    log_info "Попытка запуска через PM2..."
    if command -v pm2 > /dev/null 2>&1; then
        cd /var/www/color360
        pm2 start ecosystem.config.json 2>/dev/null || pm2 restart color360 2>/dev/null || true
        sleep 3
        
        if curl -s --connect-timeout 5 http://localhost:3000 > /dev/null; then
            log_success "Основной сервер запущен через PM2"
        else
            log_error "Не удалось запустить основной сервер"
        fi
    else
        log_warning "PM2 не найден"
    fi
fi

# Проверка LaMa API
echo
echo "🎨 LAMA AI СЕРВИС (порт 8080)"
echo "============================="

if curl -s --connect-timeout 5 http://localhost:8080/health > /dev/null; then
    response=$(curl -s http://localhost:8080/health)
    log_success "LaMa API доступен"
    log_info "Ответ: $response"
    
    # Проверяем режим работы
    if echo "$response" | grep -q '"mode":"full"'; then
        log_success "LaMa работает в полном режиме (AI)"
    elif echo "$response" | grep -q '"mode":"basic"'; then
        log_warning "LaMa работает в базовом режиме (OpenCV)"
    else
        log_info "Неизвестный режим LaMa"
    fi
else
    log_error "LaMa API недоступен"
    
    log_info "Попытка запуска LaMa сервиса..."
    if [ -f "/var/www/color360/lama-service-manager.sh" ]; then
        cd /var/www/color360
        bash lama-service-manager.sh start
        sleep 3
        
        if curl -s --connect-timeout 5 http://localhost:8080/health > /dev/null; then
            log_success "LaMa сервис запущен"
        else
            log_error "Не удалось запустить LaMa сервис"
        fi
    else
        log_warning "lama-service-manager.sh не найден"
    fi
fi

# Проверка процессов
echo
echo "🔧 ПРОЦЕССЫ И СЕРВИСЫ"
echo "===================="

# PM2 процессы
if command -v pm2 > /dev/null 2>&1; then
    pm2_processes=$(pm2 list 2>/dev/null | grep -E "(online|stopped|errored)" || echo "")
    if [ ! -z "$pm2_processes" ]; then
        log_info "PM2 процессы:"
        echo "$pm2_processes"
    else
        log_warning "PM2 процессы не найдены"
    fi
else
    log_warning "PM2 не установлен"
fi

# LaMa процессы
lama_processes=$(ps aux | grep -E "(service\.py|uvicorn.*8080)" | grep -v grep || echo "")
if [ ! -z "$lama_processes" ]; then
    log_info "LaMa процессы найдены:"
    echo "$lama_processes"
else
    log_warning "LaMa процессы не найдены"
fi

# Node.js процессы
node_processes=$(ps aux | grep -E "node.*color360" | grep -v grep || echo "")
if [ ! -z "$node_processes" ]; then
    log_info "Node.js процессы найдены:"
    echo "$node_processes"
else
    log_info "Node.js процессы color360 не найдены"
fi

# Проверка файловой системы
echo
echo "📁 ФАЙЛОВАЯ СИСТЕМА"
echo "==================="

# Проверка основных директорий
directories=(
    "/var/www/color360"
    "/var/www/color360/pano"
    "/var/www/color360/lama"
)

for dir in "${directories[@]}"; do
    if [ -d "$dir" ]; then
        log_success "Директория существует: $dir"
    else
        log_error "Директория отсутствует: $dir"
    fi
done

# Проверка важных файлов
files=(
    "/var/www/color360/server.js"
    "/var/www/color360/pano/ui/retouch_manager.js"
    "/var/www/color360/pano/core/viewer_manager.js"
    "/var/www/color360/lama-service-manager.sh"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        log_success "Файл существует: $file"
    else
        log_error "Файл отсутствует: $file"
    fi
done

# Проверка LaMa окружения
if [ -d "/var/www/color360/lama/lama_env" ]; then
    log_success "LaMa виртуальное окружение найдено"
    
    if [ -f "/var/www/color360/lama/service.py" ]; then
        log_success "LaMa service.py найден"
    else
        log_warning "LaMa service.py отсутствует"
    fi
else
    log_warning "LaMa виртуальное окружение отсутствует"
fi

# Проверка портов
echo
echo "🔌 СЕТЕВЫЕ ПОРТЫ"
echo "================"

ports=(3000 8080)
for port in "${ports[@]}"; do
    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        log_success "Порт $port открыт"
    else
        log_warning "Порт $port закрыт"
    fi
done

# Финальная сводка
echo
echo "📋 ФИНАЛЬНАЯ СВОДКА"
echo "==================="

main_server_ok=false
lama_api_ok=false

if curl -s --connect-timeout 3 http://localhost:3000 > /dev/null 2>&1; then
    main_server_ok=true
fi

if curl -s --connect-timeout 3 http://localhost:8080/health > /dev/null 2>&1; then
    lama_api_ok=true
fi

if [ "$main_server_ok" = true ] && [ "$lama_api_ok" = true ]; then
    log_success "Все сервисы работают корректно!"
    echo
    echo "🌐 Доступные URLs:"
    echo "  • Основной сайт: https://color360.ru"
    echo "  • Редактор панорам: https://color360.ru/pano/"
    echo "  • LaMa API: http://localhost:8080/health"
    echo
    echo "🎯 Система готова к использованию!"
elif [ "$main_server_ok" = true ]; then
    log_warning "Основной сервер работает, но LaMa API недоступен"
    echo "  ➤ Ретуширование может не работать"
elif [ "$lama_api_ok" = true ]; then
    log_warning "LaMa API работает, но основной сервер недоступен"
    echo "  ➤ Сайт может быть недоступен"
else
    log_error "Оба сервиса недоступны"
    echo "  ➤ Требуется ручное вмешательство"
fi

echo
echo "🔧 Для управления сервисами используйте:"
echo "  • bash lama-service-manager.sh {start|stop|restart|status}"
echo "  • pm2 {start|stop|restart|list} color360"
echo