#!/bin/bash

echo "🔐 Установка HTTPS для Color360 с Let's Encrypt..."
echo "================================================="

# Проверяем что скрипт запущен от root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Запустите от root: sudo $0"
    exit 1
fi

# Домены для сертификата
DOMAINS="color360.ru www.color360.ru"
EMAIL="admin@color360.ru"

echo "📋 Домены: $DOMAINS"
echo "📧 Email: $EMAIL"
echo ""

# 1. Устанавливаем certbot
echo "1️⃣ Установка certbot..."
apt update
apt install -y certbot python3-certbot-nginx

# 2. Проверяем текущий nginx конфиг
echo "2️⃣ Проверка nginx конфигурации..."
nginx -t
if [ $? -ne 0 ]; then
    echo "❌ Ошибка в конфигурации nginx! Исправьте перед продолжением."
    exit 1
fi

# 3. Создаем backup конфига
echo "3️⃣ Создание backup nginx конфига..."
cp /etc/nginx/sites-available/color360 /etc/nginx/sites-available/color360.backup.$(date +%Y%m%d_%H%M%S)

# 4. Получаем сертификат
echo "4️⃣ Получение SSL сертификата..."
echo "⚠️  Убедитесь что домены корректно указывают на этот сервер!"
read -p "Продолжить? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Отменено пользователем"
    exit 1
fi

# Останавливаем nginx временно для standalone режима
systemctl stop nginx

# Получаем сертификат в standalone режиме
certbot certonly --standalone \
    --email $EMAIL \
    --agree-tos \
    --no-eff-email \
    -d color360.ru \
    -d www.color360.ru

if [ $? -ne 0 ]; then
    echo "❌ Ошибка получения сертификата!"
    systemctl start nginx
    exit 1
fi

# 5. Обновляем nginx конфиг для HTTPS
echo "5️⃣ Настройка nginx для HTTPS..."

cat > /etc/nginx/sites-available/color360 << 'EOF'
# HTTP -> HTTPS redirect
server {
    listen 80;
    server_name color360.ru www.color360.ru;
    return 301 https://$server_name$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name color360.ru www.color360.ru;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/color360.ru/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/color360.ru/privkey.pem;
    
    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Document root
    root /var/www/color360;
    index index.html;
    
    # Static assets with long cache
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }
    
    # Static assets directory
    location ^~ /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }
    
    # Pano static files
    location ^~ /pano/ {
        try_files $uri $uri/ @pano_proxy;
    }
    
    # Pano proxy fallback
    location @pano_proxy {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
    
    # LaMa API
    location ^~ /lama/ {
        proxy_pass http://127.0.0.1:5002/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
    }
    
    # API routes
    location ^~ /api/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Main application
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
    
    # Security: блокируем доступ к служебным файлам
    location ~ /\. {
        deny all;
    }
    
    location ~* \.(env|git|svn)$ {
        deny all;
    }
}
EOF

# 6. Проверяем новый конфиг
echo "6️⃣ Проверка нового nginx конфига..."
nginx -t
if [ $? -ne 0 ]; then
    echo "❌ Ошибка в новом конфиге! Восстанавливаем backup..."
    cp /etc/nginx/sites-available/color360.backup.* /etc/nginx/sites-available/color360
    nginx -t
    systemctl start nginx
    exit 1
fi

# 7. Запускаем nginx
echo "7️⃣ Запуск nginx с HTTPS..."
systemctl start nginx
systemctl reload nginx

# 8. Настраиваем автообновление сертификатов
echo "8️⃣ Настройка автообновления сертификатов..."
(crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet && systemctl reload nginx") | crontab -

# 9. Обновляем server.js для работы с HTTPS
echo "9️⃣ Обновление настроек приложения для HTTPS..."
cd /var/www/color360

# Возвращаем helmet с правильными настройками для HTTPS
if [ -f server.js.backup.* ]; then
    echo "Восстанавливаем helmet из backup..."
    cp server.js.backup.* server.js
fi

# Перезапускаем приложение
systemctl restart color360-app

# 10. Финальные тесты
echo "🔟 Финальная проверка..."
echo ""

echo "HTTP redirect тест:"
curl -I http://color360.ru/ 2>/dev/null | head -3

echo ""
echo "HTTPS работа:"
curl -I https://color360.ru/ 2>/dev/null | head -10

echo ""
echo "SSL сертификат:"
echo | openssl s_client -servername color360.ru -connect color360.ru:443 2>/dev/null | openssl x509 -noout -dates

echo ""
echo "✅ HTTPS настройка завершена!"
echo ""
echo "🌐 Ваш сайт доступен по адресам:"
echo "   https://color360.ru"
echo "   https://www.color360.ru"
echo "   https://color360.ru/pano/"
echo ""
echo "🔐 Сертификат будет автоматически обновляться"
echo "📋 Backup nginx конфига: /etc/nginx/sites-available/color360.backup.*"