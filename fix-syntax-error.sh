#!/bin/bash

# Быстрое исправление синтаксической ошибки в service.py
echo "🔧 ИСПРАВЛЕНИЕ СИНТАКСИЧЕСКОЙ ОШИБКИ В SERVICE.PY"
echo "================================================="

cd /var/www/color360/lama

echo "ℹ️  Создание резервной копии service.py..."
cp service.py service.py.backup.$(date +%s)

echo "ℹ️  Исправление синтаксической ошибки..."

# Исправляем лишнюю скобку на строке 377
sed -i '377s/port=8080))/port=8080)/' service.py

# Также проверим другие возможные проблемы со скобками
sed -i 's/)))/))g' service.py
sed -i 's/,))/))g' service.py

echo "ℹ️  Проверка синтаксиса после исправления..."
if python3 -m py_compile service.py 2>/dev/null; then
    echo "✅ Синтаксис исправлен!"
else
    echo "❌ Все еще есть ошибки синтаксиса:"
    python3 -m py_compile service.py
    echo ""
    echo "ℹ️  Показываем проблемные строки (370-385):"
    sed -n '370,385p' service.py | nl -ba -v370
    exit 1
fi

echo ""
echo "ℹ️  Активация виртуального окружения..."
if [[ -d "venv" ]]; then
    source venv/bin/activate
    echo "✅ Виртуальное окружение активировано"
else
    echo "⚠️  Виртуальное окружение не найдено, используем системный Python"
fi

echo ""
echo "ℹ️  Запуск service.py..."
nohup python3 service.py > lama_service_fixed.log 2>&1 &
PID=$!
echo $PID > lama_service.pid
echo "✅ Сервис запущен с PID: $PID"

echo ""
echo "ℹ️  Ожидание инициализации (15 секунд)..."
for i in {1..15}; do
    echo -n "."
    sleep 1
    
    # Проверяем что процесс еще работает
    if ! kill -0 $PID 2>/dev/null; then
        echo ""
        echo "❌ Процесс завершился! Смотрим лог:"
        echo "=== ПОСЛЕДНИЕ 20 СТРОК ЛОГА ==="
        tail -20 lama_service_fixed.log
        exit 1
    fi
    
    # Проверяем API каждые 3 секунды
    if [[ $((i % 3)) -eq 0 ]]; then
        if curl -s --connect-timeout 2 "http://localhost:8080/health" >/dev/null 2>&1; then
            echo ""
            echo "✅ LaMa API успешно запущен на порту 8080!"
            echo ""
            echo "🧪 Тест API:"
            curl -s "http://localhost:8080/health" || echo "Ошибка при тесте"
            echo ""
            echo "🏁 ИСПРАВЛЕНИЕ ЗАВЕРШЕНО УСПЕШНО!"
            echo "================================"
            echo "Сервис работает на: http://localhost:8080"
            echo "Лог файл: /var/www/color360/lama/lama_service_fixed.log"
            echo "PID файл: /var/www/color360/lama/lama_service.pid"
            exit 0
        fi
    fi
done

echo ""
echo "⚠️  API не ответил за 15 секунд. Проверяем лог:"
echo "=== ПОСЛЕДНИЕ 10 СТРОК ЛОГА ==="
tail -10 lama_service_fixed.log

echo ""
echo "ℹ️  Для мониторинга выполните:"
echo "tail -f /var/www/color360/lama/lama_service_fixed.log"