#!/bin/bash
# Установка полноценной LaMa Cleaner для качественного ретуша панорам

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
log_lama() { echo -e "${PURPLE}🤖 $1${NC}"; }

echo ""
echo -e "${PURPLE}🤖 УСТАНОВКА ПОЛНОЦЕННОЙ LAMA CLEANER${NC}"
echo "=============================================="
echo "🎯 Для качественного удаления объектов с панорам"
echo ""

if [ "$EUID" -ne 0 ]; then
    log_error "Запустите от root: sudo bash $0"
    exit 1
fi

WORK_DIR="/var/www/color360"

# Проверяем наличие основного проекта
if [ ! -d "$WORK_DIR" ]; then
    log_error "Color360 не найден в $WORK_DIR"
    log_info "Сначала установите основное приложение"
    exit 1
fi

cd "$WORK_DIR"

# Останавливаем старый сервис если запущен
if systemctl is-active --quiet color360-lama 2>/dev/null; then
    log_info "Остановка старого LaMa сервиса..."
    systemctl stop color360-lama
fi

# Устанавливаем системные зависимости
log_info "🔧 Установка системных зависимостей..."
apt-get update -qq
apt-get install -y python3 python3-pip python3-venv python3-dev 
apt-get install -y build-essential cmake git wget curl
apt-get install -y libopencv-dev python3-opencv
apt-get install -y libgl1-mesa-glx libglib2.0-0 libsm6 libxext6 libxrender-dev libgomp1

log_success "Системные зависимости установлены"

# Создаем чистое Python окружение
log_info "🐍 Создание специализированного Python окружения..."
cd "$WORK_DIR/lama"

if [ -d "lama_env" ]; then
    log_info "Удаление старого окружения..."
    rm -rf lama_env
fi

python3 -m venv lama_env || {
    log_error "Ошибка создания Python окружения"
    exit 1
}

source lama_env/bin/activate

# Обновляем pip до последней версии
log_info "Обновление pip и базовых инструментов..."
pip install --upgrade pip setuptools wheel

# Устанавливаем PyTorch СНАЧАЛА для CPU (для совместимости)
log_lama "Установка PyTorch CPU версии..."
pip install torch==2.1.0+cpu torchvision==0.16.0+cpu torchaudio==2.1.0+cpu \
    --index-url https://download.pytorch.org/whl/cpu

# Проверяем PyTorch
python -c "import torch; print('PyTorch:', torch.__version__, 'Device:', torch.device('cpu'))"

# Устанавливаем совместимые версии HuggingFace
log_lama "Установка совместимых HuggingFace библиотек..."
pip install "huggingface_hub==0.17.3"
pip install "transformers==4.27.4"
pip install "diffusers==0.16.1"
pip install "accelerate==0.20.3"

# Устанавливаем OpenCV и обработку изображений
log_lama "Установка библиотек обработки изображений..."
pip install "opencv-python-headless==4.8.1.78"
pip install "opencv-contrib-python-headless==4.8.1.78"
pip install "pillow==10.1.0"
pip install "numpy==1.24.3"
pip install "scipy==1.11.3"
pip install "scikit-image==0.21.0"

# Устанавливаем веб-фреймворк
log_lama "Установка веб-компонентов..."
pip install "fastapi==0.104.1"
pip install "uvicorn[standard]==0.24.0"
pip install "python-multipart==0.0.6"

# Устанавливаем LaMa Cleaner с зафиксированными версиями
log_lama "Установка LaMa Cleaner..."

# Сначала устанавливаем все зависимости отдельно
pip install "loguru==0.7.0"
pip install "omegaconf==2.3.0"
pip install "yacs==0.1.8"
pip install "einops==0.7.0"
pip install "timm==0.9.8"

# Теперь устанавливаем LaMa Cleaner
pip install "lama-cleaner==1.2.2" --no-deps --force-reinstall

# Устанавливаем недостающие зависимости вручную
pip install "flask==2.2.3"
pip install "flask-cors==4.0.0"
pip install "flask-socketio==5.3.6"
pip install "controlnet-aux==0.0.3"

# Дополнительные утилиты
log_lama "Установка дополнительных инструментов..."
pip install "psutil==5.9.6"
pip install "requests==2.31.0"
pip install "pyyaml==6.0.1"

# Тестируем импорт LaMa
log_lama "Тестирование LaMa Cleaner..."

python -c "
import sys
print('Python версия:', sys.version)

try:
    import torch
    print('✅ PyTorch:', torch.__version__)
    
    import cv2
    print('✅ OpenCV:', cv2.__version__)
    
    from PIL import Image
    print('✅ Pillow:', Image.__version__)
    
    import numpy as np
    print('✅ NumPy:', np.__version__)
    
    # Тестируем LaMa Cleaner
    import lama_cleaner
    print('✅ LaMa Cleaner:', lama_cleaner.__version__)
    
    # Тестируем модель менеджер
    from lama_cleaner.model_manager import ModelManager
    print('✅ ModelManager импортирован успешно')
    
    # Тестируем основные компоненты
    from lama_cleaner.model import LaMa
    print('✅ LaMa модель доступна')
    
    print()
    print('🎉 ВСЕ КОМПОНЕНТЫ LAMA УСПЕШНО УСТАНОВЛЕНЫ!')
    
except Exception as e:
    print('❌ Ошибка тестирования:', str(e))
    import traceback
    traceback.print_exc()
    sys.exit(1)
"

if [ $? -ne 0 ]; then
    log_error "Тестирование LaMa не прошло"
    deactivate
    exit 1
fi

log_success "LaMa Cleaner успешно установлен и протестирован"

# Создаем улучшенный сервис файл
log_info "⚙️ Создание оптимизированного systemd сервиса..."

cat > /etc/systemd/system/color360-lama.service << 'EOF'
[Unit]
Description=Color360 LaMa AI Inpainting Service
Documentation=https://github.com/Sanster/lama-cleaner
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/var/www/color360/lama
Environment=PYTHONPATH=/var/www/color360/lama
Environment=PYTHONUNBUFFERED=1
Environment=LAMA_MODEL=lama
Environment=LAMA_DEVICE=cpu
Environment=LAMA_CPU_OFFLOAD=true
Environment=LAMA_LOW_MEM=true
Environment=PORT=5002
Environment=HOST=127.0.0.1

# Увеличиваем лимиты памяти для обработки панорам
LimitNOFILE=65536
LimitNPROC=4096

# Оптимизация производительности
Nice=-5
IOSchedulingClass=2
IOSchedulingPriority=4

ExecStart=/var/www/color360/lama/lama_env/bin/python service.py
ExecReload=/bin/kill -HUP $MAINPID

# Настройки перезапуска
Restart=always
RestartSec=10
KillMode=mixed
TimeoutStartSec=60
TimeoutStopSec=30

# Логирование
StandardOutput=journal
StandardError=journal
SyslogIdentifier=color360-lama

[Install]
WantedBy=multi-user.target
EOF

deactivate

# Перезагружаем systemd и включаем сервис
systemctl daemon-reload
systemctl enable color360-lama

log_info "🚀 Запуск LaMa AI сервиса..."
systemctl start color360-lama

# Ждем полной загрузки модели (может занять время)
log_info "⏱️ Ожидание загрузки LaMa модели (может занять 1-2 минуты)..."

for i in {1..60}; do
    if systemctl is-active --quiet color360-lama; then
        if curl -s --connect-timeout 2 http://localhost:5002/health >/dev/null 2>&1; then
            break
        fi
    fi
    
    if [ $((i % 10)) -eq 0 ]; then
        log_info "Загрузка... ($i/60 сек)"
    fi
    
    sleep 1
done

# Проверяем финальный статус
if systemctl is-active --quiet color360-lama; then
    log_success "LaMa сервис запущен"
else
    log_error "LaMa сервис не запустился"
    log_info "Проверьте логи: journalctl -u color360-lama -f"
    exit 1
fi

# Тестируем API
log_info "🔍 Тестирование LaMa API..."

if curl -s --connect-timeout 10 http://localhost:5002/health >/dev/null 2>&1; then
    HEALTH_RESPONSE=$(curl -s http://localhost:5002/health 2>/dev/null)
    log_success "LaMa API отвечает"
    
    # Анализируем ответ
    if echo "$HEALTH_RESPONSE" | grep -q '"lama_available":true'; then
        log_success "🎯 LaMa модель полностью загружена и готова"
        LAMA_STATUS="✅ ПОЛНОФУНКЦИОНАЛЬНЫЙ"
    elif echo "$HEALTH_RESPONSE" | grep -q '"opencv_fallback":true'; then
        log_warning "LaMa работает в режиме OpenCV fallback"
        LAMA_STATUS="⚠️ БАЗОВЫЙ РЕЖИМ"
    else
        log_warning "Неопределенный статус LaMa"
        LAMA_STATUS="❓ НЕИЗВЕСТНО"
    fi
    
    echo "   Подробный ответ: $HEALTH_RESPONSE"
else
    log_error "LaMa API не отвечает"
    LAMA_STATUS="❌ НЕ РАБОТАЕТ"
fi

# Перезапускаем основное приложение для применения изменений
if systemctl is-active --quiet color360-app; then
    log_info "🔄 Перезапуск основного приложения Color360..."
    systemctl restart color360-app
    sleep 5
    
    if systemctl is-active --quiet color360-app; then
        log_success "Основное приложение перезапущено"
    else
        log_warning "Проблема с основным приложением"
    fi
fi

# Итоговый отчет
echo ""
echo -e "${PURPLE}🎉 УСТАНОВКА LAMA CLEANER ЗАВЕРШЕНА${NC}"
echo "=============================================="
echo ""
echo -e "${GREEN}📊 СТАТУС КОМПОНЕНТОВ:${NC}"
echo "   🤖 LaMa AI: $LAMA_STATUS"
echo "   🌐 API Endpoint: http://localhost:5002"
echo "   🔧 Сервис: color360-lama"
echo ""
echo -e "${GREEN}🎯 ВОЗМОЖНОСТИ РЕТУША:${NC}"
echo "   ✅ Удаление объектов с панорам"
echo "   ✅ Заполнение фона (inpainting)"
echo "   ✅ Обработка высокого разрешения"
echo "   ✅ Качественное восстановление текстур"
echo ""
echo -e "${GREEN}📋 КОМАНДЫ УПРАВЛЕНИЯ:${NC}"
echo "   systemctl status color360-lama    # Статус"
echo "   systemctl restart color360-lama   # Перезапуск"
echo "   journalctl -u color360-lama -f    # Логи в реальном времени"
echo "   curl http://localhost:5002/health # Проверка API"
echo ""
echo -e "${GREEN}🔗 ИСПОЛЬЗОВАНИЕ В COLOR360:${NC}"
echo "   1. Откройте панорамный тур"
echo "   2. Нажмите кнопку 'Ретуш'"
echo "   3. Выделите объект для удаления"
echo "   4. Нажмите 'Готово' - LaMa AI обработает изображение"
echo ""

if echo "$HEALTH_RESPONSE" | grep -q '"lama_available":true'; then
    echo -e "${GREEN}🚀 LaMa Cleaner готов для профессионального ретуша панорам!${NC}"
else
    echo -e "${YELLOW}⚠️ LaMa работает в базовом режиме. Для полного функционала может потребоваться больше ресурсов сервера.${NC}"
fi