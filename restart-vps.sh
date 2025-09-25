#!/bin/bash

# Быстрый рестарт Color360 на VPS
echo "🔄 Рестарт Color360 сервиса..."

# Устанавливаем переменную окружения для отключения SD
export SD_DISABLED=true

# Переходим в директорию проекта
cd /var/www/color360 || {
    echo "❌ Не удалось перейти в директорию /var/www/color360"
    exit 1
}

# Функция логирования
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "🛑 Останавливаем сервис..."
sudo systemctl stop color360-app

log "⏳ Ждем остановки сервиса..."
sleep 3

log "🚀 Запускаем сервис..."
sudo systemctl start color360-app

log "⏳ Ждем запуска..."
sleep 5

log "📊 Проверяем статус..."
sudo systemctl status color360-app --no-pager -l

log "📋 Последние логи:"
sudo journalctl -u color360-app --no-pager -n 10

log "🌐 Проверяем доступность..."
if curl -f http://localhost:3000 > /dev/null 2>&1; then
    log "✅ Сервис успешно перезапущен"
else
    log "❌ Сервис недоступен, проверьте логи"
    log "Команды для диагностики:"
    log "  sudo journalctl -u color360-app -f"
    log "  sudo systemctl status color360-app"
fi