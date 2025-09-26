#!/bin/bash

echo "🚀 Быстрая установка HTTPS для Color360..."

# Установка certbot
apt update && apt install -y certbot python3-certbot-nginx

# Остановка nginx
systemctl stop nginx

# Получение сертификата
certbot certonly --standalone --agree-tos --email admin@color360.ru -d color360.ru -d www.color360.ru

if [ $? -eq 0 ]; then
    # Автоматическая настройка nginx
    certbot install --nginx -d color360.ru -d www.color360.ru
    
    # Перезапуск сервисов
    systemctl restart nginx
    systemctl restart color360-app
    
    echo "✅ HTTPS настроен! Проверьте: https://color360.ru"
else
    systemctl start nginx
    echo "❌ Ошибка получения сертификата"
fi