#!/bin/bash
# Color360 LaMa Deployment Script для VPS
# Полная автоматизация развертывания с LaMa AI

set -e  # Остановка при ошибке

echo "🚀 Color360 LaMa Deployment Script"
echo "=================================="
echo "🎯 Установка Color360 с LaMa AI на VPS"
echo "💾 Требования: 2GB RAM, 2 CPU cores"
echo ""

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Переменные
WORK_DIR="/var/www/color360"
SERVICE_USER="root"
NODE_VERSION="20.19.3"
PYTHON_VERSION="3.10"
LAMA_PORT="5002"
APP_PORT="3000"

# Логирование
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Проверка системы
check_system() {
    log_info "Проверка системных требований..."
    
    # Проверка памяти
    MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$MEMORY_GB" -lt 2 ]; then
        log_warning "Обнаружено ${MEMORY_GB}GB RAM (рекомендуется 2GB+)"
    else
        log_success "Память: ${MEMORY_GB}GB ✓"
    fi
    
    # Проверка CPU
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -lt 2 ]; then
        log_warning "Обнаружено ${CPU_CORES} CPU cores (рекомендуется 2+)"
    else
        log_success "CPU: ${CPU_CORES} cores ✓"
    fi
    
    # Проверка свободного места
    DISK_FREE=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    if [ "$DISK_FREE" -lt 5 ]; then
        log_error "Недостаточно места на диске: ${DISK_FREE}GB (требуется 5GB+)"
        exit 1
    else
        log_success "Свободное место: ${DISK_FREE}GB ✓"
    fi
}

# Установка системных зависимостей
install_system_deps() {
    log_info "Установка системных зависимостей..."
    
    apt-get update -qq
    apt-get install -y \
        curl \
        wget \
        git \
        build-essential \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        libopencv-dev \
        pkg-config \
        nginx \
        supervisor \
        htop \
        unzip \
        ca-certificates \
        gnupg \
        lsb-release > /dev/null 2>&1
    
    log_success "Системные зависимости установлены"
}

# Установка Node.js через NVM
install_nodejs() {
    log_info "Установка Node.js ${NODE_VERSION}..."
    
    # Установка NVM
    if [ ! -d "$HOME/.nvm" ]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash > /dev/null 2>&1
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    fi
    
    # Загрузка NVM если уже установлен
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # Установка и использование нужной версии Node.js
    nvm install ${NODE_VERSION} > /dev/null 2>&1
    nvm use ${NODE_VERSION} > /dev/null 2>&1
    nvm alias default ${NODE_VERSION} > /dev/null 2>&1
    
    # Создание символической ссылки для systemd
    ln -sf $HOME/.nvm/versions/node/v${NODE_VERSION}/bin/node /usr/local/bin/node
    ln -sf $HOME/.nvm/versions/node/v${NODE_VERSION}/bin/npm /usr/local/bin/npm
    
    NODE_ACTUAL=$(node --version)
    log_success "Node.js установлен: ${NODE_ACTUAL}"
}

# Клонирование и настройка проекта
setup_project() {
    log_info "Настройка проекта Color360..."
    
    # Создание рабочей директории
    mkdir -p ${WORK_DIR}
    cd ${WORK_DIR}
    
    # Клонирование репозитория если не существует
    if [ ! -d ".git" ]; then
        log_info "Клонирование репозитория..."
        git clone https://github.com/RadaRish/color360.git . > /dev/null 2>&1
    else
        log_info "Обновление репозитория..."
        git pull origin main > /dev/null 2>&1
    fi
    
    # Установка Node.js зависимостей
    log_info "Установка Node.js зависимостей..."
    npm install > /dev/null 2>&1
    
    log_success "Проект настроен"
}

# Настройка Python окружения для LaMa
setup_lama_env() {
    log_info "Настройка Python окружения для LaMa..."
    
    cd ${WORK_DIR}/sd
    
    # Создание виртуального окружения
    if [ ! -d "lama_env" ]; then
        python3 -m venv lama_env
    fi
    
    # Активация окружения
    source lama_env/bin/activate
    
    # Обновление pip
    pip install --upgrade pip > /dev/null 2>&1
    
    # Установка зависимостей
    log_info "Установка LaMa зависимостей (может занять несколько минут)..."
    pip install -r requirements.txt > /dev/null 2>&1
    
    # Предварительная загрузка LaMa модели
    log_info "Предварительная загрузка LaMa модели..."
    python -c "
from lama_cleaner.model_manager import ModelManager
print('🎯 Загрузка LaMa модели...')
model = ModelManager(name='lama', device='cpu', no_half=True)
print('✅ LaMa модель загружена успешно')
" > /dev/null 2>&1 || log_warning "Модель будет загружена при первом запуске"
    
    deactivate
    
    log_success "Python окружение настроено"
}

# Настройка systemd сервисов
setup_systemd() {
    log_info "Настройка systemd сервисов..."
    
    # Сервис для основного приложения
    cat > /etc/systemd/system/color360-app.service << EOF
[Unit]
Description=Color360 Main Application with LaMa Integration
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=${WORK_DIR}
Environment=NODE_ENV=production
Environment=LAMA_ENABLED=true
Environment=LAMA_PORT=${LAMA_PORT}
Environment=PORT=${APP_PORT}
ExecStart=/usr/local/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=color360-app

[Install]
WantedBy=multi-user.target
EOF

    # Сервис для LaMa AI
    cat > /etc/systemd/system/color360-lama.service << EOF
[Unit]
Description=Color360 LaMa Inpainting Service
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=${WORK_DIR}/sd
Environment=PYTHONUNBUFFERED=1
Environment=PORT=${LAMA_PORT}
Environment=HOST=127.0.0.1
ExecStart=${WORK_DIR}/sd/lama_env/bin/python lama_service.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=color360-lama

[Install]
WantedBy=multi-user.target
EOF

    # Перезагрузка systemd
    systemctl daemon-reload
    
    # Включение сервисов
    systemctl enable color360-app
    systemctl enable color360-lama
    
    log_success "Systemd сервисы настроены"
}

# Настройка Nginx
setup_nginx() {
    log_info "Настройка Nginx..."
    
    # Создание конфигурации Nginx
    cat > /etc/nginx/sites-available/color360 << EOF
server {
    listen 80;
    server_name _;
    
    # Максимальный размер загружаемых файлов
    client_max_body_size 50M;
    
    # Основное приложение
    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Таймауты для AI операций
        proxy_connect_timeout 60s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }
    
    # LaMa AI сервис (прямой доступ для отладки)
    location /lama/ {
        proxy_pass http://127.0.0.1:${LAMA_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        
        # Увеличенные таймауты для AI
        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
    
    # Статические файлы
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|webp|mp4)$ {
        root ${WORK_DIR};
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

    # Активация сайта
    ln -sf /etc/nginx/sites-available/color360 /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Тестирование конфигурации
    nginx -t
    
    log_success "Nginx настроен"
}

# Запуск сервисов
start_services() {
    log_info "Запуск сервисов..."
    
    # Запуск LaMa сервиса
    log_info "Запуск LaMa сервиса..."
    systemctl start color360-lama
    sleep 5
    
    # Проверка LaMa сервиса
    if systemctl is-active --quiet color360-lama; then
        log_success "LaMa сервис запущен ✓"
    else
        log_error "LaMa сервис не запустился"
        systemctl status color360-lama --no-pager -l
        exit 1
    fi
    
    # Запуск основного приложения
    log_info "Запуск основного приложения..."
    systemctl start color360-app
    sleep 3
    
    # Проверка основного приложения
    if systemctl is-active --quiet color360-app; then
        log_success "Основное приложение запущено ✓"
    else
        log_error "Основное приложение не запустилось"
        systemctl status color360-app --no-pager -l
        exit 1
    fi
    
    # Перезапуск Nginx
    systemctl restart nginx
    if systemctl is-active --quiet nginx; then
        log_success "Nginx запущен ✓"
    else
        log_error "Nginx не запустился"
        exit 1
    fi
    
    log_success "Все сервисы запущены"
}

# Проверка развертывания
verify_deployment() {
    log_info "Проверка развертывания..."
    
    # Проверка портов
    sleep 5
    
    if netstat -tuln | grep -q ":${APP_PORT}"; then
        log_success "Основное приложение доступно на порту ${APP_PORT} ✓"
    else
        log_error "Основное приложение не отвечает на порту ${APP_PORT}"
    fi
    
    if netstat -tuln | grep -q ":${LAMA_PORT}"; then
        log_success "LaMa сервис доступен на порту ${LAMA_PORT} ✓"
    else
        log_error "LaMa сервис не отвечает на порту ${LAMA_PORT}"
    fi
    
    # Проверка HTTP доступности
    if curl -s http://localhost/api/lama-health | grep -q "ok"; then
        log_success "LaMa API отвечает ✓"
    else
        log_warning "LaMa API может быть недоступен (загружается модель)"
    fi
    
    # Информация о статусе
    echo ""
    log_info "=== СТАТУС СЕРВИСОВ ==="
    systemctl status color360-app --no-pager -l | head -3
    systemctl status color360-lama --no-pager -l | head -3
    systemctl status nginx --no-pager -l | head -3
}

# Финальные инструкции
show_final_info() {
    echo ""
    echo "🎉 Развертывание Color360 с LaMa AI завершено!"
    echo "=============================================="
    echo ""
    echo "📍 Доступ к приложению:"
    echo "   🌐 Основной сайт: http://$(curl -s ifconfig.me)"
    echo "   🔧 Админ панель: http://$(curl -s ifconfig.me)/admin"
    echo "   🎯 LaMa API: http://$(curl -s ifconfig.me)/lama/health"
    echo ""
    echo "🔐 Админ доступ:"
    echo "   📧 Email: admin@color360.online"
    echo "   🔑 Пароль: Color360Admin2025!"
    echo ""
    echo "🛠️ Управление сервисами:"
    echo "   systemctl status color360-app"
    echo "   systemctl status color360-lama"
    echo "   systemctl restart color360-app"
    echo "   systemctl restart color360-lama"
    echo ""
    echo "📊 Логи:"
    echo "   journalctl -u color360-app -f"
    echo "   journalctl -u color360-lama -f"
    echo ""
    echo "🎯 LaMa тестирование:"
    echo "   curl http://localhost/api/lama-health"
    echo ""
    echo "✨ Color360 готов к профессиональному удалению объектов!"
}

# Основная функция
main() {
    echo "🚀 Начинаем развертывание Color360 с LaMa AI..."
    echo ""
    
    check_system
    install_system_deps
    install_nodejs
    setup_project
    setup_lama_env
    setup_systemd
    setup_nginx
    start_services
    verify_deployment
    show_final_info
    
    log_success "🎉 Развертывание успешно завершено!"
}

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Запустите скрипт с правами root: sudo bash $0"
    exit 1
fi

# Запуск основной функции
main "$@"