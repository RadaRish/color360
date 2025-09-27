#!/bin/bash

# Постоянный мониторинг и автоперезапуск LaMa сервиса
echo "📊 МОНИТОРИНГ И АВТОПЕРЕЗАПУСК LAMA"
echo "=================================="

# Функция проверки здоровья LaMa
check_lama_health() {
    # Проверяем systemd статус
    if ! systemctl is-active --quiet lama-inpainting; then
        echo "❌ $(date): LaMa сервис неактивен в systemd"
        return 1
    fi
    
    # Проверяем HTTP ответ
    if ! curl -s --connect-timeout 3 "http://127.0.0.1:8080/health" >/dev/null; then
        echo "❌ $(date): LaMa API не отвечает"
        return 1
    fi
    
    return 0
}

# Функция перезапуска LaMa
restart_lama() {
    echo "🔄 $(date): Перезапуск LaMa сервиса..."
    
    # Останавливаем
    systemctl stop lama-inpainting 2>/dev/null || true
    pkill -f service.py 2>/dev/null || true
    sleep 3
    
    # Освобождаем порт если занят
    if netstat -tuln | grep -q 8080; then
        fuser -k 8080/tcp 2>/dev/null || true
        sleep 2
    fi
    
    # Запускаем
    systemctl start lama-inpainting
    sleep 5
    
    # Проверяем успешность
    if check_lama_health; then
        echo "✅ $(date): LaMa успешно перезапущен"
        return 0
    else
        echo "❌ $(date): Перезапуск LaMa неудачен"
        return 1
    fi
}

# Основной цикл мониторинга
monitor_lama() {
    local check_interval=30  # Проверка каждые 30 секунд
    local failure_count=0
    local max_failures=3
    
    echo "🚀 Запуск мониторинга LaMa (интервал: ${check_interval}сек)"
    echo "Для остановки нажмите Ctrl+C"
    echo ""
    
    while true; do
        if check_lama_health; then
            if [[ $failure_count -gt 0 ]]; then
                echo "✅ $(date): LaMa восстановлен (было ошибок: $failure_count)"
                failure_count=0
            else
                echo "✅ $(date): LaMa работает нормально"
            fi
        else
            failure_count=$((failure_count + 1))
            echo "⚠️ $(date): LaMa недоступен (ошибка $failure_count/$max_failures)"
            
            if [[ $failure_count -ge $max_failures ]]; then
                echo "🚨 $(date): Превышен лимит ошибок, перезапускаем LaMa..."
                if restart_lama; then
                    failure_count=0
                else
                    echo "💥 $(date): Критическая ошибка! Не удается восстановить LaMa"
                    # Отправляем уведомление (если настроено)
                    # notify_admin "LaMa service critical failure"
                fi
            fi
        fi
        
        sleep $check_interval
    done
}

# Функция разового исправления
fix_once() {
    echo "🔧 Разовое исправление LaMa..."
    
    if check_lama_health; then
        echo "✅ LaMa работает нормально, исправление не требуется"
        return 0
    fi
    
    echo "⚠️ LaMa неисправен, выполняем восстановление..."
    if restart_lama; then
        echo "✅ Восстановление успешно"
        return 0
    else
        echo "❌ Восстановление неудачно"
        return 1
    fi
}

# Функция показа статуса
show_status() {
    echo "📊 СТАТУС LAMA СЕРВИСА"
    echo "====================="
    
    echo "Systemd статус:"
    systemctl status lama-inpainting --no-pager | head -8
    
    echo ""
    echo "Процессы:"
    ps aux | grep -E "(service\.py|uvicorn)" | grep -v grep || echo "Нет активных процессов"
    
    echo ""
    echo "Порты:"
    netstat -tuln | grep 8080 || echo "Порт 8080 свободен"
    
    echo ""
    echo "API тест:"
    if curl -s --connect-timeout 3 "http://127.0.0.1:8080/health" >/dev/null; then
        echo "✅ API отвечает"
        curl -s "http://127.0.0.1:8080/health"
    else
        echo "❌ API не отвечает"
    fi
    
    echo ""
    echo "Nginx проксирование:"
    RESPONSE=$(curl -s -w "%{http_code}" "http://localhost/api/lama/health")
    HTTP_CODE="${RESPONSE: -3}"
    
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo "✅ Nginx проксирование работает"
    else
        echo "❌ Nginx проксирование не работает (HTTP $HTTP_CODE)"
    fi
}

# Обработка аргументов командной строки
case "${1:-status}" in
    "monitor")
        monitor_lama
        ;;
    "fix")
        fix_once
        ;;
    "restart")
        restart_lama
        ;;
    "status")
        show_status
        ;;
    *)
        echo "Использование: $0 [monitor|fix|restart|status]"
        echo ""
        echo "Команды:"
        echo "  monitor  - Запуск постоянного мониторинга"
        echo "  fix      - Разовое исправление если есть проблемы"
        echo "  restart  - Принудительный перезапуск"
        echo "  status   - Показать текущий статус (по умолчанию)"
        echo ""
        echo "Примеры:"
        echo "  $0 status    # Показать статус"
        echo "  $0 fix       # Исправить если не работает"
        echo "  $0 monitor   # Запустить постоянный мониторинг"
        ;;
esac