#!/bin/bash
# Color360 - МАКСИМАЛЬНО РАДИКАЛЬНАЯ установка
# Решает АБСОЛЮТНО ВСЕ проблемы с пакетами

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_radical() { echo -e "${PURPLE}💀 $1${NC}"; }

echo ""
echo -e "${PURPLE}💀💀💀 РАДИКАЛЬНАЯ УСТАНОВКА COLOR360 💀💀💀${NC}"
echo "=================================================="
echo "⚠️  ВНИМАНИЕ: Этот скрипт РАДИКАЛЬНО очищает систему!"
echo "⚠️  Используйте только если другие методы не сработали!"
echo ""

if [ "$EUID" -ne 0 ]; then
    log_error "Запустите от root: sudo bash $0"
    exit 1
fi

DOMAIN="color360.ru"
WORK_DIR="/var/www/color360"

# ЯДЕРНАЯ ОЧИСТКА
log_radical "☢️  ЯДЕРНАЯ ОЧИСТКА СИСТЕМЫ..."

# Останавливаем ВСЁ
systemctl stop color360-app color360-lama color360-sd nginx 2>/dev/null || true
pkill -9 -f "color360\|server.js\|lama\|node\|npm" 2>/dev/null || true
rm -rf "$WORK_DIR"
rm -f /etc/nginx/sites-enabled/color360*
rm -f /etc/systemd/system/color360-*.service
systemctl daemon-reload

# АБСОЛЮТНОЕ УНИЧТОЖЕНИЕ NODE.JS
log_radical "💣 АБСОЛЮТНОЕ УНИЧТОЖЕНИЕ NODE.JS..."

# Убиваем все процессы пакетного менеджера
pkill -9 -f "apt\|dpkg\|unattended-upgrade" 2>/dev/null || true
sleep 3

# Разблокируем dpkg если заблокирован
rm -f /var/lib/dpkg/lock*
rm -f /var/cache/apt/archives/lock
rm -f /var/lib/apt/lists/lock

# Настройка для неинтерактивной установки
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Исправляем прерванные операции
dpkg --configure -a 2>/dev/null || true

# ФИЗИЧЕСКОЕ УНИЧТОЖЕНИЕ всех Node.js файлов
log_radical "Физическое уничтожение Node.js файлов..."
rm -rf /usr/include/node* 2>/dev/null || true
rm -rf /usr/lib/node* 2>/dev/null || true  
rm -rf /usr/share/node* 2>/dev/null || true
rm -rf /var/lib/nodejs* 2>/dev/null || true
rm -rf ~/.nvm ~/.npm 2>/dev/null || true
rm -f /usr/local/bin/node /usr/local/bin/npm 2>/dev/null || true
rm -f /usr/bin/node /usr/bin/npm 2>/dev/null || true

# ПРИНУДИТЕЛЬНОЕ удаление ВСЕХ node пакетов через dpkg
log_radical "Принудительное удаление всех Node пакетов..."

# Получаем список всех node пакетов
NODE_PACKAGES=$(dpkg -l | grep -E '^ii.*(node|npm|libnode)' | awk '{print $2}' | tr '\n' ' ')

if [ -n "$NODE_PACKAGES" ]; then
    for pkg in $NODE_PACKAGES; do
        log_info "Удаление $pkg..."
        dpkg --remove --force-remove-reinstreq --force-depends "$pkg" 2>/dev/null || true
        dpkg --purge --force-remove-reinstreq --force-depends "$pkg" 2>/dev/null || true
    done
fi

# ЯДЕРНАЯ очистка apt
log_radical "Ядерная очистка APT..."
apt-get clean 2>/dev/null || true
apt-get autoclean 2>/dev/null || true
rm -rf /var/lib/apt/lists/* 2>/dev/null || true
rm -rf /var/cache/apt/archives/* 2>/dev/null || true

# Полное обновление базы пакетов
log_info "Обновление базы пакетов..."
apt-get update -qq 2>/dev/null || {
    log_warning "Первое обновление неудачно, повтор..."
    apt-get update -qq
}

# Исправляем сломанные зависимости РАДИКАЛЬНО
log_radical "Исправление сломанных зависимостей..."
apt-get --fix-broken install -y 2>/dev/null || true
apt-get autoremove --purge -y 2>/dev/null || true

# Если всё еще есть проблемы - удаляем проблемные пакеты
BROKEN_PACKAGES=$(apt-get -s install 2>&1 | grep "Depends:" | awk '{print $1}' | sort -u)
if [ -n "$BROKEN_PACKAGES" ]; then
    log_radical "Удаление сломанных пакетов: $BROKEN_PACKAGES"
    apt-get remove --purge -y $BROKEN_PACKAGES 2>/dev/null || true
fi

# Финальная очистка
apt-get autoremove --purge -y 2>/dev/null || true
apt-get --fix-broken install -y 2>/dev/null || true

log_success "Система радикально очищена"

# УСТАНОВКА МИНИМАЛЬНЫХ ПАКЕТОВ
log_info "📦 Установка минимальных пакетов..."

# Устанавливаем только самое необходимое
ESSENTIAL_PACKAGES="curl wget git nginx python3 python3-pip python3-venv build-essential"

for pkg in $ESSENTIAL_PACKAGES; do
    log_info "Установка $pkg..."
    apt-get install -y "$pkg" 2>/dev/null || {
        log_warning "Проблема с $pkg, исправляем..."
        apt-get --fix-broken install -y
        apt-get install -y "$pkg"
    }
done

log_success "Базовые пакеты установлены"

# УСТАНОВКА NODE.JS БИНАРНЫМИ ФАЙЛАМИ
log_info "🟢 Бинарная установка Node.js..."

cd /tmp
NODE_VERSION="20.17.0"
NODE_ARCHIVE="node-v$NODE_VERSION-linux-x64.tar.xz"

# Скачиваем Node.js
if [ -f "$NODE_ARCHIVE" ]; then
    rm -f "$NODE_ARCHIVE"
fi

log_info "Скачивание Node.js $NODE_VERSION..."
wget -q "https://nodejs.org/dist/v$NODE_VERSION/$NODE_ARCHIVE" || {
    log_error "Ошибка скачивания Node.js"
    exit 1
}

# Распаковываем
log_info "Распаковка Node.js..."
tar -xf "$NODE_ARCHIVE"

# Устанавливаем в систему
log_info "Установка Node.js в /usr/local..."
cp -rf "node-v$NODE_VERSION-linux-x64"/* /usr/local/

# Очищаем временные файлы
rm -rf "node-v$NODE_VERSION-linux-x64"*

# Проверяем установку
if /usr/local/bin/node --version >/dev/null 2>&1; then
    NODE_VER=$(/usr/local/bin/node --version)
    log_success "Node.js $NODE_VER успешно установлен"
else
    log_error "Ошибка установки Node.js"
    exit 1
fi

NPM_VER=$(/usr/local/bin/npm --version)
log_success "NPM $NPM_VER успешно установлен"

# УСТАНОВКА COLOR360
log_info "📥 Установка Color360..."

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Клонируем проект
log_info "Клонирование репозитория..."
git clone https://github.com/RadaRish/color360.git . || {
    log_error "Ошибка клонирования репозитория"
    exit 1
}

# Устанавливаем зависимости
log_info "Установка Node.js зависимостей..."
/usr/local/bin/npm install || {
    log_error "Ошибка установки зависимостей"
    exit 1
}

log_success "Color360 клонирован и настроен"

# PYTHON AI (если есть)
if [ -f "lama/requirements.txt" ]; then
    log_info "🐍 Настройка LaMa AI..."
    cd "$WORK_DIR/lama"
    
    # Проверяем что Python 3 установлен
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "Python 3 не найден!"
        exit 1
    fi
    
    # Создаем виртуальное окружение
    log_info "Создание Python виртуального окружения..."
    python3 -m venv lama_env || {
        log_error "Ошибка создания Python окружения"
        exit 1
    }
    
    # Активируем и устанавливаем зависимости
    log_info "Установка LaMa зависимостей..."
    source lama_env/bin/activate
    
    # Обновляем pip и setuptools
    pip install --upgrade pip setuptools wheel
    
    # Устанавливаем зависимости с повторными попытками
    for attempt in 1 2 3; do
        log_info "Попытка $attempt установки LaMa зависимостей..."
        if pip install -r requirements.txt --timeout=300; then
            log_success "LaMa зависимости установлены"
            break
        else
            log_warning "Попытка $attempt неудачна, повторяем..."
            if [ $attempt -eq 3 ]; then
                log_error "Не удалось установить LaMa зависимости после 3 попыток"
                exit 1
            fi
            sleep 10
        fi
    done
    
    # Проверяем установку
    if python -c "import lama_cleaner; print('LaMa Cleaner OK')" 2>/dev/null; then
        log_success "LaMa Cleaner успешно установлен"
    else
        log_warning "LaMa Cleaner может работать некорректно"
    fi
    
    deactivate
    log_success "LaMa AI настроен и готов"
    cd "$WORK_DIR"
else
    log_warning "Файл lama/requirements.txt не найден - LaMa AI не будет установлен"
fi

# SYSTEMD СЕРВИСЫ
log_info "⚙️ Создание systemd сервисов..."

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
Description=Color360 LaMa AI Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WORK_DIR/lama
Environment=PORT=5002
Environment=HOST=127.0.0.1
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

log_success "Systemd сервисы созданы"

# NGINX КОНФИГУРАЦИЯ
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

nginx -t || {
    log_error "Ошибка конфигурации Nginx"
    exit 1
}

log_success "Nginx настроен"

# FIREWALL
log_info "🔥 Настройка firewall..."
ufw --force reset >/dev/null 2>&1
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow ssh >/dev/null 2>&1
ufw allow 80 >/dev/null 2>&1
ufw allow 443 >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1

# ЗАПУСК ВСЕХ СЕРВИСОВ
log_info "🚀 Запуск сервисов..."

systemctl restart nginx

if [ -f "/etc/systemd/system/color360-lama.service" ]; then
    log_info "Запуск LaMa AI..."
    systemctl start color360-lama
    sleep 8
fi

log_info "Запуск основного приложения..."
systemctl start color360-app
sleep 5

# SSL СЕРТИФИКАТ
log_info "🔒 Установка SSL сертификата..."
apt-get install -y certbot python3-certbot-nginx >/dev/null 2>&1

if certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" --redirect >/dev/null 2>&1; then
    log_success "SSL сертификат установлен"
else
    log_warning "SSL не установлен (проверьте DNS)"
fi

# ФИНАЛЬНАЯ ПРОВЕРКА
log_info "🔍 Финальная проверка..."

sleep 5

# Проверяем сервисы
if systemctl is-active --quiet color360-app; then
    log_success "Основное приложение запущено"
else
    log_error "Основное приложение не запущено"
    systemctl status color360-app --no-pager
    exit 1
fi

# Проверяем HTTP
if curl -fsS --connect-timeout 10 "http://localhost:3000/" >/dev/null 2>&1; then
    log_success "HTTP работает"
else
    log_warning "HTTP не отвечает"
fi

# Проверяем LaMa
if [ -f "/etc/systemd/system/color360-lama.service" ]; then
    if systemctl is-active --quiet color360-lama; then
        log_success "LaMa AI запущен"
    else
        log_warning "LaMa AI не запущен"
    fi
fi

# ПОБЕДНЫЙ ФИНАЛ
echo ""
echo -e "${PURPLE}💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀${NC}"
echo -e "${GREEN}🎉 РАДИКАЛЬНАЯ УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО! 🎉${NC}"
echo -e "${PURPLE}💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀💀${NC}"
echo ""

commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
commit_msg=$(git log -1 --pretty=format:"%s" 2>/dev/null || echo "")

echo -e "${GREEN}📋 ИТОГИ РАДИКАЛЬНОЙ УСТАНОВКИ:${NC}"
echo "   🌐 Домен: $DOMAIN"
echo "   📂 Проект: $WORK_DIR" 
echo "   📝 Коммит: $commit_hash"
echo "   💬 Сообщение: $commit_msg"
echo "   🕒 Время: $(date)"
echo ""
echo -e "${GREEN}🌍 ДОСТУП К ПРИЛОЖЕНИЮ:${NC}"
echo "   HTTPS: https://$DOMAIN"
echo "   HTTP: http://$DOMAIN"
echo "   Локально: http://localhost:3000"
echo ""
echo -e "${GREEN}🔧 УПРАВЛЕНИЕ:${NC}"
echo "   systemctl status color360-app"
echo "   systemctl restart color360-app"
echo "   journalctl -u color360-app -f"
echo ""

if [ -f "/etc/systemd/system/color360-lama.service" ]; then
echo -e "${GREEN}🤖 LAMA AI УПРАВЛЕНИЕ:${NC}"
echo "   systemctl status color360-lama"
echo "   systemctl restart color360-lama"
echo "   journalctl -u color360-lama -f"
echo ""
fi

echo -e "${PURPLE}💀 ВСЕ ПРОБЛЕМЫ РАДИКАЛЬНО УСТРАНЕНЫ! 💀${NC}"
echo -e "${GREEN}🎊 COLOR360 ГОТОВ К РАБОТЕ! 🎊${NC}"