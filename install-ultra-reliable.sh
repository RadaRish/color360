#!/bin/bash
# Color360 - Ультра-надежная установка
# Гарантированное решение Node.js конфликтов

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

echo "🔥 Color360 - Ультра-надежная установка"
echo "========================================"
echo "Домен: color360.ru"
echo ""

if [ "$EUID" -ne 0 ]; then
    log_error "Запустите от root: sudo bash $0"
    exit 1
fi

DOMAIN="color360.ru"
WORK_DIR="/var/www/color360"

# ПОЛНАЯ ОЧИСТКА
log_info "🧹 Полная очистка системы..."
systemctl stop color360-app color360-lama nginx 2>/dev/null || true
pkill -9 -f "color360\|server.js\|lama" 2>/dev/null || true
rm -rf "$WORK_DIR"
rm -f /etc/nginx/sites-enabled/color360*
rm -f /etc/systemd/system/color360-*.service
systemctl daemon-reload

log_success "Очистка завершена"

# РАДИКАЛЬНАЯ ОЧИСТКА NODE.JS
log_info "💀 Радикальная очистка Node.js..."

# Убиваем все процессы apt
pkill -9 -f "apt\|dpkg" 2>/dev/null || true
sleep 3

# Исправляем сломанные установки
export DEBIAN_FRONTEND=noninteractive
dpkg --configure -a 2>/dev/null || true

# Держим важные пакеты
apt-mark hold ubuntu-keyring ubuntu-minimal 2>/dev/null || true

# Принудительно удаляем ВСЕ следы Node.js
log_info "Удаление всех Node.js пакетов..."

# Список всех возможных Node.js пакетов
NODE_PACKAGES="nodejs npm node libnode-dev libnode72 node-* libjs-*"

for pkg in $NODE_PACKAGES; do
    dpkg --remove --force-remove-reinstreq --force-depends $pkg 2>/dev/null || true
done

# Физически удаляем файлы
rm -rf /usr/include/node*
rm -rf /usr/lib/node*
rm -rf /usr/share/node*
rm -rf /var/lib/nodejs
rm -rf ~/.nvm ~/.npm
rm -f /usr/local/bin/node /usr/local/bin/npm
rm -f /usr/bin/node /usr/bin/npm

# Чистим apt базы данных
apt-get clean 2>/dev/null || true
apt-get autoclean 2>/dev/null || true
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives/*

# Обновляем репозитории
log_info "Обновление репозиториев..."
apt-get update -qq

# Удаляем осиротевшие пакеты
apt-get autoremove --purge -y 2>/dev/null || true

log_success "Node.js полностью удален"

# УСТАНОВКА БАЗОВЫХ ПАКЕТОВ
log_info "📦 Установка базовых пакетов..."
apt-get install -y git nginx curl python3 python3-pip python3-venv build-essential

# УСТАНОВКА NODE.JS ЧЕРЕЗ BINARY
log_info "🟢 Установка Node.js через бинарные файлы..."

# Скачиваем Node.js 20 напрямую
cd /tmp
NODE_VERSION="20.17.0"
wget -q "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.xz"
tar -xf "node-v$NODE_VERSION-linux-x64.tar.xz"

# Устанавливаем в /usr/local
cp -r "node-v$NODE_VERSION-linux-x64"/* /usr/local/
rm -rf "node-v$NODE_VERSION-linux-x64"*

# Проверяем установку
if /usr/local/bin/node --version >/dev/null 2>&1; then
    log_success "Node.js $(/usr/local/bin/node --version) установлен"
else
    log_error "Ошибка установки Node.js"
    exit 1
fi

# КЛОНИРОВАНИЕ ПРОЕКТА
log_info "📥 Клонирование Color360..."
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
git clone https://github.com/RadaRish/color360.git .

# УСТАНОВКА ЗАВИСИМОСТЕЙ
log_info "📦 Установка зависимостей..."
/usr/local/bin/npm install

# PYTHON AI (опционально)
if [ -f "lama/requirements.txt" ]; then
    log_info "🐍 Настройка Python AI..."
    cd "$WORK_DIR/lama"
    python3 -m venv lama_env
    source lama_env/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    deactivate
    log_success "Python AI настроен"
    cd "$WORK_DIR"
fi

# SYSTEMD СЕРВИСЫ
log_info "⚙️ Создание сервисов..."

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

if [ -f "lama/requirements.txt" ]; then
cat > /etc/systemd/system/color360-lama.service << EOF
[Unit]
Description=Color360 LaMa AI
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WORK_DIR/lama
Environment=PORT=5002
ExecStart=$WORK_DIR/lama/lama_env/bin/python service.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
fi

systemctl daemon-reload
systemctl enable color360-app
if [ -f "/etc/systemd/system/color360-lama.service" ]; then
    systemctl enable color360-lama
fi

# NGINX
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
    }
    
    location /api/lama/ {
        proxy_pass http://localhost:5002/;
        proxy_set_header Host \$host;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
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

# FIREWALL
log_info "🔥 Настройка firewall..."
ufw --force reset >/dev/null 2>&1
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow ssh >/dev/null 2>&1
ufw allow 80 >/dev/null 2>&1
ufw allow 443 >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1

# ЗАПУСК
log_info "🚀 Запуск сервисов..."
systemctl restart nginx

if [ -f "/etc/systemd/system/color360-lama.service" ]; then
    systemctl start color360-lama
    sleep 5
fi

systemctl start color360-app
sleep 5

# SSL
log_info "🔒 SSL сертификат..."
apt-get install -y certbot python3-certbot-nginx >/dev/null 2>&1
if certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" --redirect >/dev/null 2>&1; then
    log_success "SSL установлен"
else
    log_warning "SSL не установлен (проверьте DNS)"
fi

# ПРОВЕРКА
sleep 5
if systemctl is-active --quiet color360-app; then
    if curl -fsS "http://localhost:3000/" >/dev/null; then
        echo ""
        log_success "🎉 Color360 УСПЕШНО УСТАНОВЛЕН!"
        echo ""
        echo "🌍 Доступ: https://$DOMAIN"
        echo "🔧 Управление: systemctl restart color360-app"
        echo "📝 Логи: journalctl -u color360-app -f"
        
        commit_hash=$(git rev-parse --short HEAD)
        echo "📝 Коммит: $commit_hash"
        echo ""
        
        # Показать статус
        systemctl status color360-app --no-pager -l | head -10
    else
        log_error "HTTP не отвечает"
        exit 1
    fi
else
    log_error "Приложение не запущено"
    systemctl status color360-app --no-pager
    exit 1
fi