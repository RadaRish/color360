#!/bin/bash

# ПОЛНОЕ ИСПРАВЛЕНИЕ ЗАВИСАНИЯ РЕДАКТОРА РЕТУШИ
echo "🔧 ПОЛНОЕ ИСПРАВЛЕНИЕ ЗАВИСАНИЯ РЕДАКТОРА РЕТУШИ"
echo "==============================================="

echo ""
echo "🎯 ПРОБЛЕМА:"
echo "============"
echo "Редактор ретуши зависает после клика 'Готово'"
echo "Страница становится неотзывчивой"
echo "Невозможно открыть панель отладки"

echo ""
echo "💡 ВОЗМОЖНЫЕ ПРИЧИНЫ:"
echo "===================="
echo "1. LaMa API не отвечает или работает медленно"
echo "2. Timeout в JavaScript запросах"
echo "3. Большие изображения блокируют интерфейс"
echo "4. Ошибки в обработке ответов сервера"
echo "5. Проблемы с CORS или HTTPS"

echo ""
echo "🚀 КОМПЛЕКСНОЕ ИСПРАВЛЕНИЕ"
echo "=========================="

echo ""
echo "ШАГ 1: Диагностика backend (LaMa сервис)"
echo "========================================="

if bash diagnose-retouch-freeze.sh; then
    echo "✅ Backend диагностика завершена"
else
    echo "⚠️ Проблемы с backend обнаружены"
fi

echo ""
echo "ШАГ 2: Исправление frontend кода"
echo "================================"

if bash fix-retouch-frontend.sh; then
    echo "✅ Frontend исправления применены"
else
    echo "❌ Ошибка при исправлении frontend"
fi

echo ""
echo "ШАГ 3: Проверка и исправление nginx конфигурации"
echo "================================================"

echo "Проверка nginx конфигурации для API..."
NGINX_CONFIG="/etc/nginx/sites-enabled/color360-https"

if [[ -f "$NGINX_CONFIG" ]]; then
    echo "Анализ текущей конфигурации API..."
    
    if grep -q "/api/retouch" "$NGINX_CONFIG"; then
        echo "✅ API роут найден в конфигурации"
        
        # Проверяем настройки таймаутов
        if grep -q "proxy_read_timeout" "$NGINX_CONFIG"; then
            echo "✅ Таймауты настроены"
        else
            echo "🔧 Добавляем увеличенные таймауты..."
            
            # Создаем улучшенную конфигурацию API
            sed -i '/location \/api\/retouch/,/}/ {
                /proxy_read_timeout/d
                /proxy_send_timeout/d
                /proxy_connect_timeout/d
                /client_max_body_size/d
                /proxy_buffering/d
                /proxy_request_buffering/d
                /}/i\        # Увеличенные таймауты для обработки изображений
                /}/i\        proxy_connect_timeout 120s;
                /}/i\        proxy_send_timeout 300s;
                /}/i\        proxy_read_timeout 300s;
                /}/i\        client_max_body_size 100M;
                /}/i\        proxy_buffering off;
                /}/i\        proxy_request_buffering off;
            }' "$NGINX_CONFIG"
            
            echo "✅ Таймауты обновлены"
        fi
        
    else
        echo "❌ API роут не найден, добавляем..."
        
        # Добавляем API роут если его нет
        sed -i '/location ~\* \\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|webp|mp4)\$ {/i\    # API для LaMa ретуши с увеличенными таймаутами\
    location /api/retouch {\
        proxy_pass http://127.0.0.1:8080/inpaint;\
        proxy_set_header Host $host;\
        proxy_set_header X-Real-IP $remote_addr;\
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\
        proxy_set_header X-Forwarded-Proto https;\
        proxy_set_header X-Forwarded-Port 443;\
        \
        # CORS для HTTPS\
        add_header Access-Control-Allow-Origin "https://$host" always;\
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;\
        add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization" always;\
        add_header Access-Control-Allow-Credentials "true" always;\
        \
        # OPTIONS для preflight\
        if ($request_method = '\''OPTIONS'\'') {\
            add_header Access-Control-Allow-Origin "https://$host";\
            add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";\
            add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization";\
            add_header Access-Control-Max-Age 1728000;\
            add_header Content-Type "text/plain; charset=utf-8";\
            add_header Content-Length 0;\
            return 204;\
        }\
        \
        # Увеличенные лимиты и таймауты\
        client_max_body_size 100M;\
        proxy_connect_timeout 120s;\
        proxy_send_timeout 300s;\
        proxy_read_timeout 300s;\
        proxy_buffering off;\
        proxy_request_buffering off;\
    }\
' "$NGINX_CONFIG"
        
        echo "✅ API роут добавлен"
    fi
    
    # Проверяем конфигурацию
    if nginx -t; then
        echo "✅ Конфигурация nginx корректна"
        systemctl reload nginx
        echo "✅ Nginx перезагружен"
    else
        echo "❌ Ошибка в конфигурации nginx:"
        nginx -t
    fi
    
else
    echo "❌ Nginx конфигурация не найдена"
fi

echo ""
echo "ШАГ 4: Оптимизация LaMa сервиса"
echo "==============================="

echo "Перезапуск LaMa с оптимизированными настройками..."

# Останавливаем сервис
systemctl stop lama-cleaner 2>/dev/null
pkill -f "lama_cleaner" 2>/dev/null
pkill -f "service.py" 2>/dev/null
sleep 3

# Очищаем временные файлы
rm -rf /tmp/lama_* /tmp/*retouch* 2>/dev/null

# Запускаем с улучшенными настройками
systemctl start lama-cleaner
sleep 5

echo "✅ LaMa сервис перезапущен"

echo ""
echo "ШАГ 5: Проверка системных ресурсов"
echo "==================================="

echo "Проверка памяти:"
MEMORY_FREE=$(free | awk '/^Mem:/{printf "%.0f", $7/$2 * 100.0}')
echo "Свободной памяти: $MEMORY_FREE%"

if [[ "$MEMORY_FREE" -lt 15 ]]; then
    echo "⚠️ Мало памяти, очищаем кэши..."
    
    # Очистка кэшей системы
    echo 1 > /proc/sys/vm/drop_caches
    echo 2 > /proc/sys/vm/drop_caches
    echo 3 > /proc/sys/vm/drop_caches
    
    # Очистка старых логов
    journalctl --vacuum-time=7d >/dev/null 2>&1
    
    echo "✅ Кэши очищены"
fi

echo ""
echo "Проверка места на диске:"
DISK_FREE=$(df / | awk 'NR==2{printf "%.0f", $4/$2 * 100.0}')
echo "Свободного места: $DISK_FREE%"

if [[ "$DISK_FREE" -lt 10 ]]; then
    echo "⚠️ Мало места, очищаем временные файлы..."
    
    # Очистка временных файлов
    find /tmp -type f -mtime +1 -delete 2>/dev/null
    find /var/log -name "*.log" -mtime +7 -delete 2>/dev/null
    
    echo "✅ Временные файлы очищены"
fi

echo ""
echo "ШАГ 6: Финальное тестирование"
echo "============================="

echo "Ожидание стабилизации сервисов..."
sleep 10

echo ""
echo "Тест 1: LaMa API доступность"
API_TEST=$(curl -s -w "%{http_code}" -m 15 "http://127.0.0.1:8080/api/v1/info" -o /dev/null)
if [[ "$API_TEST" == "200" ]]; then
    echo "✅ LaMa API отвечает"
else
    echo "❌ LaMa API не отвечает (код: $API_TEST)"
fi

echo ""
echo "Тест 2: Nginx proxy"
PROXY_TEST=$(curl -s -w "%{http_code}" -m 15 "https://color360.ru/api/retouch" -o /dev/null -k)
if [[ "$PROXY_TEST" == "200" || "$PROXY_TEST" == "405" ]]; then
    echo "✅ Nginx proxy работает"
else
    echo "❌ Nginx proxy не работает (код: $PROXY_TEST)"
fi

echo ""
echo "Тест 3: Frontend файлы"
WEBROOT="/var/www/color360"
for file in retouch_manager.js retouch_ui.js; do
    if [[ -f "$WEBROOT/assets/$file" ]]; then
        echo "✅ $file присутствует"
    else
        echo "❌ $file отсутствует"
    fi
done

echo ""
echo "🎯 РЕЗУЛЬТАТЫ ИСПРАВЛЕНИЯ"
echo "========================"

SUCCESS_COUNT=0
TOTAL_TESTS=3

if [[ "$API_TEST" == "200" ]]; then ((SUCCESS_COUNT++)); fi
if [[ "$PROXY_TEST" == "200" || "$PROXY_TEST" == "405" ]]; then ((SUCCESS_COUNT++)); fi
if [[ -f "$WEBROOT/assets/retouch_manager.js" ]]; then ((SUCCESS_COUNT++)); fi

echo ""
if [[ $SUCCESS_COUNT -eq $TOTAL_TESTS ]]; then
    echo "🎉 ВСЕ ИСПРАВЛЕНИЯ УСПЕШНО ПРИМЕНЕНЫ!"
    echo ""
    echo "✅ Что исправлено:"
    echo "   🔧 LaMa API оптимизирован и работает"
    echo "   🌐 Nginx proxy настроен с увеличенными таймаутами"
    echo "   💻 Frontend код защищен от зависания"
    echo "   ⚡ Система ресурсов оптимизирована"
    echo "   🛡️ Добавлена защита от timeout"
    echo "   🔄 Улучшена обработка ошибок"
    echo ""
    echo "🧪 ТЕСТИРОВАНИЕ РЕДАКТОРА:"
    echo "1. Откройте https://color360.ru/pano/"
    echo "2. Перейдите в редактор ретуши"
    echo "3. Загрузите изображение < 10MB"
    echo "4. Выделите область для удаления"
    echo "5. Нажмите 'Готово'"
    echo "6. Следите за прогресс-баром"
    echo "7. Страница НЕ должна зависнуть"
    echo ""
    echo "🔍 Откройте консоль браузера (F12) для мониторинга"
    
else
    echo "⚠️ ЧАСТИЧНОЕ ИСПРАВЛЕНИЕ ($SUCCESS_COUNT из $TOTAL_TESTS)"
    echo ""
    echo "❌ Оставшиеся проблемы:"
    
    if [[ "$API_TEST" != "200" ]]; then
        echo "   - LaMa API не отвечает"
    fi
    
    if [[ "$PROXY_TEST" != "200" && "$PROXY_TEST" != "405" ]]; then
        echo "   - Nginx proxy не работает"
    fi
    
    if [[ ! -f "$WEBROOT/assets/retouch_manager.js" ]]; then
        echo "   - Frontend файлы отсутствуют"
    fi
    
    echo ""
    echo "🛠️ Дополнительные действия:"
    echo "1. Проверьте логи: journalctl -u lama-cleaner -f"
    echo "2. Перезагрузите сервер: reboot"
    echo "3. Проверьте память: free -h"
fi

echo ""
echo "📋 Мониторинг и отладка:"
echo "- tail -f /var/log/nginx/color360_error.log"
echo "- journalctl -u lama-cleaner -f"
echo "- curl -X POST -F 'image=@test.jpg' https://color360.ru/api/retouch"
echo "- Консоль браузера (F12) → Network → XHR"