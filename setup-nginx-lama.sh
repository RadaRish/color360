#!/bin/bash

# Настройка nginx для проксирования LaMa API
echo "🔧 НАСТРОЙКА NGINX ДЛЯ LAMA API"
echo "=============================="

# Определяем пути конфигурации nginx
NGINX_SITES_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"

# Ищем основной конфиг сайта
SITE_CONFIG=""
for config_name in color360.ru color360 default; do
    if [[ -f "$NGINX_SITES_DIR/$config_name" ]]; then
        SITE_CONFIG="$NGINX_SITES_DIR/$config_name"
        echo "✅ Найден конфиг: $SITE_CONFIG"
        break
    fi
done

if [[ -z "$SITE_CONFIG" ]]; then
    echo "❌ Конфиг nginx для color360.ru не найден"
    echo "Создаем новый конфиг..."
    SITE_CONFIG="$NGINX_SITES_DIR/color360.ru"
fi

echo ""
echo "📝 Создание резервной копии..."
if [[ -f "$SITE_CONFIG" ]]; then
    cp "$SITE_CONFIG" "$SITE_CONFIG.backup.$(date +%s)"
    echo "✅ Резервная копия создана"
fi

echo ""
echo "🔧 Настройка проксирования для /api/retouch..."

# Проверяем есть ли уже настройки для /api/retouch
if [[ -f "$SITE_CONFIG" ]] && grep -q "location /api/retouch" "$SITE_CONFIG"; then
    echo "⚠️ Настройки для /api/retouch уже существуют"
    echo "Текущая конфигурация:"
    grep -A 10 "location /api/retouch" "$SITE_CONFIG"
else
    echo "ℹ️ Добавляем новые настройки проксирования..."
    
    # Создаем временный файл с настройками LaMa API
    cat > "/tmp/lama_nginx_config" << 'EOF'

    # LaMa AI API проксирование
    location /api/retouch {
        # Проксируем на LaMa сервис
        proxy_pass http://localhost:8080/inpaint;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Настройки для загрузки изображений
        client_max_body_size 100M;
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
        proxy_buffering off;
        
        # CORS headers для веб-интерфейса
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
        add_header Access-Control-Allow-Headers "Content-Type, Authorization";
        
        # Обработка OPTIONS запросов
        if ($request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
            add_header Access-Control-Allow-Headers "Content-Type, Authorization";
            return 204;
        }
    }

    # Дополнительные эндпоинты LaMa API
    location /api/lama/ {
        proxy_pass http://localhost:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        client_max_body_size 100M;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # CORS
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
        add_header Access-Control-Allow-Headers "Content-Type, Authorization";
    }

EOF
    
    # Добавляем настройки в конфиг nginx
    if [[ -f "$SITE_CONFIG" ]]; then
        # Ищем блок server и добавляем настройки перед закрывающей скобкой
        sed -i '/^[[:space:]]*}[[:space:]]*$/i\
    # Добавлено: LaMa API проксирование' "$SITE_CONFIG"
        
        # Вставляем настройки LaMa перед последней закрывающей скобкой в server блоке
        awk '
        /^[[:space:]]*server[[:space:]]*{/ { in_server = 1 }
        in_server && /^[[:space:]]*}[[:space:]]*$/ && !added { 
            while ((getline line < "/tmp/lama_nginx_config") > 0) print line
            close("/tmp/lama_nginx_config")
            added = 1
        }
        { print }
        ' "$SITE_CONFIG" > "/tmp/nginx_new_config"
        
        mv "/tmp/nginx_new_config" "$SITE_CONFIG"
        rm -f "/tmp/lama_nginx_config"
        
    else
        # Создаем новый конфиг с нуля
        cat > "$SITE_CONFIG" << 'EOF'
server {
    listen 80;
    server_name color360.ru www.color360.ru;
    
    root /var/www/color360;
    index index.html;
    
    # Основные статические файлы
    location / {
        try_files $uri $uri/ =404;
    }

    # LaMa AI API проксирование
    location /api/retouch {
        proxy_pass http://localhost:8080/inpaint;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        client_max_body_size 100M;
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
        proxy_buffering off;
        
        # CORS
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
        add_header Access-Control-Allow-Headers "Content-Type, Authorization";
        
        if ($request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
            add_header Access-Control-Allow-Headers "Content-Type, Authorization";
            return 204;
        }
    }

    location /api/lama/ {
        proxy_pass http://localhost:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        client_max_body_size 100M;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
        add_header Access-Control-Allow-Headers "Content-Type, Authorization";
    }
}
EOF
    fi
    
    echo "✅ Настройки LaMa API добавлены"
fi

echo ""
echo "🔗 Активация сайта..."
if [[ ! -L "$NGINX_ENABLED_DIR/color360.ru" ]]; then
    ln -sf "$SITE_CONFIG" "$NGINX_ENABLED_DIR/color360.ru"
    echo "✅ Сайт активирован"
fi

echo ""
echo "🧪 Проверка конфигурации nginx..."
if nginx -t 2>/dev/null; then
    echo "✅ Конфигурация nginx корректна"
    
    echo ""
    echo "🔄 Перезапуск nginx..."
    systemctl reload nginx
    echo "✅ Nginx перезапущен"
    
else
    echo "❌ Ошибка в конфигурации nginx:"
    nginx -t
    echo ""
    echo "Восстанавливаем из резервной копии..."
    if [[ -f "$SITE_CONFIG.backup."* ]]; then
        BACKUP_FILE=$(ls -1t "$SITE_CONFIG.backup."* | head -1)
        cp "$BACKUP_FILE" "$SITE_CONFIG"
        echo "✅ Конфигурация восстановлена из $BACKUP_FILE"
    fi
    exit 1
fi

echo ""
echo "🧪 Тестирование API через nginx..."
sleep 2

echo "Тест /api/lama/health:"
if curl -s --connect-timeout 5 "http://localhost/api/lama/health" >/dev/null 2>&1; then
    echo "✅ /api/lama/health работает"
    curl -s "http://localhost/api/lama/health" | head -1
else
    echo "❌ /api/lama/health недоступен"
fi

echo ""
echo "Тест внешнего доступа:"
if curl -s --connect-timeout 5 "http://color360.ru/api/lama/health" >/dev/null 2>&1; then
    echo "✅ http://color360.ru/api/lama/health работает"
    curl -s "http://color360.ru/api/lama/health" | head -1
else
    echo "❌ http://color360.ru/api/lama/health недоступен"
fi

echo ""
echo "🏁 НАСТРОЙКА NGINX ЗАВЕРШЕНА"
echo "============================"
echo "LaMa API теперь доступен через:"
echo "- http://color360.ru/api/retouch (для ретуши)"
echo "- http://color360.ru/api/lama/ (полный API)"
echo "- http://localhost:8080 (прямой доступ)"
echo ""
echo "Веб-интерфейс будет автоматически использовать /api/retouch"
echo "Настройки nginx: $SITE_CONFIG"