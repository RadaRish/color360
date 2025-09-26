#!/bin/bash

echo "📈 Обновление лимитов nginx для обработки больших панорам..."

# Backup текущего конфига
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)

# Обновляем основные лимиты в nginx.conf
sed -i '/client_max_body_size/c\        client_max_body_size 200M;' /etc/nginx/nginx.conf

# Если директивы нет, добавляем в http блок
if ! grep -q "client_max_body_size" /etc/nginx/nginx.conf; then
    sed -i '/http {/a\        client_max_body_size 200M;\n        client_body_timeout 300s;\n        client_header_timeout 300s;\n        proxy_connect_timeout 300s;\n        proxy_send_timeout 300s;\n        proxy_read_timeout 300s;' /etc/nginx/nginx.conf
fi

# Обновляем конфиг сайта для оптимизации больших файлов
cat > /tmp/nginx_retouch_limits << 'EOF'

    # Увеличенные лимиты для ретуши панорам
    client_max_body_size 200M;
    client_body_timeout 300s;
    client_header_timeout 300s;
    
    # Оптимизация прокси для больших файлов
    proxy_connect_timeout 300s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;
    proxy_buffering off;
    proxy_request_buffering off;
EOF

# Добавляем в server блок если еще нет
if ! grep -q "client_max_body_size 200M" /etc/nginx/sites-available/color360; then
    sed -i '/server_name.*color360.ru;/r /tmp/nginx_retouch_limits' /etc/nginx/sites-available/color360
fi

# Очистка временного файла
rm /tmp/nginx_retouch_limits

echo "✅ Лимиты nginx обновлены:"
echo "   - client_max_body_size: 200M"
echo "   - Таймауты: 300s"
echo "   - Оптимизация буферизации отключена"

# Проверяем конфигурацию
nginx -t

if [ $? -eq 0 ]; then
    echo "🔄 Перезагружаем nginx..."
    systemctl reload nginx
    echo "✅ nginx перезагружен успешно!"
else
    echo "❌ Ошибка в конфигурации nginx!"
    echo "Восстанавливаем backup..."
    cp /etc/nginx/nginx.conf.backup.* /etc/nginx/nginx.conf
    exit 1
fi

echo ""
echo "📊 Текущие лимиты:"
grep -A5 -B5 "client_max_body_size\|proxy.*timeout" /etc/nginx/nginx.conf