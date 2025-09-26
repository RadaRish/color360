# 🎯 LaMa AI Setup Guide для Color360

Полное руководство по настройке профессионального AI удаления объектов через LaMa на VPS с 2GB RAM.

## 🚀 Быстрый старт

### Автоматическая установка (Рекомендуется)

```bash
# 1. Скачать скрипт развертывания
wget https://raw.githubusercontent.com/RadaRish/color360/main/deploy-lama-vps.sh

# 2. Сделать исполняемым
chmod +x deploy-lama-vps.sh

# 3. Запустить с правами root
sudo ./deploy-lama-vps.sh
```

### Быстрое обновление

```bash
# Обновление без переустановки зависимостей
sudo ./quick-update-lama.sh
```

## 📋 Системные требования

- **ОС**: Ubuntu 20.04+ / Debian 11+
- **RAM**: 2GB минимум (рекомендуется 4GB)
- **CPU**: 2+ cores
- **Диск**: 10GB свободного места
- **Сеть**: Стабильное интернет соединение

## 🏗️ Архитектура решения

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Nginx         │    │   Node.js App    │    │   LaMa Service  │
│   Reverse Proxy │────▶│   (Port 3000)    │────▶│   (Port 5002)   │
│   (Port 80)     │    │   Express Server │    │   Python/FastAPI│
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Systemd Services                             │
│  color360-app.service     color360-lama.service                │
└─────────────────────────────────────────────────────────────────┘
```

## 🔧 Ручная установка

### 1. Подготовка системы

```bash
# Обновление системы
sudo apt update && sudo apt upgrade -y

# Установка базовых зависимостей
sudo apt install -y curl wget git build-essential python3 python3-pip python3-venv nginx
```

### 2. Установка Node.js через NVM

```bash
# Установка NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc

# Установка Node.js 20.19.3
nvm install 20.19.3
nvm use 20.19.3
nvm alias default 20.19.3

# Создание символических ссылок для systemd
sudo ln -sf ~/.nvm/versions/node/v20.19.3/bin/node /usr/local/bin/node
sudo ln -sf ~/.nvm/versions/node/v20.19.3/bin/npm /usr/local/bin/npm
```

### 3. Клонирование и настройка проекта

```bash
# Создание рабочей директории
sudo mkdir -p /var/www/color360
cd /var/www/color360

# Клонирование репозитория
sudo git clone https://github.com/RadaRish/color360.git .
sudo chown -R $USER:$USER /var/www/color360

# Установка Node.js зависимостей
npm install
```

### 4. Настройка LaMa Python окружения

```bash
cd /var/www/color360/sd

# Создание виртуального окружения
python3 -m venv lama_env
source lama_env/bin/activate

# Обновление pip и установка зависимостей
pip install --upgrade pip
pip install -r requirements.txt

# Тестирование LaMa
python -c "from lama_cleaner.model_manager import ModelManager; print('LaMa OK')"

deactivate
```

### 5. Настройка systemd сервисов

#### Основное приложение

```bash
sudo cat > /etc/systemd/system/color360-app.service << 'EOF'
[Unit]
Description=Color360 Main Application with LaMa Integration
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/color360
Environment=NODE_ENV=production
Environment=LAMA_ENABLED=true
Environment=LAMA_PORT=5002
Environment=PORT=3000
ExecStart=/usr/local/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=color360-app

[Install]
WantedBy=multi-user.target
EOF
```

#### LaMa AI сервис

```bash
sudo cat > /etc/systemd/system/color360-lama.service << 'EOF'
[Unit]
Description=Color360 LaMa Inpainting Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/color360/sd
Environment=PYTHONUNBUFFERED=1
Environment=PORT=5002
Environment=HOST=127.0.0.1
ExecStart=/var/www/color360/sd/lama_env/bin/python lama_service.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=color360-lama

[Install]
WantedBy=multi-user.target
EOF
```

### 6. Настройка Nginx

```bash
sudo cat > /etc/nginx/sites-available/color360 << 'EOF'
server {
    listen 80;
    server_name _;
    
    client_max_body_size 50M;
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }
    
    location /lama/ {
        proxy_pass http://127.0.0.1:5002/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}
EOF

# Активация сайта
sudo ln -sf /etc/nginx/sites-available/color360 /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
```

### 7. Запуск сервисов

```bash
# Перезагрузка systemd
sudo systemctl daemon-reload

# Включение автозапуска
sudo systemctl enable color360-app color360-lama nginx

# Запуск сервисов
sudo systemctl start color360-lama  # Сначала LaMa
sleep 5
sudo systemctl start color360-app   # Потом основное приложение
sudo systemctl restart nginx
```

## ✅ Проверка работы

### Проверка статуса сервисов

```bash
# Статус всех сервисов
sudo systemctl status color360-app color360-lama nginx

# Проверка портов
sudo netstat -tuln | grep -E ":(3000|5002|80)"
```

### Тестирование API

```bash
# Проверка основного приложения
curl http://localhost:3000

# Проверка LaMa сервиса
curl http://localhost:5002/health

# Проверка через Nginx
curl http://localhost/api/lama-health
```

### Проверка логов

```bash
# Логи основного приложения
sudo journalctl -u color360-app -f

# Логи LaMa сервиса
sudo journalctl -u color360-lama -f

# Логи Nginx
sudo tail -f /var/log/nginx/access.log
```

## 🛠️ Управление и обслуживание

### Перезапуск сервисов

```bash
# Перезапуск всех сервисов
sudo systemctl restart color360-lama color360-app nginx

# Перезапуск только LaMa (при проблемах с AI)
sudo systemctl restart color360-lama
```

### Обновление кода

```bash
cd /var/www/color360

# Быстрое обновление
sudo ./quick-update-lama.sh

# Ручное обновление
sudo systemctl stop color360-app color360-lama
sudo git pull origin main
sudo npm install  # Если изменился package.json
sudo systemctl start color360-lama color360-app
```

### Мониторинг ресурсов

```bash
# Использование памяти
free -h

# Процессы Color360
ps aux | grep -E "(node|python.*lama)"

# Использование диска
df -h

# Системная нагрузка
htop
```

## 🚨 Устранение неполадок

### LaMa сервис не запускается

```bash
# Проверка логов
sudo journalctl -u color360-lama --no-pager -l

# Проверка Python окружения
cd /var/www/color360/sd
source lama_env/bin/activate
python -c "from lama_cleaner.model_manager import ModelManager; print('OK')"
deactivate

# Переустановка Python зависимостей
source lama_env/bin/activate
pip install --upgrade pip
pip install -r requirements.txt --force-reinstall
deactivate
```

### Основное приложение не запускается

```bash
# Проверка логов
sudo journalctl -u color360-app --no-pager -l

# Проверка Node.js
/usr/local/bin/node --version

# Тестирование запуска
cd /var/www/color360
/usr/local/bin/node server.js
```

### Проблемы с памятью

```bash
# Проверка использования памяти
sudo systemctl status color360-lama color360-app
free -h

# Оптимизация - остановка неиспользуемых сервисов
sudo systemctl stop apache2 mysql  # Если установлены

# Настройка swap (если нет)
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### Nginx ошибки

```bash
# Проверка конфигурации
sudo nginx -t

# Логи ошибок
sudo tail -f /var/log/nginx/error.log

# Перезагрузка конфигурации
sudo systemctl reload nginx
```

## 🔐 Безопасность

### Базовые настройки

```bash
# Настройка firewall
sudo ufw allow ssh
sudo ufw allow 80
sudo ufw allow 443
sudo ufw --force enable

# Обновление системы
sudo apt update && sudo apt upgrade -y
sudo apt autoremove -y
```

### SSL сертификат (Let's Encrypt)

```bash
# Установка Certbot
sudo apt install certbot python3-certbot-nginx -y

# Получение сертификата (замените domain.com на ваш домен)
sudo certbot --nginx -d domain.com

# Автоматическое обновление
sudo crontab -e
# Добавить: 0 12 * * * /usr/bin/certbot renew --quiet
```

## 📊 Производительность

### Оптимизация для 2GB RAM

LaMa сервис оптимизирован для работы с минимальными ресурсами:

- **CPU версия PyTorch** - не требует GPU
- **Модель загружается по требованию** - экономит память
- **Автоматический fallback на OpenCV** - при нехватке ресурсов
- **Умное управление памятью** - освобождение после обработки

### Мониторинг производительности

```bash
# Создание скрипта мониторинга
cat > /usr/local/bin/color360-status << 'EOF'
#!/bin/bash
echo "=== Color360 Status ==="
systemctl is-active color360-app color360-lama nginx
echo "=== Memory Usage ==="
free -h
echo "=== Disk Usage ==="
df -h /
echo "=== Process Info ==="
ps aux | grep -E "(node|python.*lama)" | grep -v grep
EOF

chmod +x /usr/local/bin/color360-status

# Использование
color360-status
```

## 📞 Поддержка

- **GitHub Issues**: https://github.com/RadaRish/color360/issues
- **Документация**: README.md в репозитории
- **Логи для отладки**: `sudo journalctl -u color360-lama -u color360-app --since "1 hour ago"`

## 🎯 Особенности LaMa интеграции

- ✅ **Профессиональное качество** - удаление объектов без артефактов
- ✅ **Ресурсоэффективность** - работает на 2GB RAM
- ✅ **Автоматический fallback** - OpenCV при недоступности LaMa
- ✅ **Обратная совместимость** - поддержка старых SD API
- ✅ **Готовность к production** - systemd сервисы и мониторинг

🎉 **Color360 с LaMa AI готов к профессиональному удалению объектов из панорам!**