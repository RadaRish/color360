#!/bin/bash

# Экстренная диагностика и восстановление доступности сайта
echo "🚨 ЭКСТРЕННАЯ ДИАГНОСТИКА ДОСТУПНОСТИ САЙТА"
echo "==========================================="

echo "🔍 1. ПРОВЕРКА СЕТЕВОЙ ДОСТУПНОСТИ"
echo "=================================="

echo "Проверка DNS резолва для color360.ru:"
if nslookup color360.ru >/dev/null 2>&1; then
    echo "✅ DNS резолв работает"
    nslookup color360.ru | grep "Address:" | head -2
else
    echo "❌ DNS резолв не работает"
fi

echo ""
echo "Проверка доступности сервера по IP:"
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "неизвестен")
echo "IP сервера: $SERVER_IP"

echo "Проверка порта 80:"
if netstat -tuln | grep -q ":80 "; then
    echo "✅ Порт 80 слушается"
    netstat -tuln | grep ":80 "
else
    echo "❌ Порт 80 не слушается!"
fi

echo ""
echo "🔍 2. ПРОВЕРКА NGINX"
echo "=================="

echo "Статус nginx:"
if systemctl is-active --quiet nginx; then
    echo "✅ Nginx активен"
else
    echo "❌ Nginx неактивен!"
    systemctl status nginx --no-pager | head -10
fi

echo ""
echo "Проверка конфигурации nginx:"
if nginx -t 2>/dev/null; then
    echo "✅ Конфигурация nginx корректна"
else
    echo "❌ Ошибки в конфигурации nginx:"
    nginx -t
fi

echo ""
echo "Проверка активных сайтов:"
ls -la /etc/nginx/sites-enabled/ || echo "Директория sites-enabled недоступна"

echo ""
echo "🔍 3. ПРОВЕРКА ФАЙЛОВ САЙТА"
echo "=========================="

WEBROOT="/var/www/color360"
echo "Корневая директория сайта: $WEBROOT"

if [[ -d "$WEBROOT" ]]; then
    echo "✅ Директория $WEBROOT существует"
    echo "Содержимое:"
    ls -la "$WEBROOT" | head -10
    
    echo ""
    echo "Проверка панорамы:"
    if [[ -d "$WEBROOT/pano" ]]; then
        echo "✅ Директория /pano существует"
        if [[ -f "$WEBROOT/pano/index.html" ]]; then
            echo "✅ index.html в pano найден"
        else
            echo "❌ index.html в pano отсутствует"
        fi
    else
        echo "❌ Директория /pano отсутствует"
    fi
    
    echo ""
    echo "Проверка основного index.html:"
    if [[ -f "$WEBROOT/index.html" ]]; then
        echo "✅ Основной index.html найден"
    else
        echo "❌ Основной index.html отсутствует"
    fi
    
else
    echo "❌ Директория $WEBROOT не существует!"
fi

echo ""
echo "🔍 4. ТЕСТ ЛОКАЛЬНОГО ДОСТУПА"
echo "============================="

echo "Тест HTTP запроса к localhost:"
LOCAL_RESPONSE=$(curl -s -w "%{http_code}" -m 10 "http://localhost/")
LOCAL_CODE="${LOCAL_RESPONSE: -3}"
LOCAL_BODY="${LOCAL_RESPONSE%???}"

echo "HTTP код: $LOCAL_CODE"
if [[ "$LOCAL_CODE" == "200" ]]; then
    echo "✅ Локальный доступ работает"
    echo "Размер ответа: ${#LOCAL_BODY} символов"
elif [[ "$LOCAL_CODE" == "404" ]]; then
    echo "⚠️ Локальный доступ возвращает 404 (файл не найден)"
elif [[ "$LOCAL_CODE" == "403" ]]; then
    echo "⚠️ Локальный доступ возвращает 403 (нет доступа)"
else
    echo "❌ Локальный доступ не работает"
    echo "Ответ: $LOCAL_BODY" | head -3
fi

echo ""
echo "Тест панорамы локально:"
PANO_RESPONSE=$(curl -s -w "%{http_code}" -m 10 "http://localhost/pano/")
PANO_CODE="${PANO_RESPONSE: -3}"

echo "HTTP код /pano/: $PANO_CODE"
if [[ "$PANO_CODE" == "200" ]]; then
    echo "✅ Панорама доступна локально"
else
    echo "❌ Панорама недоступна локально"
fi

echo ""
echo "🔍 5. ПРОВЕРКА ЛОГОВ"
echo "=================="

echo "Последние ошибки nginx:"
if [[ -f "/var/log/nginx/error.log" ]]; then
    echo "=== /var/log/nginx/error.log ==="
    tail -10 /var/log/nginx/error.log 2>/dev/null || echo "Не удается прочитать лог"
fi

if [[ -f "/var/log/nginx/color360_error.log" ]]; then
    echo ""
    echo "=== /var/log/nginx/color360_error.log ==="
    tail -10 /var/log/nginx/color360_error.log 2>/dev/null || echo "Не удается прочитать лог"
fi

echo ""
echo "🛠️ АВТОМАТИЧЕСКОЕ ИСПРАВЛЕНИЕ"
echo "============================="

NEED_RESTART=false

# Проверяем и исправляем nginx
if ! systemctl is-active --quiet nginx; then
    echo "🔧 Запуск nginx..."
    systemctl start nginx
    NEED_RESTART=true
fi

# Проверяем конфигурацию и исправляем если нужно
if ! nginx -t >/dev/null 2>&1; then
    echo "🔧 Ошибка конфигурации nginx, восстанавливаем базовый конфиг..."
    
    # Создаем минимальный рабочий конфиг
    cat > /etc/nginx/sites-available/color360-emergency << 'EOF'
server {
    listen 80;
    server_name color360.ru www.color360.ru _;
    
    root /var/www/color360;
    index index.html;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    location /pano {
        try_files $uri $uri/ /pano/index.html;
    }
    
    # Базовые статические файлы
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }
}
EOF
    
    # Отключаем старые конфиги и включаем аварийный
    rm -f /etc/nginx/sites-enabled/color360*
    ln -sf /etc/nginx/sites-available/color360-emergency /etc/nginx/sites-enabled/color360-emergency
    
    echo "✅ Создан аварийный конфиг"
    NEED_RESTART=true
fi

# Проверяем наличие файлов сайта
if [[ ! -d "/var/www/color360" ]]; then
    echo "🔧 Создание базовой структуры сайта..."
    mkdir -p /var/www/color360/pano
    
    # Создаем базовый index.html
    cat > /var/www/color360/index.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Color360 - Виртуальные туры</title>
</head>
<body>
    <h1>Color360</h1>
    <p>Сайт временно недоступен. Выполняется восстановление.</p>
    <p><a href="/pano/">Панорамный просмотр</a></p>
</body>
</html>
EOF
    
    # Создаем базовый index.html для панорамы
    cat > /var/www/color360/pano/index.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Панорама - Color360</title>
</head>
<body>
    <h1>Панорамный просмотр</h1>
    <p>Панорамный просмотр временно недоступен. Выполняется восстановление.</p>
</body>
</html>
EOF
    
    # Устанавливаем правильные права
    chown -R www-data:www-data /var/www/color360
    chmod -R 755 /var/www/color360
    
    echo "✅ Создана базовая структура сайта"
fi

# Перезапускаем nginx если нужно
if [[ "$NEED_RESTART" == "true" ]]; then
    echo "🔧 Перезапуск nginx..."
    systemctl restart nginx
    sleep 2
fi

echo ""
echo "🧪 ФИНАЛЬНАЯ ПРОВЕРКА ПОСЛЕ ИСПРАВЛЕНИЯ"
echo "======================================="

sleep 3

echo "1. Статус nginx:"
if systemctl is-active --quiet nginx; then
    echo "✅ Nginx работает"
else
    echo "❌ Nginx все еще не работает"
fi

echo ""
echo "2. Тест доступности:"
FINAL_RESPONSE=$(curl -s -w "%{http_code}" -m 10 "http://localhost/")
FINAL_CODE="${FINAL_RESPONSE: -3}"

if [[ "$FINAL_CODE" == "200" ]]; then
    echo "✅ Сайт доступен локально (HTTP $FINAL_CODE)"
else
    echo "❌ Сайт недоступен локально (HTTP $FINAL_CODE)"
fi

echo ""
echo "3. Тест панорамы:"
FINAL_PANO=$(curl -s -w "%{http_code}" -m 10 "http://localhost/pano/")
FINAL_PANO_CODE="${FINAL_PANO: -3}"

if [[ "$FINAL_PANO_CODE" == "200" ]]; then
    echo "✅ Панорама доступна (HTTP $FINAL_PANO_CODE)"
else
    echo "❌ Панорама недоступна (HTTP $FINAL_PANO_CODE)"
fi

echo ""
echo "🏁 ДИАГНОСТИКА ЗАВЕРШЕНА"
echo "========================"

if [[ "$FINAL_CODE" == "200" ]]; then
    echo "✅ САЙТ ВОССТАНОВЛЕН!"
    echo "Теперь должен быть доступен по адресу: http://color360.ru"
    echo "Панорама: http://color360.ru/pano/"
else
    echo "❌ САЙТ ВСЕ ЕЩЕ НЕДОСТУПЕН"
    echo ""
    echo "Дополнительные действия:"
    echo "1. Проверьте DNS настройки домена"
    echo "2. Проверьте файрвол: ufw status"
    echo "3. Проверьте процессы: ps aux | grep nginx"
    echo "4. Перезагрузите сервер: reboot"
fi

echo ""
echo "📊 Полезные команды для диагностики:"
echo "- systemctl status nginx"
echo "- nginx -t"  
echo "- tail -f /var/log/nginx/error.log"
echo "- curl -I http://localhost/"