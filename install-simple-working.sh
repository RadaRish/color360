#!/bin/bash
# Color360 - Минимальная рабочая установка без AI
# Домен: color360.ru

set -e

# Цвета
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

echo "⚡ Color360 - Быстрая рабочая установка"
echo "====================================="
echo "Домен: color360.ru (без AI)"
echo ""

# Проверка root
if [ "$EUID" -ne 0 ]; then
    log_error "Запустите от root: sudo bash $0"
    exit 1
fi

DOMAIN="color360.ru"
WORK_DIR="/var/www/color360"

# Очистка
log_info "🧹 Очистка..."
systemctl stop color360-app color360-lama nginx 2>/dev/null || true
pkill -9 -f "color360\|server.js" 2>/dev/null || true
rm -rf "$WORK_DIR"
rm -f /etc/nginx/sites-enabled/color360*

# Системные пакеты
log_info "📦 Установка пакетов..."
apt-get update -qq
apt-get remove -y nodejs npm libnode-dev 2>/dev/null || true
apt-get install -y git nginx curl certbot python3-certbot-nginx ufw

# Node.js через NVM
log_info "🟢 Установка Node.js..."

# Агрессивная очистка Node.js
killall apt apt-get dpkg 2>/dev/null || true
dpkg --configure -a 2>/dev/null || true
apt-get remove --purge -y nodejs npm libnode-dev node-* 2>/dev/null || true
apt-get autoremove --purge -y 2>/dev/null || true
apt-get clean && apt-get autoclean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
apt-get update -qq

rm -rf /usr/include/node /usr/lib/node_modules /usr/share/nodejs
rm -rf /usr/local/bin/node /usr/local/bin/npm /usr/bin/node /usr/bin/npm
rm -rf ~/.nvm ~/.npm

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

nvm install 20
nvm use 20
nvm alias default 20

ln -sf ~/.nvm/versions/node/v*/bin/node /usr/local/bin/node
ln -sf ~/.nvm/versions/node/v*/bin/npm /usr/local/bin/npm

log_success "Node.js $(node --version) установлен"

# Проект
log_info "📥 Клонирование проекта..."
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
git clone https://github.com/RadaRish/color360.git .

log_info "📦 Установка зависимостей..."
npm install

# Systemd сервис
log_info "⚙️ Создание сервиса..."
cat > /etc/systemd/system/color360-app.service << EOF
[Unit]
Description=Color360 Application
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

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable color360-app

# Nginx
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
        alias $WORK_DIR/assets/;
        expires 1y;
    }
    
    location /pano/ {
        alias $WORK_DIR/pano/;
        try_files \$uri \$uri/ /pano/index.html;
    }
}
EOF

ln -sf /etc/nginx/sites-available/color360 /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Firewall
log_info "🔥 Firewall..."
ufw --force reset >/dev/null 2>&1
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow ssh >/dev/null 2>&1
ufw allow 'Nginx Full' >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1

# Запуск
log_info "🚀 Запуск..."
systemctl restart nginx
systemctl start color360-app

# SSL
log_info "🔒 SSL..."
if certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" --redirect >/dev/null 2>&1; then
    log_success "SSL установлен"
else
    log_warning "SSL не установлен"
fi

# Проверка
sleep 5
if systemctl is-active --quiet color360-app && curl -fsS "http://localhost:3000/" >/dev/null; then
    echo ""
    log_success "🎉 Color360 готов!"
    echo ""
    echo "🌍 Доступ: https://$DOMAIN"
    echo "🔧 Управление: systemctl restart color360-app"
    echo "📝 Логи: journalctl -u color360-app -f"
    echo ""
    
    commit_hash=$(git rev-parse --short HEAD)
    echo "📝 Коммит: $commit_hash"
else
    log_error "Ошибка!"
    systemctl status color360-app --no-pager
fi