#!/bin/bash

# ================================================================
# Color360 Migration Script: /var/www/color -> /var/www/color360
# Скрипт для безопасного обновления существующей установки
# ================================================================

set -e  # Остановиться при ошибках

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции для цветного вывода
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Конфигурация
OLD_PATH="/var/www/color"
NEW_PATH="/var/www/color360"
BACKUP_PATH="/var/backups/color360-migration-$(date +%Y%m%d_%H%M%S)"
DOMAIN="color360.ru"

# Проверка прав доступа
if [[ $EUID -ne 0 ]]; then
   log_error "Этот скрипт должен быть запущен с правами root"
   exit 1
fi

log_info "🚀 Начинаем миграцию Color360: $OLD_PATH -> $NEW_PATH"

# ================================================================
# Этап 1: Анализ текущей установки
# ================================================================

log_info "📋 Анализ текущей установки..."

if [ ! -d "$OLD_PATH" ]; then
    log_error "Старая установка не найдена в $OLD_PATH"
    exit 1
fi

log_success "Найдена старая установка в $OLD_PATH"

# Проверка запущенных процессов
RUNNING_PROCESSES=$(ps aux | grep -E "(node|pm2).*color" | grep -v grep || true)
if [ ! -z "$RUNNING_PROCESSES" ]; then
    log_warning "Обнаружены запущенные процессы Color360:"
    echo "$RUNNING_PROCESSES"
fi

# Проверка Nginx конфигурации
NGINX_CONFIG=$(find /etc/nginx -name "*color*" 2>/dev/null || true)
if [ ! -z "$NGINX_CONFIG" ]; then
    log_success "Найдена конфигурация Nginx: $NGINX_CONFIG"
fi

# ================================================================
# Этап 2: Создание резервной копии
# ================================================================

log_info "💾 Создание полной резервной копии..."

mkdir -p "$BACKUP_PATH"

# Копируем старую установку
log_info "Копирование файлов проекта..."
cp -r "$OLD_PATH" "$BACKUP_PATH/old_installation"

# Копируем конфигурацию Nginx
if [ ! -z "$NGINX_CONFIG" ]; then
    log_info "Копирование конфигурации Nginx..."
    mkdir -p "$BACKUP_PATH/nginx"
    cp -r /etc/nginx "$BACKUP_PATH/nginx/"
fi

# Копируем systemd сервисы
log_info "Копирование systemd сервисов..."
mkdir -p "$BACKUP_PATH/systemd"
systemctl list-units --all | grep color > "$BACKUP_PATH/systemd/services.txt" 2>/dev/null || true
find /etc/systemd -name "*color*" -exec cp {} "$BACKUP_PATH/systemd/" \; 2>/dev/null || true

# Копируем SSL сертификаты
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    log_info "Копирование SSL сертификатов..."
    mkdir -p "$BACKUP_PATH/ssl"
    cp -r "/etc/letsencrypt/live/$DOMAIN" "$BACKUP_PATH/ssl/" 2>/dev/null || true
fi

log_success "Резервная копия создана в $BACKUP_PATH"

# ================================================================
# Этап 3: Извлечение настроек из старой установки
# ================================================================

log_info "🔍 Извлечение настроек из старой установки..."

# Поиск .env файла
OLD_ENV_FILE=""
if [ -f "$OLD_PATH/.env" ]; then
    OLD_ENV_FILE="$OLD_PATH/.env"
elif [ -f "$OLD_PATH/.env.production" ]; then
    OLD_ENV_FILE="$OLD_PATH/.env.production"
fi

# Извлечение пользовательских данных
USER_DATA_PATHS=(
    "$OLD_PATH/uploads"
    "$OLD_PATH/user_data"
    "$OLD_PATH/data"
    "$OLD_PATH/sessions"
    "$OLD_PATH/avatars"
    "$OLD_PATH/panoramas"
)

FOUND_DATA=""
for path in "${USER_DATA_PATHS[@]}"; do
    if [ -d "$path" ]; then
        FOUND_DATA="$FOUND_DATA $path"
        log_info "Найдены пользовательские данные: $path"
    fi
done

# ================================================================
# Этап 4: Остановка старых сервисов
# ================================================================

log_info "⏹️ Остановка старых сервисов..."

# Остановка Nginx
systemctl stop nginx 2>/dev/null || true

# Остановка Node.js процессов
pkill -f "node.*color" 2>/dev/null || true
pkill -f "pm2.*color" 2>/dev/null || true

# Остановка Python/LaMa процессов
pkill -f "python.*color" 2>/dev/null || true
pkill -f "python.*lama" 2>/dev/null || true

# Остановка systemd сервисов
systemctl stop color 2>/dev/null || true
systemctl stop color-lama 2>/dev/null || true

log_success "Старые сервисы остановлены"

# ================================================================
# Этап 5: Загрузка новой версии
# ================================================================

log_info "📥 Загрузка новой версии Color360..."

# Удаление старой директории (если есть конфликт)
if [ -d "$NEW_PATH" ]; then
    log_warning "Директория $NEW_PATH уже существует, создаем бэкап..."
    mv "$NEW_PATH" "$BACKUP_PATH/existing_new_path"
fi

# Клонирование нового репозитория
log_info "Клонирование репозитория..."
git clone https://github.com/RadaRish/color360.git "$NEW_PATH"
cd "$NEW_PATH"

# Установка Node.js зависимостей
log_info "Установка Node.js зависимостей..."
npm install

# Установка зависимостей для редактора панорам
if [ -d "pano" ]; then
    cd pano
    npm install
    cd ..
fi

# ================================================================
# Этап 6: Настройка Python окружения для LaMa
# ================================================================

log_info "🐍 Настройка Python окружения для LaMa..."

if [ -d "lama" ]; then
    cd lama
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    deactivate
    cd ..
    log_success "Python окружение для LaMa настроено"
fi

# ================================================================
# Этап 7: Миграция данных и конфигураций
# ================================================================

log_info "🔄 Миграция данных и конфигураций..."

# Создание директорий
mkdir -p uploads logs data backups

# Копирование пользовательских данных
for data_path in $FOUND_DATA; do
    destination=$(basename "$data_path")
    if [ -d "$data_path" ]; then
        log_info "Копирование $data_path -> $NEW_PATH/$destination"
        cp -r "$data_path" "$NEW_PATH/$destination"
    fi
done

# Создание .env файла
log_info "Создание .env файла..."
cp .env.example .env

# Если найден старый .env, извлекаем важные настройки
if [ ! -z "$OLD_ENV_FILE" ] && [ -f "$OLD_ENV_FILE" ]; then
    log_info "Извлечение настроек из $OLD_ENV_FILE"
    
    # Извлекаем важные переменные
    if grep -q "JWT_SECRET" "$OLD_ENV_FILE"; then
        OLD_JWT_SECRET=$(grep "JWT_SECRET" "$OLD_ENV_FILE" | cut -d'=' -f2)
        sed -i "s/JWT_SECRET=.*/JWT_SECRET=$OLD_JWT_SECRET/" .env
    fi
    
    if grep -q "ADMIN_PASSWORD" "$OLD_ENV_FILE"; then
        OLD_ADMIN_PASSWORD=$(grep "ADMIN_PASSWORD" "$OLD_ENV_FILE" | cut -d'=' -f2)
        sed -i "s/ADMIN_PASSWORD=.*/ADMIN_PASSWORD=$OLD_ADMIN_PASSWORD/" .env
    fi
    
    if grep -q "DOMAIN" "$OLD_ENV_FILE"; then
        OLD_DOMAIN=$(grep "DOMAIN" "$OLD_ENV_FILE" | cut -d'=' -f2)
        sed -i "s/DOMAIN=.*/DOMAIN=$OLD_DOMAIN/" .env
    fi
fi

# Установка правильных прав доступа
chown -R www-data:www-data uploads logs data
chmod -R 755 uploads logs data

# ================================================================
# Этап 8: Настройка Nginx
# ================================================================

log_info "🌐 Настройка Nginx..."

# Создание новой конфигурации Nginx
cat > /etc/nginx/sites-available/color360 << 'EOF'
server {
    listen 80;
    server_name color360.ru www.color360.ru;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name color360.ru www.color360.ru;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/color360.ru/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/color360.ru/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Root directory
    root /var/www/color360;
    index index.html index.htm;

    # Main site
    location / {
        try_files $uri $uri/ @node;
    }

    # Panorama editor
    location /pano/ {
        try_files $uri $uri/ /pano/index.html;
    }

    # API routes
    location /api/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }

    # LaMa AI service
    location /ai/ {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 50M;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }

    # Node.js fallback
    location @node {
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

    # Static files with caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Uploads directory
    location /uploads/ {
        expires 1y;
        add_header Cache-Control "public";
    }

    # Security: deny access to sensitive files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~ \.(env|log|sql|json)$ {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF

# Удаление старых конфигураций
rm -f /etc/nginx/sites-enabled/color 2>/dev/null || true
rm -f /etc/nginx/sites-available/color 2>/dev/null || true

# Включение новой конфигурации
ln -sf /etc/nginx/sites-available/color360 /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Проверка конфигурации Nginx
if ! nginx -t; then
    log_error "Ошибка в конфигурации Nginx"
    exit 1
fi

# ================================================================
# Этап 9: Настройка PM2 и сервисов
# ================================================================

log_info "⚙️ Настройка PM2 и сервисов..."

# Установка PM2 глобально
npm install -g pm2

# Создание ecosystem конфигурации
cat > ecosystem.config.js << 'EOF'
module.exports = {
  apps: [
    {
      name: 'color360-main',
      script: 'server.js',
      cwd: '/var/www/color360',
      instances: 'max',
      exec_mode: 'cluster',
      watch: false,
      max_memory_restart: '1G',
      env: {
        NODE_ENV: 'production',
        PORT: 3000
      },
      error_file: '/var/log/color360/app-error.log',
      out_file: '/var/log/color360/app-out.log',
      log_file: '/var/log/color360/app.log',
      time: true,
      merge_logs: true
    },
    {
      name: 'color360-lama',
      script: 'lama/venv/bin/python',
      args: 'lama/app.py',
      cwd: '/var/www/color360',
      instances: 1,
      watch: false,
      env: {
        PYTHONPATH: '/var/www/color360/lama',
        PORT: 5000
      },
      error_file: '/var/log/color360/lama-error.log',
      out_file: '/var/log/color360/lama-out.log',
      log_file: '/var/log/color360/lama.log',
      time: true
    }
  ]
};
EOF

# Создание директории для логов
mkdir -p /var/log/color360
chown -R www-data:www-data /var/log/color360

# Остановка старых PM2 процессов
pm2 kill 2>/dev/null || true

# ================================================================
# Этап 10: Создание systemd сервисов
# ================================================================

log_info "🔧 Создание systemd сервисов..."

# Удаление старых сервисов
systemctl stop color 2>/dev/null || true
systemctl disable color 2>/dev/null || true
rm -f /etc/systemd/system/color.service

systemctl stop color-lama 2>/dev/null || true
systemctl disable color-lama 2>/dev/null || true
rm -f /etc/systemd/system/color-lama.service

# Создание нового сервиса для PM2
cat > /etc/systemd/system/color360.service << 'EOF'
[Unit]
Description=Color360 PM2 Service
Documentation=https://github.com/RadaRish/color360
After=network.target

[Service]
Type=notify
User=www-data
WorkingDirectory=/var/www/color360
ExecStart=/usr/bin/pm2-runtime start ecosystem.config.js
ExecReload=/bin/kill -USR2 $MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=300
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Обновление systemd
systemctl daemon-reload
systemctl enable color360

# ================================================================
# Этап 11: Запуск всех сервисов
# ================================================================

log_info "🚀 Запуск всех сервисов..."

# Запуск Color360
systemctl start color360

# Ждем запуска
sleep 10

# Запуск Nginx
systemctl start nginx
systemctl enable nginx

# ================================================================
# Этап 12: Проверка работоспособности
# ================================================================

log_info "🔍 Проверка работоспособности..."

# Проверка портов
if netstat -tlnp | grep -q ":3000"; then
    log_success "✅ Node.js сервер запущен на порту 3000"
else
    log_error "❌ Node.js сервер не запущен"
fi

if netstat -tlnp | grep -q ":5000"; then
    log_success "✅ LaMa сервис запущен на порту 5000"
else
    log_warning "⚠️ LaMa сервис не запущен (может запуститься позже)"
fi

if netstat -tlnp | grep -q ":80\|:443"; then
    log_success "✅ Nginx запущен"
else
    log_error "❌ Nginx не запущен"
fi

# Проверка HTTP ответов
sleep 5

if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ | grep -q "200\|301\|302"; then
    log_success "✅ Основной сайт отвечает"
else
    log_warning "⚠️ Основной сайт не отвечает"
fi

# ================================================================
# Этап 13: Финальный отчет
# ================================================================

log_success "🎉 Миграция Color360 завершена успешно!"

echo
echo "========================================================"
echo "           ОТЧЕТ О МИГРАЦИИ COLOR360"
echo "========================================================"
echo "📁 Старая установка: $OLD_PATH"
echo "📁 Новая установка: $NEW_PATH"
echo "💾 Резервная копия: $BACKUP_PATH"
echo "🌐 Домен: $DOMAIN"
echo
echo "🔗 URL для проверки:"
echo "   • Главная страница: https://$DOMAIN/"
echo "   • Редактор панорам: https://$DOMAIN/pano/"
echo "   • API здоровья: https://$DOMAIN/api/health"
echo "   • Админ панель: https://$DOMAIN/admin-dashboard.html"
echo
echo "📊 Управление сервисами:"
echo "   • systemctl status color360"
echo "   • systemctl restart color360"
echo "   • pm2 status"
echo "   • pm2 logs"
echo
echo "📋 Логи:"
echo "   • Приложение: /var/log/color360/"
echo "   • Nginx: /var/log/nginx/"
echo "   • Systemd: journalctl -u color360 -f"
echo
echo "🔄 В случае проблем:"
echo "   • Откат: systemctl stop color360 nginx"
echo "   • Восстановление: cp -r $BACKUP_PATH/old_installation $OLD_PATH"
echo "   • Поддержка: admin@color360.ru"
echo "========================================================"

log_info "Миграция завершена. Проверьте работу сайта: https://$DOMAIN/"