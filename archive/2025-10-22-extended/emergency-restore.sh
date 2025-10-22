#!/bin/bash

# БЫСТРОЕ ВОССТАНОВЛЕНИЕ ДОСТУПНОСТИ САЙТА
echo "⚡ ЭКСТРЕННОЕ ВОССТАНОВЛЕНИЕ САЙТА"
echo "================================="

# Остановка всех конфликтующих процессов
echo "🛑 Остановка конфликтующих процессов..."
systemctl stop nginx 2>/dev/null
pkill -f "nginx" 2>/dev/null
sleep 2

# Очистка проблемных конфигов
echo "🧹 Очистка nginx конфигурации..."
rm -f /etc/nginx/sites-enabled/color360*
rm -f /etc/nginx/sites-enabled/default

# Создание минимального рабочего конфига
echo "📝 Создание базовой конфигурации..."
cat > /etc/nginx/sites-available/color360-basic << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    server_name color360.ru www.color360.ru _;
    
    root /var/www/html;
    index index.html index.htm;
    
    # Основные локации
    location / {
        try_files $uri $uri/ @fallback;
    }
    
    location /pano {
        alias /var/www/html/pano;
        try_files $uri $uri/ /pano/index.html;
    }
    
    location /pano/ {
        alias /var/www/html/pano/;
        try_files $uri $uri/ /pano/index.html;
    }
    
    # Статические файлы
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|webp)$ {
        expires 1h;
        add_header Cache-Control "public";
        try_files $uri =404;
    }
    
    # Fallback для основного сайта
    location @fallback {
        return 200 '<!DOCTYPE html>
<html><head><title>Color360</title><meta charset="utf-8"></head>
<body style="font-family:Arial,sans-serif;text-align:center;padding:50px;">
<h1>🌐 Color360</h1>
<p>Сайт временно восстанавливается...</p>
<p><a href="/pano/" style="color:blue;">→ Перейти к панорамному просмотру</a></p>
<hr style="margin:30px 0;">
<small>Сервис будет полностью восстановлен в ближайшее время</small>
</body></html>';
        add_header Content-Type text/html;
    }
    
    # Базовая безопасность
    location ~ /\. {
        deny all;
    }
}
EOF

# Активация конфига
ln -sf /etc/nginx/sites-available/color360-basic /etc/nginx/sites-enabled/color360-basic

# Создание базовой структуры сайта
echo "📁 Создание файловой структуры..."
mkdir -p /var/www/html/pano

# Создание временного index.html для панорамы
cat > /var/www/html/pano/index.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Панорама - Color360</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            text-align: center;
            padding: 50px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            margin: 0;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
        }
        .container {
            background: rgba(255,255,255,0.1);
            padding: 40px;
            border-radius: 20px;
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
        }
        h1 {
            font-size: 2.5em;
            margin-bottom: 20px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.5);
        }
        p {
            font-size: 1.2em;
            margin: 15px 0;
            opacity: 0.9;
        }
        .status {
            background: rgba(255,255,255,0.2);
            padding: 15px;
            border-radius: 10px;
            margin: 20px 0;
            font-family: monospace;
        }
        a {
            color: #fff;
            text-decoration: none;
            background: rgba(255,255,255,0.2);
            padding: 10px 20px;
            border-radius: 25px;
            display: inline-block;
            margin: 10px;
            transition: all 0.3s;
        }
        a:hover {
            background: rgba(255,255,255,0.3);
            transform: translateY(-2px);
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎭 Панорамный просмотр</h1>
        <p>Система панорамного просмотра временно недоступна</p>
        
        <div class="status">
            <strong>Статус:</strong> Выполняется восстановление сервиса<br>
            <strong>Время:</strong> <span id="time"></span>
        </div>
        
        <p>Мы работаем над восстановлением функциональности</p>
        
        <a href="/">← Вернуться на главную</a>
        <a href="#" onclick="location.reload()">🔄 Обновить страницу</a>
    </div>
    
    <script>
        function updateTime() {
            document.getElementById('time').textContent = new Date().toLocaleString('ru-RU');
        }
        updateTime();
        setInterval(updateTime, 1000);
        
        // Автообновление каждые 30 секунд
        setTimeout(() => location.reload(), 30000);
    </script>
</body>
</html>
EOF

# Создание основного index.html
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Color360 - Виртуальные туры и панорамы</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
        }
        .container {
            text-align: center;
            background: rgba(255,255,255,0.1);
            padding: 60px;
            border-radius: 20px;
            backdrop-filter: blur(15px);
            box-shadow: 0 15px 35px rgba(0,0,0,0.3);
            max-width: 600px;
        }
        h1 {
            font-size: 3em;
            margin-bottom: 20px;
            text-shadow: 2px 2px 8px rgba(0,0,0,0.5);
        }
        .subtitle {
            font-size: 1.3em;
            opacity: 0.9;
            margin-bottom: 40px;
        }
        .service-status {
            background: rgba(255,193,7,0.2);
            border: 1px solid rgba(255,193,7,0.5);
            padding: 20px;
            border-radius: 15px;
            margin: 30px 0;
        }
        .nav-buttons {
            margin: 40px 0;
        }
        .btn {
            display: inline-block;
            background: rgba(255,255,255,0.2);
            color: white;
            text-decoration: none;
            padding: 15px 30px;
            margin: 10px;
            border-radius: 30px;
            font-size: 1.1em;
            font-weight: 500;
            transition: all 0.3s ease;
            border: 2px solid rgba(255,255,255,0.3);
        }
        .btn:hover {
            background: rgba(255,255,255,0.3);
            transform: translateY(-3px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.3);
        }
        .btn.primary {
            background: rgba(0,123,255,0.3);
            border-color: rgba(0,123,255,0.5);
        }
        .footer {
            margin-top: 40px;
            opacity: 0.7;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌐 Color360</h1>
        <div class="subtitle">Виртуальные туры и панорамная фотография</div>
        
        <div class="service-status">
            <h3>⚠️ Уведомление о техработах</h3>
            <p>В данный момент выполняется плановое обслуживание системы.<br>
            Сервис будет полностью восстановлен в ближайшее время.</p>
        </div>
        
        <div class="nav-buttons">
            <a href="/pano/" class="btn primary">🎭 Панорамный просмотр</a>
            <a href="/profile.html" class="btn">👤 Профиль</a>
            <a href="/admin-dashboard.html" class="btn">⚙️ Управление</a>
        </div>
        
        <div class="footer">
            <p>© 2024 Color360 | Система восстанавливается автоматически</p>
            <p><small>Время: <span id="current-time"></span></small></p>
        </div>
    </div>
    
    <script>
        function updateTime() {
            document.getElementById('current-time').textContent = 
                new Date().toLocaleString('ru-RU');
        }
        updateTime();
        setInterval(updateTime, 1000);
        
        // Проверяем восстановление каждые 60 секунд
        setInterval(() => {
            fetch('/assets/app.js')
                .then(() => location.reload())
                .catch(() => {});
        }, 60000);
    </script>
</body>
</html>
EOF

# Установка прав
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# Тест конфигурации
echo "🔍 Проверка конфигурации nginx..."
if nginx -t; then
    echo "✅ Конфигурация корректна"
else
    echo "❌ Ошибка конфигурации!"
    exit 1
fi

# Запуск nginx
echo "🚀 Запуск nginx..."
systemctl start nginx
systemctl enable nginx

# Ожидание запуска
sleep 3

echo "🧪 Проверка доступности..."

# Тест основного сайта
MAIN_TEST=$(curl -s -w "%{http_code}" -m 10 "http://localhost/")
MAIN_CODE="${MAIN_TEST: -3}"

# Тест панорамы  
PANO_TEST=$(curl -s -w "%{http_code}" -m 10 "http://localhost/pano/")
PANO_CODE="${PANO_TEST: -3}"

echo ""
echo "📊 РЕЗУЛЬТАТЫ ВОССТАНОВЛЕНИЯ"
echo "============================"

echo "Статус nginx: $(systemctl is-active nginx)"
echo "Основной сайт: HTTP $MAIN_CODE"
echo "Панорама: HTTP $PANO_CODE"

if [[ "$MAIN_CODE" == "200" ]]; then
    echo ""
    echo "✅ УСПЕХ! Базовая доступность восстановлена"
    echo ""
    echo "🌐 Сайт доступен по адресу:"
    echo "   http://color360.ru/"
    echo "   http://color360.ru/pano/"
    echo ""
    echo "⚡ Для полного восстановления выполните:"
    echo "   bash restore-from-github.sh"
    echo ""
    echo "📋 Мониторинг:"
    echo "   tail -f /var/log/nginx/access.log"
    echo "   tail -f /var/log/nginx/error.log"
else
    echo ""
    echo "❌ Проблема с восстановлением!"
    echo "Дополнительная диагностика:"
    echo "- systemctl status nginx"
    echo "- journalctl -u nginx -f"
    echo "- netstat -tuln | grep :80"
fi