#!/bin/bash

# Улучшенный скрипт деплоя для VPS с обработкой ошибок
echo "🚀 Начинаем деплой Color360 на VPS..."

# Функция логирования
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Функция проверки ошибок
check_error() {
    if [ $? -ne 0 ]; then
        log "❌ Ошибка: $1"
        exit 1
    fi
}

# Устанавливаем переменную окружения для отключения SD на продакшне
export SD_DISABLED=true

# Переходим в директорию проекта
cd /var/www/color360 || {
    log "❌ Не удалось перейти в директорию /var/www/color360"
    exit 1
}

log "📁 Текущая директория: $(pwd)"

# Обновляем код из git
log "🔄 Обновляем код из репозитория..."
git fetch origin
check_error "Git fetch failed"

git reset --hard origin/main
check_error "Git reset failed"

log "✅ Код обновлен"

# Проверяем наличие Node.js
if ! command -v node &> /dev/null; then
    log "❌ Node.js не найден. Устанавливаем..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
    check_error "Node.js installation failed"
fi

log "📦 Версия Node.js: $(node --version)"
log "📦 Версия npm: $(npm --version)"

# Устанавливаем зависимости Node.js
log "📦 Устанавливаем зависимости..."
npm install --production
check_error "npm install failed"

# Проверяем структуру проекта
log "📋 Проверяем файлы проекта..."
if [ ! -f "server.js" ]; then
    log "❌ server.js не найден!"
    exit 1
fi

if [ ! -f "package.json" ]; then
    log "❌ package.json не найден!"
    exit 1
fi

# Устанавливаем права доступа
log "🔐 Настраиваем права доступа..."
sudo chown -R www-data:www-data /var/www/color360
sudo chmod -R 755 /var/www/color360

# Создаем/обновляем systemd сервис
log "⚙️ Настраиваем systemd сервис..."
sudo tee /etc/systemd/system/color360-app.service > /dev/null << EOF
[Unit]
Description=Color360 Main Application
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/var/www/color360
Environment=NODE_ENV=production
Environment=SD_DISABLED=true
Environment=PORT=3000
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=color360-app

[Install]
WantedBy=multi-user.target
EOF

# Перезагружаем systemd и запускаем сервис
log "🔄 Перезагружаем systemd..."
sudo systemctl daemon-reload
check_error "systemctl daemon-reload failed"

log "🛑 Останавливаем старый сервис..."
sudo systemctl stop color360-app

log "🚀 Запускаем новый сервис..."
sudo systemctl start color360-app
check_error "systemctl start failed"

sudo systemctl enable color360-app
check_error "systemctl enable failed"

# Ждем запуска сервиса
log "⏳ Ждем запуска сервиса..."
sleep 5

# Проверяем статус
log "📊 Проверяем статус сервиса..."
sudo systemctl status color360-app --no-pager

# Проверяем логи
log "📋 Последние логи сервиса:"
sudo journalctl -u color360-app --no-pager -n 20

# Проверяем доступность приложения
log "🌐 Проверяем доступность приложения..."
if curl -f http://localhost:3000 > /dev/null 2>&1; then
    log "✅ Приложение доступно на порту 3000"
else
    log "⚠️ Приложение пока недоступно, проверьте логи"
fi

# Проверяем nginx конфигурацию
if [ -f /etc/nginx/sites-available/color360 ]; then
    log "🌐 Проверяем nginx конфигурацию..."
    sudo nginx -t
    if [ $? -eq 0 ]; then
        log "🔄 Перезагружаем nginx..."
        sudo systemctl reload nginx
        log "✅ Nginx перезагружен"
    else
        log "⚠️ Ошибка в конфигурации nginx"
    fi
fi

log "🎉 Деплой завершен!"
log "📋 Полезные команды для мониторинга:"
log "   sudo systemctl status color360-app"
log "   sudo journalctl -u color360-app -f"
log "   sudo systemctl restart color360-app"