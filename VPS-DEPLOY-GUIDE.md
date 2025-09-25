# Деплой Color360 на VPS - Пошаговая инструкция

## 🚀 Быстрый деплой

### 1. Подключение к VPS
```bash
ssh root@your-server-ip
# или
ssh your-user@your-server-ip
```

### 2. Подготовка системы
```bash
# Обновляем систему
apt update && apt upgrade -y

# Устанавливаем необходимые пакеты
apt install -y curl git nginx nodejs npm

# Проверяем версии
node --version  # должно быть >= 16
npm --version
```

### 3. Клонирование проекта
```bash
# Переходим в директорию веб-сервера
cd /var/www

# Клонируем репозиторий
git clone https://github.com/your-username/color360.git
cd color360

# Делаем скрипты исполняемыми
chmod +x *.sh
```

### 4. Быстрый деплой
```bash
# Запускаем улучшенный скрипт деплоя
./deploy-vps-fixed.sh
```

## 🔧 Ручная настройка (если нужно)

### 1. Установка зависимостей
```bash
cd /var/www/color360
npm install --production
```

### 2. Настройка systemd сервиса
```bash
# Создаем сервисный файл
sudo tee /etc/systemd/system/color360-app.service > /dev/null << 'EOF'
[Unit]
Description=Color360 Main Application
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/var/www/color360
Environment=NODE_ENV=production
Environment=SD_DISABLED=true
Environment=PORT=3000
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=color360-app

[Install]
WantedBy=multi-user.target
EOF

# Перезагружаем systemd и запускаем сервис
sudo systemctl daemon-reload
sudo systemctl enable color360-app
sudo systemctl start color360-app
```

### 3. Настройка Nginx (опционально)
```bash
# Создаем конфигурацию Nginx
sudo tee /etc/nginx/sites-available/color360 > /dev/null << 'EOF'
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

# Активируем сайт
sudo ln -s /etc/nginx/sites-available/color360 /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

## 📊 Мониторинг и управление

### Проверка статуса
```bash
# Проверка сервиса
sudo systemctl status color360-app

# Просмотр логов
sudo journalctl -u color360-app -f

# Быстрая диагностика
./check-vps-status.sh
```

### Управление сервисом
```bash
# Перезапуск
./restart-vps.sh

# Или вручную
sudo systemctl restart color360-app

# Остановка
sudo systemctl stop color360-app

# Запуск
sudo systemctl start color360-app
```

### Мониторинг в реальном времени
```bash
# Запуск мониторинга
./monitor-vps.sh
```

### Обновление приложения
```bash
cd /var/www/color360
git pull origin main
npm install --production
sudo systemctl restart color360-app
```

## 🛠️ Диагностика проблем

### 1. Сервис не запускается
```bash
# Проверяем логи
sudo journalctl -u color360-app --no-pager -n 50

# Проверяем права доступа
ls -la /var/www/color360/

# Проверяем порт
netstat -tlnp | grep :3000
```

### 2. Ошибки с Node.js
```bash
# Проверяем версию Node.js
node --version

# Переустанавливаем зависимости
cd /var/www/color360
rm -rf node_modules package-lock.json
npm install --production
```

### 3. Проблемы с памятью
```bash
# Проверяем использование памяти
free -h
htop

# Увеличиваем swap если нужно
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

## 🔐 Безопасность

### Настройка файрвола
```bash
# UFW (Ubuntu)
sudo ufw enable
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'
sudo ufw allow 3000
```

### SSL/HTTPS (с Let's Encrypt)
```bash
# Устанавливаем Certbot
sudo apt install certbot python3-certbot-nginx

# Получаем сертификат
sudo certbot --nginx -d your-domain.com
```

## 📝 Важные замечания

1. **Stable Diffusion отключен**: В production режиме SD сервис отключен (SD_DISABLED=true)
2. **Права доступа**: Сервис запускается под пользователем www-data
3. **Логирование**: Все логи доступны через journalctl
4. **Автозапуск**: Сервис автоматически запускается при загрузке системы
5. **Перезапуск**: Сервис автоматически перезапускается при ошибках

## 🚨 Если что-то идет не так

1. Запустите диагностику: `./check-vps-status.sh`
2. Проверьте логи: `sudo journalctl -u color360-app -f`
3. Перезапустите сервис: `./restart-vps.sh`
4. Мониторьте в реальном времени: `./monitor-vps.sh`

## 📞 Полезные команды

```bash
# Полная переустановка сервиса
sudo systemctl stop color360-app
sudo systemctl disable color360-app
sudo rm /etc/systemd/system/color360-app.service
./deploy-vps-fixed.sh

# Очистка логов
sudo journalctl --vacuum-time=7d

# Проверка дискового пространства
df -h
du -sh /var/www/color360/*
```