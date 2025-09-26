#!/bin/bash

echo "🎯 Критическое исправление координат и камеры v2..."

cd /var/www/color360

# 1. Загружаем новые исправления
echo "1️⃣ Загрузка исправлений координат и управления камерой v2..."
git pull --ff-only origin main

# 2. Перезапускаем с новыми исправлениями
echo "2️⃣ Перезапуск с улучшенными исправлениями..."
systemctl restart color360-app

# 3. Проверяем статус
echo "3️⃣ Проверка статуса после исправлений v2..."
sleep 3

if systemctl is-active --quiet color360-app; then
    echo "✅ Приложение запущено с исправлениями v2"
else
    echo "❌ Проблема с запуском"
    systemctl status color360-app --no-pager
    exit 1
fi

# 4. Проверка функциональности
echo "4️⃣ Проверка функциональности..."
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
if [ "$HEALTH_STATUS" = "200" ]; then
    echo "✅ Приложение отвечает"
else
    echo "⚠️ Приложение код: $HEALTH_STATUS"
fi

# 5. Проверка LaMa AI
echo "5️⃣ Проверка LaMa AI сервиса..."
LAMA_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5002/health 2>/dev/null || echo "000")
if [ "$LAMA_STATUS" = "200" ]; then
    echo "✅ LaMa AI отвечает"
else
    echo "⚠️ LaMa AI недоступен - перезапускаем..."
    systemctl restart color360-lama
    sleep 3
    systemctl is-active color360-lama
fi

# 6. Очистка временных файлов
echo "6️⃣ Очистка временных файлов..."
if [ -d "/var/www/color360/temp" ]; then
    find /var/www/color360/temp -name "temp_*" -mtime +1 -delete 2>/dev/null
    echo "Очищены файлы старше 1 дня"
fi

echo ""
echo "🎯 КРИТИЧЕСКИЕ ИСПРАВЛЕНИЯ V2 ПРИМЕНЕНЫ!"
echo ""
echo "🎨 Исправления ретуши:"
echo "   ✅ Кисть сделана тоньше: lineWidth = 10 (было 20)"
echo "   ✅ Полный сброс камеры: позиция + ориентация + матрицы"
echo "   ✅ Принудительное обновление проекционной матрицы"
echo "   ✅ Детальное логирование состояния камеры"
echo ""
echo "🎥 Исправления управления камерой:"
echo "   ✅ Увеличена задержка отключения look-controls до 2 секунд"
echo "   ✅ Принудительная очистка внутреннего состояния A-Frame"
echo "   ✅ Сброс pitchObject и yawObject для предотвращения возврата"
echo "   ✅ Детальное логирование процесса установки дефолтного вида"
echo ""
echo "📊 Ожидаемые результаты:"
echo "   🎯 Координаты ретуши: точное попадание в выделенную область"
echo "   🎥 Дефолтный вид: стабильный, БЕЗ возврата к предыдущей позиции"
echo "   ⏱️ Задержка установки: 2 секунды для полной стабилизации"
echo ""
echo "🧪 Логи для мониторинга:"
echo "   'камера полностью сброшена в исходное состояние'"
echo "   'восстановлена исходная позиция и ориентация камеры'"
echo "   'сброшено внутреннее состояние look-controls'"
echo "   'look-controls включены после 2сек стабилизации'"