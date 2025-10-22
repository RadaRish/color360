#!/bin/bash

# Диагностика проблем с LaMa сервисом
# Запустите на сервере: bash diagnose-lama-service.sh

echo "🔍 ДИАГНОСТИКА LAMA СЕРВИСА"
echo "=========================="

# Определяем директорию LaMa
LAMA_DIRS=(
    "/var/www/color360/lama"
    "/tmp/lama" 
    "/home/lama"
    "$(pwd)/lama"
    "$(pwd)"
)

LAMA_DIR=""
for dir in "${LAMA_DIRS[@]}"; do
    if [[ -f "$dir/service.py" ]]; then
        LAMA_DIR="$dir"
        break
    fi
done

if [[ -z "$LAMA_DIR" ]]; then
    echo "❌ service.py не найден в стандартных местах"
    echo "Поиск service.py по всей системе..."
    find / -name "service.py" -path "*/lama/*" 2>/dev/null | head -5
    exit 1
fi

echo "✅ Найден LaMa в: $LAMA_DIR"
cd "$LAMA_DIR"

# 1. Проверяем активные процессы
echo ""
echo "📊 АКТИВНЫЕ ПРОЦЕССЫ:"
ps aux | grep -E "(service\.py|uvicorn|python.*lama)" | grep -v grep || echo "Нет активных процессов LaMa"

# 2. Проверяем порты
echo ""
echo "🔌 ЗАНЯТЫЕ ПОРТЫ:"
netstat -tuln | grep -E ":(8080|5002|3000)" || echo "Целевые порты свободны"

# 3. Проверяем файлы
echo ""
echo "📁 ФАЙЛЫ В ДИРЕКТОРИИ:"
ls -la service.py requirements.txt *.log *.pid 2>/dev/null || echo "Некоторые файлы отсутствуют"

# 4. Проверяем содержимое service.py
echo ""
echo "🔧 ПРОВЕРКА service.py:"
if [[ -f "service.py" ]]; then
    echo "Размер файла: $(wc -l < service.py) строк"
    echo "Порт в коде:"
    grep -n "uvicorn.run\|port\s*=" service.py | head -3
    
    # Проверяем синтаксис
    echo "Проверка синтаксиса Python:"
    python3 -m py_compile service.py 2>&1 && echo "✅ Синтаксис OK" || echo "❌ Ошибка синтаксиса"
else
    echo "❌ service.py отсутствует"
fi

# 5. Проверяем виртуальное окружение
echo ""
echo "🐍 PYTHON ОКРУЖЕНИЕ:"
if [[ -d "venv" ]] || [[ -n "$VIRTUAL_ENV" ]]; then
    echo "Виртуальное окружение:"
    which python3
    python3 --version
    
    echo "Установленные пакеты (критичные):"
    python3 -c "
import sys
packages = ['numpy', 'cv2', 'fastapi', 'uvicorn', 'torch', 'diffusers', 'transformers', 'accelerate']
for pkg in packages:
    try:
        __import__(pkg)
        print(f'  ✅ {pkg}')
    except ImportError as e:
        print(f'  ❌ {pkg}: {e}')
"
else
    echo "⚠️ Виртуальное окружение не активировано"
fi

# 6. Проверяем логи
echo ""
echo "📋 ЛОГИ:"
for log in lama_service.log service.log uvicorn.log; do
    if [[ -f "$log" ]]; then
        echo "=== $log (последние 10 строк) ==="
        tail -10 "$log"
        echo ""
    fi
done

# 7. Тестируем запуск в интерактивном режиме
echo "🧪 ТЕСТ ЗАПУСКА В ОТЛАДОЧНОМ РЕЖИМЕ:"
echo "Останавливаем существующие процессы..."
pkill -f service.py 2>/dev/null || true
sleep 2

echo "Запускаем service.py в переднем плане на 10 секунд..."
timeout 10s python3 service.py 2>&1 || echo "Процесс завершен"

# 8. Проверяем доступность API
echo ""
echo "🌐 ТЕСТ API:"
for port in 8080 5002; do
    echo "Тестируем порт $port:"
    if curl -s --connect-timeout 3 "http://localhost:$port/health" >/dev/null; then
        echo "  ✅ Порт $port отвечает"
    else
        echo "  ❌ Порт $port недоступен"
    fi
done

echo ""
echo "🏁 ДИАГНОСТИКА ЗАВЕРШЕНА"
echo "========================"
echo "Если проблемы не найдены, попробуйте:"
echo "1. cd $LAMA_DIR"
echo "2. source venv/bin/activate (если есть venv)"
echo "3. python3 service.py"
echo "4. Проверьте вывод на экран для ошибок"