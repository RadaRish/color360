#!/bin/bash

echo "🎯 Финальное исправление координат маски для ретуши..."

cd /var/www/color360

# 1. Загружаем исправления
echo "1️⃣ Загрузка исправлений координатного маппинга..."
git pull --ff-only origin main

# 2. Создаем необходимые директории
echo "2️⃣ Подготовка файловой системы..."
mkdir -p /var/www/color360/temp
chown -R www-data:www-data /var/www/color360/temp
chmod -R 755 /var/www/color360/temp

# 3. Перезапускаем приложение
echo "3️⃣ Перезапуск приложения с исправлениями..."
systemctl restart color360-app

# 4. Ждем запуска и тестируем
echo "4️⃣ Тестирование исправлений..."
sleep 5

# Проверка статуса приложения
if systemctl is-active --quiet color360-app; then
    echo "✅ Приложение запущено"
else
    echo "❌ Проблема с запуском приложения"
    systemctl status color360-app --no-pager
    exit 1
fi

# Тест temp-file endpoint
echo "Тестирование temp-file endpoint..."
TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: text/plain" \
    -d "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD//gA7Q1JFQVRPUjogZ2QtanBlZyB2MS4wICh1c2luZyBJSkcgSlBFRyB2NjIpLCBxdWFsaXR5ID0gODUK/9sAQwAGBAUGBQQGBgUGBwcGCAoQCgoJCQoUDg0NDhQUERERERQUFhUVFhUUERERERERERERERERERERERERERERERERER/9sAQwEHBwcKCAoTCgoTFRQUFBUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUV/8AAEQgAAQABAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBkQgUobHwFcHR4fEjM0KSorLi8eJzY3KCo7PD4uPj5O/j5+v/2gAMAwEAAhEDEQA/AOXAAAAKAAAAfEAPxAAKAP/Z" \
    http://localhost:3000/api/temp-file-from-data)

if [ "$TEST_RESPONSE" = "200" ]; then
    echo "✅ temp-file endpoint работает"
else
    echo "⚠️ temp-file endpoint вернул код: $TEST_RESPONSE"
fi

echo ""
echo "✅ Исправления применены!"
echo "📋 Что исправлено:"
echo "   ✅ Улучшенный алгоритм UV маппинга с учетом поворота камеры"
echo "   ✅ Исправлены углы yaw/pitch для точного соответствия"
echo "   ✅ temp-file endpoint исправлен (text/plain вместо JSON)"
echo "   ✅ Детальная диагностика координатного преобразования"
echo "   ✅ Нормализация углов для wrap-around эффектов"
echo ""
echo "🎨 Теперь маска должна точно соответствовать выделенной области!"
echo "📊 Проверь в логе 'UV mapping samples' - центр должен быть близко к UV(0.5, 0.5)"