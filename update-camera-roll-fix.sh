#!/bin/bash

# Быстрое обновление fix для camera roll на color360.online
echo "🔧 ОБНОВЛЕНИЕ ИСПРАВЛЕНИЯ CAMERA ROLL"
echo "====================================="

# Переходим в директорию панорамы
cd /var/www/color360/pano/core

echo "ℹ️  Создаем резервные копии..."
cp viewer_manager.js viewer_manager.js.backup.$(date +%s)

echo "ℹ️  Загружаем обновленные файлы с GitHub..."

# Загружаем новую систему защиты от roll
wget -O camera_roll_protection.js "https://raw.githubusercontent.com/RadaRish/color360/main/pano/core/camera_roll_protection.js"

# Загружаем обновленный viewer_manager.js
wget -O viewer_manager.js "https://raw.githubusercontent.com/RadaRish/color360/main/pano/core/viewer_manager.js"

echo "✅ Файлы обновлены"

echo ""
echo "🧪 Проверяем синтаксис JavaScript..."

# Проверка синтаксиса через Node.js (если доступен)
if command -v node >/dev/null 2>&1; then
    echo "Проверка camera_roll_protection.js:"
    if node -c camera_roll_protection.js 2>/dev/null; then
        echo "✅ camera_roll_protection.js - синтаксис OK"
    else
        echo "❌ Ошибка в camera_roll_protection.js:"
        node -c camera_roll_protection.js
    fi
    
    echo "Проверка viewer_manager.js:"
    if node -c viewer_manager.js 2>/dev/null; then
        echo "✅ viewer_manager.js - синтаксис OK"  
    else
        echo "❌ Ошибка в viewer_manager.js:"
        node -c viewer_manager.js
    fi
else
    echo "Node.js недоступен - пропускаем проверку синтаксиса"
fi

echo ""
echo "📊 Статус файлов:"
ls -la camera_roll_protection.js viewer_manager.js

echo ""
echo "🏁 ОБНОВЛЕНИЕ ЗАВЕРШЕНО"
echo "======================="
echo "Обновленная система защиты от camera roll:"
echo "- 🎯 Агрессивная защита на 60fps + 30fps + 10fps"
echo "- 🔒 Перехват всех методов look-controls"  
echo "- ⚡ Немедленная коррекция после событий мыши/тач"
echo "- 🧭 Ограничение pitch в пределах ±85°"
echo "- 🚫 Полное блокирование roll (Z-rotation)"
echo ""
echo "Откройте color360.online/pano для проверки!"
echo "Теперь вертикальное движение НЕ должно вызывать перекос камеры."