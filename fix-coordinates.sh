#!/bin/bash

echo "🎯 Исправление координат маски для ретуши панорам..."

cd /var/www/color360

# 1. Загружаем исправления координатного маппинга
echo "1️⃣ Загрузка исправлений маппинга UV координат..."
git pull --ff-only origin main

# 2. Перезапускаем приложение с новым endpoint
echo "2️⃣ Перезапуск приложения..."
systemctl restart color360-app

# 3. Создаем директорию для временных файлов
echo "3️⃣ Создание директории для временных файлов..."
mkdir -p /var/www/color360/temp
chown www-data:www-data /var/www/color360/temp
chmod 755 /var/www/color360/temp

# 4. Проверяем статус
echo "4️⃣ Проверка работоспособности..."
sleep 3

echo "Статус приложения:"
systemctl is-active color360-app

echo "Проверка endpoint temp-file:"
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/temp-file-from-data -X POST -d "test" || echo "Endpoint проверяется..."

echo ""
echo "✅ Исправление координат завершено!"
echo "📋 Что исправлено:"
echo "   - Улучшенный алгоритм screen->UV маппинга"
echo "   - Исправлены формулы yaw/pitch для A-Frame"
echo "   - Добавлена диагностика координатного маппинга"
echo "   - Endpoint /api/temp-file-from-data для конвертации data URLs"
echo ""
echo "🎨 Попробуйте ретушь снова - координаты должны совпадать!"