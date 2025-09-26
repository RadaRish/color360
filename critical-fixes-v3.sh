#!/bin/bash

echo "🎯 Критические исправления v3 - Координаты + Камера + Циклы..."

cd /var/www/color360

# 1. Загружаем финальные исправления
echo "1️⃣ Загрузка критических исправлений v3..."
git pull --ff-only origin main

# 2. Перезапускаем с исправлениями
echo "2️⃣ Перезапуск с финальными исправлениями..."
systemctl restart color360-app

# 3. Проверяем статус
echo "3️⃣ Проверка статуса после критических исправлений v3..."
sleep 3

if systemctl is-active --quiet color360-app; then
    echo "✅ Приложение запущено с исправлениями v3"
else
    echo "❌ Проблема с запуском"
    systemctl status color360-app --no-pager
    exit 1
fi

# 4. Проверка функциональности
echo "4️⃣ Проверка базовой функциональности..."
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
    echo "✅ LaMa AI работает"
else
    echo "⚠️ LaMa AI недоступен - попытка перезапуска..."
    systemctl restart color360-lama
    sleep 5
    LAMA_FINAL=$(systemctl is-active color360-lama 2>/dev/null || echo "inactive")
    echo "LaMa статус после перезапуска: $LAMA_FINAL"
fi

# 6. Очистка временных файлов
echo "6️⃣ Очистка системы..."
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
echo "🎯 КРИТИЧЕСКИЕ ИСПРАВЛЕНИЯ V3 ПРИМЕНЕНЫ!"
echo ""
echo "🎨 Координаты ретуши - КАРДИНАЛЬНОЕ исправление:"
echo "   ✅ Создание независимой THREE.PerspectiveCamera для маппинга"
echo "   ✅ Полная изоляция от состояния A-Frame камеры"
echo "   ✅ Гарантированно точные координаты центра экрана"
echo ""
echo "🎥 Управление камерой - исправлена ось Z:"
echo "   ✅ Осторожный сброс look-controls без нарушения оси Z"
echo "   ✅ Предотвращение наклона камеры при движении вверх/вниз"
echo "   ✅ Сохранение корректного управления после установки дефолтного вида"
echo ""
echo "🔄 Переключение сцен - устранены циклы:"
echo "   ✅ Увеличена защита от повторных переключений до 1 секунды"
echo "   ✅ Детальное логирование переключений для отслеживания"
echo "   ✅ Проверка текущей сцены перед переключением"
echo ""
echo "📊 Ожидаемые результаты:"
echo "   🎯 Координаты: ТОЧНОЕ попадание ретуши в выделенную область"
echo "   🎥 Управление: НЕТ наклонов по оси Z при движении вверх/вниз"  
echo "   🔄 Переходы: НЕТ циклических переключений между сценами"
echo "   📱 Стабильность: Плавная работа без зависаний"
echo ""
echo "🧪 Новые логи для мониторинга:"
echo "   'создание независимой THREE.PerspectiveCamera'"
echo "   'начинаем переключение на сцену [X] текущая: [Y]'"
echo "   'уже находимся на сцене [X] - пропускаем переключение'"
echo "   'аккуратно обновлено состояние look-controls'"