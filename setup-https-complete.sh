#!/bin/bash

# ПОЛНАЯ НАСТРОЙКА HTTPS ДЛЯ COLOR360.RU
echo "🔒 НАСТРОЙКА HTTPS ДЛЯ COLOR360.RU"
echo "=================================="

DOMAIN="color360.ru"
WWW_DOMAIN="www.color360.ru"
EMAIL="admin@color360.ru"
WEBROOT="/var/www/color360"

echo "🔍 1. ПРОВЕРКА ТЕКУЩЕГО СОСТОЯНИЯ"
echo "================================="

echo "Домен: $DOMAIN"
echo "WWW домен: $WWW_DOMAIN"
echo "Email для сертификата: $EMAIL"
echo "Webroot: $WEBROOT"

echo ""
echo "Проверка DNS резолва:"
for domain in $DOMAIN $WWW_DOMAIN; do
    if nslookup $domain >/dev/null 2>&1; then
        echo "✅ $domain резолвится"
        nslookup $domain | grep "Address:" | head -2
    else
        echo "❌ $domain не резолвится!"
    fi
done

echo ""
echo "Проверка доступности по HTTP:"
for domain in $DOMAIN $WWW_DOMAIN; do
    HTTP_CODE=$(curl -s -w "%{http_code}" -m 10 "http://$domain/" -o /dev/null)
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo "✅ http://$domain/ доступен (HTTP $HTTP_CODE)"
    else
        echo "❌ http://$domain/ недоступен (HTTP $HTTP_CODE)"
    fi
done

echo ""
echo "📦 2. УСТАНОВКА CERTBOT"
echo "======================"

# Обновление системы
echo "Обновление пакетов..."
apt update -y

# Установка snap если нужно
if ! command -v snap >/dev/null 2>&1; then
    echo "Установка snap..."
    apt install snapd -y
    systemctl enable snapd
    systemctl start snapd
    # Ждем инициализации snap
    sleep 10
fi

# Установка certbot через snap (рекомендуемый способ)
echo "Установка certbot..."
snap install core; snap refresh core
snap install --classic certbot

# Создание симлинка
ln -sf /snap/bin/certbot /usr/bin/certbot

# Проверка установки
if certbot --version >/dev/null 2>&1; then
    echo "✅ Certbot установлен: $(certbot --version)"
else
    echo "❌ Ошибка установки certbot!"
    # Fallback к apt установке
    echo "Попытка установки через apt..."
    apt install certbot python3-certbot-nginx -y
fi

echo ""
echo "🔧 3. ПОДГОТОВКА NGINX"
echo "====================="

# Остановка nginx для чистой установки
systemctl stop nginx 2>/dev/null

# Резервная копия конфигурации
BACKUP_DIR="/tmp/nginx-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r /etc/nginx/sites-* "$BACKUP_DIR/" 2>/dev/null || true
echo "Резервная копия nginx: $BACKUP_DIR"

# Очистка старых конфигураций
rm -f /etc/nginx/sites-enabled/color360*
rm -f /etc/nginx/sites-enabled/default

# Создание базовой HTTP конфигурации для получения сертификата
cat > /etc/nginx/sites-available/color360-http << 'EOF'
server {
    listen 80;
    server_name color360.ru www.color360.ru;
    
    root /var/www/color360;
    index index.html index.htm;
    
    # Для верификации Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/color360;
        allow all;
    }
    
    # Временно разрешаем HTTP доступ для получения сертификата
    location / {
        try_files $uri $uri/ /index.html;
    }
    
    location /pano {
        try_files $uri $uri/ /pano/index.html;
    }
    
    location /pano/ {
        try_files $uri $uri/ /pano/index.html;
    }
    
    # Статические файлы
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|webp)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }
    
    # API проксирование для LaMa
    location /api/retouch {
        proxy_pass http://127.0.0.1:8080/inpaint;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # CORS заголовки
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
        add_header Access-Control-Allow-Headers "Origin, Content-Type, Accept, Authorization";
        
        # Увеличиваем таймауты и размеры
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        client_max_body_size 50M;
    }
}
EOF

# Активация HTTP конфигурации
ln -sf /etc/nginx/sites-available/color360-http /etc/nginx/sites-enabled/color360-http

# Создание директории сайта если нужно
mkdir -p "$WEBROOT/.well-known/acme-challenge"

# Проверка конфигурации
if nginx -t; then
    echo "✅ Базовая HTTP конфигурация корректна"
    systemctl start nginx
else
    echo "❌ Ошибка в конфигурации nginx!"
    nginx -t
    exit 1
fi

echo ""
echo "🌐 4. ПРОВЕРКА HTTP ДОСТУПНОСТИ ПЕРЕД СЕРТИФИКАЦИЕЙ"
echo "=================================================="

sleep 3

for domain in $DOMAIN $WWW_DOMAIN; do
    HTTP_TEST=$(curl -s -w "%{http_code}" -m 15 "http://$domain/" -o /dev/null)
    if [[ "$HTTP_TEST" == "200" ]]; then
        echo "✅ http://$domain/ доступен для верификации"
    else
        echo "❌ http://$domain/ недоступен! Код: $HTTP_TEST"
        echo "   Проверьте DNS и файрвол перед продолжением"
    fi
done

echo ""
echo "🔒 5. ПОЛУЧЕНИЕ SSL СЕРТИФИКАТА"
echo "==============================="

# Получение сертификата через webroot
echo "Получение сертификата для $DOMAIN и $WWW_DOMAIN..."

# Тестовый режим (раскомментировать для production)
# TEST_FLAG="--dry-run"
TEST_FLAG=""

CERT_CMD="certbot certonly \
    --webroot \
    --webroot-path=$WEBROOT \
    --email $EMAIL \
    --agree-tos \
    --no-eff-email \
    --domains $DOMAIN,$WWW_DOMAIN \
    --non-interactive \
    $TEST_FLAG"

echo "Выполняется: $CERT_CMD"

if eval $CERT_CMD; then
    echo "✅ SSL сертификат получен успешно!"
    
    # Проверяем наличие файлов сертификата
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
    if [[ -f "$CERT_PATH/fullchain.pem" && -f "$CERT_PATH/privkey.pem" ]]; then
        echo "✅ Файлы сертификата найдены в $CERT_PATH"
        ls -la "$CERT_PATH/"
    else
        echo "⚠️ Файлы сертификата не найдены в ожидаемом месте"
    fi
else
    echo "❌ Ошибка получения SSL сертификата!"
    echo ""
    echo "Возможные причины:"
    echo "1. Домен не указывает на этот сервер"
    echo "2. Порт 80 заблокирован"
    echo "3. Файрвол блокирует доступ"
    echo "4. Достигнут лимит запросов Let's Encrypt"
    echo ""
    echo "Для диагностики выполните:"
    echo "- dig $DOMAIN"
    echo "- curl -I http://$DOMAIN/"
    echo "- ufw status"
    echo "- certbot certificates"
    exit 1
fi

echo ""
echo "🔧 6. СОЗДАНИЕ ПОЛНОЙ HTTPS КОНФИГУРАЦИИ"
echo "========================================"

# Создание полной HTTPS конфигурации
cat > /etc/nginx/sites-available/color360-https << 'EOF'
# Редирект с HTTP на HTTPS
server {
    listen 80;
    server_name color360.ru www.color360.ru;
    
    # Для обновления сертификатов
    location /.well-known/acme-challenge/ {
        root /var/www/color360;
        allow all;
    }
    
    # Все остальное перенаправляем на HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# Основной HTTPS сервер
server {
    listen 443 ssl http2;
    server_name color360.ru www.color360.ru;
    
    root /var/www/color360;
    index index.html index.htm;
    
    # SSL конфигурация
    ssl_certificate /etc/letsencrypt/live/color360.ru/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/color360.ru/privkey.pem;
    
    # Современные SSL настройки
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
    ssl_ecdh_curve secp384r1;
    ssl_session_timeout 10m;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # Безопасность
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";
    
    # Основные локации
    location / {
        try_files $uri $uri/ /index.html;
    }
    
    location /pano {
        try_files $uri $uri/ /pano/index.html;
    }
    
    location /pano/ {
        try_files $uri $uri/ /pano/index.html;
    }
    
    # Статические файлы с кэшированием
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|webp)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Vary "Accept-Encoding";
        try_files $uri =404;
    }
    
    # API проксирование для LaMa (HTTPS)
    location /api/retouch {
        proxy_pass http://127.0.0.1:8080/inpaint;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Port 443;
        
        # CORS заголовки
        add_header Access-Control-Allow-Origin "https://color360.ru";
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
        add_header Access-Control-Allow-Headers "Origin, Content-Type, Accept, Authorization";
        add_header Access-Control-Allow-Credentials true;
        
        # Preflight запросы
        if ($request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin "https://color360.ru";
            add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
            add_header Access-Control-Allow-Headers "Origin, Content-Type, Accept, Authorization";
            add_header Access-Control-Max-Age 1728000;
            add_header Content-Type "text/plain charset=UTF-8";
            add_header Content-Length 0;
            return 204;
        }
        
        # Увеличиваем таймауты и размеры
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        client_max_body_size 50M;
    }
    
    # Блокировка скрытых файлов
    location ~ /\. {
        deny all;
    }
    
    # Логирование
    access_log /var/log/nginx/color360_access.log;
    error_log /var/log/nginx/color360_error.log;
}
EOF

# Замена конфигурации
rm -f /etc/nginx/sites-enabled/color360*
ln -sf /etc/nginx/sites-available/color360-https /etc/nginx/sites-enabled/color360-https

echo ""
echo "🧪 7. ПРОВЕРКА И АКТИВАЦИЯ HTTPS"
echo "==============================="

# Проверка конфигурации
if nginx -t; then
    echo "✅ HTTPS конфигурация корректна"
    
    # Перезагрузка nginx
    systemctl reload nginx
    sleep 3
    
    echo "✅ Nginx перезагружен с HTTPS конфигурацией"
else
    echo "❌ Ошибка в HTTPS конфигурации!"
    nginx -t
    exit 1
fi

echo ""
echo "🔐 8. НАСТРОЙКА АВТООБНОВЛЕНИЯ СЕРТИФИКАТОВ"
echo "=========================================="

# Создание скрипта для обновления сертификатов
cat > /usr/local/bin/renew-color360-cert.sh << 'EOF'
#!/bin/bash
# Обновление SSL сертификата для color360.ru

echo "$(date): Проверка обновления сертификата color360.ru" >> /var/log/certbot-renew.log

# Обновление сертификата
if certbot renew --quiet --no-self-upgrade; then
    echo "$(date): Сертификат обновлен успешно" >> /var/log/certbot-renew.log
    
    # Проверяем, нужно ли перезагружать nginx
    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx
        echo "$(date): Nginx перезагружен" >> /var/log/certbot-renew.log
    else
        echo "$(date): ОШИБКА: Конфигурация nginx некорректна!" >> /var/log/certbot-renew.log
    fi
else
    echo "$(date): Ошибка обновления сертификата" >> /var/log/certbot-renew.log
fi
EOF

chmod +x /usr/local/bin/renew-color360-cert.sh

# Добавление в crontab (проверка каждые 12 часов)
CRON_JOB="0 */12 * * * /usr/local/bin/renew-color360-cert.sh"
(crontab -l 2>/dev/null | grep -v "renew-color360-cert"; echo "$CRON_JOB") | crontab -

echo "✅ Автообновление сертификатов настроено"
echo "   Скрипт: /usr/local/bin/renew-color360-cert.sh"
echo "   Лог: /var/log/certbot-renew.log"
echo "   Cron: каждые 12 часов"

echo ""
echo "🧪 9. ФИНАЛЬНОЕ ТЕСТИРОВАНИЕ HTTPS"
echo "================================="

sleep 5

echo "Тестирование HTTPS доступности..."

# Тест основного домена
HTTPS_MAIN=$(curl -s -w "%{http_code}" -m 15 "https://$DOMAIN/" -o /dev/null -k)
if [[ "$HTTPS_MAIN" == "200" ]]; then
    echo "✅ https://$DOMAIN/ доступен (HTTP $HTTPS_MAIN)"
else
    echo "❌ https://$DOMAIN/ недоступен (HTTP $HTTPS_MAIN)"
fi

# Тест WWW домена
HTTPS_WWW=$(curl -s -w "%{http_code}" -m 15 "https://$WWW_DOMAIN/" -o /dev/null -k)
if [[ "$HTTPS_WWW" == "200" ]]; then
    echo "✅ https://$WWW_DOMAIN/ доступен (HTTP $HTTPS_WWW)"
else
    echo "❌ https://$WWW_DOMAIN/ недоступен (HTTP $HTTPS_WWW)"
fi

# Тест панорамы
HTTPS_PANO=$(curl -s -w "%{http_code}" -m 15 "https://$DOMAIN/pano/" -o /dev/null -k)
if [[ "$HTTPS_PANO" == "200" ]]; then
    echo "✅ https://$DOMAIN/pano/ доступна (HTTP $HTTPS_PANO)"
else
    echo "❌ https://$DOMAIN/pano/ недоступна (HTTP $HTTPS_PANO)"
fi

# Тест редиректа с HTTP на HTTPS
HTTP_REDIRECT=$(curl -s -w "%{http_code}" -m 15 "http://$DOMAIN/" -o /dev/null)
if [[ "$HTTP_REDIRECT" == "301" ]]; then
    echo "✅ HTTP → HTTPS редирект работает (HTTP $HTTP_REDIRECT)"
else
    echo "⚠️ HTTP → HTTPS редирект: HTTP $HTTP_REDIRECT"
fi

echo ""
echo "🔍 10. ПРОВЕРКА SSL СЕРТИФИКАТА"
echo "==============================="

# Информация о сертификате
echo "Информация о сертификате:"
certbot certificates | grep -A 10 "$DOMAIN" || echo "Сертификат не найден в списке"

# SSL тест через openssl
echo ""
echo "SSL тест подключения:"
timeout 10 openssl s_client -connect $DOMAIN:443 -servername $DOMAIN </dev/null 2>/dev/null | grep -E "(subject|issuer|verify return code)" || echo "SSL тест недоступен"

echo ""
echo "🏁 НАСТРОЙКА HTTPS ЗАВЕРШЕНА"
echo "============================"

if [[ "$HTTPS_MAIN" == "200" && "$HTTPS_PANO" == "200" ]]; then
    echo "🎉 УСПЕХ! HTTPS полностью настроен и работает"
    echo ""
    echo "✅ Доступные URL:"
    echo "   🌐 https://color360.ru/"
    echo "   🎭 https://color360.ru/pano/"
    echo "   🌐 https://www.color360.ru/"
    echo ""
    echo "✅ Функции:"
    echo "   🔒 SSL/TLS шифрование активно"
    echo "   🔄 Автоматический редирект HTTP → HTTPS"
    echo "   📱 HTTP/2 поддержка"
    echo "   🔐 Современные SSL настройки безопасности"
    echo "   ⏰ Автообновление сертификатов"
    echo ""
    echo "🔧 Управление:"
    echo "   - Проверка сертификата: certbot certificates"
    echo "   - Обновление сертификата: certbot renew"
    echo "   - Тест SSL: openssl s_client -connect color360.ru:443"
    echo "   - Лог обновлений: tail -f /var/log/certbot-renew.log"
else
    echo "⚠️ HTTPS настроен, но есть проблемы с доступностью"
    echo ""
    echo "Проверьте:"
    echo "1. DNS настройки домена"
    echo "2. Файрвол: ufw allow 443/tcp"
    echo "3. Логи nginx: tail -f /var/log/nginx/error.log"
    echo "4. Статус сертификата: certbot certificates"
fi

echo ""
echo "📊 Полезные команды:"
echo "- systemctl status nginx"
echo "- certbot certificates"
echo "- certbot renew --dry-run"
echo "- tail -f /var/log/nginx/color360_error.log"
echo "- curl -I https://color360.ru/"