#!/bin/bash

echo "🚀 Быстрое исправление ошибки HTTP 413 для ретуши панорам..."

cd /var/www/color360

# 1. Загружаем исправления
echo "1️⃣ Загрузка обновлений..."
git pull --ff-only origin main
chmod +x update-nginx-limits.sh

# 2. Обновляем лимиты nginx
echo "2️⃣ Обновление лимитов nginx..."
./update-nginx-limits.sh

# 3. Перезапускаем приложение с новыми лимитами
echo "3️⃣ Перезапуск приложения..."
systemctl restart color360-app

# 4. Проверяем что всё работает
echo "4️⃣ Проверка работоспособности..."
sleep 3

# Проверка приложения
echo "Статус приложения:"
systemctl is-active color360-app

echo "Статус nginx:"
systemctl is-active nginx

echo "Лимиты загрузки файлов:"
grep -E "client_max_body_size|body_timeout" /etc/nginx/nginx.conf || echo "Конфигурация не найдена"

echo ""
echo "✅ Исправление HTTP 413 завершено!"
echo "📊 Новые лимиты:"
echo "   - Максимальный размер файла: 200MB"
echo "   - Таймауты: 300 секунд"
echo "   - Буферизация: отключена для больших файлов"
echo ""
echo "🎨 Попробуйте ретушь панорамы снова!"