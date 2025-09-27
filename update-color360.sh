#!/bin/bash

# Скрипт автоматического обновления Color360 с сохранением локальных изменений

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
echo "🔄 АВТОМАТИЧЕСКОЕ ОБНОВЛЕНИЕ COLOR360"
echo "===================================="

# Переходим в директорию проекта
if [ ! -d "/var/www/color360" ]; then
    log_error "Директория /var/www/color360 не найдена!"
    exit 1
fi

cd /var/www/color360

# Проверяем статус git
log_info "Проверка статуса git репозитория..."
git status --porcelain > /tmp/git_status.txt

if [ -s /tmp/git_status.txt ]; then
    log_warning "Найдены локальные изменения:"
    cat /tmp/git_status.txt
    echo
    
    # Создаем резервные копии измененных файлов
    log_info "Создание резервных копий..."
    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*M[[:space:]]+(.*) ]]; then
            file="${BASH_REMATCH[1]}"
            if [ -f "$file" ]; then
                backup_file="${file}.backup.$(date +%s)"
                cp "$file" "$backup_file"
                log_info "Создана резервная копия: $backup_file"
            fi
        fi
    done < /tmp/git_status.txt
    
    # Сохраняем изменения в stash
    log_info "Сохранение локальных изменений в git stash..."
    git stash push -m "Automatic backup before update $(date)"
    
    STASH_CREATED=true
else
    log_success "Локальных изменений не найдено"
    STASH_CREATED=false
fi

# Обновляем код
log_info "Обновление кода с GitHub..."
git pull origin main

if [ "$STASH_CREATED" = true ]; then
    log_warning "Локальные изменения сохранены в git stash"
    log_info "Для восстановления используйте: git stash pop"
    log_info "Для просмотра изменений: git stash show -p"
    log_info "Для удаления stash: git stash drop"
fi

# Перезапускаем сервисы
log_info "Перезапуск сервисов..."

# Перезапускаем основной сервер если запущен
if pm2 list | grep -q color360; then
    log_info "Перезапуск основного сервера..."
    pm2 restart color360 || log_warning "Не удалось перезапустить основной сервер"
fi

# Перезапускаем LaMa сервис если он был запущен
if curl -s http://localhost:8080/health > /dev/null 2>&1; then
    log_info "Перезапуск LaMa сервиса..."
    
    # Останавливаем старый процесс
    pkill -f "python.*service.py" 2>/dev/null || true
    sleep 2
    
    # Запускаем новый
    if [ -f "lama/service.py" ] && [ -d "lama/lama_env" ]; then
        cd lama
        source lama_env/bin/activate
        nohup python service.py > lama_service.log 2>&1 &
        echo $! > lama_service.pid
        cd ..
        
        sleep 3
        if curl -s http://localhost:8080/health > /dev/null 2>&1; then
            log_success "LaMa сервис перезапущен успешно"
        else
            log_warning "Возможны проблемы с LaMa сервисом"
        fi
    fi
else
    log_info "LaMa сервис не был запущен, пропускаем"
fi

echo
log_success "Обновление завершено!"
echo
echo "📋 РЕЗЮМЕ:"
echo "=========="
log_info "Код обновлен до последней версии"
if [ "$STASH_CREATED" = true ]; then
    log_warning "Локальные изменения сохранены в git stash"
    echo "   Восстановить: git stash pop"
    echo "   Посмотреть: git stash show -p"
fi
log_info "Сервисы перезапущены"
echo
echo "🔗 Проверка:"
echo "curl http://localhost:3000  # Основной сервер"
echo "curl http://localhost:8080/health  # LaMa API"
echo