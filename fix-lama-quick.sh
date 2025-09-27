#!/bin/bash

# Быстрое исправление проблем LaMa сервиса

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "ℹ️  $1"; }
log_success() { echo -e "✅ $1"; }
log_warning() { echo -e "⚠️  $1"; }
log_error() { echo -e "❌ $1"; }
log_fix() { echo -e "🔧 $1"; }

echo
echo "🔧 БЫСТРОЕ ИСПРАВЛЕНИЕ LAMA СЕРВИСА"
echo "=================================="

# Проверяем директорию LaMa
if [ ! -d "/var/www/color360/lama" ]; then
    log_error "Директория LaMa не найдена!"
    exit 1
fi

cd /var/www/color360/lama

# 1. Останавливаем все процессы LaMa
log_info "Остановка всех процессов LaMa..."
pkill -f "service.py" 2>/dev/null || true
pkill -f "uvicorn.*8080" 2>/dev/null || true
pkill -f "uvicorn.*5002" 2>/dev/null || true
sleep 2

# Освобождаем порты принудительно
for port in 5002 8080; do
    pid=$(lsof -ti:$port 2>/dev/null || echo "")
    if [ ! -z "$pid" ]; then
        log_warning "Принудительно освобождаем порт $port (PID: $pid)"
        kill -9 $pid 2>/dev/null || true
    fi
done

log_success "Все процессы остановлены"

# 2. Проверяем виртуальное окружение
if [ ! -d "lama_env" ]; then
    log_error "Виртуальное окружение не найдено! Запустите fix-lama-compatibility-v3.sh"
    exit 1
fi

log_info "Активация виртуального окружения..."
source lama_env/bin/activate

# 3. Проверяем и устанавливаем недостающие зависимости
log_info "Проверка зависимостей..."

missing_deps=()

# Проверяем критически важные пакеты
if ! python -c "import diffusers" 2>/dev/null; then
    missing_deps+=("diffusers==0.21.4")
fi

if ! python -c "import transformers" 2>/dev/null; then
    missing_deps+=("transformers==4.33.2")
fi

if ! python -c "import accelerate" 2>/dev/null; then
    missing_deps+=("accelerate==0.21.0")
fi

if ! python -c "import lama_cleaner" 2>/dev/null; then
    missing_deps+=("lama-cleaner==1.2.2")
fi

if ! python -c "import controlnet_aux" 2>/dev/null; then
    missing_deps+=("controlnet-aux==0.0.3")
fi

# Устанавливаем недостающие зависимости
if [ ${#missing_deps[@]} -gt 0 ]; then
    log_warning "Недостают зависимости: ${missing_deps[*]}"
    log_info "Установка недостающих зависимостей..."
    
    for dep in "${missing_deps[@]}"; do
        log_info "Установка $dep..."
        pip install "$dep" --no-deps 2>/dev/null || pip install "$dep" || {
            log_error "Не удалось установить $dep"
            continue
        }
    done
else
    log_success "Все зависимости установлены"
fi

# 4. Исправляем service.py если нужно
if [ -f "service.py" ]; then
    log_info "Проверка порта в service.py..."
    
    # Проверяем текущий порт
    current_port=$(grep -o "port.*[0-9]\+" service.py | grep -o "[0-9]\+" | head -1 || echo "")
    
    if [ "$current_port" != "8080" ]; then
        log_warning "Неправильный порт в service.py: $current_port, исправляем на 8080"
        
        # Создаем резервную копию
        cp service.py service.py.backup.$(date +%s)
        
        # Исправляем порт
        sed -i 's/port.*=.*[0-9]\+/port=8080/g' service.py
        
        log_success "Порт исправлен на 8080"
    else
        log_success "Порт уже настроен правильно: 8080"
    fi
else
    log_error "service.py не найден!"
    
    # Создаем минимальный service.py
    log_info "Создание базового service.py..."
    cat > service.py << 'EOF'
#!/usr/bin/env python3
"""
Минимальный LaMa сервис для Color360
"""

import os
import cv2
import numpy as np
from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import tempfile

app = FastAPI(title="Basic LaMa Service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"], 
    allow_headers=["*"],
)

@app.get("/")
async def root():
    return {"status": "running", "mode": "basic_opencv"}

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
        
        # Приводим размеры
        h, w = img.shape[:2]
        mask_img = cv2.resize(mask_img, (w, h))
        
        # Применяем OpenCV inpainting
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
        raise HTTPException(status_code=500, detail=f"Ошибка обработки: {str(e)}")

if __name__ == "__main__":
    print("🔧 Запуск базового LaMa сервиса на порту 8080")
    uvicorn.run(app, host="0.0.0.0", port=8080, log_level="info")
EOF
    chmod +x service.py
    log_success "Базовый service.py создан"
fi

# 5. Тестируем зависимости
log_info "Тестирование зависимостей..."

test_results=()

# Тест основных библиотек
libraries=("numpy" "cv2" "fastapi" "uvicorn")
for lib in "${libraries[@]}"; do
    if python -c "import $lib" 2>/dev/null; then
        test_results+=("✅ $lib")
    else
        test_results+=("❌ $lib")
    fi
done

# Показываем результаты
log_info "Результаты тестирования:"
for result in "${test_results[@]}"; do
    echo "  $result"
done

# 6. Запускаем сервис
log_info "Запуск LaMa сервиса на порту 8080..."

# Запускаем в фоне
nohup python service.py > lama_service.log 2>&1 &
SERVICE_PID=$!

# Сохраняем PID
echo $SERVICE_PID > lama_service.pid
log_success "LaMa сервис запущен с PID: $SERVICE_PID"

# 7. Проверяем доступность
log_info "Ожидание инициализации сервиса..."
sleep 5

# Проверяем API
for attempt in {1..10}; do
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        response=$(curl -s http://localhost:8080/health)
        log_success "LaMa API доступен!"
        log_info "Ответ: $response"
        break
    elif [ $attempt -eq 10 ]; then
        log_error "LaMa API недоступен после 10 попыток"
        log_info "Проверьте лог: tail -f lama_service.log"
        exit 1
    else
        log_info "Попытка $attempt/10..."
        sleep 2
    fi
done

# 8. Финальная проверка
echo
log_success "🎉 LaMa сервис успешно запущен и работает!"
echo
echo "📋 ИНФОРМАЦИЯ О СЕРВИСЕ:"
echo "========================"
log_info "PID: $SERVICE_PID"
log_info "Порт: 8080"
log_info "Лог файл: $(pwd)/lama_service.log"
log_info "PID файл: $(pwd)/lama_service.pid"
echo
echo "🔗 ПРОВЕРКА API:"
echo "curl http://localhost:8080/health"
echo
echo "📊 УПРАВЛЕНИЕ:"
echo "bash lama-service-manager.sh {start|stop|restart|status}"
echo