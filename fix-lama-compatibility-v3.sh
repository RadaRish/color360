#!/bin/bash

# Автоматическое исправление LaMa Cleaner - Полная версия v3
# Автоматически создает окружение и решает все проблемы совместимости

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
log_info() { echo -e "ℹ️  $1"; }
log_success() { echo -e "✅ $1"; }
log_warning() { echo -e "⚠️  $1"; }
log_error() { echo -e "❌ $1"; }
log_fix() { echo -e "🔧 $1"; }

# Функция для определения директории lama
find_lama_directory() {
    # Возможные пути к директории lama
    local paths=(
        "/var/www/color360/lama"
        "/var/www/html/color360/lama" 
        "/var/www/html/lama"
        "/opt/color360/lama"
        "/home/$(whoami)/color360/lama"
        "./lama"
        "../lama"
        "lama"
    )
    
    for path in "${paths[@]}"; do
        if [ -d "$path" ] || mkdir -p "$path" 2>/dev/null; then
            echo "$path"
            return 0
        fi
    done
    
    # Создаем директорию в текущем месте
    mkdir -p "lama"
    echo "lama"
}

# Функция создания виртуального окружения
create_virtual_env() {
    local lama_dir=$1
    
    log_info "Создание виртуального окружения в $lama_dir..."
    
    cd "$lama_dir"
    
    # Удаляем старое окружение если есть
    if [ -d "lama_env" ]; then
        log_warning "Удаление старого окружения..."
        rm -rf lama_env
    fi
    
    # Проверяем наличие python3
    if ! command -v python3 &> /dev/null; then
        log_error "Python3 не найден! Установите Python3 сначала."
        exit 1
    fi
    
    # Создаем новое окружение
    python3 -m venv lama_env
    
    if [ ! -d "lama_env" ]; then
        log_error "Не удалось создать виртуальное окружение"
        exit 1
    fi
    
    log_success "Виртуальное окружение создано"
}

# Функция для тестирования компонентов
test_lama_components() {
    local mode=$1
    log_info "Тестирование установленных компонентов..."
    
    # Тест NumPy
    NUMPY_VERSION=$(python -c "import numpy; print(numpy.__version__)" 2>/dev/null || echo "ERROR")
    if [[ "$NUMPY_VERSION" != "ERROR" ]]; then
        log_success "NumPy: $NUMPY_VERSION"
    else
        log_error "NumPy не работает"
        return 1
    fi
    
    # Тест PyTorch
    TORCH_TEST=$(python -c "
import warnings
warnings.filterwarnings('ignore')
try:
    import torch
    print(torch.__version__)
except Exception as e:
    print('ERROR:', str(e))
    exit(1)
" 2>/dev/null || echo "ERROR")
    
    if [[ "$TORCH_TEST" != ERROR* ]]; then
        log_success "PyTorch: $TORCH_TEST"
    else
        log_error "PyTorch не работает: $TORCH_TEST"
        return 1
    fi
    
    # Тест OpenCV
    CV_TEST=$(python -c "
import warnings
warnings.filterwarnings('ignore')
try:
    import cv2
    print(cv2.__version__)
except Exception as e:
    print('ERROR:', str(e))
    exit(1)
" 2>/dev/null || echo "ERROR")
    
    if [[ "$CV_TEST" != ERROR* ]]; then
        log_success "OpenCV: $CV_TEST"
        
        if [[ "$mode" == "full" ]]; then
            # Тест LaMa Cleaner (только для полного режима)
            LAMA_TEST=$(python -c "
import warnings
warnings.filterwarnings('ignore')
try:
    from lama_cleaner import model_manager
    print('OK')
except Exception as e:
    print('ERROR:', str(e))
    exit(1)
" 2>/dev/null || echo "ERROR")
            
            if [[ "$LAMA_TEST" != ERROR* ]]; then
                log_success "LaMa Cleaner: доступен"
                return 0
            else
                log_error "LaMa Cleaner не работает: $LAMA_TEST"
                return 1
            fi
        else
            return 0
        fi
    else
        log_error "OpenCV не работает: $CV_TEST"
        return 1
    fi
}

# Функция полной очистки окружения
clean_environment() {
    log_info "Полная очистка Python окружения..."
    
    # Удаляем все проблемные пакеты
    pip uninstall -y numpy scipy torch torchvision torchaudio \
        opencv-python opencv-python-headless opencv-contrib-python-headless \
        scikit-image pillow lama-cleaner controlnet-aux \
        gradio rich markdown-it-py pygments 2>/dev/null || true
    
    # Очищаем кэш pip
    pip cache purge 2>/dev/null || true
    
    log_success "Окружение очищено"
}

# Функция установки базовых зависимостей в правильном порядке
install_compatible_base() {
    log_info "Установка совместимых базовых зависимостей..."
    
    # Обновляем pip
    pip install --upgrade pip==23.3.1
    
    # Устанавливаем numpy 1.24.3 первым (критически важно)
    log_info "Установка NumPy 1.24.3 (совместимая версия)..."
    pip install "numpy==1.24.3" --no-deps --force-reinstall
    
    # Scipy совместимая с numpy 1.24.3
    log_info "Установка SciPy 1.10.1..."
    pip install "scipy==1.10.1"
    
    # Pillow стабильная версия
    log_info "Установка Pillow 9.5.0..."
    pip install "pillow==9.5.0"
    
    # PyTorch старая стабильная версия (совместимая с numpy 1.24.3)
    log_info "Установка PyTorch 1.13.1 (совместимая версия)..."
    pip install torch==1.13.1+cpu torchvision==0.14.1+cpu torchaudio==0.13.1+cpu \
        --index-url https://download.pytorch.org/whl/cpu
    
    # OpenCV совместимая версия (пробуем разные версии)
    log_info "Установка OpenCV..."
    pip install "opencv-python-headless==4.8.0.76" || \
    pip install "opencv-python-headless==4.8.1.78" || \
    pip install "opencv-python-headless==4.7.0.72" || \
    pip install "opencv-python-headless" || {
        log_warning "OpenCV headless не установился, пробуем обычный opencv-python"
        pip install "opencv-python==4.8.0.76" || \
        pip install "opencv-python==4.8.1.78" || \
        pip install "opencv-python"
    }
    
    log_success "Базовые зависимости установлены"
}

# Функция установки веб-сервера
install_web_server() {
    log_info "Установка веб-сервера..."
    
    pip install "fastapi==0.100.1"
    pip install "uvicorn[standard]==0.22.0"
    pip install "python-multipart==0.0.6"
    pip install "psutil==5.9.5"
    pip install "requests==2.31.0"
    pip install "pyyaml==6.0.1"
    
    log_success "Веб-сервер установлен"
}

# Функция попытки установки полного LaMa
try_install_full_lama() {
    log_fix "Попытка установки полного LaMa Cleaner..."
    
    # Дополнительные зависимости для LaMa
    log_info "Установка зависимостей LaMa Cleaner..."
    
    # Rich с совместимыми зависимостями
    pip install "rich==13.3.0"
    pip install "markdown-it-py==2.2.0" 
    pip install "pygments==2.15.0"
    
    # Дополнительные зависимости
    pip install "loguru==0.7.0"
    pip install "omegaconf==2.3.0"
    pip install "yacs==0.1.8" 
    pip install "einops==0.6.1"
    
    # Timm совместимая версия
    pip install "timm==0.9.2"
    
    # Флинт, но без градio (может вызывать конфликты)
    pip install "flaskwebgui==0.3.5" || log_warning "FlaskWebGUI пропущен"
    pip install "piexif==1.1.3" || log_warning "Piexif пропущен"
    
    # Попытка установки LaMa Cleaner
    log_info "Установка LaMa Cleaner..."
    pip install "lama-cleaner==1.2.2" --no-deps || {
        log_warning "Прямая установка не удалась, пробуем альтернативный способ..."
        return 1
    }
    
    return 0
}

# Функция создания service.py для базового режима
create_basic_service() {
    log_info "Создание базового сервиса без LaMa..."
    
    cat > service.py << 'EOF'
#!/usr/bin/env python3
"""
Базовый сервис ретуши без LaMa Cleaner
Использует простую обработку OpenCV для демонстрации
"""

import os
import sys
import cv2
import numpy as np
from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import traceback
from pathlib import Path
import tempfile
import base64
from io import BytesIO
from PIL import Image

app = FastAPI(title="Basic Retouch Service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"], 
    allow_headers=["*"],
)

@app.get("/")
async def root():
    return {
        "status": "running",
        "mode": "basic_opencv",
        "message": "Базовый сервис ретуши. LaMa недоступен, используется OpenCV."
    }

@app.get("/health")
async def health():
    return {"status": "healthy", "mode": "basic"}

@app.post("/inpaint")
async def inpaint_image(
    image: UploadFile = File(...),
    mask: UploadFile = File(...),
    model: str = Form(default="opencv")
):
    """Базовая ретушь с использованием OpenCV inpainting"""
    
    try:
        # Читаем изображение
        image_bytes = await image.read()
        image_array = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(image_array, cv2.IMREAD_COLOR)
        
        if img is None:
            raise HTTPException(status_code=400, detail="Не удалось прочитать изображение")
        
        # Читаем маску
        mask_bytes = await mask.read()
        mask_array = np.frombuffer(mask_bytes, np.uint8)
        mask_img = cv2.imdecode(mask_array, cv2.IMREAD_GRAYSCALE)
        
        if mask_img is None:
            raise HTTPException(status_code=400, detail="Не удалось прочитать маску")
        
        # Приводим размеры к одинаковым
        h, w = img.shape[:2]
        mask_img = cv2.resize(mask_img, (w, h))
        
        # Применяем OpenCV inpainting
        # Используем TELEA алгоритм как более быстрый
        result = cv2.inpaint(img, mask_img, 3, cv2.INPAINT_TELEA)
        
        # Сохраняем результат
        with tempfile.NamedTemporaryFile(suffix='.jpg', delete=False) as tmp:
            cv2.imwrite(tmp.name, result, [cv2.IMWRITE_JPEG_QUALITY, 95])
            return FileResponse(
                tmp.name,
                media_type="image/jpeg",
                filename="retouched.jpg"
            )
    
    except Exception as e:
        print(f"Ошибка при обработке: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Ошибка обработки: {str(e)}")

if __name__ == "__main__":
    print("🔧 Запуск базового сервиса ретуши (OpenCV режим)")
    print("📍 Сервис будет доступен на: http://localhost:8080")
    print("⚠️  LaMa Cleaner недоступен, используется базовый OpenCV inpainting")
    
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8080,
        log_level="info"
    )
EOF

    chmod +x service.py
    log_success "Базовый сервис создан"
}

# Функция создания полного service.py с LaMa
create_full_service() {
    log_info "Создание полного сервиса с LaMa..."
    
    cat > service.py << 'EOF'
#!/usr/bin/env python3
"""
Полный сервис ретуши с LaMa Cleaner
"""

import os
import sys
import warnings
warnings.filterwarnings('ignore')

# Устанавливаем переменные окружения до импорта
os.environ['PYTORCH_ENABLE_MPS_FALLBACK'] = '1'
os.environ['CUDA_VISIBLE_DEVICES'] = ''

import cv2
import numpy as np
from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import traceback
from pathlib import Path
import tempfile

# Пробуем импортировать LaMa
LAMA_AVAILABLE = False
try:
    from lama_cleaner.model_manager import ModelManager
    from lama_cleaner.schema import Config, HDStrategy, LDMSampler
    LAMA_AVAILABLE = True
    print("✅ LaMa Cleaner успешно загружен")
except Exception as e:
    print(f"⚠️  LaMa Cleaner недоступен: {e}")
    print("🔄 Будет использоваться OpenCV fallback")

app = FastAPI(title="Professional Retouch Service", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"], 
    allow_headers=["*"],
)

# Глобальная переменная для модели
model_manager = None

def init_lama():
    """Инициализация LaMa модели"""
    global model_manager
    if LAMA_AVAILABLE and model_manager is None:
        try:
            model_manager = ModelManager(
                name="lama",
                device="cpu",
                no_half=True
            )
            print("✅ LaMa модель инициализирована")
            return True
        except Exception as e:
            print(f"❌ Ошибка инициализации LaMa: {e}")
            return False
    return LAMA_AVAILABLE

@app.on_event("startup")
async def startup_event():
    init_lama()

@app.get("/")
async def root():
    mode = "full_lama" if LAMA_AVAILABLE and model_manager else "basic_opencv"
    return {
        "status": "running",
        "mode": mode,
        "lama_available": LAMA_AVAILABLE,
        "model_loaded": model_manager is not None
    }

@app.get("/health")
async def health():
    return {
        "status": "healthy", 
        "lama_available": LAMA_AVAILABLE,
        "model_ready": model_manager is not None
    }

def opencv_inpaint(img, mask):
    """Fallback OpenCV inpainting"""
    return cv2.inpaint(img, mask, 3, cv2.INPAINT_TELEA)

def lama_inpaint(img, mask):
    """LaMa inpainting"""
    if not LAMA_AVAILABLE or model_manager is None:
        return opencv_inpaint(img, mask)
    
    try:
        config = Config(
            ldm_steps=20,
            ldm_sampler=LDMSampler.plms,
            hd_strategy=HDStrategy.RESIZE,
            hd_strategy_resize_limit=2048,
        )
        
        result = model_manager(img, mask, config)
        return result
        
    except Exception as e:
        print(f"LaMa ошибка, используем OpenCV: {e}")
        return opencv_inpaint(img, mask)

@app.post("/inpaint")
async def inpaint_image(
    image: UploadFile = File(...),
    mask: UploadFile = File(...),
    model: str = Form(default="lama")
):
    """Профессиональная ретушь изображений"""
    
    try:
        # Читаем изображение
        image_bytes = await image.read()
        image_array = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(image_array, cv2.IMREAD_COLOR)
        
        if img is None:
            raise HTTPException(status_code=400, detail="Не удалось прочитать изображение")
        
        # Читаем маску
        mask_bytes = await mask.read()
        mask_array = np.frombuffer(mask_bytes, np.uint8)
        mask_img = cv2.imdecode(mask_array, cv2.IMREAD_GRAYSCALE)
        
        if mask_img is None:
            raise HTTPException(status_code=400, detail="Не удалось прочитать маску")
        
        # Приводим размеры
        h, w = img.shape[:2]
        mask_img = cv2.resize(mask_img, (w, h))
        
        # Выбираем алгоритм
        if model == "lama" and LAMA_AVAILABLE:
            result = lama_inpaint(img, mask_img)
        else:
            result = opencv_inpaint(img, mask_img)
        
        # Сохраняем результат
        with tempfile.NamedTemporaryFile(suffix='.jpg', delete=False) as tmp:
            cv2.imwrite(tmp.name, result, [cv2.IMWRITE_JPEG_QUALITY, 95])
            return FileResponse(
                tmp.name,
                media_type="image/jpeg", 
                filename="retouched.jpg"
            )
    
    except Exception as e:
        print(f"Ошибка при обработке: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Ошибка обработки: {str(e)}")

if __name__ == "__main__":
    mode_name = "LaMa AI" if LAMA_AVAILABLE else "OpenCV"
    print(f"🔧 Запуск профессионального сервиса ретуши ({mode_name} режим)")
    print("📍 Сервис будет доступен на: http://localhost:8080")
    
    uvicorn.run(
        app,
        host="0.0.0.0", 
        port=8080,
        log_level="info"
    )
EOF

    chmod +x service.py
    log_success "Полный сервис создан"
}

# Функция создания start скрипта
create_start_script() {
    log_info "Создание скрипта запуска..."
    
    cat > start_lama.sh << 'EOF'
#!/bin/bash

# Скрипт запуска LaMa сервиса

LAMA_DIR="/var/www/color360/lama"

# Если не в нужной директории, переходим
if [ ! -f "service.py" ]; then
    if [ -d "$LAMA_DIR" ]; then
        cd "$LAMA_DIR"
    else
        echo "❌ Не найден service.py и директория $LAMA_DIR"
        exit 1
    fi
fi

# Активируем окружение
if [ -d "lama_env" ]; then
    source lama_env/bin/activate
    echo "✅ Виртуальное окружение активировано"
else
    echo "❌ Виртуальное окружение не найдено"
    exit 1
fi

# Проверяем service.py
if [ ! -f "service.py" ]; then
    echo "❌ Файл service.py не найден"
    exit 1
fi

echo "🚀 Запуск LaMa сервиса..."
python service.py
EOF

    chmod +x start_lama.sh
    log_success "Скрипт запуска создан"
}

# MAIN EXECUTION
echo
echo "🔧 АВТОМАТИЧЕСКОЕ ИСПРАВЛЕНИЕ LAMA CLEANER v3"
echo "=============================================="
echo "Полная автоматическая установка с созданием окружения"
echo

# Находим или создаем директорию lama
LAMA_DIR=$(find_lama_directory)
log_info "Использование директории: $LAMA_DIR"

# Создаем виртуальное окружение если его нет
if [ ! -d "$LAMA_DIR/lama_env" ]; then
    create_virtual_env "$LAMA_DIR"
else
    log_info "Виртуальное окружение уже существует"
    cd "$LAMA_DIR"
fi

# Активируем окружение
log_info "Активация Python окружения..."
source lama_env/bin/activate

# Полная очистка и переустановка
clean_environment

# Устанавливаем базовые зависимости
install_compatible_base

# Проверяем базовые компоненты
if ! test_lama_components "basic"; then
    log_error "Критическая ошибка: не удалось установить базовые компоненты"
    exit 1
fi

# Устанавливаем веб-сервер
install_web_server

# Пробуем установить полный LaMa
if try_install_full_lama && test_lama_components "full"; then
    log_success "🎉 ПОЛНЫЙ LAMA CLEANER УСПЕШНО УСТАНОВЛЕН!"
    create_full_service
    LAMA_MODE="full"
else
    log_warning "Полный LaMa недоступен, настраиваем базовый режим"
    create_basic_service
    LAMA_MODE="basic"
fi

# Создаем скрипт запуска
create_start_script

# Финальные инструкции
echo
echo "✅ УСТАНОВКА ЗАВЕРШЕНА!"
echo "======================="

if [ "$LAMA_MODE" = "full" ]; then
    echo "🎉 Режим: ПОЛНЫЙ LaMa AI Cleaner"
    echo "✨ Профессиональное удаление объектов с панорам"
else
    echo "⚠️  Режим: Базовый OpenCV inpainting"  
    echo "📝 LaMa недоступен, используется упрощенная обработка"
fi

echo
echo "📂 Все файлы созданы в: $LAMA_DIR"
echo
echo "🚀 ЗАПУСК СЕРВИСА:"
echo "bash $LAMA_DIR/start_lama.sh"
echo
echo "🔗 ИЛИ РУЧНОЙ ЗАПУСК:"
echo "cd $LAMA_DIR"
echo "source lama_env/bin/activate"
echo "python service.py"
echo
echo "🌐 Сервис будет доступен на: http://localhost:8080"
echo "🔗 Тест API: curl http://localhost:8080/health"
echo

log_success "Готово к использованию!"