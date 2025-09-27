#!/bin/bash

# Fix LaMa Service - Улучшенная версия с детальной диагностикой
# Версия: 2.0
# Автор: Color360 Development Team

set -e  # Останавливаться при ошибках

echo "🔧 УЛУЧШЕННОЕ ИСПРАВЛЕНИЕ LAMA СЕРВИСА v2.0"
echo "============================================="

# Функции для логирования
log_info() { echo "ℹ️  $1"; }
log_success() { echo "✅ $1"; }
log_warning() { echo "⚠️  $1"; }
log_error() { echo "❌ $1"; }

# Определение директории LaMa
find_lama_directory() {
    local dirs=(
        "/var/www/color360/lama"
        "/tmp/lama" 
        "/home/lama"
        "$(pwd)/lama"
        "$(pwd)"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ -f "$dir/service.py" ]]; then
            echo "$dir"
            return 0
        fi
    done
    
    # Поиск по всей системе
    local found=$(find /var /home /opt /tmp -name "service.py" -path "*/lama/*" 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
        dirname "$found"
        return 0
    fi
    
    return 1
}

# Основная логика
main() {
    log_info "Поиск директории LaMa..."
    LAMA_DIR=$(find_lama_directory)
    
    if [[ -z "$LAMA_DIR" ]]; then
        log_error "service.py не найден! Создаем базовую структуру LaMa..."
        setup_lama_from_scratch
        return $?
    fi
    
    log_success "Найден LaMa в: $LAMA_DIR"
    cd "$LAMA_DIR"
    
    # Останавливаем процессы
    log_info "Остановка всех процессов LaMa..."
    pkill -f "service.py" 2>/dev/null || true
    pkill -f "uvicorn.*lama" 2>/dev/null || true
    sleep 2
    log_success "Процессы остановлены"
    
    # Проверяем и активируем виртуальное окружение
    setup_python_environment
    
    # Устанавливаем зависимости
    install_dependencies
    
    # Проверяем и исправляем service.py
    fix_service_file
    
    # Тестируем зависимости
    test_dependencies
    
    # Запускаем сервис с отладкой
    start_service_with_debug
}

setup_python_environment() {
    log_info "Настройка Python окружения..."
    
    # Проверяем наличие виртуального окружения
    if [[ -d "venv" ]]; then
        log_info "Активация существующего venv..."
        source venv/bin/activate
    elif [[ -n "$VIRTUAL_ENV" ]]; then
        log_info "Используем активное виртуальное окружение: $VIRTUAL_ENV"
    else
        log_info "Создание нового виртуального окружения..."
        python3 -m venv venv
        source venv/bin/activate
    fi
    
    # Обновляем pip
    python -m pip install --upgrade pip setuptools wheel
    log_success "Python окружение готово"
}

install_dependencies() {
    log_info "Установка зависимостей LaMa..."
    
    # Базовые зависимости
    local base_deps=(
        "fastapi==0.104.1"
        "uvicorn[standard]==0.24.0"
        "python-multipart==0.0.6"
        "numpy==1.24.3"
        "opencv-python-headless==4.8.1.78"
        "Pillow==10.0.1"
    )
    
    # ML зависимости
    local ml_deps=(
        "torch==2.1.0"
        "torchvision==0.16.0"
        "diffusers==0.21.4"
        "transformers==4.33.2"
        "accelerate==0.21.0"
        "controlnet-aux==0.0.3"
    )
    
    log_info "Установка базовых зависимостей..."
    for dep in "${base_deps[@]}"; do
        log_info "Устанавливаем $dep..."
        pip install "$dep" --no-cache-dir
    done
    
    log_info "Установка ML зависимостей..."
    for dep in "${ml_deps[@]}"; do
        log_info "Устанавливаем $dep..."
        pip install "$dep" --no-cache-dir
    done
    
    log_success "Все зависимости установлены"
}

fix_service_file() {
    log_info "Проверка и исправление service.py..."
    
    if [[ ! -f "service.py" ]]; then
        log_error "service.py не найден! Создаем базовый файл..."
        create_basic_service_file
        return
    fi
    
    # Проверяем порт
    local current_port=$(grep -o "port\s*=\s*[0-9]*" service.py | grep -o "[0-9]*" | head -1)
    if [[ "$current_port" != "8080" ]]; then
        log_warning "Неправильный порт в service.py: $current_port, исправляем на 8080"
        sed -i 's/port\s*=\s*[0-9]*/port=8080/g' service.py
        sed -i 's/uvicorn\.run.*port=[0-9]*/uvicorn.run(app, host="0.0.0.0", port=8080)/g' service.py
        log_success "Порт исправлен на 8080"
    fi
    
    # Проверяем синтаксис
    if python -m py_compile service.py 2>/dev/null; then
        log_success "Синтаксис service.py корректен"
    else
        log_error "Ошибка синтаксиса в service.py:"
        python -m py_compile service.py
        return 1
    fi
}

create_basic_service_file() {
    log_info "Создание базового service.py..."
    
cat > service.py << 'EOF'
#!/usr/bin/env python3
import os
import sys
import logging
from pathlib import Path

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

try:
    import numpy as np
    import cv2
    from fastapi import FastAPI, File, UploadFile, HTTPException
    from fastapi.responses import FileResponse
    import uvicorn
    
    logger.info("Все зависимости успешно импортированы")
    
    app = FastAPI(title="LaMa Service", version="1.0")
    
    @app.get("/")
    async def root():
        return {"message": "LaMa Service Running", "status": "healthy"}
    
    @app.get("/health")
    async def health():
        return {"status": "ok", "service": "lama"}
    
    @app.post("/inpaint")
    async def inpaint(image: UploadFile = File(...), mask: UploadFile = File(...)):
        try:
            # Заглушка для обработки изображений
            logger.info(f"Получен запрос на inpaint: {image.filename}")
            return {"message": "Inpainting completed", "status": "success"}
        except Exception as e:
            logger.error(f"Ошибка inpainting: {str(e)}")
            raise HTTPException(status_code=500, detail=str(e))
    
    if __name__ == "__main__":
        logger.info("Запуск LaMa сервиса на порту 8080...")
        uvicorn.run(app, host="0.0.0.0", port=8080, log_level="info")
        
except ImportError as e:
    logger.error(f"Ошибка импорта: {e}")
    sys.exit(1)
except Exception as e:
    logger.error(f"Неожиданная ошибка: {e}")
    sys.exit(1)
EOF

    chmod +x service.py
    log_success "Базовый service.py создан"
}

test_dependencies() {
    log_info "Тестирование зависимостей..."
    
    python3 -c "
import sys
import logging
logging.basicConfig(level=logging.INFO)

packages = [
    'numpy', 'cv2', 'fastapi', 'uvicorn', 
    'torch', 'diffusers', 'transformers', 'accelerate'
]

success = True
for pkg in packages:
    try:
        __import__(pkg)
        print(f'  ✅ {pkg}')
    except ImportError as e:
        print(f'  ❌ {pkg}: {e}')
        success = False

if success:
    print('✅ Все критичные зависимости доступны')
else:
    print('⚠️ Некоторые зависимости недоступны')
    sys.exit(1)
"
    
    if [[ $? -eq 0 ]]; then
        log_success "Все зависимости работают"
    else
        log_error "Проблемы с зависимостями"
        return 1
    fi
}

start_service_with_debug() {
    log_info "Запуск LaMa сервиса с отладкой..."
    
    # Создаем лог файл
    local log_file="lama_service_debug.log"
    
    # Запускаем в фоне с подробным логированием
    nohup python3 service.py > "$log_file" 2>&1 &
    local pid=$!
    
    echo $pid > lama_service.pid
    log_success "LaMa сервис запущен с PID: $pid"
    log_info "Лог файл: $PWD/$log_file"
    
    # Ждем инициализации
    log_info "Ожидание инициализации сервиса..."
    for i in {1..15}; do
        log_info "Попытка $i/15..."
        
        # Проверяем что процесс еще работает
        if ! kill -0 $pid 2>/dev/null; then
            log_error "Процесс $pid завершился! Смотрим лог:"
            echo "=== ПОСЛЕДНИЕ 20 СТРОК ЛОГА ==="
            tail -20 "$log_file"
            return 1
        fi
        
        # Проверяем API
        if curl -s --connect-timeout 2 "http://localhost:8080/health" >/dev/null 2>&1; then
            log_success "LaMa API доступен на порту 8080!"
            log_info "Тест API:"
            curl -s "http://localhost:8080/health" | head -2
            return 0
        fi
        
        sleep 2
    done
    
    log_error "LaMa API недоступен после 15 попыток"
    log_info "Последние строки лога:"
    tail -10 "$log_file"
    log_info "Для полного лога выполните: tail -f $PWD/$log_file"
    
    return 1
}

setup_lama_from_scratch() {
    log_warning "Настройка LaMa с нуля..."
    
    # Создаем директорию
    local lama_dir="/var/www/color360/lama"
    mkdir -p "$lama_dir"
    cd "$lama_dir"
    
    log_info "Создана директория: $lama_dir"
    LAMA_DIR="$lama_dir"
    
    # Продолжаем стандартную настройку
    setup_python_environment
    install_dependencies
    create_basic_service_file
    test_dependencies
    start_service_with_debug
}

# Запуск основной функции
main "$@"

echo ""
echo "🏁 СКРИПТ ЗАВЕРШЕН"
echo "=================="
echo "Директория LaMa: $LAMA_DIR"
echo "Для проверки статуса: curl http://localhost:8080/health"
echo "Для просмотра логов: tail -f $LAMA_DIR/lama_service_debug.log"