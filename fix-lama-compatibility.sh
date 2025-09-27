#!/bin/bash
# Автоматическое исправление проблем совместимости LaMa Cleaner

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
log_fix() { echo -e "${PURPLE}🔧 $1${NC}"; }

echo ""
echo -e "${PURPLE}🔧 АВТОМАТИЧЕСКОЕ ИСПРАВЛЕНИЕ LAMA CLEANER${NC}"
echo "=============================================="
echo "Исправляет проблемы совместимости NumPy и зависимостей"
echo ""

if [ "$EUID" -ne 0 ]; then
    log_error "Запустите от root: sudo bash $0"
    exit 1
fi

WORK_DIR="/var/www/color360"
LAMA_DIR="$WORK_DIR/lama"

# Проверяем наличие проекта
if [ ! -d "$LAMA_DIR" ]; then
    log_error "LaMa директория не найдена: $LAMA_DIR"
    exit 1
fi

cd "$LAMA_DIR"

# Останавливаем сервис если запущен
if systemctl is-active --quiet color360-lama 2>/dev/null; then
    log_info "Остановка LaMa сервиса..."
    systemctl stop color360-lama
fi

# Функция проверки работоспособности
test_lama_components() {
    local mode="$1"  # "full" или "basic"
    
    python -c "
import sys
success = True

try:
    import numpy as np
    print('✅ NumPy:', np.__version__)
    
    import torch
    print('✅ PyTorch:', torch.__version__)
    
    import cv2
    print('✅ OpenCV:', cv2.__version__)
    
    from PIL import Image
    print('✅ Pillow:', Image.__version__)
    
    if '$mode' == 'full':
        import rich
        print('✅ Rich:', rich.__version__)
        
        import lama_cleaner
        print('✅ LaMa Cleaner:', lama_cleaner.__version__)
        
        from lama_cleaner.model_manager import ModelManager
        print('✅ ModelManager: OK')
        
        print('🎉 ПОЛНЫЙ LAMA CLEANER РАБОТАЕТ!')
    else:
        print('🎯 БАЗОВЫЕ КОМПОНЕНТЫ РАБОТАЮТ!')
    
except Exception as e:
    print('❌ Ошибка:', str(e))
    success = False

sys.exit(0 if success else 1)
"
    return $?
}

# Функция установки полной версии
install_full_lama() {
    log_fix "Попытка установки полного LaMa Cleaner..."
    
    # Исправляем NumPy
    log_info "Исправление проблемы NumPy 2.x..."
    pip uninstall numpy -y 2>/dev/null || true
    pip install "numpy==1.24.3"
    
    # Устанавливаем недостающие зависимости
    log_info "Установка недостающих зависимостей..."
    pip install "rich==13.7.0"
    pip install "markdown-it-py==3.0.0"
    pip install "pygments==2.17.2"
    
    # Переустанавливаем PyTorch с правильными зависимостями
    log_info "Переустановка PyTorch..."
    pip uninstall torch torchvision torchaudio -y 2>/dev/null || true
    pip install torch==2.1.0+cpu torchvision==0.16.0+cpu torchaudio==2.1.0+cpu \
        --index-url https://download.pytorch.org/whl/cpu --force-reinstall
    
    # Переустанавливаем OpenCV
    log_info "Переустановка OpenCV..."
    pip uninstall opencv-python opencv-python-headless opencv-contrib-python-headless -y 2>/dev/null || true
    pip install "opencv-python-headless==4.8.1.78"
    
    # Переустанавливаем scikit-image
    log_info "Переустановка scikit-image..."
    pip uninstall scikit-image -y 2>/dev/null || true
    pip install "scikit-image==0.21.0" --force-reinstall
    
    # Дополнительные зависимости LaMa
    pip install "loguru==0.7.0"
    pip install "omegaconf==2.3.0" 
    pip install "yacs==0.1.8"
    pip install "einops==0.7.0"
    pip install "timm==0.9.8"
    
    # Тестируем
    if test_lama_components "full"; then
        log_success "Полный LaMa Cleaner успешно установлен!"
        return 0
    else
        log_warning "Полная установка не удалась, пробуем базовый режим..."
        return 1
    fi
}

# Функция установки базовой версии
install_basic_lama() {
    log_fix "Установка базового режима LaMa..."
    
    # Полная очистка окружения
    log_info "Создание нового чистого окружения..."
    cd "$LAMA_DIR"
    rm -rf lama_env
    python3 -m venv lama_env
    source lama_env/bin/activate
    
    # Устанавливаем строго совместимые версии
    pip install --upgrade pip==23.3.1
    
    # Базовые математические библиотеки (старые стабильные версии)
    log_info "Установка базовых библиотек..."
    pip install "numpy==1.24.3"
    pip install "scipy==1.10.1"
    pip install "pillow==9.5.0"
    
    # PyTorch старой стабильной версии
    log_info "Установка PyTorch 1.13..."
    pip install torch==1.13.1+cpu torchvision==0.14.1+cpu torchaudio==0.13.1+cpu \
        --index-url https://download.pytorch.org/whl/cpu
    
    # OpenCV совместимая версия
    pip install "opencv-python-headless==4.7.1.72"
    
    # Веб компоненты
    log_info "Установка веб-сервера..."
    pip install "fastapi==0.100.1"
    pip install "uvicorn[standard]==0.22.0"
    pip install "python-multipart==0.0.5"
    
    # Дополнительные утилиты
    pip install "psutil==5.9.5"
    pip install "requests==2.30.0"
    pip install "pyyaml==6.0"
    
    # Тестируем базовые компоненты
    if test_lama_components "basic"; then
        log_success "Базовый режим успешно установлен!"
        return 0
    else
        log_error "Даже базовая установка не удалась"
        return 1
    fi
}

# Основная логика
log_info "Активация Python окружения..."

if [ -d "lama_env" ]; then
    source lama_env/bin/activate
    
    log_info "Проверка текущего состояния..."
    
    # Сначала пробуем исправить текущее окружение
    if install_full_lama; then
        LAMA_MODE="full"
    else
        log_warning "Полная версия не работает, устанавливаем базовый режим..."
        if install_basic_lama; then
            LAMA_MODE="basic"
        else
            log_error "Установка не удалась"
            exit 1
        fi
    fi
else
    log_warning "Python окружение не найдено, создаем базовый режим..."
    if install_basic_lama; then
        LAMA_MODE="basic"
    else
        log_error "Создание базового режима не удалось"
        exit 1
    fi
fi

# Обновляем service.py для поддержки базового режима
log_fix "Обновление service.py..."

cat > service.py << 'EOF'
#!/usr/bin/env python3
"""
LaMa Inpainting Service для Color360 - Адаптивный режим
Автоматически переключается между полным LaMa и OpenCV fallback
"""

import os
import io
import logging
import traceback
from typing import Optional
import asyncio
from PIL import Image
import numpy as np
import cv2
from fastapi import FastAPI, File, UploadFile, HTTPException, Form
from fastapi.responses import Response, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

# Настройка логирования
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger("LaMa-Adaptive")

app = FastAPI(title="LaMa Adaptive Service", version="3.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# Глобальные переменные
LAMA_MODEL = None
LAMA_AVAILABLE = False
DEVICE = "cpu"

def check_lama_availability():
    """Проверка доступности LaMa Cleaner"""
    global LAMA_AVAILABLE, LAMA_MODEL
    
    try:
        from lama_cleaner.model_manager import ModelManager
        
        LAMA_MODEL = ModelManager(
            name="lama",
            device=DEVICE,
            no_half=True,
            cpu_offload=True,
            disable_nsfw=True,
        )
        
        LAMA_AVAILABLE = True
        logger.info("✅ LaMa Cleaner успешно загружен")
        return True
        
    except Exception as e:
        logger.warning(f"⚠️ LaMa Cleaner недоступен: {e}")
        logger.info("🔧 Работаем в режиме OpenCV fallback")
        LAMA_AVAILABLE = False
        return False

def opencv_inpainting(image: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Базовый inpainting через OpenCV"""
    try:
        # Используем INPAINT_TELEA - лучший алгоритм OpenCV
        result = cv2.inpaint(image, mask, 5, cv2.INPAINT_TELEA)
        
        # Дополнительное сглаживание для панорам
        kernel = np.ones((3,3), np.uint8)
        smooth_mask = cv2.dilate(mask, kernel, iterations=2)
        smooth_mask = cv2.GaussianBlur(smooth_mask, (5,5), 0)
        smooth_mask = smooth_mask.astype(np.float32) / 255.0
        
        # Смешиваем с оригиналом для плавных переходов
        smooth_mask = np.expand_dims(smooth_mask, axis=2)
        result = result * smooth_mask + image * (1 - smooth_mask)
        
        return result.astype(np.uint8)
        
    except Exception as e:
        logger.error(f"Ошибка OpenCV inpainting: {e}")
        return image

def lama_inpainting(image: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Профессиональный inpainting через LaMa"""
    try:
        from lama_cleaner.schema import Config, HDStrategy
        
        # Конвертируем в PIL
        pil_image = Image.fromarray(image)
        pil_mask = Image.fromarray(mask)
        
        # Конфигурация для панорам
        config = Config(
            hd_strategy=HDStrategy.CROP,
            hd_strategy_crop_margin=64,
            hd_strategy_crop_trigger_size=1024,
            hd_strategy_resize_limit=2048,
        )
        
        # Выполняем inpainting
        result = LAMA_MODEL(pil_image, pil_mask, config)
        
        return np.array(result)
        
    except Exception as e:
        logger.error(f"Ошибка LaMa inpainting: {e}")
        logger.info("Переключаемся на OpenCV fallback")
        return opencv_inpainting(image, mask)

@app.get("/health")
async def health():
    """Проверка здоровья сервиса"""
    try:
        import psutil
        memory = psutil.virtual_memory()
        
        return {
            "status": "healthy" if LAMA_AVAILABLE else "degraded",
            "service": "lama-adaptive",
            "version": "3.0.0",
            "lama_available": LAMA_AVAILABLE,
            "opencv_available": True,
            "device": DEVICE,
            "memory": {
                "available_mb": memory.available // 1024 // 1024,
                "used_percent": memory.percent
            },
            "features": {
                "lama_inpainting": LAMA_AVAILABLE,
                "opencv_fallback": True,
                "adaptive_mode": True
            }
        }
    except Exception as e:
        return {"status": "error", "error": str(e)}

@app.post("/inpaint")
async def inpaint(
    image: UploadFile = File(...),
    mask: UploadFile = File(...),
):
    """Адаптивный inpainting endpoint"""
    try:
        # Читаем изображения
        image_bytes = await image.read()
        mask_bytes = await mask.read()
        
        # Конвертируем в PIL
        pil_image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        pil_mask = Image.open(io.BytesIO(mask_bytes)).convert("L")
        
        # Конвертируем в numpy
        np_image = np.array(pil_image)
        np_mask = np.array(pil_mask)
        
        logger.info(f"Обработка изображения {np_image.shape}, маска {np_mask.shape}")
        
        # Выбираем метод обработки
        if LAMA_AVAILABLE:
            logger.info("Использование LaMa Cleaner")
            result = lama_inpainting(np_image, np_mask)
            method = "lama"
        else:
            logger.info("Использование OpenCV fallback")
            result = opencv_inpainting(np_image, np_mask)
            method = "opencv"
        
        # Конвертируем результат обратно в изображение
        result_image = Image.fromarray(result)
        
        # Сохраняем в буфер
        output_buffer = io.BytesIO()
        result_image.save(output_buffer, format="JPEG", quality=95)
        output_buffer.seek(0)
        
        return Response(
            content=output_buffer.getvalue(),
            media_type="image/jpeg",
            headers={
                "X-Inpaint-Method": method,
                "X-Service-Mode": "lama" if LAMA_AVAILABLE else "opencv-fallback"
            }
        )
        
    except Exception as e:
        logger.error(f"Ошибка inpainting: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    logger.info("🚀 Запуск LaMa Adaptive Service...")
    
    # Проверяем доступность LaMa
    check_lama_availability()
    
    # Запускаем сервер
    uvicorn.run(
        app,
        host="127.0.0.1",
        port=5002,
        log_level="info"
    )
EOF

deactivate

# Создаем адаптивный systemd сервис
log_fix "Создание адаптивного systemd сервиса..."

cat > /etc/systemd/system/color360-lama.service << 'EOF'
[Unit]
Description=Color360 LaMa Adaptive Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/color360/lama
Environment=PYTHONPATH=/var/www/color360/lama
Environment=PYTHONUNBUFFERED=1
ExecStart=/var/www/color360/lama/lama_env/bin/python service.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Перезагружаем и запускаем сервис
systemctl daemon-reload
systemctl enable color360-lama

log_info "🚀 Запуск адаптивного LaMa сервиса..."
systemctl start color360-lama

# Ждем запуска
sleep 10

# Проверяем результат
log_info "🔍 Проверка результата..."

if systemctl is-active --quiet color360-lama; then
    log_success "Сервис запущен"
    
    if curl -s --connect-timeout 5 http://localhost:5002/health >/dev/null 2>&1; then
        HEALTH_RESPONSE=$(curl -s http://localhost:5002/health 2>/dev/null)
        log_success "API отвечает"
        
        # Анализируем режим работы
        if echo "$HEALTH_RESPONSE" | grep -q '"lama_available":true'; then
            MODE_STATUS="🎯 ПОЛНОФУНКЦИОНАЛЬНЫЙ LaMa"
        elif echo "$HEALTH_RESPONSE" | grep -q '"opencv_available":true'; then
            MODE_STATUS="🔧 OpenCV FALLBACK"
        else
            MODE_STATUS="❓ НЕИЗВЕСТНЫЙ РЕЖИМ"
        fi
    else
        log_error "API не отвечает"
        MODE_STATUS="❌ НЕ РАБОТАЕТ"
    fi
else
    log_error "Сервис не запустился"
    MODE_STATUS="❌ НЕ ЗАПУЩЕН"
fi

# Финальный отчет
echo ""
echo -e "${PURPLE}🎉 АВТОМАТИЧЕСКОЕ ИСПРАВЛЕНИЕ ЗАВЕРШЕНО${NC}"
echo "=============================================="
echo ""
echo -e "${GREEN}📊 РЕЗУЛЬТАТ:${NC}"
echo "   🤖 LaMa режим: $MODE_STATUS"
echo "   🌐 API: http://localhost:5002"
echo "   📋 Сервис: color360-lama"
echo ""

if [ "$MODE_STATUS" != "❌ НЕ РАБОТАЕТ" ] && [ "$MODE_STATUS" != "❌ НЕ ЗАПУЩЕН" ]; then
    echo -e "${GREEN}✅ LaMa готов к работе!${NC}"
    echo ""
    echo -e "${GREEN}🎯 Функции ретуша:${NC}"
    if echo "$HEALTH_RESPONSE" | grep -q '"lama_available":true'; then
        echo "   ✅ Профессиональное удаление объектов (LaMa AI)"
        echo "   ✅ HD обработка до 2048px" 
        echo "   ✅ Качественное восстановление текстур"
    else
        echo "   ✅ Базовое удаление объектов (OpenCV)"
        echo "   ✅ Быстрая обработка"
        echo "   ✅ Стабильная работа"
    fi
else
    echo -e "${RED}❌ Требуется ручная диагностика${NC}"
    echo "   Проверьте логи: journalctl -u color360-lama -f"
fi

echo ""
echo -e "${BLUE}📋 КОМАНДЫ УПРАВЛЕНИЯ:${NC}"
echo "   systemctl status color360-lama"
echo "   systemctl restart color360-lama"
echo "   curl http://localhost:5002/health"