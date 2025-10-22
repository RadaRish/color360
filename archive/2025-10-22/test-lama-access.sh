#!/bin/bash

# Проверка и настройка доступа к LaMa API через color360.ru
echo "🌐 НАСТРОЙКА ДОСТУПА К LAMA API ЧЕРЕЗ COLOR360.RU"
echo "==============================================="

echo "🧪 Тестирование доступа..."

# Локальный доступ
echo "1. Локальный доступ (localhost):"
if curl -s --connect-timeout 3 "http://localhost:8080/health" >/dev/null 2>&1; then
    echo "✅ http://localhost:8080 - работает"
    curl -s "http://localhost:8080/health" | head -1
else
    echo "❌ http://localhost:8080 - недоступен"
fi

echo ""
# Внешний IP
echo "2. Прямой IP доступ:"
EXTERNAL_IP=$(curl -s ifconfig.me 2>/dev/null || echo "неизвестен")
echo "Внешний IP сервера: $EXTERNAL_IP"

if [[ "$EXTERNAL_IP" != "неизвестен" ]]; then
    if curl -s --connect-timeout 5 "http://$EXTERNAL_IP:8080/health" >/dev/null 2>&1; then
        echo "✅ http://$EXTERNAL_IP:8080 - работает"
    else
        echo "❌ http://$EXTERNAL_IP:8080 - недоступен"
    fi
fi

echo ""
# Тест доменов
echo "3. Доменные имена:"
for domain in color360.ru color360.online; do
    echo "Тестируем $domain:"
    if curl -s --connect-timeout 5 "http://$domain:8080/health" >/dev/null 2>&1; then
        echo "✅ http://$domain:8080 - работает"
        curl -s "http://$domain:8080/health" | head -1
    else
        echo "❌ http://$domain:8080 - недоступен"
        # Проверяем резолв домена
        if nslookup $domain >/dev/null 2>&1; then
            echo "   DNS: домен резолвится"
        else
            echo "   DNS: домен не резолвится"
        fi
    fi
    echo ""
done

echo ""
echo "🔧 Проверка конфигурации nginx..."

# Проверяем есть ли nginx и его конфигурация для API
if command -v nginx >/dev/null 2>&1; then
    echo "Nginx установлен"
    
    # Проверяем конфигурацию для проксирования API
    if grep -r "location.*lama\|location.*8080\|proxy_pass.*8080" /etc/nginx/ 2>/dev/null; then
        echo "✅ Найдены настройки проксирования для LaMa API"
        grep -r "location.*lama\|location.*8080\|proxy_pass.*8080" /etc/nginx/ 2>/dev/null | head -5
    else
        echo "⚠️ Настройки проксирования для LaMa API не найдены"
        echo ""
        echo "📝 РЕКОМЕНДУЕМАЯ КОНФИГУРАЦИЯ NGINX:"
        echo "Добавьте в /etc/nginx/sites-available/color360.ru:"
        echo ""
        cat << 'EOF'
# Проксирование LaMa API
location /api/lama/ {
    proxy_pass http://localhost:8080/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    
    # Увеличиваем лимиты для загрузки изображений
    client_max_body_size 50M;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}

# Прямой доступ к API (опционально)
location /lama-api/ {
    proxy_pass http://localhost:8080/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    
    client_max_body_size 50M;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}
EOF
    fi
else
    echo "⚠️ Nginx не установлен или недоступен"
fi

echo ""
echo "🔌 Проверка firewall (ufw)..."
ufw status | grep 8080 && echo "✅ Порт 8080 открыт" || echo "⚠️ Порт 8080 может быть закрыт"

echo ""
echo "📊 Статус LaMa сервиса:"
systemctl status lama-inpainting --no-pager | head -10

echo ""
echo "🏁 РЕЗУЛЬТАТЫ ДИАГНОСТИКИ"
echo "========================"
echo "LaMa API должен быть доступен по адресам:"
echo "- Локально: http://localhost:8080"
if [[ "$EXTERNAL_IP" != "неизвестен" ]]; then
    echo "- Прямой IP: http://$EXTERNAL_IP:8080"
fi
echo "- Через nginx (если настроено): http://color360.ru/api/lama/"
echo ""
echo "Для веб-интерфейса обновите URL в retouch_manager.js:"
echo "const LAMA_API_URL = 'http://color360.ru/api/lama';"
echo "или"  
echo "const LAMA_API_URL = 'http://localhost:8080';"