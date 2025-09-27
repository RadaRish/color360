#!/bin/bash

# БЫСТРОЕ ИСПРАВЛЕНИЕ HTTP → HTTPS
echo "⚡ БЫСТРОЕ ИСПРАВЛЕНИЕ HTTP → HTTPS"
echo "=================================="

DOMAIN="color360.ru"

echo "🔍 1. ПРОВЕРКА ТЕКУЩЕГО СОСТОЯНИЯ"
echo "================================="

# Проверяем наличие сертификата
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
if [[ -f "$CERT_PATH/fullchain.pem" && -f "$CERT_PATH/privkey.pem" ]]; then
    echo "✅ SSL сертификат найден"
    
    # Проверяем срок действия
    if EXPIRE_DATE=$(openssl x509 -in "$CERT_PATH/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2); then
        if EXPIRE_EPOCH=$(date -d "$EXPIRE_DATE" +%s 2>/dev/null); then
            CURRENT_EPOCH=$(date +%s)
            DAYS_LEFT=$(( ($EXPIRE_EPOCH - $CURRENT_EPOCH) / 86400 ))
            if [[ $DAYS_LEFT -gt 7 ]]; then
                echo "✅ Сертификат действителен еще $DAYS_LEFT дней"
                CERT_VALID=true
            else
                echo "⚠️ Сертификат истекает через $DAYS_LEFT дней"
                CERT_VALID=false
            fi
        fi
    fi
else
    echo "❌ SSL сертификат отсутствует!"
    CERT_VALID=false
fi

echo ""
echo "🔧 2. СОЗДАНИЕ КОНФИГУРАЦИИ С HTTPS"
echo "===================================="

if [[ "$CERT_VALID" == "true" ]]; then
    echo "Создание HTTPS конфигурации с существующим сертификатом..."
    
    # Остановка nginx
    systemctl stop nginx 2>/dev/null
    
    # Резервная копия
    BACKUP_DIR="/tmp/nginx-backup-https-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp -r /etc/nginx/sites-* "$BACKUP_DIR/" 2>/dev/null || true
    echo "Резервная копия: $BACKUP_DIR"
    
    # Очистка старых конфигов
    rm -f /etc/nginx/sites-enabled/color360*
    
    # Создание HTTPS конфигурации
    cat > /etc/nginx/sites-available/color360-https-fixed << 'EOF'
# Редирект HTTP на HTTPS
server {
    listen 80;
    server_name color360.ru www.color360.ru _;
    
    # Для обновления сертификатов Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/color360;
        allow all;
    }
    
    # Все остальное - редирект на HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS сервер
server {
    listen 443 ssl http2;
    server_name color360.ru www.color360.ru;
    
    root /var/www/color360;
    index index.html index.htm;
    
    # SSL настройки
    ssl_certificate /etc/letsencrypt/live/color360.ru/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/color360.ru/privkey.pem;
    
    # Современная SSL конфигурация
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # Заголовки безопасности
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Основные страницы
    location / {
        try_files $uri $uri/ @fallback;
    }
    
    # Панорама
    location /pano {
        try_files $uri $uri/ /pano/index.html;
    }
    
    location /pano/ {
        try_files $uri $uri/ /pano/index.html;
    }
    
    # Профиль и админка
    location /profile.html {
        try_files $uri =404;
    }
    
    location /admin-dashboard.html {
        try_files $uri =404;
    }
    
    # Статические файлы
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|webp|mp4)$ {
        expires 1y;
        add_header Cache-Control "public, no-transform";
        try_files $uri =404;
    }
    
    # API для LaMa (с HTTPS заголовками)
    location /api/retouch {
        proxy_pass http://127.0.0.1:8080/inpaint;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Port 443;
        
        # CORS для HTTPS
        add_header Access-Control-Allow-Origin "https://$host" always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization" always;
        add_header Access-Control-Allow-Credentials "true" always;
        
        # OPTIONS для preflight
        if ($request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin "https://$host";
            add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
            add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization";
            add_header Access-Control-Max-Age 1728000;
            add_header Content-Type "text/plain; charset=utf-8";
            add_header Content-Length 0;
            return 204;
        }
        
        # Увеличенные лимиты
        client_max_body_size 100M;
        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
        proxy_buffering off;
        proxy_request_buffering off;
    }
    
    # Fallback для несуществующих страниц
    location @fallback {
        return 200 '<!DOCTYPE html>
<html lang="ru"><head><meta charset="UTF-8">
<title>Color360</title>
<style>body{font-family:Arial,sans-serif;text-align:center;padding:50px;background:linear-gradient(135deg,#667eea,#764ba2);color:white;margin:0;min-height:100vh;display:flex;justify-content:center;align-items:center}</style>
</head><body>
<div><h1>🌐 Color360</h1><p>Добро пожаловать в Color360!</p>
<p><a href="/pano/" style="color:#fff;background:rgba(255,255,255,0.2);padding:10px 20px;border-radius:5px;text-decoration:none;">→ Панорамный просмотр</a></p>
</div></body></html>';
        add_header Content-Type "text/html; charset=utf-8";
    }
    
    # Безопасность
    location ~ /\. {
        deny all;
    }
    
    # Логи
    access_log /var/log/nginx/color360_access.log;
    error_log /var/log/nginx/color360_error.log;
}
EOF
    
    # Активация
    ln -sf /etc/nginx/sites-available/color360-https-fixed /etc/nginx/sites-enabled/color360-https-fixed
    
else
    echo "❌ Сертификат недействителен или отсутствует"
    echo "Сначала выполните: bash setup-https-complete.sh"
    exit 1
fi

echo ""
echo "🧪 3. ПРОВЕРКА И ЗАПУСК"
echo "======================"

# Проверка конфигурации
if nginx -t; then
    echo "✅ Конфигурация nginx корректна"
    
    # Запуск nginx
    systemctl start nginx
    systemctl enable nginx
    
    echo "✅ Nginx запущен"
else
    echo "❌ Ошибка конфигурации nginx:"
    nginx -t
    exit 1
fi

echo ""
echo "⏱️ 4. ОЖИДАНИЕ И ТЕСТИРОВАНИЕ"
echo "============================="

echo "Ожидание запуска служб..."
sleep 5

# Тесты
echo ""
echo "Тест HTTP → HTTPS редиректа:"
HTTP_REDIRECT=$(curl -s -w "%{http_code}" -m 10 "http://$DOMAIN/" -o /dev/null)
if [[ "$HTTP_REDIRECT" == "301" ]]; then
    echo "✅ HTTP корректно перенаправляется на HTTPS"
else
    echo "⚠️ HTTP редирект: код $HTTP_REDIRECT"
fi

echo ""
echo "Тест HTTPS доступности:"
HTTPS_MAIN=$(curl -s -w "%{http_code}" -m 15 "https://$DOMAIN/" -o /dev/null)
if [[ "$HTTPS_MAIN" == "200" ]]; then
    echo "✅ https://$DOMAIN/ доступен"
else
    echo "❌ https://$DOMAIN/ недоступен (код: $HTTPS_MAIN)"
fi

echo ""
echo "Тест HTTPS панорамы:"
HTTPS_PANO=$(curl -s -w "%{http_code}" -m 15 "https://$DOMAIN/pano/" -o /dev/null)
if [[ "$HTTPS_PANO" == "200" ]]; then
    echo "✅ https://$DOMAIN/pano/ доступна"
else
    echo "❌ https://$DOMAIN/pano/ недоступна (код: $HTTPS_PANO)"
fi

echo ""
echo "SSL тест:"
if timeout 10 openssl s_client -connect $DOMAIN:443 -servername $DOMAIN </dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
    echo "✅ SSL сертификат валиден"
else
    echo "⚠️ Проблемы с SSL сертификатом"
fi

echo ""
echo "🎯 5. ФИНАЛЬНЫЙ СТАТУС"
echo "======================"

if [[ "$HTTP_REDIRECT" == "301" && "$HTTPS_MAIN" == "200" && "$HTTPS_PANO" == "200" ]]; then
    echo ""
    echo "🎉 HTTPS УСПЕШНО НАСТРОЕН!"
    echo "========================="
    echo ""
    echo "✅ Все работает корректно:"
    echo "   🔒 https://color360.ru/"
    echo "   🎭 https://color360.ru/pano/"
    echo "   🔄 http:// автоматически перенаправляется на https://"
    echo ""
    echo "🔧 Дополнительно:"
    echo "   - SSL сертификат активен"
    echo "   - Заголовки безопасности установлены"
    echo "   - HTTP/2 поддержка включена"
    echo "   - CORS настроен для HTTPS API"
    echo ""
    echo "📱 Теперь можете безопасно использовать:"
    echo "   - Панорамный просмотр через HTTPS"
    echo "   - Редактирование изображений с LaMa API"
    echo "   - Все функции сайта с SSL шифрованием"
    
else
    echo ""
    echo "⚠️ ЧАСТИЧНЫЙ УСПЕХ"
    echo "=================="
    
    if [[ "$HTTPS_MAIN" == "200" ]]; then
        echo "✅ HTTPS основной сайт работает"
    else
        echo "❌ Проблема с HTTPS основного сайта"
    fi
    
    if [[ "$HTTPS_PANO" == "200" ]]; then
        echo "✅ HTTPS панорама работает"
    else
        echo "❌ Проблема с HTTPS панорамы"
    fi
    
    if [[ "$HTTP_REDIRECT" == "301" ]]; then
        echo "✅ HTTP редирект работает"
    else
        echo "❌ Проблема с HTTP редиректом"
    fi
    
    echo ""
    echo "🛠️ Для диагностики:"
    echo "   bash diagnose-https.sh"
fi

echo ""
echo "📋 Полезные команды:"
echo "- curl -I https://color360.ru/"
echo "- systemctl status nginx"
echo "- tail -f /var/log/nginx/color360_error.log"
echo "- certbot certificates"