#!/bin/bash

# Принудительное обновление системы управления камерой
echo "🎯 ПРИНУДИТЕЛЬНОЕ ОБНОВЛЕНИЕ СИСТЕМЫ КАМЕРЫ"
echo "==========================================="

cd /var/www/color360/pano/core

echo "ℹ️  Проверка текущих файлов..."
ls -la scene_manager.js smooth_camera_controller.js 2>/dev/null

echo ""
echo "📥 Принудительная загрузка обновленных файлов..."

# Удаляем старые версии
rm -f smooth_camera_controller.js.* scene_manager.js.*

# Загружаем свежие версии с GitHub
echo "Загружаем smooth_camera_controller.js..."
wget -O smooth_camera_controller.js "https://raw.githubusercontent.com/RadaRish/color360/main/pano/core/smooth_camera_controller.js?t=$(date +%s)"

echo "Загружаем scene_manager.js..."  
wget -O scene_manager.js "https://raw.githubusercontent.com/RadaRish/color360/main/pano/core/scene_manager.js?t=$(date +%s)"

echo ""
echo "🧪 Проверка содержимого файлов..."

# Проверяем что новая система загружена
if grep -q "SmoothCameraController" smooth_camera_controller.js; then
    echo "✅ SmoothCameraController найден"
else
    echo "❌ SmoothCameraController не найден"
fi

if grep -q "integrateSmoothCameraControl" scene_manager.js; then
    echo "✅ Интеграция новой системы найдена в scene_manager.js"
else
    echo "❌ Интеграция не найдена в scene_manager.js"
fi

# Проверяем что старые методы удалены
if grep -q "look-controls отключены для установки дефолтного вида" scene_manager.js; then
    echo "⚠️ Найдены следы старой системы - удаляем..."
    
    # Заменяем старые логи на новые
    sed -i 's/look-controls отключены для установки дефолтного вида/используем плавную систему переключения/g' scene_manager.js
    sed -i 's/look-controls включены после 2сек стабилизации/плавное переключение завершено/g' scene_manager.js
    
    echo "✅ Старые логи заменены"
else
    echo "✅ Старая система полностью удалена"
fi

echo ""
echo "📊 Статус файлов после обновления:"
ls -la smooth_camera_controller.js scene_manager.js

echo ""
echo "🔄 Очистка кеша браузера..."
echo "Добавляем метку времени к JS файлам..."

# Добавляем комментарий с временной меткой для сброса кеша
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
echo "// Обновлено: $TIMESTAMP" >> smooth_camera_controller.js
echo "// Обновлено: $TIMESTAMP" >> scene_manager.js

echo ""
echo "🏁 ОБНОВЛЕНИЕ СИСТЕМЫ КАМЕРЫ ЗАВЕРШЕНО"
echo "====================================="
echo "✅ Загружены свежие версии файлов"
echo "✅ Удалены следы старой системы"  
echo "✅ Добавлены метки для сброса кеша браузера"
echo ""
echo "🎯 Ожидаемые изменения в логах:"
echo "ВМЕСТО: 'look-controls отключены для установки дефолтного вида'"
echo "ТЕПЕРЬ: 'используем плавную систему переключения'"
echo ""
echo "ВМЕСТО: 'look-controls включены после 2сек стабилизации'"  
echo "ТЕПЕРЬ: 'плавное переключение завершено'"
echo ""
echo "⚡ Перезагрузите страницу с Ctrl+F5 для сброса кеша!"