#!/bin/bash

# Диагностика проблем с ретушью и исправление зависания
echo "🎨 ДИАГНОСТИКА И ИСПРАВЛЕНИЕ РЕТУШИ"
echo "=================================="

echo "🔍 Проверяем доступность LaMa API..."

# Проверяем все возможные эндпоинты
echo "1. Локальный API (localhost:8080):"
if curl -s --connect-timeout 3 "http://localhost:8080/health" >/dev/null 2>&1; then
    echo "✅ localhost:8080/health доступен"
    curl -s "http://localhost:8080/health" | head -1
else
    echo "❌ localhost:8080/health недоступен"
fi

echo ""
echo "2. Nginx проксированный API (/api/lama/health):"
RESPONSE=$(curl -s -w "%{http_code}" "http://localhost/api/lama/health")
HTTP_CODE="${RESPONSE: -3}"
BODY="${RESPONSE%???}"

echo "HTTP код: $HTTP_CODE"
if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ /api/lama/health работает"
    echo "Ответ: $BODY" | head -1
else
    echo "❌ Проблема с /api/lama/health"
    echo "Ответ: $BODY" | head -2
fi

echo ""
echo "3. Эндпоинт ретуши (/api/retouch):"
RETOUCH_RESPONSE=$(curl -s -w "%{http_code}" -X POST "http://localhost/api/retouch" \
    -H "Content-Type: application/json" \
    -d '{}')
RETOUCH_CODE="${RETOUCH_RESPONSE: -3}"

echo "HTTP код для POST /api/retouch: $RETOUCH_CODE"
if [[ "$RETOUCH_CODE" =~ ^(200|400|422)$ ]]; then
    echo "✅ Эндпоинт /api/retouch отвечает (ошибка данных ожидаема)"
else
    echo "❌ Эндпоинт /api/retouch недоступен"
fi

echo ""
echo "🔍 Анализ retouch_manager.js..."

cd /var/www/color360/pano/ui

if [[ -f "retouch_manager.js" ]]; then
    echo "📁 Файл retouch_manager.js найден"
    
    # Проверяем URL API в коде
    echo "🔗 URL API в коде:"
    grep -n "fetch.*api" retouch_manager.js | head -3
    
    echo ""
    echo "⏱️ Таймауты в коде:"
    grep -n "timeout\|setTimeout" retouch_manager.js | head -3
    
    echo ""
    echo "🔍 Проверяем обработку ошибок:"
    if grep -q "catch.*error\|\.catch" retouch_manager.js; then
        echo "✅ Обработка ошибок найдена"
    else
        echo "⚠️ Обработка ошибок может отсутствовать"
    fi
    
else
    echo "❌ retouch_manager.js не найден"
fi

echo ""
echo "🛠️ Создаем улучшенную версию с таймаутами и отладкой..."

# Создаем патч для добавления таймаутов
cat > "/tmp/retouch_patch.js" << 'EOF'
// Функция для fetch с таймаутом
function fetchWithTimeout(url, options = {}, timeoutMs = 30000) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    
    const fetchOptions = {
        ...options,
        signal: controller.signal
    };
    
    return fetch(url, fetchOptions)
        .finally(() => clearTimeout(timeoutId))
        .catch(error => {
            if (error.name === 'AbortError') {
                throw new Error(`Timeout после ${timeoutMs}мс: ${url}`);
            }
            throw error;
        });
}

// Добавляем в window для использования
window.fetchWithTimeout = fetchWithTimeout;
EOF

# Если retouch_manager.js существует, добавляем патч
if [[ -f "retouch_manager.js" ]]; then
    # Создаем резервную копию
    cp retouch_manager.js "retouch_manager.js.backup.$(date +%s)"
    
    # Добавляем патч в начало файла
    cat /tmp/retouch_patch.js retouch_manager.js > retouch_manager_patched.js
    mv retouch_manager_patched.js retouch_manager.js
    
    echo "✅ Патч с таймаутами добавлен"
    
    # Заменяем обычные fetch на fetchWithTimeout где это критично
    sed -i 's/fetch(\x27\/api\/retouch\x27/fetchWithTimeout(\x27\/api\/retouch\x27/g' retouch_manager.js
    sed -i 's/fetch("\/api\/retouch"/fetchWithTimeout("\/api\/retouch"/g' retouch_manager.js
    
    echo "✅ Критичные fetch заменены на fetchWithTimeout"
fi

rm -f /tmp/retouch_patch.js

echo ""
echo "📊 Мониторинг логов LaMa сервиса..."

if [[ -f "/var/www/color360/lama/lama_service_restart.log" ]]; then
    echo "📋 Последние строки лога LaMa сервиса:"
    tail -10 /var/www/color360/lama/lama_service_restart.log
elif [[ -f "/var/www/color360/lama/lama_systemd.log" ]]; then
    echo "📋 Последние строки systemd лога:"
    tail -10 /var/www/color360/lama/lama_systemd.log
else
    echo "⚠️ Логи LaMa сервиса не найдены"
fi

echo ""
echo "🧪 Финальная проверка готовности к ретуши..."

# Проверяем все компоненты
ALL_OK=true

echo "Компоненты системы ретуши:"
if systemctl is-active --quiet lama-inpainting; then
    echo "✅ LaMa сервис запущен"
else
    echo "❌ LaMa сервис не запущен"
    ALL_OK=false
fi

if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ Nginx проксирование работает" 
else
    echo "❌ Nginx проксирование не работает"
    ALL_OK=false
fi

if [[ -f "/var/www/color360/pano/ui/retouch_manager.js" ]]; then
    echo "✅ retouch_manager.js найден"
else
    echo "❌ retouch_manager.js отсутствует"
    ALL_OK=false
fi

echo ""
if [[ "$ALL_OK" == "true" ]]; then
    echo "🏁 ВСЕ КОМПОНЕНТЫ ГОТОВЫ К РАБОТЕ!"
    echo "================================="
    echo "✅ Можно тестировать ретушь в веб-интерфейсе"
else
    echo "⚠️ ЕСТЬ ПРОБЛЕМЫ С КОМПОНЕНТАМИ"
    echo "=============================="
    echo "Запустите исправления перед тестированием"
fi

echo ""
echo "🔧 Команды для исправления проблем:"
echo "- Перезапуск LaMa: systemctl restart lama-inpainting"
echo "- Проверка nginx: nginx -t && systemctl reload nginx" 
echo "- Логи LaMa: journalctl -u lama-inpainting -f"
echo "- Логи nginx: tail -f /var/log/nginx/color360_error.log"