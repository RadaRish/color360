#!/bin/bash

################################################################################
# Скрипт автоматической установки Color360 (PanoBro) на VPS TimeWeb
# IP: 72.56.82.203
# Дата: 16 ноября 2025
################################################################################

set -e  # Остановка при ошибке

echo "🚀 Начинаем установку PanoBro на VPS TimeWeb..."
echo "================================================="

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Функция логирования
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    log_error "Запустите скрипт с правами root: sudo bash deploy-timeweb.sh"
    exit 1
fi

# 1. Обновление системы
log_info "Обновление системы..."
apt-get update -y
apt-get upgrade -y

# 2. Установка необходимых пакетов
log_info "Установка базовых пакетов..."
apt-get install -y \
    git \
    curl \
    wget \
    unzip \
    nano \
    htop \
    build-essential \
    software-properties-common \
    ufw \
    fail2ban

# 3. Установка Node.js (LTS версия)
log_info "Установка Node.js..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

# Проверка версий
node --version
npm --version

# 4. Установка PM2 (менеджер процессов)
log_info "Установка PM2..."
npm install -g pm2

# 5. Установка Nginx
log_info "Установка Nginx..."
apt-get install -y nginx

# 6. Создание директории для проекта
log_info "Создание директории проекта..."
PROJECT_DIR="/var/www/panobro"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# 7. Клонирование репозитория
log_info "Клонирование репозитория с GitHub..."
if [ -d ".git" ]; then
    log_warn "Репозиторий уже существует, выполняем git pull..."
    git pull origin main
else
    git clone https://github.com/RadaRish/color360.git .
fi

# 8. Установка зависимостей (если есть package.json в корне)
if [ -f "package.json" ]; then
    log_info "Установка зависимостей проекта..."
    npm install --production
fi

# 9. Настройка прав доступа
log_info "Настройка прав доступа..."
chown -R www-data:www-data $PROJECT_DIR
chmod -R 755 $PROJECT_DIR

# 10. Настройка Nginx
log_info "Настройка Nginx..."
cat > /etc/nginx/sites-available/panobro << 'NGINX_EOF'
server {
    listen 80;
    listen [::]:80;
    
    server_name 72.56.82.203;
    
    root /var/www/panobro;
    index index.html;
    
    # Логи
    access_log /var/log/nginx/panobro-access.log;
    error_log /var/log/nginx/panobro-error.log;
    
    # Основной location для главной страницы
    location / {
        try_files $uri $uri/ /index.html;
    }
    
    # Location для редактора панорам
    location /pano/ {
        alias /var/www/panobro/pano/;
        try_files $uri $uri/ /pano/index.html;
        
        # CORS заголовки для локальных файлов
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods 'GET, POST, OPTIONS';
        add_header Access-Control-Allow-Headers 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
    }
    
    # Кеширование статических файлов
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|webp|mp4|webm)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Безопасность
    location ~ /\. {
        deny all;
    }
    
    # Размер загружаемых файлов (для панорам)
    client_max_body_size 500M;
}
NGINX_EOF

# Создание символической ссылки
ln -sf /etc/nginx/sites-available/panobro /etc/nginx/sites-enabled/

# Удаление дефолтной конфигурации
rm -f /etc/nginx/sites-enabled/default

# Проверка конфигурации Nginx
log_info "Проверка конфигурации Nginx..."
nginx -t

# Перезапуск Nginx
log_info "Перезапуск Nginx..."
systemctl restart nginx
systemctl enable nginx

# 11. Настройка файрвола (UFW)
log_info "Настройка файрвола..."
ufw --force enable
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS (на будущее)
ufw status

# 12. Настройка Fail2Ban (защита от брутфорса)
log_info "Настройка Fail2Ban..."
systemctl enable fail2ban
systemctl start fail2ban

# 13. Создание скрипта для обновления проекта
log_info "Создание скрипта обновления..."
cat > /usr/local/bin/update-panobro << 'UPDATE_EOF'
#!/bin/bash
cd /var/www/panobro
echo "🔄 Обновление PanoBro..."
git pull origin main
chown -R www-data:www-data /var/www/panobro
systemctl reload nginx
echo "✅ Обновление завершено!"
UPDATE_EOF

chmod +x /usr/local/bin/update-panobro

# 14. Оптимизация системы
log_info "Оптимизация системных параметров..."

# Увеличение лимитов для файлов
cat >> /etc/security/limits.conf << EOF
* soft nofile 65536
* hard nofile 65536
EOF

# Настройка swap (если нет)
if [ ! -f /swapfile ]; then
    log_info "Создание swap файла (2GB)..."
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# 15. Создание информационного файла
cat > $PROJECT_DIR/SERVER_INFO.txt << EOF
===========================================
PanoBro - Информация о сервере
===========================================

IP адрес: 72.56.82.203
Дата установки: $(date)

Директория проекта: /var/www/panobro
Конфигурация Nginx: /etc/nginx/sites-available/panobro

Полезные команды:
- Обновить проект: sudo update-panobro
- Перезапустить Nginx: sudo systemctl restart nginx
- Просмотр логов Nginx: sudo tail -f /var/log/nginx/panobro-access.log
- Статус файрвола: sudo ufw status

Доступ к сайту:
- Главная страница: http://72.56.82.203/
- Редактор панорам: http://72.56.82.203/pano/

Git репозиторий: https://github.com/RadaRish/color360
===========================================
EOF

# 16. Финальная проверка
log_info "Проверка статуса сервисов..."
systemctl status nginx --no-pager
ufw status

echo ""
echo "================================================="
log_info "✅ Установка завершена успешно!"
echo "================================================="
echo ""
echo "🌐 Ваш сайт доступен по адресу:"
echo "   Главная: http://72.56.82.203/"
echo "   Редактор: http://72.56.82.203/pano/"
echo ""
echo "📋 Полезные команды:"
echo "   - Обновить проект: sudo update-panobro"
echo "   - Логи Nginx: sudo tail -f /var/log/nginx/panobro-access.log"
echo "   - Перезапуск Nginx: sudo systemctl restart nginx"
echo ""
echo "📁 Информация о сервере: $PROJECT_DIR/SERVER_INFO.txt"
echo ""
log_warn "⚠️  Не забудьте настроить SSL сертификат (Let's Encrypt)!"
echo ""
