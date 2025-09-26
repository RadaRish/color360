#!/bin/bash
# Color360 Complete Clean Install Script
# Полная очистка и установка проекта с нуля

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

echo "🔥 Color360 Complete Clean Install"
echo "=================================="
echo "⚠️  ВНИМАНИЕ: Это удалит все старые версии!"
echo ""

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    log_error "Запустите с правами root: sudo bash $0"
    exit 1
fi

WORK_DIR="/var/www/color360"
BACKUP_DIR="/tmp/color360-backup-$(date +%Y%m%d-%H%M%S)"

# Создание резервной копии (если нужно)
backup_if_exists() {
    if [ -d "$WORK_DIR" ]; then
        log_info "Создание резервной копии в $BACKUP_DIR..."
        mkdir -p "$BACKUP_DIR"
        cp -r "$WORK_DIR" "$BACKUP_DIR/" 2>/dev/null || true
        log_success "Резервная копия создана"
    fi
}

# Полная остановка и очистка
complete_cleanup() {
    log_info "🛑 Полная остановка всех сервисов..."
    
    # Остановка systemd сервисов
    systemctl stop color360-app color360-lama nginx 2>/dev/null || true
    systemctl disable color360-app color360-lama 2>/dev/null || true
    
    # Удаление systemd сервисов
    rm -f /etc/systemd/system/color360-*.service
    
    # Принудительная остановка процессов
    pkill -9 -f "color360\|lama.*service\|server.js" 2>/dev/null || true
    
    # Освобождение портов
    fuser -k 3000/tcp 2>/dev/null || true
    fuser -k 5002/tcp 2>/dev/null || true
    
    # Удаление старых файлов проекта
    if [ -d "$WORK_DIR" ]; then
        log_info "🗑️ Удаление старого проекта..."
        rm -rf "$WORK_DIR"
    fi
    
    # Удаление старых Nginx конфигов
    rm -f /etc/nginx/sites-enabled/color360 /etc/nginx/sites-available/color360
    
    systemctl daemon-reload
    
    log_success "Очистка завершена"
}

# Установка системных зависимостей
install_system_deps() {
    log_info "📦 Установка системных зависимостей..."
    
    apt-get update -qq
    apt-get install -y \
        curl wget git build-essential \
        python3 python3-pip python3-venv python3-dev \
        nginx supervisor htop unzip \
        ca-certificates gnupg lsb-release > /dev/null 2>&1
    
    log_success "Системные зависимости установлены"
}

# Установка Node.js
install_nodejs() {
    log_info "🟢 Установка Node.js 20.19.3..."
    
    # Удаление старого NVM если есть
    rm -rf ~/.nvm 2>/dev/null || true
    
    # Установка NVM
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash > /dev/null 2>&1
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # Установка Node.js
    nvm install 20.19.3 > /dev/null 2>&1
    nvm use 20.19.3 > /dev/null 2>&1
    nvm alias default 20.19.3 > /dev/null 2>&1
    
    # Символические ссылки для systemd
    rm -f /usr/local/bin/node /usr/local/bin/npm
    ln -sf ~/.nvm/versions/node/v20.19.3/bin/node /usr/local/bin/node
    ln -sf ~/.nvm/versions/node/v20.19.3/bin/npm /usr/local/bin/npm
    
    log_success "Node.js $(node --version) установлен"
}

# Клонирование свежего проекта
clone_fresh_project() {
    log_info "📥 Клонирование свежего проекта..."
    
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # Клонирование репозитория
    git clone https://github.com/RadaRish/color360.git . > /dev/null 2>&1
    
    # Установка Node.js зависимостей
    log_info "📦 Установка Node.js зависимостей..."
    npm install > /dev/null 2>&1
    
    log_success "Проект клонирован и настроен"
}

# Настройка LaMa окружения
setup_lama_environment() {
    log_info "🎯 Настройка LaMa окружения..."
    
    cd "$WORK_DIR/lama"
    
    # Создание Python окружения
    python3 -m venv lama_env
    
    # Активация и установка зависимостей
    source lama_env/bin/activate
    
    log_info "📦 Установка LaMa зависимостей (это займёт время)..."
    pip install --upgrade pip > /dev/null 2>&1
    
    # Установка зависимостей по одной для лучшей диагностики
    pip install --extra-index-url https://download.pytorch.org/whl/cpu \
        torch==2.1.0+cpu torchvision==0.16.0+cpu torchaudio==2.1.0+cpu > /dev/null 2>&1
    
    pip install fastapi==0.104.1 uvicorn[standard]==0.24.0 > /dev/null 2>&1
    pip install python-multipart==0.0.6 > /dev/null 2>&1
    pip install pillow==10.1.0 opencv-python-headless==4.8.1.78 numpy==1.24.3 > /dev/null 2>&1
    pip install lama-cleaner==1.2.2 > /dev/null 2>&1
    pip install psutil==5.9.6 requests==2.31.0 > /dev/null 2>&1
    
    deactivate
    
    log_success "LaMa окружение настроено"
}

# Создание systemd сервисов
create_systemd_services() {
    log_info "⚙️ Создание systemd сервисов..."
    
    # LaMa сервис
    cat > /etc/systemd/system/color360-lama.service << 'EOF'
[Unit]
Description=Color360 LaMa Inpainting Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/color360/lama
Environment=PYTHONUNBUFFERED=1
Environment=PORT=5002
Environment=HOST=127.0.0.1
ExecStart=/var/www/color360/lama/lama_env/bin/python service.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=color360-lama

[Install]
WantedBy=multi-user.target
EOF

    # Основное приложение
    cat > /etc/systemd/system/color360-app.service << 'EOF'
[Unit]
Description=Color360 Main Application
After=network.target color360-lama.service

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/color360
Environment=NODE_ENV=production
Environment=LAMA_ENABLED=true
Environment=LAMA_PORT=5002
Environment=PORT=3000
ExecStart=/usr/local/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=color360-app

[Install]
WantedBy=multi-user.target
EOF

    log_success "Systemd сервисы созданы"
}

# Настройка Nginx
setup_nginx() {
    log_info "🌐 Настройка Nginx..."
    
    cat > /etc/nginx/sites-available/color360 << 'EOF'
server {
    listen 80;
    server_name _;
    
    client_max_body_size 50M;
    
    # Основное приложение
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }
    
    # Прямой доступ к LaMa для отладки
    location /lama/ {
        proxy_pass http://127.0.0.1:5002/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
    
    # Статические файлы
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|webp|mp4)$ {
        root /var/www/color360;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

    # Активация сайта
    ln -sf /etc/nginx/sites-available/color360 /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Тест конфигурации
    if nginx -t; then
        log_success "Nginx настроен"
    else
        log_error "Ошибка конфигурации Nginx"
        exit 1
    fi
}

# Запуск сервисов
start_services() {
    log_info "🚀 Запуск сервисов..."
    
    # Перезагрузка systemd
    systemctl daemon-reload
    
    # Включение автозапуска
    systemctl enable color360-lama color360-app nginx
    
    # Запуск LaMa
    log_info "🎯 Запуск LaMa сервиса..."
    systemctl start color360-lama
    
    # Ожидание готовности LaMa
    log_info "⏳ Ожидание готовности LaMa (30 сек)..."
    for i in {1..30}; do
        if systemctl is-active --quiet color360-lama; then
            if curl -s http://localhost:5002/health > /dev/null 2>&1; then
                log_success "LaMa сервис готов"
                break
            fi
        fi
        sleep 1
        echo -n "."
    done
    echo ""
    
    # Запуск основного приложения
    log_info "🌐 Запуск основного приложения..."
    systemctl start color360-app
    sleep 5
    
    # Запуск Nginx
    systemctl restart nginx
    
    log_success "Все сервисы запущены"
}

# Проверка установки
verify_installation() {
    log_info "🔍 Проверка установки..."
    
    # Проверка статуса сервисов
    local services_ok=0
    
    if systemctl is-active --quiet color360-lama; then
        log_success "LaMa сервис работает"
        ((services_ok++))
    else
        log_error "LaMa сервис не работает"
    fi
    
    if systemctl is-active --quiet color360-app; then
        log_success "Основное приложение работает"
        ((services_ok++))
    else
        log_error "Основное приложение не работает"
    fi
    
    if systemctl is-active --quiet nginx; then
        log_success "Nginx работает"
        ((services_ok++))
    else
        log_error "Nginx не работает"
    fi
    
    # Проверка API
    local api_ok=0
    
    if curl -s http://localhost:5002/health | grep -q "healthy\|degraded"; then
        log_success "LaMa API отвечает"
        ((api_ok++))
    fi
    
    if curl -s http://localhost:3000 > /dev/null 2>&1; then
        log_success "Основное приложение отвечает"
        ((api_ok++))
    fi
    
    if curl -s http://localhost/lama/health > /dev/null 2>&1; then
        log_success "Nginx проксирование работает"
        ((api_ok++))
    fi
    
    echo ""
    log_info "📊 Результат установки:"
    echo "   Сервисы: ${services_ok}/3"
    echo "   API: ${api_ok}/3"
    
    return $((services_ok + api_ok))
}

# Показать финальную информацию
show_final_info() {
    local external_ip=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")
    
    echo ""
    echo "🎉 Color360 с LaMa AI установлен!"
    echo "================================="
    echo ""
    echo "🌐 Доступ:"
    echo "   Сайт: http://${external_ip}"
    echo "   Админ: http://${external_ip}/admin"
    echo "   LaMa API: http://${external_ip}/lama/health"
    echo ""
    echo "🔐 Админ вход:"
    echo "   Email: admin@color360.online"
    echo "   Пароль: Color360Admin2025!"
    echo ""
    echo "🛠️ Управление:"
    echo "   systemctl status color360-app color360-lama nginx"
    echo "   journalctl -u color360-lama -f"
    echo "   journalctl -u color360-app -f"
    echo ""
    echo "🎯 Тестирование LaMa:"
    echo "   curl http://localhost:5002/health"
    echo "   curl http://${external_ip}/lama/health"
    echo ""
    echo "✨ Готово к профессиональному удалению объектов!"
}

# Основная функция
main() {
    log_info "Начинаем полную переустановку Color360..."
    
    # Спрашиваем подтверждение
    echo -n "❓ Продолжить? Это удалит все старые данные! (y/N): "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Установка отменена"
        exit 0
    fi
    
    backup_if_exists
    complete_cleanup
    install_system_deps
    install_nodejs
    clone_fresh_project
    setup_lama_environment
    create_systemd_services
    setup_nginx
    start_services
    
    local result
    verify_installation
    result=$?
    
    show_final_info
    
    if [ $result -ge 5 ]; then
        log_success "🎉 Установка успешно завершена!"
    else
        log_warning "⚠️ Установка завершена с предупреждениями"
        log_info "Проверьте логи: journalctl -u color360-lama -u color360-app"
    fi
}

# Запуск
main "$@"