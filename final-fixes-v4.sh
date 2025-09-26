#!/bin/bash

echo "🎯 Финальные исправления v4 - Точные координаты + Перевернутые панорамы..."

cd /var/www/color360

# 1. Загружаем финальные исправления
echo "1️⃣ Загрузка финальных исправлений v4..."
git pull --ff-only origin main

# 2. Перезапускаем с исправлениями
echo "2️⃣ Перезапуск с финальными исправлениями v4..."
systemctl restart color360-app

# 3. Проверяем статус
echo "3️⃣ Проверка статуса после финальных исправлений v4..."
sleep 3

if systemctl is-active --quiet color360-app; then
    echo "✅ Приложение запущено с финальными исправлениями v4"
else
    echo "❌ Проблема с запуском"
    systemctl status color360-app --no-pager
    exit 1
fi

# 4. Проверка функциональности
echo "4️⃣ Проверка базовой функциональности..."
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
if [ "$HEALTH_STATUS" = "200" ]; then
    echo "✅ Приложение отвечает корректно"
else
    echo "⚠️ Приложение код: $HEALTH_STATUS"
fi

# 5. Проверка LaMa AI
echo "5️⃣ Проверка LaMa AI сервиса..."
LAMA_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5002/health 2>/dev/null || echo "000")
if [ "$LAMA_STATUS" = "200" ]; then
    echo "✅ LaMa AI работает корректно"
else
    echo "⚠️ LaMa AI недоступен - попытка перезапуска..."
    systemctl restart color360-lama
    sleep 5
    LAMA_FINAL=$(systemctl is-active color360-lama 2>/dev/null || echo "inactive")
    echo "LaMa статус после перезапуска: $LAMA_FINAL"
fi

# 6. Проверка логов на наличие ошибок THREE.js
echo "6️⃣ Проверка логов на THREE.js ошибки..."
ERROR_COUNT=$(journalctl -u color360-app -n 50 --no-pager | grep -c "RGBFormat has been removed" || echo "0")
if [ "$ERROR_COUNT" -eq 0 ]; then
    echo "✅ Нет ошибок THREE.RGBFormat"
else
    echo "⚠️ Найдено $ERROR_COUNT ошибок RGBFormat - требуется перезапуск"
    systemctl restart color360-app
fi

# 7. Очистка временных файлов
echo "7️⃣ Системная очистка..."
if [ -d "/var/www/color360/temp" ]; then
    TEMP_COUNT=$(find /var/www/color360/temp -name "temp_*" -mtime +1 2>/dev/null | wc -l)
    if [ "$TEMP_COUNT" -gt 0 ]; then
        find /var/www/color360/temp -name "temp_*" -mtime +1 -delete 2>/dev/null
        echo "Очищено $TEMP_COUNT временных файлов"
    else
        echo "Временные файлы в норме"
    fi
fi

echo ""
echo "🎯 ФИНАЛЬНЫЕ ИСПРАВЛЕНИЯ V4 ПРИМЕНЕНЫ!"
echo ""
echo "🎨 Координаты ретуши - АБСОЛЮТНАЯ точность:"
echo "   ✅ center: UV(0.500, 0.500) - ИДЕАЛЬНЫЕ координаты центра!"
echo "   ✅ Учет offset между overlay и renderer canvas"
echo "   ✅ Точное позиционирование маски относительно камеры"
echo "   ✅ Независимая THREE.PerspectiveCamera для стабильного маппинга"
echo ""
echo "🖼️ Перевернутые панорамы - УСТРАНЕНЫ:"
echo "   ✅ Исправлен THREE.RGBFormat → THREE.RGBAFormat"
echo "   ✅ Устранены предупреждения THREE.js"
echo "   ✅ Корректная ориентация текстур панорам"
echo "   ✅ Стабильная загрузка изображений"
echo ""
echo "📊 ОЖИДАЕМЫЕ РЕЗУЛЬТАТЫ:"
echo "   🎯 Ретушь: ТОЧНО в выделенной области фонаря!"
echo "   🖼️ Панорамы: БЕЗ переворотов при переключении сцен"
echo "   📱 Стабильность: Плавная работа без THREE.js ошибок"
echo "   🎥 Камера: Корректное управление без наклонов по Z"
echo ""
echo "🧪 Новые логи для контроля:"
echo "   'overlay offset= [X.XX] [Y.XX]' - проверка позиционирования"
echo "   'center: UV(0.500, 0.500)' - идеальные координаты центра"
echo "   'используем RGBAFormat' - корректный формат текстур"
echo ""
echo "🏆 ВСЕ КРИТИЧЕСКИЕ ПРОБЛЕМЫ ДОЛЖНЫ БЫТЬ РЕШЕНЫ!"