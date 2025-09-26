#!/bin/bash

echo "🎯 Итоговое исправление координат и качества ретуши..."

cd /var/www/color360

# 1. Загружаем финальные исправления
echo "1️⃣ Загрузка итоговых исправлений..."
git pull --ff-only origin main

# 2. Перезапускаем приложение
echo "2️⃣ Перезапуск приложения с исправлениями..."
systemctl restart color360-app

# 3. Проверяем LaMa сервис
echo "3️⃣ Проверка LaMa сервиса..."
LAMA_STATUS=$(systemctl is-active color360-lama)
if [ "$LAMA_STATUS" = "active" ]; then
    echo "✅ LaMa сервис активен"
else
    echo "⚠️ LaMa сервис: $LAMA_STATUS"
    echo "Попытка перезапуска LaMa..."
    systemctl restart color360-lama
    sleep 3
    systemctl is-active color360-lama
fi

# 4. Тестируем здоровье LaMa
echo "4️⃣ Тест LaMa API..."
LAMA_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5002/health 2>/dev/null || echo "000")
if [ "$LAMA_HEALTH" = "200" ]; then
    echo "✅ LaMa API отвечает"
    # Получаем детали
    curl -s http://localhost:5002/health | head -5
else
    echo "⚠️ LaMa API код: $LAMA_HEALTH"
    echo "Проверяем логи LaMa:"
    journalctl -u color360-lama -n 10 --no-pager
fi

# 5. Проверяем основное приложение
echo "5️⃣ Проверка основного приложения..."
APP_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
if [ "$APP_HEALTH" = "200" ]; then
    echo "✅ Основное приложение отвечает"
else
    echo "⚠️ Приложение код: $APP_HEALTH"
fi

# 6. Освобождаем место (удаляем старые temp файлы)
echo "6️⃣ Очистка временных файлов..."
if [ -d "/var/www/color360/temp" ]; then
    find /var/www/color360/temp -name "temp_*" -mtime +1 -delete 2>/dev/null
    echo "Очищены файлы старше 1 дня"
fi

echo ""
echo "✅ Итоговые исправления применены!"
echo "📋 Что исправлено:"
echo "   🎯 Стабильный UV маппинг без накопления ошибок камеры"
echo "   🎨 Улучшенные AI параметры для архитектурных объектов:"
echo "      - guidance_scale: 12.0 (баланс качества/естественности)"
echo "      - num_inference_steps: 50 (высокое качество)"
echo "      - strength: 0.95 (сохранение деталей)"
echo "      - Специальные промпты для панорам"
echo "   🔧 Упрощенная сферическая проекция (theta/phi)"
echo "   ⚡ Автоочистка временных файлов"
echo ""
echo "🎨 Теперь координаты должны быть стабильными, а качество - высоким!"
echo "📊 В логах ожидайте UV близкие к (0.5, 0.5) для центра экрана"
echo "   ✅ Нормализация углов для wrap-around эффектов"
echo ""
echo "🎨 Теперь маска должна точно соответствовать выделенной области!"
echo "📊 Проверь в логе 'UV mapping samples' - центр должен быть близко к UV(0.5, 0.5)"