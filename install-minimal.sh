#!/bin/bash
# Color360 - Быстрая установка только основного приложения
# Домен: color360.ru (без AI сервиса)
# Версия: 1.0 - Минимальная установка

set -e

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

echo "⚡ Color360 - Быстрая установка"
echo "==============================="
echo "Домен: color360.ru (только основное приложение)"
echo ""

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    log_error "Запустите с правами root: sudo bash $0"
    exit 1
fi

DOMAIN="color360.ru"
PROJECT_DIR="/var/www/color360"

# Полная очистка
log_info "🧹 Очистка системы..."
systemctl stop color360-app nginx 2>/dev/null || true
pkill -9 -f "color360\|server.js" 2>/dev/null || true
rm -rf "$PROJECT_DIR"
rm -f /etc/nginx/sites-enabled/color360*

# Обновление системы
log_info "📦 Обновление системы..."
apt update -qq && apt upgrade -y -qq

# Установка пакетов
log_info "📦 Установка Node.js и Nginx..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs nginx git curl certbot python3-certbot-nginx ufw

# Клонирование проекта
log_info "📥 Клонирование проекта..."
git clone "https://github.com/RadaRish/color360.git" "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Установка зависимостей
log_info "📦 Установка зависимостей..."
npm install --production

# Создание systemd сервиса
log_info "⚙️ Создание сервиса..."
cat > /etc/systemd/system/color360-app.service << EOF
[Unit]
Description=Color360 Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable color360-app

# Настройка Nginx
log_info "🌐 Настройка Nginx..."
cat > /etc/nginx/sites-available/color360 << EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    client_max_body_size 100M;
    
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
    }
    
    location /assets/ {
        alias $PROJECT_DIR/assets/;
        expires 1y;
    }
    
    location /pano/ {
        alias $PROJECT_DIR/pano/;
        try_files \$uri \$uri/ /pano/index.html;
    }
}
EOF

ln -sf /etc/nginx/sites-available/color360 /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Firewall
log_info "🔥 Настройка firewall..."
ufw --force reset >/dev/null 2>&1
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow ssh >/dev/null 2>&1
ufw allow 'Nginx Full' >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1

# Запуск сервисов
log_info "🚀 Запуск сервисов..."
systemctl restart nginx
systemctl start color360-app

# SSL
log_info "🔒 Установка SSL..."
if certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" --redirect >/dev/null 2>&1; then
    log_success "SSL установлен"
else
    log_warning "SSL не установлен (проверьте DNS)"
fi

# Проверка
sleep 5
if systemctl is-active --quiet color360-app && curl -fsS "http://localhost:3000/" >/dev/null; then
    echo ""
    log_success "🎉 Color360 успешно установлен!"
    echo ""
    echo "🌍 Доступ: https://$DOMAIN"
    echo "🔧 Управление: systemctl restart color360-app"
    echo "📝 Логи: journalctl -u color360-app -f"
    echo ""
else
    log_error "Ошибка установки!"
    systemctl status color360-app --no-pager
fi