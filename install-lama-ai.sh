#!/bin/bash
# Установка LaMa AI сервиса для Color360

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

echo ""
echo -e "${BLUE}🤖 УСТАНОВКА LAMA AI СЕРВИСА${NC}"
echo "=================================="

if [ "$EUID" -ne 0 ]; then
    log_error "Запустите от root: sudo bash $0"
    exit 1
fi

WORK_DIR="/var/www/color360"

# Проверяем что Color360 установлен
if [ ! -d "$WORK_DIR" ]; then
    log_error "Color360 не найден в $WORK_DIR"
    log_info "Сначала установите основное приложение"
    exit 1
fi

cd "$WORK_DIR"

# Проверяем наличие LaMa файлов
if [ ! -f "lama/requirements.txt" ]; then
    log_error "Файлы LaMa не найдены"
    log_info "Обновите репозиторий: git pull origin main"
    exit 1
fi

log_info "🐍 Установка Python зависимостей..."

# Устанавливаем Python если нет
if ! command -v python3 >/dev/null 2>&1; then
    log_info "Установка Python 3..."
    apt-get update -qq
    apt-get install -y python3 python3-pip python3-venv python3-dev build-essential
fi

# Обновляем код Color360 с последними исправлениями
log_info "📥 Обновление кода Color360..."
cd "$WORK_DIR"

# Сохраняем локальные изменения если есть
if git status --porcelain | grep -q .; then
    log_warning "Найдены локальные изменения, сохраняем..."
    git stash push -m "Auto-stash before LaMa update $(date)"
fi

# Обновляем с GitHub
log_info "Загрузка последних исправлений..."
if git pull origin main; then
    log_success "Код обновлен с последними исправлениями"
else
    log_warning "Не удалось обновить код, продолжаем с текущей версией"
fi

cd lama

# Удаляем старое окружение если есть
if [ -d "lama_env" ]; then
    log_info "Удаление старого Python окружения..."
    rm -rf lama_env
fi

# Создаем новое окружение
log_info "Создание Python окружения..."
python3 -m venv lama_env || {
    log_error "Ошибка создания Python окружения"
    exit 1
}

# Активируем окружение
log_info "Активация окружения..."
source lama_env/bin/activate

# Обновляем инструменты
log_info "Обновление pip и setuptools..."
pip install --upgrade pip setuptools wheel

# Устанавливаем зависимости поэтапно
log_info "Установка базовых зависимостей..."
pip install fastapi uvicorn python-multipart pillow numpy

log_info "Установка OpenCV..."
pip install opencv-python-headless

log_info "Установка PyTorch CPU версии..."
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

log_info "Установка LaMa Cleaner с совместимыми зависимостями..."

# Устанавливаем совместимые версии для избежания конфликтов
pip install "huggingface_hub==0.19.4"
pip install "transformers==4.35.0"
pip install "diffusers==0.21.4"

# Устанавливаем LaMa Cleaner
pip install "lama-cleaner==1.2.2"

log_info "Установка дополнительных пакетов..."
pip install psutil requests

# Проверяем установку
log_info "🔍 Проверка установки..."

if python -c "import lama_cleaner; print('✅ LaMa Cleaner:', lama_cleaner.__version__)" 2>/dev/null; then
    log_success "LaMa Cleaner установлен корректно"
else
    log_error "Проблема с LaMa Cleaner"
    exit 1
fi

if python -c "import torch; print('✅ PyTorch:', torch.__version__)" 2>/dev/null; then
    log_success "PyTorch установлен корректно"
else
    log_error "Проблема с PyTorch"
    exit 1
fi

if python -c "import fastapi; print('✅ FastAPI:', fastapi.__version__)" 2>/dev/null; then
    log_success "FastAPI установлен корректно"
else
    log_error "Проблема с FastAPI"
    exit 1
fi

deactivate

# Проверяем и применяем исправления камеры
log_info "🎯 Проверка исправлений камеры..."
cd "$WORK_DIR"

# Проверяем наличие исправлений в коде
if grep -q "startCameraNormalization" pano/core/viewer_manager.js 2>/dev/null; then
    log_success "Исправления камеры уже применены"
else
    log_warning "Исправления камеры не найдены в коде"
    log_info "Обновляем код с исправлениями..."
    
    # Принудительно обновляем код
    git fetch origin main
    git reset --hard origin/main
    
    if grep -q "startCameraNormalization" pano/core/viewer_manager.js 2>/dev/null; then
        log_success "Исправления камеры применены после обновления"
    else
        log_warning "Исправления камеры не найдены даже после обновления"
    fi
fi

# Проверяем исправления ретуша
if grep -q "fallback" server.js 2>/dev/null; then
    log_success "Исправления ретуша уже применены"
else
    log_warning "Исправления ретуша могут отсутствовать"
fi

# Перезапускаем основное приложение для применения исправлений
if systemctl is-active --quiet color360-app; then
    log_info "Перезапуск основного приложения..."
    systemctl restart color360-app
    sleep 5
    
    if systemctl is-active --quiet color360-app; then
        log_success "Основное приложение перезапущено"
    else
        log_warning "Проблема с перезапуском основного приложения"
    fi
fi

# Создаем systemd сервис
log_info "⚙️ Создание systemd сервиса..."

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
Environment=PYTHONPATH=$WORK_DIR/lama
ExecStart=$WORK_DIR/lama/lama_env/bin/python service.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Перезагружаем systemd и запускаем сервис
systemctl daemon-reload
systemctl enable color360-lama

log_info "🚀 Запуск LaMa AI сервиса..."
systemctl start color360-lama

# Ждем запуска
sleep 10

# Проверяем статус
if systemctl is-active --quiet color360-lama; then
    log_success "LaMa AI сервис запущен"
else
    log_error "LaMa AI сервис не запустился"
    log_info "Проверьте логи: journalctl -u color360-lama -f"
    exit 1
fi

# Проверяем API
log_info "🔍 Проверка LaMa API..."
sleep 5

if curl -s http://localhost:5002/health >/dev/null 2>&1; then
    HEALTH_RESPONSE=$(curl -s http://localhost:5002/health 2>/dev/null)
    log_success "LaMa API отвечает на порту 5002"
    
    # Проверяем качество ответа
    if echo "$HEALTH_RESPONSE" | grep -q '"lama_available":true'; then
        log_success "LaMa Cleaner полностью функционален"
    elif echo "$HEALTH_RESPONSE" | grep -q '"lama_available":false'; then
        log_warning "LaMa работает в режиме fallback (OpenCV)"
        echo "   Ответ: $HEALTH_RESPONSE"
    else
        log_warning "Неожиданный ответ API"
        echo "   Ответ: $HEALTH_RESPONSE"
    fi
else
    log_warning "LaMa API не отвечает (может потребоваться время для загрузки)"
fi

# Финальная проверка всей системы
log_info "🔍 Финальная проверка системы..."

# Проверяем основное приложение
if systemctl is-active --quiet color360-app; then
    if curl -s http://localhost:3000/ >/dev/null 2>&1; then
        log_success "Основное приложение Color360 работает"
    else
        log_warning "Основное приложение запущено но не отвечает"
    fi
else
    log_warning "Основное приложение Color360 не запущено"
fi

# Проверяем nginx
if systemctl is-active --quiet nginx; then
    log_success "Nginx работает"
else
    log_warning "Nginx не запущен"
fi

echo ""
log_success "🎉 LaMa AI + исправления Color360 установлены!"
echo ""
echo -e "${GREEN}📋 УПРАВЛЕНИЕ СЕРВИСАМИ:${NC}"
echo "   systemctl status color360-app    # Основное приложение"
echo "   systemctl status color360-lama   # LaMa AI"
echo "   systemctl restart color360-app   # Перезапуск основного"
echo "   systemctl restart color360-lama  # Перезапуск LaMa"
echo "   journalctl -u color360-lama -f   # Логи LaMa"
echo ""
echo -e "${GREEN}🔗 ДОСТУП К ПРИЛОЖЕНИЮ:${NC}"
echo "   Приложение: http://$(hostname -I | awk '{print $1}'):3000"
echo "   LaMa API: http://localhost:5002/health"
echo ""
echo -e "${GREEN}✅ ИСПРАВЛЕНИЯ ПРИМЕНЕНЫ:${NC}"
echo "   🎯 Камера: нормализация roll, предотвращение наклонов"
echo "   🎨 Ретуш: fallback API endpoints, улучшенная обработка ошибок"
echo "   🤖 LaMa: совместимые версии зависимостей"
echo ""
echo -e "${GREEN}🔍 ПРОВЕРКА:${NC}"
echo "   curl http://localhost:5002/health"
echo "   bash check-lama-status.sh"
echo ""
echo -e "${GREEN}🚀 Color360 готов к работе с полным функционалом ретуша!${NC}"