# 🎯 Color360 с LaMa AI - Полная Установка 

> **Профессиональный редактор панорам с AI-удалением объектов**

## 🚀 Быстрый Старт

### 🔥 Метод 1: Полная Автоустановка (Рекомендуется)

```bash
# Загрузка и запуск автоустановщика
wget https://raw.githubusercontent.com/RadaRish/color360/main/deploy-clean-install.sh
chmod +x deploy-clean-install.sh
sudo bash deploy-clean-install.sh
```

**Что делает скрипт:**
- ✅ Полная очистка старых версий  
- ✅ Установка Node.js 20.19.3 + Python 3.10
- ✅ Клонирование свежего проекта
- ✅ Настройка LaMa AI окружения
- ✅ Создание systemd сервисов
- ✅ Настройка Nginx
- ✅ Автозапуск и тестирование

### 🐳 Метод 2: Docker Production

```bash
# Клонирование
git clone https://github.com/RadaRish/color360.git
cd color360

# Создание data директорий
mkdir -p data/{temp,avatars,news_images,pano} logs/{supervisor,nginx}

# Сборка и запуск
docker-compose -f docker-compose.production.yml up -d --build

# Проверка
docker-compose -f docker-compose.production.yml logs -f
```

## 🛠️ Ручная Установка

### Шаг 1: Подготовка системы
```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y curl wget git build-essential python3 python3-pip python3-venv nginx

# Установка Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
```

### Шаг 2: Клонирование проекта
```bash
sudo mkdir -p /var/www/color360
cd /var/www/color360
sudo git clone https://github.com/RadaRish/color360.git .
sudo npm install
```

### Шаг 3: Настройка LaMa AI
```bash
cd /var/www/color360/lama

# Создание Python окружения
sudo python3 -m venv lama_env
sudo ./lama_env/bin/activate

# Установка зависимостей
sudo ./lama_env/bin/pip install --extra-index-url https://download.pytorch.org/whl/cpu \
    torch==2.1.0+cpu torchvision==0.16.0+cpu torchaudio==2.1.0+cpu
sudo ./lama_env/bin/pip install fastapi uvicorn lama-cleaner pillow opencv-python-headless numpy psutil
```

### Шаг 4: Создание systemd сервисов
```bash
# LaMa сервис
sudo tee /etc/systemd/system/color360-lama.service > /dev/null << 'EOF'
[Unit]
Description=Color360 LaMa AI Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/color360/lama
Environment=PORT=5002
ExecStart=/var/www/color360/lama/lama_env/bin/python service.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Основное приложение
sudo tee /etc/systemd/system/color360-app.service > /dev/null << 'EOF'
[Unit]
Description=Color360 Main Application
After=color360-lama.service

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/color360
Environment=NODE_ENV=production
Environment=PORT=3000
Environment=LAMA_ENABLED=true
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

### Шаг 5: Настройка Nginx
```bash
sudo tee /etc/nginx/sites-available/color360 > /dev/null << 'EOF'
server {
    listen 80;
    server_name _;
    client_max_body_size 50M;
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    
    location /lama/ {
        proxy_pass http://127.0.0.1:5002/;
        proxy_read_timeout 300s;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/color360 /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
```

### Шаг 6: Запуск
```bash
sudo systemctl daemon-reload
sudo systemctl enable color360-lama color360-app nginx
sudo systemctl start color360-lama
sudo systemctl start color360-app  
sudo systemctl restart nginx
```

## 🔍 Диагностика и Ремонт

```bash
# Скачивание диагностического инструмента
wget https://raw.githubusercontent.com/RadaRish/color360/main/diagnostic-repair.sh
chmod +x diagnostic-repair.sh
sudo bash diagnostic-repair.sh
```

**Возможности:**
- 🔍 Полная диагностика системы
- 🔧 Быстрое восстановление сервисов  
- 📋 Просмотр логов
- 🎯 Переустановка только LaMa

## 📊 Мониторинг

### Проверка статуса
```bash
# Статус сервисов
sudo systemctl status color360-app color360-lama nginx

# Проверка портов
sudo netstat -tlnp | grep -E ":3000|:5002|:80"

# Проверка API
curl http://localhost:5002/health
curl http://localhost:3000
```

### Логи
```bash
# Логи в реальном времени
sudo journalctl -u color360-lama -f
sudo journalctl -u color360-app -f

# Логи Nginx
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

## 🎯 Использование LaMa AI

### API Endpoints

**Проверка здоровья:**
```bash
curl http://your-server/lama/health
```

**Удаление объектов:**
```bash
curl -X POST http://your-server/lama/inpaint \
  -F "image=@photo.jpg" \
  -F "mask=@mask.png"
```

### Через веб-интерфейс
1. Откройте http://your-server
2. Загрузите панораму  
3. Выберите инструмент удаления
4. Нарисуйте маску на объекте
5. Нажмите "Удалить объект"

## 🔒 Безопасность

### Админ панель
- **URL:** http://your-server/admin
- **Email:** admin@color360.online  
- **Пароль:** Color360Admin2025!

### Настройки безопасности
```bash
# Изменение админ пароля
sudo nano /var/www/color360/server.js
# Найти adminPassword и изменить

# Firewall
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp  
sudo ufw enable
```

## 🚀 Производительность

### Системные требования
- **Минимум:** 2 CPU, 4GB RAM, 10GB диск
- **Рекомендуется:** 4 CPU, 8GB RAM, 20GB диск
- **Оптимально:** 8 CPU, 16GB RAM, 50GB SSD

### Оптимизация
```bash
# Увеличение лимитов файлов
echo "fs.file-max = 65536" >> /etc/sysctl.conf
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

# Применение
sudo sysctl -p
```

## 🆘 Решение проблем

### Частые проблемы

**1. LaMa не запускается**
```bash
# Переустановка LaMa окружения  
cd /var/www/color360/lama
sudo rm -rf lama_env
sudo python3 -m venv lama_env
# Повторить установку зависимостей
```

**2. Порт занят**
```bash
# Освобождение портов
sudo fuser -k 3000/tcp 5002/tcp
sudo systemctl restart color360-lama color360-app
```

**3. Nginx ошибки**
```bash
# Проверка конфигурации
sudo nginx -t
sudo systemctl reload nginx
```

**4. Нет памяти для AI**
```bash
# Добавление swap
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### Восстановление из бэкапа
```bash
# При проблемах - полная переустановка
sudo bash deploy-clean-install.sh
```

## 📞 Поддержка

- **GitHub:** https://github.com/RadaRish/color360
- **Issues:** https://github.com/RadaRish/color360/issues
- **Документация:** https://github.com/RadaRish/color360/wiki

## 🎉 Готово!

После успешной установки:
- 🌐 **Сайт:** http://your-server
- 🛠️ **Админ:** http://your-server/admin  
- 🎯 **LaMa API:** http://your-server/lama/health

**Профессиональное AI-удаление объектов готово к работе!** 🚀