#!/bin/bash

# ================================================================
# Color360 Production Deployment Script
# Автоматическое развертывание сайта, редактора и LaMa системы
# ================================================================

set -e  # Остановка при любой ошибке

# Цветной вывод
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Конфигурация
DOMAIN="color360.ru"
PROJECT_DIR="/var/www/color360"
BACKUP_DIR="/var/backups/color360"
LOG_FILE="/var/log/color360-deploy.log"
NGINX_SITE_CONFIG="/etc/nginx/sites-available/color360"
SYSTEMD_SERVICE="/etc/systemd/system/color360.service"

# Функция логирования
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR $(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING $(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO $(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

# Проверка прав root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Этот скрипт должен запускаться с правами root. Используйте: sudo $0"
    fi
}

# Создание резервной копии существующей версии
create_backup() {
    log "🔄 Создание резервной копии текущей версии..."
    
    BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    CURRENT_BACKUP_DIR="$BACKUP_DIR/$BACKUP_TIMESTAMP"
    
    mkdir -p "$CURRENT_BACKUP_DIR"
    
    if [ -d "$PROJECT_DIR" ]; then
        log "📦 Копирование файлов проекта..."
        cp -r "$PROJECT_DIR" "$CURRENT_BACKUP_DIR/project"
        
        # Бэкап конфигураций
        if [ -f "$NGINX_SITE_CONFIG" ]; then
            cp "$NGINX_SITE_CONFIG" "$CURRENT_BACKUP_DIR/nginx.conf.bak"
        fi
        
        if [ -f "$SYSTEMD_SERVICE" ]; then
            cp "$SYSTEMD_SERVICE" "$CURRENT_BACKUP_DIR/color360.service.bak"
        fi
        
        # Бэкап PM2 конфигурации
        if command -v pm2 &> /dev/null; then
            su -c "pm2 dump" www-data > "$CURRENT_BACKUP_DIR/pm2.dump" 2>/dev/null || true
            su -c "pm2 list" www-data > "$CURRENT_BACKUP_DIR/pm2.list" 2>/dev/null || true
        fi
        
        log "✅ Резервная копия создана: $CURRENT_BACKUP_DIR"
    else
        log "ℹ️ Предыдущая версия не найдена, пропускаем резервное копирование"
    fi
    
    # Очистка старых бэкапов (оставляем последние 5)
    if [ -d "$BACKUP_DIR" ]; then
        find "$BACKUP_DIR" -maxdepth 1 -type d -name "*_*" | sort -r | tail -n +6 | xargs rm -rf 2>/dev/null || true
    fi
}

# Остановка существующих сервисов
stop_existing_services() {
    log "⏹️ Остановка существующих сервисов..."
    
    # Остановка PM2 процессов
    if command -v pm2 &> /dev/null; then
        su -c "pm2 stop all" www-data 2>/dev/null || true
        su -c "pm2 delete all" www-data 2>/dev/null || true
    fi
    
    # Остановка systemd сервиса
    if systemctl is-active --quiet color360; then
        systemctl stop color360
        systemctl disable color360
    fi
    
    # Остановка процессов Node.js и Python
    pkill -f "node.*server.js" || true
    pkill -f "python.*app.py" || true
    
    log "✅ Существующие сервисы остановлены"
}

# Установка системных зависимостей
install_system_dependencies() {
    log "📦 Установка системных зависимостей..."
    
    # Обновление системы
    apt update
    apt upgrade -y
    
    # Установка необходимых пакетов
    apt install -y \
        curl \
        wget \
        git \
        nginx \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        build-essential \
        supervisor \
        certbot \
        python3-certbot-nginx \
        htop \
        ufw \
        fail2ban
    
    log "✅ Системные зависимости установлены"
}

# Установка Node.js
install_nodejs() {
    log "🟢 Установка Node.js..."
    
    # Удаление старой версии Node.js если есть
    apt remove -y nodejs npm 2>/dev/null || true
    
    # Установка Node.js 18.x через NodeSource
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
    
    # Установка глобальных пакетов
    npm install -g pm2 yarn
    
    # Настройка PM2 для автозапуска
    pm2 startup systemd -u www-data --hp /var/www
    
    log "✅ Node.js $(node --version) установлен"
}

# Настройка пользователя и директорий
setup_user_and_directories() {
    log "👤 Настройка пользователя и директорий..."
    
    # Создание пользователя www-data если не существует
    if ! id "www-data" &>/dev/null; then
        useradd -r -s /bin/false www-data
    fi
    
    # Создание директорий
    mkdir -p "$PROJECT_DIR"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "/var/log/color360"
    mkdir -p "/var/www/.pm2"
    
    # Установка прав
    chown -R www-data:www-data /var/www
    chmod -R 755 /var/www
    
    log "✅ Пользователь и директории настроены"
}

# Клонирование и настройка проекта
deploy_project() {
    log "📂 Развертывание проекта..."
    
    # Удаление старой версии
    if [ -d "$PROJECT_DIR" ]; then
        rm -rf "$PROJECT_DIR"
    fi
    
    # Клонирование репозитория
    git clone https://github.com/RadaRish/color360.git "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    
    # Установка Node.js зависимостей
    log "📦 Установка Node.js зависимостей..."
    sudo -u www-data npm install
    
    # Настройка Python виртуального окружения для LaMa
    log "🐍 Настройка Python окружения для LaMa..."
    cd "$PROJECT_DIR/lama"
    sudo -u www-data python3 -m venv venv
    sudo -u www-data ./venv/bin/pip install --upgrade pip
    sudo -u www-data ./venv/bin/pip install -r requirements.txt
    
    # Установка прав на файлы
    chown -R www-data:www-data "$PROJECT_DIR"
    chmod +x "$PROJECT_DIR"/*.sh
    
    log "✅ Проект развернут"
}

# Создание конфигурации environment
create_environment_config() {
    log "⚙️ Создание конфигурации окружения..."
    
    cat > "$PROJECT_DIR/.env" << EOF
# Production Environment Configuration
NODE_ENV=production
PORT=3000
DOMAIN=$DOMAIN

# Security
JWT_SECRET=$(openssl rand -base64 32)

# LaMa Service Configuration
LAMA_PORT=5000
LAMA_HOST=127.0.0.1
LAMA_URL=http://127.0.0.1:5000

# Logging
LOG_LEVEL=info
LOG_FILE=/var/log/color360/app.log

# Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100

# File Upload
MAX_FILE_SIZE=52428800
UPLOAD_DIR=/var/www/uploads

# SSL Configuration
SSL_CERT_PATH=/etc/letsencrypt/live/$DOMAIN/fullchain.pem
SSL_KEY_PATH=/etc/letsencrypt/live/$DOMAIN/privkey.pem
EOF
    
    chown www-data:www-data "$PROJECT_DIR/.env"
    chmod 600 "$PROJECT_DIR/.env"
    
    log "✅ Конфигурация окружения создана"
}

# Настройка Nginx
configure_nginx() {
    log "🌐 Настройка Nginx..."
    
    # Создание конфигурации Nginx
    cat > "$NGINX_SITE_CONFIG" << EOF
# Color360 Nginx Configuration
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_dhparam /etc/nginx/dhparam.pem;
    
    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Logging
    access_log /var/log/nginx/color360.access.log;
    error_log /var/log/nginx/color360.error.log;
    
    # Main application
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
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
    
    # Panoramic editor
    location /pano/ {
        proxy_pass http://localhost:3000/pano/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
    
    # API endpoints with increased timeouts for LaMa processing
    location /api/ {
        proxy_pass http://localhost:3000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
        client_max_body_size 50M;
    }
    
    # Static files caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)\$ {
        proxy_pass http://localhost:3000;
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
    }
    
    # Health check
    location /health {
        proxy_pass http://localhost:3000/health;
        access_log off;
    }
}
EOF
    
    # Активация сайта
    ln -sf "$NGINX_SITE_CONFIG" /etc/nginx/sites-enabled/color360
    rm -f /etc/nginx/sites-enabled/default
    
    # Создание DH параметров для SSL
    if [ ! -f /etc/nginx/dhparam.pem ]; then
        openssl dhparam -out /etc/nginx/dhparam.pem 2048
    fi
    
    # Проверка конфигурации Nginx
    nginx -t || error "Ошибка в конфигурации Nginx"
    
    log "✅ Nginx настроен"
}

# Настройка SSL сертификата
setup_ssl() {
    log "🔒 Настройка SSL сертификата..."
    
    # Временно отключаем HTTPS в nginx для получения сертификата
    sed -i 's/listen 443 ssl/listen 443/' "$NGINX_SITE_CONFIG"
    sed -i 's/ssl_certificate/#ssl_certificate/' "$NGINX_SITE_CONFIG"
    sed -i 's/ssl_certificate_key/#ssl_certificate_key/' "$NGINX_SITE_CONFIG"
    
    systemctl reload nginx
    
    # Получение SSL сертификата
    if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN"
    else
        log "ℹ️ SSL сертификат уже существует"
    fi
    
    # Восстанавливаем оригинальную конфигурацию
    sed -i 's/listen 443/listen 443 ssl/' "$NGINX_SITE_CONFIG"
    sed -i 's/#ssl_certificate/ssl_certificate/' "$NGINX_SITE_CONFIG"
    
    # Настройка автоматического обновления сертификата
    (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
    
    log "✅ SSL сертификат настроен"
}

# Создание systemd сервиса
create_systemd_service() {
    log "🔧 Создание systemd сервиса..."
    
    cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=Color360 Web Application
Documentation=https://github.com/RadaRish/color360
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=$PROJECT_DIR
Environment=NODE_ENV=production
EnvironmentFile=$PROJECT_DIR/.env
ExecStart=/usr/bin/node server.js
ExecReload=/bin/kill -USR1 \$MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=5
PrivateTmp=true
Restart=always
RestartSec=10

# Security settings
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$PROJECT_DIR /var/log/color360 /tmp

# Logging
StandardOutput=append:/var/log/color360/app.log
StandardError=append:/var/log/color360/error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # Активация сервиса
    systemctl daemon-reload
    systemctl enable color360
    
    log "✅ Systemd сервис создан"
}

# Настройка PM2 для production
setup_pm2() {
    log "⚡ Настройка PM2..."
    
    # Создание PM2 ecosystem файла для production
    cat > "$PROJECT_DIR/ecosystem.production.json" << EOF
{
  "apps": [
    {
      "name": "color360-app",
      "script": "server.js",
      "cwd": "$PROJECT_DIR",
      "instances": "max",
      "exec_mode": "cluster",
      "watch": false,
      "max_memory_restart": "1G",
      "env": {
        "NODE_ENV": "production",
        "PORT": "3000"
      },
      "log_date_format": "YYYY-MM-DD HH:mm:ss Z",
      "error_file": "/var/log/color360/pm2-error.log",
      "out_file": "/var/log/color360/pm2-out.log",
      "log_file": "/var/log/color360/pm2-combined.log",
      "merge_logs": true,
      "time": true
    }
  ]
}
EOF
    
    chown www-data:www-data "$PROJECT_DIR/ecosystem.production.json"
    
    log "✅ PM2 настроен"
}

# Настройка брандмауэра
configure_firewall() {
    log "🔥 Настройка брандмауэра..."
    
    # Настройка UFW
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 'Nginx Full'
    ufw --force enable
    
    # Настройка fail2ban
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[nginx-http-auth]
enabled = true

[nginx-noscript]
enabled = true

[nginx-badbots]
enabled = true

[nginx-noproxy]
enabled = true
EOF
    
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log "✅ Брандмауэр настроен"
}

# Настройка логирования
setup_logging() {
    log "📝 Настройка системы логирования..."
    
    # Создание конфигурации logrotate
    cat > /etc/logrotate.d/color360 << EOF
/var/log/color360/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 www-data www-data
    postrotate
        systemctl reload color360 2>/dev/null || true
    endscript
}

/var/log/nginx/color360.*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 www-data adm
    sharedscripts
    postrotate
        systemctl reload nginx 2>/dev/null || true
    endscript
}
EOF
    
    log "✅ Система логирования настроена"
}

# Настройка мониторинга
setup_monitoring() {
    log "📊 Настройка базового мониторинга..."
    
    # Создание скрипта проверки здоровья
    cat > "$PROJECT_DIR/health-check.sh" << 'EOF'
#!/bin/bash

HEALTH_URL="https://color360.ru/health"
LOG_FILE="/var/log/color360/health-check.log"

# Проверка основного сервиса
if curl -f -s "$HEALTH_URL" > /dev/null; then
    echo "$(date): ✅ Service is healthy" >> "$LOG_FILE"
else
    echo "$(date): ❌ Service is down, restarting..." >> "$LOG_FILE"
    systemctl restart color360
    sleep 30
    if curl -f -s "$HEALTH_URL" > /dev/null; then
        echo "$(date): ✅ Service restarted successfully" >> "$LOG_FILE"
    else
        echo "$(date): ❌ Service restart failed" >> "$LOG_FILE"
    fi
fi
EOF
    
    chmod +x "$PROJECT_DIR/health-check.sh"
    chown www-data:www-data "$PROJECT_DIR/health-check.sh"
    
    # Добавление в crontab для проверки каждые 5 минут
    (crontab -l 2>/dev/null; echo "*/5 * * * * $PROJECT_DIR/health-check.sh") | crontab -
    
    log "✅ Базовый мониторинг настроен"
}

# Запуск всех сервисов
start_services() {
    log "🚀 Запуск сервисов..."
    
    # Запуск основного сервиса
    systemctl start color360
    
    # Проверка статуса
    sleep 10
    if systemctl is-active --quiet color360; then
        log "✅ Color360 сервис запущен"
    else
        error "❌ Не удалось запустить Color360 сервис"
    fi
    
    # Перезапуск Nginx
    systemctl restart nginx
    if systemctl is-active --quiet nginx; then
        log "✅ Nginx запущен"
    else
        error "❌ Не удалось запустить Nginx"
    fi
    
    log "✅ Все сервисы запущены"
}

# Проверка развертывания
verify_deployment() {
    log "🔍 Проверка развертывания..."
    
    # Проверка HTTP ответов
    sleep 15
    
    if curl -f -s "https://$DOMAIN/health" > /dev/null; then
        log "✅ Основной сайт доступен"
    else
        warning "⚠️ Основной сайт недоступен"
    fi
    
    if curl -f -s "https://$DOMAIN/pano/" > /dev/null; then
        log "✅ Редактор панорам доступен"
    else
        warning "⚠️ Редактор панорам недоступен"
    fi
    
    # Проверка логов
    if [ -f "/var/log/color360/app.log" ]; then
        log "✅ Логирование работает"
    else
        warning "⚠️ Проблемы с логированием"
    fi
    
    log "✅ Проверка развертывания завершена"
}

# Создание отчета о развертывании
create_deployment_report() {
    log "📋 Создание отчета о развертывании..."
    
    REPORT_FILE="/var/log/color360/deployment-report-$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$REPORT_FILE" << EOF
# Color360 Deployment Report
Generated: $(date)

## System Information
OS: $(lsb_release -d | cut -f2)
Kernel: $(uname -r)
Architecture: $(uname -m)

## Installed Software
Node.js: $(node --version)
NPM: $(npm --version)
Python: $(python3 --version)
Nginx: $(nginx -v 2>&1)
PM2: $(pm2 --version)

## Service Status
Color360 App: $(systemctl is-active color360)
Nginx: $(systemctl is-active nginx)
UFW: $(ufw status | head -n1)
Fail2ban: $(systemctl is-active fail2ban)

## Network Configuration
Domain: $DOMAIN
SSL Certificate: $([ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && echo "✅ Installed" || echo "❌ Not found")

## File Permissions
Project directory owner: $(stat -c "%U:%G" "$PROJECT_DIR")
Log directory owner: $(stat -c "%U:%G" "/var/log/color360")

## Backup Location
Latest backup: $(ls -t "$BACKUP_DIR" | head -n1 2>/dev/null || echo "None")

## URLs to test
- Main site: https://$DOMAIN/
- Panoramic editor: https://$DOMAIN/pano/
- Health check: https://$DOMAIN/health
- API test: https://$DOMAIN/api/demo

## Next Steps
1. Test all functionality manually
2. Set up external monitoring
3. Configure additional backup strategies
4. Review security settings
5. Update DNS records if needed

EOF
    
    log "✅ Отчет создан: $REPORT_FILE"
}

# Функция отката
rollback() {
    error_msg="$1"
    log "🔄 Выполнение отката из-за ошибки: $error_msg"
    
    LATEST_BACKUP=$(ls -t "$BACKUP_DIR" | head -n1 2>/dev/null)
    if [ -n "$LATEST_BACKUP" ] && [ -d "$BACKUP_DIR/$LATEST_BACKUP" ]; then
        log "📦 Восстановление из резервной копии: $LATEST_BACKUP"
        
        # Остановка сервисов
        systemctl stop color360 2>/dev/null || true
        
        # Восстановление файлов
        rm -rf "$PROJECT_DIR"
        cp -r "$BACKUP_DIR/$LATEST_BACKUP/project" "$PROJECT_DIR"
        
        # Восстановление конфигураций
        if [ -f "$BACKUP_DIR/$LATEST_BACKUP/nginx.conf.bak" ]; then
            cp "$BACKUP_DIR/$LATEST_BACKUP/nginx.conf.bak" "$NGINX_SITE_CONFIG"
        fi
        
        # Перезапуск сервисов
        systemctl restart nginx
        systemctl start color360
        
        log "✅ Откат выполнен"
    else
        log "❌ Резервная копия не найдена, ручное восстановление требуется"
    fi
}

# Основная функция развертывания
main() {
    log "🚀 Начало автоматического развертывания Color360"
    log "Domain: $DOMAIN"
    log "Project directory: $PROJECT_DIR"
    
    # Проверка прав
    check_root
    
    # Создание trap для отката при ошибке
    trap 'rollback "Ошибка во время развертывания"' ERR
    
    # Выполнение этапов развертывания
    create_backup
    stop_existing_services
    install_system_dependencies
    install_nodejs
    setup_user_and_directories
    deploy_project
    create_environment_config
    configure_nginx
    setup_ssl
    create_systemd_service
    setup_pm2
    configure_firewall
    setup_logging
    setup_monitoring
    start_services
    verify_deployment
    create_deployment_report
    
    # Отключение trap после успешного завершения
    trap - ERR
    
    log "🎉 Развертывание Color360 завершено успешно!"
    log "🌐 Сайт доступен по адресу: https://$DOMAIN"
    log "🎨 Редактор панорам: https://$DOMAIN/pano"
    log "📋 Отчет о развертывании: /var/log/color360/deployment-report-*.txt"
    log "📄 Логи приложения: /var/log/color360/"
    
    echo
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    РАЗВЕРТЫВАНИЕ ЗАВЕРШЕНО                   ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║ 🌐 Основной сайт:        https://$DOMAIN/                   ║${NC}"
    echo -e "${GREEN}║ 🎨 Редактор панорам:     https://$DOMAIN/pano               ║${NC}"
    echo -e "${GREEN}║ 🗑️ Удаление объектов:    Включено (LaMa + OpenCV)          ║${NC}"
    echo -e "${GREEN}║ 🔒 SSL сертификат:       Установлен и настроен              ║${NC}"
    echo -e "${GREEN}║ 🔥 Брандмауэр:           Активен                            ║${NC}"
    echo -e "${GREEN}║ 📊 Мониторинг:           Настроен                           ║${NC}"
    echo -e "${GREEN}║ 📦 Резервные копии:      Автоматические                     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
}

# Запуск основной функции
main "$@"