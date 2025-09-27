#!/bin/bash

# Комплексное исправление проблем с LaMa и nginx
echo "🔧 КОМПЛЕКСНОЕ ИСПРАВЛЕНИЕ LAMA И NGINX"
echo "======================================"

echo "🔍 Диагностика текущих проблем..."

echo "1. Проверка статуса LaMa сервиса:"
systemctl status lama-inpainting --no-pager | head -10

echo ""
echo "2. Проверка процессов на порту 8080:"
netstat -tuln | grep 8080 || echo "Порт 8080 свободен"

echo ""
echo "3. Проверка конфликтов nginx:"
nginx -t 2>&1 | grep -i "conflicting\|warning" || echo "Конфликтов не найдено"

echo ""
echo "🛠️ ИСПРАВЛЕНИЕ 1: Перезапуск LaMa сервиса"
echo "=========================================="

echo "Остановка всех процессов LaMa..."
systemctl stop lama-inpainting 2>/dev/null || true
pkill -f "service.py" 2>/dev/null || true
pkill -f "uvicorn.*lama" 2>/dev/null || true
sleep 3

echo "Проверка что порт 8080 освободился..."
if netstat -tuln | grep -q 8080; then
    echo "⚠️ Порт 8080 все еще занят, принудительно освобождаем..."
    fuser -k 8080/tcp 2>/dev/null || true
    sleep 2
fi

echo "Запуск LaMa сервиса..."
systemctl start lama-inpainting

echo "Ожидание запуска (10 секунд)..."
sleep 10

echo "Проверка статуса после перезапуска:"
if systemctl is-active --quiet lama-inpainting; then
    echo "✅ LaMa сервис запущен"
    systemctl status lama-inpainting --no-pager | head -5
else
    echo "❌ LaMa сервис не запустился"
    echo "Последние строки лога:"
    journalctl -u lama-inpainting --no-pager -n 10
fi

echo ""
echo "🛠️ ИСПРАВЛЕНИЕ 2: Устранение конфликтов nginx"
echo "============================================="

# Проверяем какие конфиги есть
echo "Поиск конфигов с color360.ru..."
find /etc/nginx -name "*.conf" -exec grep -l "color360.ru" {} \; 2>/dev/null

# Показываем активные сайты
echo ""
echo "Активные сайты в sites-enabled:"
ls -la /etc/nginx/sites-enabled/ | grep color360 || echo "Не найдено"

# Проверяем основной конфиг
MAIN_CONFIG="/etc/nginx/sites-available/color360"
if [[ -f "$MAIN_CONFIG" ]]; then
    echo ""
    echo "Найден основной конфиг: $MAIN_CONFIG"
    
    # Отключаем дублирующие server_name если есть
    echo "Проверка на дублирующие server блоки..."
    SERVER_COUNT=$(grep -c "server_name.*color360.ru" "$MAIN_CONFIG" 2>/dev/null || echo "0")
    echo "Найдено server_name с color360.ru: $SERVER_COUNT"
    
    if [[ "$SERVER_COUNT" -gt 1 ]]; then
        echo "⚠️ Найдены дублирующие server блоки, исправляем..."
        
        # Создаем резервную копию
        cp "$MAIN_CONFIG" "$MAIN_CONFIG.backup.$(date +%s)"
        
        # Создаем чистый конфиг без дублей
        cat > "$MAIN_CONFIG" << 'EOF'
server {
    listen 80;
    server_name color360.ru www.color360.ru;
    
    root /var/www/color360;
    index index.html;
    
    # LaMa API - точное соответствие для /api/retouch  
    location = /api/retouch {
        proxy_pass http://127.0.0.1:8080/inpaint;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        client_max_body_size 100M;
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
        proxy_buffering off;
        
        # CORS headers
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With" always;
        
        if ($request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin * always;
            add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
            add_header Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With" always;
            add_header Access-Control-Max-Age 3600 always;
            add_header Content-Length 0 always;
            return 204;
        }
    }
    
    # LaMa API - для /api/lama/
    location /api/lama/ {
        rewrite ^/api/lama/(.*)$ /$1 break;
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        client_max_body_size 100M;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With" always;
    }
    
    # Основные статические файлы
    location / {
        try_files $uri $uri/ =404;
    }
    
    # Панорама
    location /pano {
        try_files $uri $uri/ /pano/index.html;
    }
    
    # Логирование
    access_log /var/log/nginx/color360_access.log;
    error_log /var/log/nginx/color360_error.log;
}
EOF
        
        echo "✅ Конфиг очищен от дублей"
    fi
    
    # Убеждаемся что используется 127.0.0.1 вместо localhost
    sed -i 's/localhost:8080/127.0.0.1:8080/g' "$MAIN_CONFIG"
    sed -i 's/\[::1\]:8080/127.0.0.1:8080/g' "$MAIN_CONFIG"
    
    echo "✅ Исправлены адреса upstream на 127.0.0.1"
fi

# Удаляем дублирующие конфиги если есть
echo ""
echo "Проверка на дублирующие конфиги..."
for config in /etc/nginx/sites-enabled/*; do
    if [[ -f "$config" && "$config" != "/etc/nginx/sites-enabled/color360" ]]; then
        if grep -q "color360.ru" "$config" 2>/dev/null; then
            echo "⚠️ Найден дублирующий конфиг: $config"
            echo "Отключаем: $(basename "$config")"
            rm -f "$config"
        fi
    fi
done

echo ""
echo "Проверка конфигурации nginx..."
if nginx -t; then
    echo "✅ Конфигурация nginx корректна"
    systemctl reload nginx
    echo "✅ Nginx перезагружен"
else
    echo "❌ Ошибка конфигурации nginx"
    exit 1
fi

echo ""
echo "🧪 ФИНАЛЬНАЯ ПРОВЕРКА"
echo "===================="

sleep 3

echo "1. Статус LaMa сервиса:"
if systemctl is-active --quiet lama-inpainting; then
    echo "✅ LaMa активен"
else
    echo "❌ LaMa неактивен"
fi

echo ""
echo "2. Тест локального API:"
if curl -s --connect-timeout 3 "http://127.0.0.1:8080/health" >/dev/null; then
    echo "✅ Прямой доступ к LaMa работает"
    curl -s "http://127.0.0.1:8080/health" | head -1
else
    echo "❌ Прямой доступ к LaMa не работает"
fi

echo ""
echo "3. Тест nginx проксирования:"
RESPONSE=$(curl -s -w "%{http_code}" "http://localhost/api/lama/health")
HTTP_CODE="${RESPONSE: -3}"
BODY="${RESPONSE%???}"

if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ Nginx проксирование работает (HTTP $HTTP_CODE)"
    echo "Ответ: $BODY" | head -1
else
    echo "❌ Nginx проксирование не работает (HTTP $HTTP_CODE)"
    echo "Ответ: $BODY" | head -2
fi

echo ""
echo "4. Тест эндпоинта ретуши:"
RETOUCH_RESPONSE=$(curl -s -w "%{http_code}" -X OPTIONS "http://localhost/api/retouch")
RETOUCH_CODE="${RETOUCH_RESPONSE: -3}"

if [[ "$RETOUCH_CODE" =~ ^(200|204)$ ]]; then
    echo "✅ Эндпоинт /api/retouch отвечает (HTTP $RETOUCH_CODE)"
else
    echo "❌ Эндпоинт /api/retouch проблемы (HTTP $RETOUCH_CODE)"
fi

echo ""
echo "🏁 ИСПРАВЛЕНИЕ ЗАВЕРШЕНО"
echo "========================"

if systemctl is-active --quiet lama-inpainting && [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ ВСЕ РАБОТАЕТ! Можно тестировать ретушь."
    echo ""
    echo "🎨 Для тестирования ретуши:"
    echo "1. Перезагрузите страницу с Ctrl+F5"
    echo "2. Попробуйте функцию ретуши"
    echo "3. Проверьте Network вкладку в DevTools"
else
    echo "⚠️ Остались проблемы, проверьте логи:"
    echo "- journalctl -u lama-inpainting -f"
    echo "- tail -f /var/log/nginx/color360_error.log"
fi

echo ""
echo "📊 Мониторинг в реальном времени:"
echo "watch -n 2 'systemctl status lama-inpainting --no-pager | head -5'"