#!/bin/bash

# ДИАГНОСТИКА И ИСПРАВЛЕНИЕ ЗАВИСАНИЯ РЕДАКТОРА РЕТУШИ
echo "🔧 ДИАГНОСТИКА ЗАВИСАНИЯ РЕДАКТОРА РЕТУШИ"
echo "========================================="

echo "🔍 1. ПРОВЕРКА СТАТУСА LAMA СЕРВИСА"
echo "==================================="

echo "Статус systemd сервиса LaMa:"
if systemctl is-active --quiet lama-cleaner; then
    echo "✅ LaMa сервис активен"
    systemctl status lama-cleaner --no-pager | head -10
else
    echo "❌ LaMa сервис неактивен!"
    systemctl status lama-cleaner --no-pager | head -10
fi

echo ""
echo "Проверка процесса LaMa:"
LAMA_PID=$(pgrep -f "lama_cleaner\|service.py" | head -1)
if [[ -n "$LAMA_PID" ]]; then
    echo "✅ LaMa процесс найден (PID: $LAMA_PID)"
    ps aux | grep -E "lama_cleaner|service.py" | grep -v grep
else
    echo "❌ LaMa процесс не найден!"
fi

echo ""
echo "Проверка порта 8080 (LaMa API):"
if netstat -tuln | grep -q ":8080 "; then
    echo "✅ Порт 8080 слушается"
    netstat -tuln | grep ":8080"
else
    echo "❌ Порт 8080 не слушается!"
fi

echo ""
echo "🌐 2. ТЕСТИРОВАНИЕ LAMA API"
echo "==========================="

echo "Тест доступности API локально:"
LOCAL_API_TEST=$(curl -s -w "%{http_code}" -m 10 "http://127.0.0.1:8080/api/v1/info" -o /dev/null 2>/dev/null)
if [[ "$LOCAL_API_TEST" == "200" ]]; then
    echo "✅ LaMa API доступен локально (HTTP $LOCAL_API_TEST)"
else
    echo "❌ LaMa API недоступен локально (HTTP $LOCAL_API_TEST)"
fi

echo ""
echo "Тест через nginx proxy:"
PROXY_API_TEST=$(curl -s -w "%{http_code}" -m 10 "https://color360.ru/api/retouch" -o /dev/null -k 2>/dev/null)
if [[ "$PROXY_API_TEST" == "200" || "$PROXY_API_TEST" == "405" ]]; then
    echo "✅ Nginx proxy работает (HTTP $PROXY_API_TEST)"
else
    echo "❌ Nginx proxy не работает (HTTP $PROXY_API_TEST)"
fi

echo ""
echo "Детальная проверка API:"
echo "curl -X GET http://127.0.0.1:8080/api/v1/info"
curl -X GET "http://127.0.0.1:8080/api/v1/info" 2>/dev/null | head -5 || echo "API не отвечает"

echo ""
echo "📋 3. АНАЛИЗ ЛОГОВ ЗАВИСАНИЯ"
echo "============================"

echo "Логи systemd LaMa сервиса:"
if systemctl is-active --quiet lama-cleaner; then
    echo "=== Последние 20 строк лога LaMa ==="
    journalctl -u lama-cleaner -n 20 --no-pager 2>/dev/null || echo "Логи недоступны"
else
    echo "Сервис неактивен, логи могут быть недоступны"
fi

echo ""
echo "Логи nginx (ошибки API):"
if [[ -f "/var/log/nginx/color360_error.log" ]]; then
    echo "=== Последние ошибки nginx ==="
    tail -20 /var/log/nginx/color360_error.log | grep -E "(retouch|api|proxy|upstream)" || echo "API ошибок не найдено"
else
    echo "Лог color360_error.log не найден"
fi

echo ""
echo "📊 4. ПРОВЕРКА РЕСУРСОВ СИСТЕМЫ"
echo "==============================="

echo "Использование памяти:"
free -h

echo ""
echo "Использование CPU:"
top -bn1 | head -5

echo ""
echo "Использование диска:"
df -h / /tmp | head -3

echo ""
echo "Проверка /tmp директории:"
ls -la /tmp/ | grep -E "(lama|color360|temp)" | head -10 || echo "Временные файлы LaMa не найдены"

echo ""
echo "🔧 5. АВТОМАТИЧЕСКОЕ ИСПРАВЛЕНИЕ"
echo "==============================="

NEED_RESTART=false

# Перезапуск LaMa если не работает
if [[ "$LOCAL_API_TEST" != "200" ]]; then
    echo "🔄 LaMa API не отвечает, перезапускаем сервис..."
    
    # Остановка всех процессов LaMa
    systemctl stop lama-cleaner 2>/dev/null
    pkill -f "lama_cleaner" 2>/dev/null
    pkill -f "service.py" 2>/dev/null
    sleep 3
    
    # Очистка временных файлов
    rm -f /tmp/lama_* 2>/dev/null
    rm -f /tmp/*retouch* 2>/dev/null
    
    # Запуск сервиса
    systemctl start lama-cleaner
    sleep 5
    
    echo "✅ LaMa сервис перезапущен"
    NEED_RESTART=true
fi

# Перезапуск nginx если proxy не работает
if [[ "$PROXY_API_TEST" != "200" && "$PROXY_API_TEST" != "405" ]]; then
    echo "🔄 Nginx proxy не работает, перезапускаем nginx..."
    systemctl reload nginx
    sleep 2
    echo "✅ Nginx перезагружен"
fi

echo ""
echo "⏱️ 6. ПОВТОРНОЕ ТЕСТИРОВАНИЕ ПОСЛЕ ИСПРАВЛЕНИЯ"
echo "=============================================="

if [[ "$NEED_RESTART" == "true" ]]; then
    echo "Ожидание запуска LaMa..."
    sleep 10
fi

# Повторные тесты
echo "Повторный тест LaMa API:"
FIXED_API_TEST=$(curl -s -w "%{http_code}" -m 15 "http://127.0.0.1:8080/api/v1/info" -o /dev/null 2>/dev/null)
if [[ "$FIXED_API_TEST" == "200" ]]; then
    echo "✅ LaMa API восстановлен (HTTP $FIXED_API_TEST)"
else
    echo "❌ LaMa API все еще не работает (HTTP $FIXED_API_TEST)"
fi

echo ""
echo "Повторный тест nginx proxy:"
FIXED_PROXY_TEST=$(curl -s -w "%{http_code}" -m 15 "https://color360.ru/api/retouch" -o /dev/null -k 2>/dev/null)
if [[ "$FIXED_PROXY_TEST" == "200" || "$FIXED_PROXY_TEST" == "405" ]]; then
    echo "✅ Nginx proxy восстановлен (HTTP $FIXED_PROXY_TEST)"
else
    echo "❌ Nginx proxy все еще не работает (HTTP $FIXED_PROXY_TEST)"
fi

echo ""
echo "🧪 7. ТЕСТ ПОЛНОГО ЦИКЛА РЕТУШИ"
echo "==============================="

# Создаем тестовое изображение
TEST_IMG="/tmp/test_retouch.png"
echo "Создание тестового изображения..."

# Создаем простое PNG изображение 100x100
python3 -c "
import os
try:
    from PIL import Image
    import numpy as np
    
    # Создаем простое изображение
    img = Image.new('RGB', (100, 100), color='red')
    img.save('$TEST_IMG')
    print('✅ Тестовое изображение создано')
except ImportError:
    print('❌ PIL не установлен, создаем изображение другим способом')
except Exception as e:
    print(f'❌ Ошибка создания изображения: {e}')
" 2>/dev/null

# Альтернативное создание через convert если PIL недоступен
if [[ ! -f "$TEST_IMG" ]] && command -v convert >/dev/null 2>&1; then
    convert -size 100x100 xc:red "$TEST_IMG" 2>/dev/null && echo "✅ Тестовое изображение создано (ImageMagick)"
fi

if [[ -f "$TEST_IMG" ]]; then
    echo "Тестирование API с реальным изображением..."
    
    # Тест загрузки изображения
    UPLOAD_TEST=$(curl -s -w "%{http_code}" -X POST \
        -F "image=@$TEST_IMG" \
        -F "mask=@$TEST_IMG" \
        "http://127.0.0.1:8080/inpaint" \
        -o /tmp/retouch_result.tmp \
        -m 30 2>/dev/null)
    
    if [[ "$UPLOAD_TEST" == "200" ]]; then
        echo "✅ Тест загрузки и обработки прошел успешно (HTTP $UPLOAD_TEST)"
        
        # Проверяем размер результата
        if [[ -f "/tmp/retouch_result.tmp" ]]; then
            RESULT_SIZE=$(stat -c%s "/tmp/retouch_result.tmp" 2>/dev/null || echo "0")
            if [[ "$RESULT_SIZE" -gt 100 ]]; then
                echo "✅ Результат получен ($RESULT_SIZE байт)"
            else
                echo "⚠️ Результат слишком мал ($RESULT_SIZE байт)"
            fi
        fi
    else
        echo "❌ Тест загрузки не прошел (HTTP $UPLOAD_TEST)"
    fi
    
    # Очистка
    rm -f "$TEST_IMG" /tmp/retouch_result.tmp 2>/dev/null
else
    echo "⚠️ Не удалось создать тестовое изображение"
fi

echo ""
echo "📊 8. РЕЗЮМЕ ДИАГНОСТИКИ"
echo "========================"

ISSUES=0

# Проверка компонентов
if ! systemctl is-active --quiet lama-cleaner; then
    echo "❌ LaMa сервис не запущен"
    ((ISSUES++))
fi

if [[ "$FIXED_API_TEST" != "200" ]]; then
    echo "❌ LaMa API недоступен"
    ((ISSUES++))
fi

if [[ "$FIXED_PROXY_TEST" != "200" && "$FIXED_PROXY_TEST" != "405" ]]; then
    echo "❌ Nginx proxy не работает"
    ((ISSUES++))
fi

# Проверка ресурсов
MEMORY_FREE=$(free | awk '/^Mem:/{printf "%.0f", $7/$2 * 100.0}')
if [[ "$MEMORY_FREE" -lt 10 ]]; then
    echo "⚠️ Мало свободной памяти ($MEMORY_FREE%)"
    ((ISSUES++))
fi

echo ""
if [[ $ISSUES -eq 0 ]]; then
    echo "🎉 ВСЕ КОМПОНЕНТЫ РАБОТАЮТ КОРРЕКТНО!"
    echo ""
    echo "✅ Система готова к использованию:"
    echo "   - LaMa сервис активен"
    echo "   - API отвечает"
    echo "   - Nginx proxy работает"
    echo "   - Достаточно ресурсов"
    echo ""
    echo "🔍 Если редактор все еще зависает:"
    echo "   1. Проверьте консоль браузера (F12)"
    echo "   2. Очистите кэш браузера (Ctrl+Shift+R)"
    echo "   3. Попробуйте в режиме инкогнито"
    echo "   4. Проверьте размер загружаемого изображения"
else
    echo "⚠️ ОБНАРУЖЕНО $ISSUES ПРОБЛЕМ(Ы)"
    echo ""
    echo "🛠️ Следующие шаги для исправления:"
    
    if ! systemctl is-active --quiet lama-cleaner; then
        echo "1. Запустить LaMa: systemctl start lama-cleaner"
    fi
    
    if [[ "$FIXED_API_TEST" != "200" ]]; then
        echo "2. Проверить LaMa логи: journalctl -u lama-cleaner -f"
    fi
    
    if [[ "$MEMORY_FREE" -lt 10 ]]; then
        echo "3. Освободить память: bash clean-system-resources.sh"
    fi
fi

echo ""
echo "🔧 Полезные команды для дальнейшей диагностики:"
echo "- journalctl -u lama-cleaner -f (мониторинг LaMa)"
echo "- tail -f /var/log/nginx/color360_error.log (мониторинг nginx)"
echo "- htop (мониторинг ресурсов)"
echo "- curl -X POST -F 'image=@/path/to/image.jpg' http://127.0.0.1:8080/inpaint (тест API)"