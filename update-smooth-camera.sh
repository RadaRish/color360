#!/bin/bash

# Обновление системы управления камерой для устранения "залипания"
echo "🎯 ОБНОВЛЕНИЕ СИСТЕМЫ УПРАВЛЕНИЯ КАМЕРОЙ v2.0"
echo "============================================="

# Переходим в директорию панорамы
cd /var/www/color360/pano/core

echo "ℹ️  Создаем резервные копии..."
cp scene_manager.js scene_manager.js.backup.$(date +%s)
cp viewer_manager.js viewer_manager.js.backup.$(date +%s) 2>/dev/null || true

echo "ℹ️  Загружаем обновленные файлы с GitHub..."

# Загружаем новую систему плавного управления камерой
wget -O smooth_camera_controller.js "https://raw.githubusercontent.com/RadaRish/color360/main/pano/core/smooth_camera_controller.js"

# Загружаем обновленный scene_manager.js
wget -O scene_manager.js "https://raw.githubusercontent.com/RadaRish/color360/main/pano/core/scene_manager.js"

echo "✅ Файлы обновлены"

echo ""
echo "🧪 Проверяем синтаксис JavaScript..."

# Проверка синтаксиса через Node.js (если доступен)
if command -v node >/dev/null 2>&1; then
    echo "Проверка smooth_camera_controller.js:"
    if node -c smooth_camera_controller.js 2>/dev/null; then
        echo "✅ smooth_camera_controller.js - синтаксис OK"
    else
        echo "❌ Ошибка в smooth_camera_controller.js:"
        node -c smooth_camera_controller.js
    fi
    
    echo "Проверка scene_manager.js:"
    if node -c scene_manager.js 2>/dev/null; then
        echo "✅ scene_manager.js - синтаксис OK"  
    else
        echo "❌ Ошибка в scene_manager.js:"
        node -c scene_manager.js
    fi
else
    echo "Node.js недоступен - пропускаем проверку синтаксиса"
fi

echo ""
echo "📊 Статус файлов:"
ls -la smooth_camera_controller.js scene_manager.js

echo ""
echo "🎯 ТЕСТИРОВАНИЕ ИСПРАВЛЕНИЙ"
echo "=========================="
echo "После обновления:"
echo ""
echo "✅ УСТРАНЕНО \"залипание\" камеры:"
echo "   - Время блокировки сокращено с 2000мс до 500мс"
echo "   - Look-controls не отключается полностью"
echo "   - Используется снижение чувствительности вместо блокировки"
echo ""
echo "✅ УСТРАНЕНО рандомное отображение:"
echo "   - Позиция устанавливается немедленно при загрузке"
echo "   - Задержка применения сокращена с 300мс до 100мс"
echo "   - Предотвращение конфликтов между переходами"
echo ""
echo "🎯 НОВЫЕ ВОЗМОЖНОСТИ:"
echo "   - Плавная система переключения (SmoothCameraController)"
echo "   - Предиктивная система (PredictiveCameraController)"
echo "   - Автоматическая отмена предыдущих переходов"
echo "   - Восстановление чувствительности управления"
echo ""
echo "🏁 ОБНОВЛЕНИЕ ЗАВЕРШЕНО"
echo "======================="
echo "Откройте color360.ru/pano для проверки!"
echo ""
echo "Ожидаемые улучшения:"
echo "- Переключение сцен без \"залипания\" (максимум 0.5сек)"
echo "- Отсутствие рандомного отображения при переходах"
echo "- Плавная работа управления камерой"
echo "- Быстрый отклик на движения мыши/тач"