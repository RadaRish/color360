#!/bin/bash
# Color360 - Полная установка с нуля на VPS
# Домен: color360.ru
# Версия: 1.0 - Простая установка без резервных копий

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

echo "🔥 Color360 - Полная установка на VPS"
echo "======================================"
echo "Домен: color360.ru"
echo "Время: $(date)"
echo ""

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    log_error "Запустите с правами root: sudo bash $0"
    exit 1
fi

# Конфигурация
DOMAIN="color360.ru"
PROJECT_DIR="/var/www/color360"
GIT_REPO="https://github.com/RadaRish/color360.git"
APP_USER="color360"

log_info "Начинаем полную установку..."

# 1. ПОЛНАЯ ОЧИСТКА СИСТЕМЫ
log_info "🧹 Полная очистка предыдущих установок..."

# Останавливаем все сервисы
systemctl stop color360-app color360-sd color360-lama nginx 2>/dev/null || true
systemctl disable color360-app color360-sd color360-lama 2>/dev/null || true

# Убиваем все процессы
pkill -9 -f "color360\|server.js\|lama.*service" 2>/dev/null || true
fuser -k 3000/tcp 5002/tcp 80/tcp 443/tcp 2>/dev/null || true

# Удаляем systemd сервисы
rm -f /etc/systemd/system/color360-*.service
systemctl daemon-reload

# Удаляем директорию проекта
rm -rf "$PROJECT_DIR"

# Удаляем nginx конфигурации
rm -f /etc/nginx/sites-enabled/color360* /etc/nginx/sites-available/color360*
rm -f /etc/nginx/conf.d/color360*

# Удаляем SSL сертификаты
rm -rf /etc/letsencrypt/live/color360.ru /etc/letsencrypt/archive/color360.ru /etc/letsencrypt/renewal/color360.ru.conf 2>/dev/null || true

# Удаляем пользователя
userdel -r "$APP_USER" 2>/dev/null || true

log_success "Система полностью очищена"

# 2. ОБНОВЛЕНИЕ СИСТЕМЫ
log_info "📦 Обновление системы..."
apt update -qq && apt upgrade -y -qq

# 3. УСТАНОВКА БАЗОВЫХ ПАКЕТОВ
log_info "📦 Установка базовых пакетов..."
apt install -y curl wget git build-essential python3 python3-pip python3-venv nginx certbot python3-certbot-nginx ufw htop unzip

# 4. УСТАНОВКА NODE.JS
log_info "🟢 Установка Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Проверяем версии
node_version=$(node --version)
npm_version=$(npm --version)
log_success "Node.js $node_version, npm $npm_version установлены"

# 5. СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ
log_info "👤 Создание пользователя $APP_USER..."
groupadd -r "$APP_USER" 2>/dev/null || true
useradd -r -s /bin/bash -g "$APP_USER" -d "/home/$APP_USER" "$APP_USER"
mkdir -p "/home/$APP_USER"
chown "$APP_USER:$APP_USER" "/home/$APP_USER"

# 6. КЛОНИРОВАНИЕ ПРОЕКТА
log_info "📥 Клонирование Color360 с GitHub..."
git clone "$GIT_REPO" "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Получаем информацию о коммите
commit_hash=$(git rev-parse --short HEAD)
commit_msg=$(git log -1 --pretty=format:"%s")
log_success "Клонирован коммит $commit_hash: $commit_msg"

# Устанавливаем права
chown -R "$APP_USER:$APP_USER" "$PROJECT_DIR"

# 7. УСТАНОВКА NODE.JS ЗАВИСИМОСТЕЙ
log_info "📦 Установка Node.js зависимостей..."
sudo -u "$APP_USER" npm install --production
log_success "Node.js зависимости установлены"

# 8. УСТАНОВКА PYTHON ЗАВИСИМОСТЕЙ (AI)
if [ -f "sd/requirements.txt" ]; then
    log_info "🐍 Установка Python AI зависимостей..."
    sudo -u "$APP_USER" python3 -m venv sd_env
    sudo -u "$APP_USER" bash -c "source sd_env/bin/activate && pip install --upgrade pip && pip install -r sd/requirements.txt"
    log_success "Python AI зависимости установлены"
fi

# 9. СОЗДАНИЕ SYSTEMD СЕРВИСОВ
log_info "⚙️ Создание systemd сервисов..."

# Основное приложение
cat > /etc/systemd/system/color360-app.service << EOF
[Unit]
Description=Color360 Main Application
After=network.target

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5

Environment=NODE_ENV=production
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
EOF

# AI сервис (если есть)
if [ -f "sd/requirements.txt" ]; then
cat > /etc/systemd/system/color360-sd.service << EOF
[Unit]
Description=Color360 AI Service
After=network.target

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$PROJECT_DIR/sd
Environment=PATH=$PROJECT_DIR/sd_env/bin
ExecStart=$PROJECT_DIR/sd_env/bin/python lama_service.py
Restart=always
RestartSec=10

Environment=PORT=5002
Environment=HOST=127.0.0.1

[Install]
WantedBy=multi-user.target
EOF
fi

# Перезагружаем systemd
systemctl daemon-reload

# Включаем сервисы
systemctl enable color360-app
if [ -f "/etc/systemd/system/color360-sd.service" ]; then
    systemctl enable color360-sd
fi

log_success "Systemd сервисы созданы"

# 10. НАСТРОЙКА NGINX
log_info "🌐 Настройка Nginx для $DOMAIN..."

cat > /etc/nginx/sites-available/color360 << 'EOF'
server {
    listen 80;
    server_name color360.ru www.color360.ru;
    
    # Увеличиваем лимиты для загрузки файлов
    client_max_body_size 100M;
    
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
        
        # Увеличиваем таймауты
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # AI сервис для обработки изображений
    location /api/ai/ {
        proxy_pass http://localhost:5002/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Увеличенные таймауты для AI обработки
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
    
    # Статические файлы
    location /assets/ {
        alias /var/www/color360/assets/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    location /pano/ {
        alias /var/www/color360/pano/;
        try_files $uri $uri/ /pano/index.html;
    }
}
EOF

# Включаем сайт
ln -sf /etc/nginx/sites-available/color360 /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Тестируем конфигурацию
if nginx -t; then
    log_success "Конфигурация Nginx корректна"
else
    log_error "Ошибка в конфигурации Nginx"
    exit 1
fi

# 11. НАСТРОЙКА FIREWALL
log_info "🔥 Настройка UFW firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 'Nginx Full'
ufw --force enable
log_success "Firewall настроен"

# 12. ЗАПУСК СЕРВИСОВ
log_info "🚀 Запуск всех сервисов..."

# Запускаем nginx
systemctl restart nginx
systemctl enable nginx

# Запускаем AI сервис (если есть)
if [ -f "/etc/systemd/system/color360-sd.service" ]; then
    log_info "Запуск AI сервиса..."
    systemctl start color360-sd
    sleep 5
fi

# Запускаем основное приложение
log_info "Запуск основного приложения..."
systemctl start color360-app
sleep 3

# 13. ПРОВЕРКА РАБОТОСПОСОБНОСТИ
log_info "✅ Проверка работоспособности..."

# Проверяем systemd сервисы
if systemctl is-active --quiet color360-app; then
    log_success "Основное приложение запущено"
else
    log_error "Основное приложение не запущено"
    systemctl status color360-app --no-pager
    exit 1
fi

# Проверяем HTTP
sleep 5
if curl -fsS --connect-timeout 10 "http://localhost:3000/" >/dev/null; then
    log_success "Приложение отвечает на HTTP запросы"
else
    log_warning "Приложение не отвечает на HTTP запросы"
fi

# Проверяем AI сервис
if [ -f "/etc/systemd/system/color360-sd.service" ]; then
    if systemctl is-active --quiet color360-sd; then
        log_success "AI сервис запущен"
        if curl -fsS --connect-timeout 5 "http://localhost:5002/health" >/dev/null; then
            log_success "AI сервис отвечает"
        else
            log_warning "AI сервис не отвечает (возможно еще запускается)"
        fi
    else
        log_warning "AI сервис не запущен"
    fi
fi

# 14. УСТАНОВКА SSL (LET'S ENCRYPT)
log_info "🔒 Установка SSL сертификата для $DOMAIN..."
if certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" --redirect; then
    log_success "SSL сертификат установлен"
else
    log_warning "Не удалось установить SSL сертификат (возможно DNS не настроен)"
fi

# 15. ФИНАЛЬНЫЙ ОТЧЕТ
echo ""
echo "🎉======================================🎉"
log_success "Color360 успешно установлен!"
echo "🎉======================================🎉"
echo ""
log_info "📋 Информация об установке:"
echo "   🌐 Домен: $DOMAIN"
echo "   📂 Директория: $PROJECT_DIR"
echo "   👤 Пользователь: $APP_USER"
echo "   📝 Коммит: $commit_hash"
echo "   💬 Изменения: $commit_msg"
echo "   🕒 Время установки: $(date)"
echo ""
log_info "🌍 Доступ к приложению:"
echo "   HTTP: http://$DOMAIN"
echo "   HTTPS: https://$DOMAIN (если SSL установлен)"
echo "   Локально: http://localhost:3000"
echo ""
log_info "🔧 Управление сервисами:"
echo "   systemctl status color360-app"
echo "   systemctl restart color360-app"
echo "   systemctl logs -u color360-app -f"
echo ""
log_info "📁 Важные пути:"
echo "   Проект: $PROJECT_DIR"
echo "   Nginx: /etc/nginx/sites-available/color360"
echo "   Логи: journalctl -u color360-app -f"
echo ""
log_info "🔄 Для обновления в будущем:"
echo "   cd $PROJECT_DIR && git pull && systemctl restart color360-app"
echo ""

log_success "🎊 Установка завершена! Color360 готов к работе!"

# Показываем статус всех сервисов
echo ""
log_info "📊 Финальный статус сервисов:"
systemctl status color360-app --no-pager -l
if [ -f "/etc/systemd/system/color360-sd.service" ]; then
    systemctl status color360-sd --no-pager -l
fi
systemctl status nginx --no-pager -l