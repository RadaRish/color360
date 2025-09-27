#!/bin/bash

# Диагностика и перезапуск LaMa сервиса
echo "🔍 ДИАГНОСТИКА И ПЕРЕЗАПУСК LAMA СЕРВИСА"
echo "========================================"

cd /var/www/color360/lama

echo "📊 Проверка процессов LaMa..."
ps aux | grep -E "(service\.py|uvicorn|python.*lama)" | grep -v grep || echo "Процессы LaMa не найдены"

echo ""
echo "🔌 Проверка портов..."
netstat -tuln | grep -E ":(8080|5002|3000)" || echo "Целевые порты свободны"

echo ""
echo "📁 Проверка файлов и логов..."
ls -la service.py *.log *.pid 2>/dev/null || echo "Некоторые файлы отсутствуют"

echo ""
if [[ -f "lama_service_debug.log" ]]; then
    echo "📋 Последние строки debug лога:"
    tail -10 lama_service_debug.log
fi

if [[ -f "lama_service.log" ]]; then
    echo "📋 Последние строки основного лога:"
    tail -10 lama_service.log  
fi

echo ""
echo "🛑 Останавливаем все процессы LaMa..."
pkill -f service.py 2>/dev/null || true
pkill -f uvicorn 2>/dev/null || true
sleep 2

echo ""
echo "🔧 Активация виртуального окружения..."
if [[ -d "venv" ]]; then
    source venv/bin/activate
    echo "✅ Виртуальное окружение активировано"
else
    echo "⚠️ Создаем новое виртуальное окружение..."
    python3 -m venv venv
    source venv/bin/activate
    echo "✅ Новое виртуальное окружение создано и активировано"
fi

echo ""
echo "🧪 Тест синтаксиса service.py..."
if python3 -m py_compile service.py 2>/dev/null; then
    echo "✅ Синтаксис service.py корректен"
else
    echo "❌ Ошибка синтаксиса в service.py:"
    python3 -m py_compile service.py
    exit 1
fi

echo ""
echo "📦 Проверка критичных зависимостей..."
python3 -c "
import sys
packages = ['fastapi', 'uvicorn', 'numpy', 'cv2']
missing = []
for pkg in packages:
    try:
        __import__(pkg)
        print(f'✅ {pkg}')
    except ImportError:
        print(f'❌ {pkg}')
        missing.append(pkg)

if missing:
    print(f'\\nУстановка недостающих: {missing}')
    sys.exit(1)
"

if [[ $? -ne 0 ]]; then
    echo "Установка недостающих зависимостей..."
    pip install fastapi uvicorn numpy opencv-python-headless
fi

echo ""
echo "🚀 Запуск LaMa сервиса..."
nohup python3 service.py > lama_service_restart.log 2>&1 &
PID=$!
echo $PID > lama_service.pid

echo "✅ LaMa сервис запущен с PID: $PID"
echo "📝 Лог файл: lama_service_restart.log"

echo ""
echo "⏳ Ожидание запуска (20 секунд)..."
for i in {1..20}; do
    echo -n "."
    sleep 1
    
    # Проверяем что процесс работает
    if ! kill -0 $PID 2>/dev/null; then
        echo ""
        echo "❌ Процесс $PID завершился преждевременно!"
        echo "Последние строки лога:"
        tail -20 lama_service_restart.log
        exit 1
    fi
    
    # Проверяем API каждые 5 секунд
    if [[ $((i % 5)) -eq 0 ]]; then
        if curl -s --connect-timeout 2 "http://localhost:8080/health" >/dev/null 2>&1; then
            echo ""
            echo "✅ LaMa API запущен и отвечает!"
            break
        fi
    fi
done

echo ""
echo "🧪 Финальная проверка API..."

echo "Тест /health:"
curl -s "http://localhost:8080/health" 2>/dev/null && echo "" || echo "❌ /health недоступен"

echo "Тест /:"
curl -s "http://localhost:8080/" 2>/dev/null && echo "" || echo "❌ / недоступен"

echo "Тест внешнего доступа:"
curl -s --connect-timeout 3 "http://color360.online:8080/health" 2>/dev/null && echo "✅ Внешний доступ работает" || echo "❌ Внешний доступ недоступен"

echo ""
echo "🏁 ДИАГНОСТИКА ЗАВЕРШЕНА"
echo "========================"

if kill -0 $PID 2>/dev/null; then
    echo "✅ Сервис работает (PID: $PID)"
    echo "🌐 Локальный доступ: http://localhost:8080"
    echo "🌍 Внешний доступ: http://color360.online:8080"
    echo "📋 Мониторинг: tail -f lama_service_restart.log"
else
    echo "❌ Сервис не запущен"
    echo "📋 Проверьте лог: cat lama_service_restart.log"
fi