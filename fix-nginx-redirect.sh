#!/bin/bash

# Исправление nginx конфигурации для устранения 301 редиректа
echo "🔧 ИСПРАВЛЕНИЕ NGINX КОНФИГУРАЦИИ (301 РЕДИРЕКТ)"
echo "============================================="

NGINX_CONFIG="/etc/nginx/sites-available/color360"

echo "📋 Диагностика проблемы с 301 редиректом..."

# Проверяем текущую конфигурацию
echo "Текущая конфигурация nginx:"
if [[ -f "$NGINX_CONFIG" ]]; then
    grep -A 5 -B 5 "location /api" "$NGINX_CONFIG" || echo "Настройки /api не найдены"
else
    echo "❌ Конфиг $NGINX_CONFIG не найден"
    exit 1
fi

echo ""
echo "🔍 Проверяем HTTPS редиректы и trailing slash..."

# Проверяем есть ли принудительные редиректы на HTTPS
if grep -q "return 301 https" "$NGINX_CONFIG"; then
    echo "⚠️ Найден редирект на HTTPS - может вызывать 301"
    grep -n "return 301" "$NGINX_CONFIG"
fi

# Проверяем trailing slash редиректы
if grep -q "rewrite.*\$" "$NGINX_CONFIG"; then
    echo "⚠️ Найдены rewrite правила - могут вызывать 301"
    grep -n "rewrite" "$NGINX_CONFIG"
fi

echo ""
echo "🔧 Создаем исправленную конфигурацию..."

# Создаем резервную копию
cp "$NGINX_CONFIG" "$NGINX_CONFIG.backup.$(date +%s)"

# Создаем новую конфигурацию без проблемных редиректов
cat > "$NGINX_CONFIG" << 'EOF'
server {
    listen 80;
    server_name color360.ru www.color360.ru;
    
    root /var/www/color360;
    index index.html;
    
    # Отключаем автоматическое добавление trailing slash для API
    location /api {
        # НЕ добавляем trailing slash для API эндпоинтов
    }
    
    # LaMa API - точное соответствие для /api/retouch
    location = /api/retouch {
        proxy_pass http://localhost:8080/inpaint;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Увеличенные лимиты для изображений
        client_max_body_size 100M;
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
        proxy_buffering off;
        
        # CORS headers
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With" always;
        
        # Обработка preflight OPTIONS
        if ($request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin * always;
            add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
            add_header Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With" always;
            add_header Access-Control-Max-Age 3600 always;
            add_header Content-Length 0 always;
            return 204;
        }
    }
    
    # LaMa API - префиксное соответствие для /api/lama/
    location /api/lama/ {
        # Убираем /api/lama/ и передаем остаток
        rewrite ^/api/lama/(.*)$ /$1 break;
        
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        client_max_body_size 100M;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # CORS
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With" always;
    }
    
    # Дополнительные API эндпоинты (если есть)
    location /api/temp-file-from-data {
        # Прокси на основной сервер Node.js если есть
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        
        client_max_body_size 100M;
        add_header Access-Control-Allow-Origin * always;
    }
    
    # Основные статические файлы
    location / {
        try_files $uri $uri/ =404;
        
        # Кеширование статических ресурсов
        location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }
    
    # Специальная обработка панорамы
    location /pano {
        try_files $uri $uri/ /pano/index.html;
    }
    
    # Логирование для отладки
    access_log /var/log/nginx/color360_access.log;
    error_log /var/log/nginx/color360_error.log;
}
EOF

echo "✅ Новая конфигурация создана"

echo ""
echo "🧪 Проверка синтаксиса nginx..."
if nginx -t 2>/dev/null; then
    echo "✅ Синтаксис корректен"
    
    echo ""
    echo "🔄 Перезапуск nginx..."
    systemctl reload nginx
    echo "✅ Nginx перезапущен"
    
else
    echo "❌ Ошибка синтаксиса:"
    nginx -t
    echo ""
    echo "Восстанавливаем из резервной копии..."
    BACKUP_FILE=$(ls -1t "$NGINX_CONFIG.backup."* | head -1)
    cp "$BACKUP_FILE" "$NGINX_CONFIG"
    echo "✅ Конфигурация восстановлена"
    exit 1
fi

echo ""
echo "🧪 Тестирование исправленного API..."
sleep 2

echo "1. Тест прямого доступа /api/lama/health:"
RESPONSE=$(curl -s -w "%{http_code}" "http://localhost/api/lama/health")
HTTP_CODE="${RESPONSE: -3}"
BODY="${RESPONSE%???}"

if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ HTTP 200 - работает!"
    echo "Ответ: $BODY" | head -1
elif [[ "$HTTP_CODE" == "301" ]]; then
    echo "❌ Все еще HTTP 301 редирект"
else
    echo "⚠️ HTTP $HTTP_CODE"
    echo "Ответ: $BODY" | head -2
fi

echo ""
echo "2. Тест эндпоинта ретуши /api/retouch:"
RESPONSE2=$(curl -s -w "%{http_code}" -X OPTIONS "http://localhost/api/retouch")
HTTP_CODE2="${RESPONSE2: -3}"

if [[ "$HTTP_CODE2" == "204" ]]; then
    echo "✅ HTTP 204 - OPTIONS preflight работает!"
elif [[ "$HTTP_CODE2" == "200" ]]; then
    echo "✅ HTTP 200 - эндпоинт доступен!"
else
    echo "❌ HTTP $HTTP_CODE2 - проблема с доступом"
fi

echo ""
echo "3. Тест внешнего доступа:"
RESPONSE3=$(curl -s -w "%{http_code}" "http://color360.ru/api/lama/health")
HTTP_CODE3="${RESPONSE3: -3}"
BODY3="${RESPONSE3%???}"

if [[ "$HTTP_CODE3" == "200" ]]; then
    echo "✅ Внешний доступ работает!"
    echo "Ответ: $BODY3" | head -1
else
    echo "❌ Внешний доступ: HTTP $HTTP_CODE3"
fi

echo ""
echo "🏁 ИСПРАВЛЕНИЕ NGINX ЗАВЕРШЕНО"
echo "=============================="
if [[ "$HTTP_CODE" == "200" && "$HTTP_CODE2" =~ ^(200|204)$ ]]; then
    echo "✅ Проблема 301 редиректа устранена!"
    echo "✅ API доступен и готов к использованию"
else
    echo "⚠️ Могут остаться проблемы с доступом"
    echo "Проверьте логи: tail -f /var/log/nginx/color360_error.log"
fi

echo ""
echo "Доступные эндпоинты:"
echo "- http://color360.ru/api/retouch (POST для ретуши)"
echo "- http://color360.ru/api/lama/health (GET проверка статуса)"
echo "- http://color360.ru/api/lama/ (полный API)"