#!/bin/bash

# Скрипт диагностики Color360 на VPS
echo "🔍 Диагностика Color360 на VPS..."

# Функция логирования
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "=== СИСТЕМНАЯ ИНФОРМАЦИЯ ==="
log "Операционная система: $(lsb_release -d 2>/dev/null | cut -f2 || echo 'Unknown')"
log "Архитектура: $(uname -m)"
log "Память: $(free -h | grep '^Mem:' | awk '{print $2 " total, " $3 " used"}')"
log "Свободное место: $(df -h / | tail -1 | awk '{print $4 " available"}')"

log "=== NODE.JS И NPM ==="
if command -v node &> /dev/null; then
    log "✅ Node.js найден: $(node --version)"
else
    log "❌ Node.js не найден"
fi

if command -v npm &> /dev/null; then
    log "✅ npm найден: $(npm --version)"
else
    log "❌ npm не найден"
fi

log "=== ФАЙЛЫ ПРОЕКТА ==="
cd /var/www/color360 2>/dev/null || {
    log "❌ Директория /var/www/color360 не найдена"
    exit 1
}

log "📁 Текущая директория: $(pwd)"

if [ -f "server.js" ]; then
    log "✅ server.js найден"
    log "📏 Размер server.js: $(ls -lh server.js | awk '{print $5}')"
else
    log "❌ server.js не найден"
fi

if [ -f "package.json" ]; then
    log "✅ package.json найден"
    log "📦 Основные зависимости:"
    cat package.json | jq -r '.dependencies | keys[]' 2>/dev/null || grep -o '"[^"]*"[[:space:]]*:[[:space:]]*"[^"]*"' package.json | head -10
else
    log "❌ package.json не найден"
fi

if [ -d "node_modules" ]; then
    log "✅ node_modules найден"
    log "📦 Количество пакетов: $(ls node_modules | wc -l)"
else
    log "❌ node_modules не найден"
fi

log "=== ПРАВА ДОСТУПА ==="
log "Права на /var/www/color360: $(ls -ld /var/www/color360 | awk '{print $1 " " $3 ":" $4}')"
log "Права на server.js: $(ls -l server.js 2>/dev/null | awk '{print $1 " " $3 ":" $4}' || echo 'Файл не найден')"

log "=== SYSTEMD СЕРВИС ==="
if [ -f /etc/systemd/system/color360-app.service ]; then
    log "✅ Сервисный файл найден"
    log "📋 Содержимое сервисного файла:"
    cat /etc/systemd/system/color360-app.service
else
    log "❌ Сервисный файл не найден"
fi

log "=== СТАТУС СЕРВИСА ==="
sudo systemctl status color360-app --no-pager || log "❌ Не удалось получить статус сервиса"

log "=== ПОСЛЕДНИЕ ЛОГИ СЕРВИСА ==="
sudo journalctl -u color360-app --no-pager -n 30 || log "❌ Не удалось получить логи сервиса"

log "=== ПРОЦЕССЫ NODE.JS ==="
ps aux | grep node || log "❌ Процессы Node.js не найдены"

log "=== СЕТЕВЫЕ ПОДКЛЮЧЕНИЯ ==="
netstat -tlnp | grep :3000 || log "❌ Порт 3000 не прослушивается"

log "=== ТЕСТ ПОДКЛЮЧЕНИЯ ==="
if curl -f http://localhost:3000 > /dev/null 2>&1; then
    log "✅ Приложение отвечает на порту 3000"
else
    log "❌ Приложение не отвечает на порту 3000"
fi

log "=== PYTHON И ЗАВИСИМОСТИ ==="
if command -v python3 &> /dev/null; then
    log "✅ Python3 найден: $(python3 --version)"
else
    log "❌ Python3 не найден"
fi

if command -v pip3 &> /dev/null; then
    log "✅ pip3 найден: $(pip3 --version)"
else
    log "❌ pip3 не найден"
fi

# Проверяем виртуальное окружение
if [ -d "sd_env" ]; then
    log "✅ Виртуальное окружение sd_env найдено"
    if [ -f "sd_env/bin/activate" ]; then
        source sd_env/bin/activate
        python --version 2>/dev/null || log "❌ Не удалось активировать виртуальное окружение"
        deactivate 2>/dev/null
    fi
else
    log "❌ Виртуальное окружение sd_env не найдено"
fi

log "=== NGINX ==="
if command -v nginx &> /dev/null; then
    log "✅ Nginx найден: $(nginx -v 2>&1)"
    nginx -t 2>&1 | head -5
    sudo systemctl status nginx --no-pager | head -10
else
    log "❌ Nginx не найден"
fi

log "=== ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ ==="
log "NODE_ENV: ${NODE_ENV:-'не установлено'}"
log "SD_DISABLED: ${SD_DISABLED:-'не установлено'}"
log "PORT: ${PORT:-'не установлено'}"

log "🔍 Диагностика завершена"