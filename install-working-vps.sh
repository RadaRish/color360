#!/bin/bash
# Color360 - Рабочий скрипт полной установки на VPS
# Домен: color360# Установка Node.js через NVM (проверенный способ)
log_info "🟢 Установка Node.js через NVM..."

# АГРЕССИВНАЯ очистка Node.js конфликтов
log_info "Полная очистка Node.js пакетов..."

# Останавливаем apt процессы
killall apt apt-get dpkg 2>/dev/null || true
sleep 2

# Исправляем сломанные пакеты
dpkg --configure -a 2>/dev/null || true

# Принудительно удаляем конфликтующие пакеты
apt-get remove --purge -y nodejs npm libnode-dev node-* 2>/dev/null || true
apt-get autoremove --purge -y 2>/dev/null || true

# Чистим apt кэш
apt-get clean
apt-get autoclean
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives/*

# Обновляем базу пакетов заново
apt-get update -qq

# Полностью удаляем следы Node.js
rm -rf /usr/include/node /usr/lib/node_modules /usr/share/nodejs
rm -rf /usr/local/bin/node /usr/local/bin/npm /usr/bin/node /usr/bin/npm
rm -rf ~/.nvm ~/.npm

log_success "Node.js полностью удален"ован на проверенных скриптах из репозитория

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

echo "🔥 Color360 - Проверенная полная установка"
echo "=========================================="
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
WORK_DIR="/var/www/color360"

log_info "Начинаем проверенную установку..."

# 1. ПОЛНАЯ ОЧИСТКА СИСТЕМЫ
log_info "🧹 Полная остановка и очистка..."

# Остановка всех сервисов
systemctl stop color360-app color360-lama color360-sd nginx 2>/dev/null || true
systemctl disable color360-app color360-lama color360-sd 2>/dev/null || true

# Убиваем все процессы
pkill -9 -f "color360\|lama.*service\|server.js" 2>/dev/null || true
fuser -k 3000/tcp 5002/tcp 80/tcp 443/tcp 2>/dev/null || true

# Удаляем systemd сервисы
rm -f /etc/systemd/system/color360-*.service
systemctl daemon-reload

# Удаляем проект
rm -rf "$WORK_DIR"

# Удаляем nginx конфигурации
rm -f /etc/nginx/sites-enabled/color360* /etc/nginx/sites-available/color360*

# Удаляем SSL (если есть)
rm -rf /etc/letsencrypt/live/$DOMAIN /etc/letsencrypt/archive/$DOMAIN /etc/letsencrypt/renewal/$DOMAIN.conf 2>/dev/null || true

log_success "Система полностью очищена"

# 2. ОБНОВЛЕНИЕ СИСТЕМЫ И УСТАНОВКА ЗАВИСИМОСТЕЙ
log_info "📦 Обновление системы..."

# Обновляем систему
apt-get update -qq
apt-get upgrade -y -qq

# Устанавливаем базовые пакеты
log_info "📦 Установка базовых пакетов..."
apt-get install -y \
    curl wget git build-essential \
    python3 python3-pip python3-venv python3-dev \
    nginx supervisor htop unzip \
    ca-certificates gnupg lsb-release \
    certbot python3-certbot-nginx ufw

log_success "Базовые пакеты установлены"

# 3. УСТАНОВКА NODE.JS ЧЕРЕЗ NVM (проверенный способ)
log_info "🟢 Установка Node.js через NVM..."

# Удаление конфликтующих пакетов
apt-get remove -y nodejs npm libnode-dev 2>/dev/null || true
apt-get autoremove -y

# Удаление старого NVM
rm -rf ~/.nvm /usr/local/bin/node /usr/local/bin/npm 2>/dev/null || true

# Установка NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Установка Node.js 20
nvm install 20
nvm use 20
nvm alias default 20

# Создание символических ссылок для systemd
mkdir -p /usr/local/bin
ln -sf ~/.nvm/versions/node/v*/bin/node /usr/local/bin/node
ln -sf ~/.nvm/versions/node/v*/bin/npm /usr/local/bin/npm

node_version=$(node --version)
npm_version=$(npm --version)
log_success "Node.js $node_version и npm $npm_version установлены"

# 4. КЛОНИРОВАНИЕ И НАСТРОЙКА ПРОЕКТА
log_info "📥 Клонирование Color360..."

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Клонирование репозитория
git clone https://github.com/RadaRish/color360.git .

# Получение информации о коммите
commit_hash=$(git rev-parse --short HEAD)
commit_msg=$(git log -1 --pretty=format:"%s")
log_success "Клонирован коммит $commit_hash: $commit_msg"

# Установка Node.js зависимостей
log_info "📦 Установка Node.js зависимостей..."
npm install

log_success "Node.js зависимости установлены"

# 5. НАСТРОЙКА LAMA AI (если есть)
if [ -f "lama/requirements.txt" ]; then
    log_info "🎯 Настройка LaMa AI..."
    
    cd "$WORK_DIR/lama"
    
    # Создание Python окружения
    python3 -m venv lama_env
    source lama_env/bin/activate
    
    # Установка зависимостей
    log_info "📦 Установка LaMa зависимостей..."
    pip install --upgrade pip
    pip install -r requirements.txt
    
    deactivate
    log_success "LaMa AI настроен"
    
    cd "$WORK_DIR"
fi

# 6. СОЗДАНИЕ SYSTEMD СЕРВИСОВ
log_info "⚙️ Создание systemd сервисов..."

# Основное приложение
cat > /etc/systemd/system/color360-app.service << EOF
[Unit]
Description=Color360 Main Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WORK_DIR
Environment=NODE_ENV=production
Environment=PORT=3000
ExecStart=/usr/local/bin/node server.js
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# LaMa сервис (если есть)
if [ -f "lama/requirements.txt" ]; then
cat > /etc/systemd/system/color360-lama.service << EOF
[Unit]
Description=Color360 LaMa AI Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WORK_DIR/lama
Environment=PYTHONUNBUFFERED=1
Environment=PORT=5002
Environment=HOST=127.0.0.1
ExecStart=$WORK_DIR/lama/lama_env/bin/python service.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
fi

# Перезагружаем systemd
systemctl daemon-reload

# Включаем автозапуск
systemctl enable color360-app
if [ -f "/etc/systemd/system/color360-lama.service" ]; then
    systemctl enable color360-lama
fi

log_success "Systemd сервисы созданы"

# 7. НАСТРОЙКА NGINX
log_info "🌐 Настройка Nginx..."

cat > /etc/nginx/sites-available/color360 << EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    
    # Увеличиваем лимиты
    client_max_body_size 100M;
    client_body_timeout 300s;
    client_header_timeout 300s;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Увеличенные таймауты
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # LaMa AI API
    location /api/lama/ {
        proxy_pass http://localhost:5002/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Длинные таймауты для AI
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
    
    # Статические файлы
    location /assets/ {
        alias $WORK_DIR/assets/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    location /pano/ {
        alias $WORK_DIR/pano/;
        try_files \$uri \$uri/ /pano/index.html;
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
    nginx -t
    exit 1
fi

# 8. НАСТРОЙКА FIREWALL
log_info "🔥 Настройка firewall..."
ufw --force reset >/dev/null 2>&1
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow ssh >/dev/null 2>&1
ufw allow 'Nginx Full' >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1
log_success "Firewall настроен"

# 9. ЗАПУСК СЕРВИСОВ
log_info "🚀 Запуск сервисов..."

# Запускаем nginx
systemctl restart nginx
systemctl enable nginx

# Запускаем LaMa (если есть)
if [ -f "/etc/systemd/system/color360-lama.service" ]; then
    log_info "Запуск LaMa AI..."
    systemctl start color360-lama
    sleep 8
fi

# Запускаем основное приложение
log_info "Запуск основного приложения..."
systemctl start color360-app
sleep 5

# 10. ПРОВЕРКА РАБОТОСПОСОБНОСТИ
log_info "✅ Проверка работоспособности..."

# Проверяем основное приложение
if systemctl is-active --quiet color360-app; then
    log_success "Основное приложение запущено"
else
    log_error "Ошибка запуска основного приложения"
    systemctl status color360-app --no-pager
    exit 1
fi

# Проверяем HTTP
sleep 5
if curl -fsS --connect-timeout 10 "http://localhost:3000/" >/dev/null; then
    log_success "Приложение отвечает на HTTP"
else
    log_warning "HTTP не отвечает (возможно еще запускается)"
fi

# Проверяем LaMa
if [ -f "/etc/systemd/system/color360-lama.service" ]; then
    if systemctl is-active --quiet color360-lama; then
        log_success "LaMa AI запущен"
    else
        log_warning "LaMa AI не запущен"
    fi
fi

# 11. УСТАНОВКА SSL
log_info "🔒 Установка SSL сертификата..."
if certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" --redirect >/dev/null 2>&1; then
    log_success "SSL сертификат установлен"
else
    log_warning "SSL не установлен (проверьте DNS настройки)"
fi

# 12. ФИНАЛЬНЫЙ ОТЧЕТ
echo ""
echo "🎉======================================🎉"
log_success "Color360 успешно установлен!"
echo "🎉======================================🎉"
echo ""
log_info "📋 Сводка установки:"
echo "   🌐 Домен: $DOMAIN"
echo "   📂 Директория: $WORK_DIR"
echo "   📝 Коммит: $commit_hash"
echo "   💬 Изменения: $commit_msg"
echo "   🕒 Время: $(date)"
echo ""
log_info "🌍 Доступ к приложению:"
echo "   HTTPS: https://$DOMAIN"
echo "   HTTP: http://$DOMAIN"
echo "   Локально: http://localhost:3000"
echo ""
log_info "🔧 Управление:"
echo "   systemctl status color360-app"
echo "   systemctl restart color360-app"
echo "   journalctl -u color360-app -f"
echo ""
if [ -f "/etc/systemd/system/color360-lama.service" ]; then
echo "   # LaMa AI управление:"
echo "   systemctl status color360-lama"
echo "   systemctl restart color360-lama"
echo "   journalctl -u color360-lama -f"
echo ""
fi

# Показываем финальный статус
log_info "📊 Статус сервисов:"
systemctl status color360-app --no-pager -l
if [ -f "/etc/systemd/system/color360-lama.service" ]; then
    systemctl status color360-lama --no-pager -l
fi
systemctl status nginx --no-pager -l

echo ""
log_success "🎊 Установка завершена! Color360 готов к работе!"