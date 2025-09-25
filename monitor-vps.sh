#!/bin/bash

# Мониторинг Color360 на VPS
echo "📊 Мониторинг Color360..."

while true; do
    clear
    echo "=== Color360 VPS Мониторинг ==="
    echo "Время: $(date)"
    echo ""
    
    # Статус systemd сервиса
    echo "🔧 Systemd сервис:"
    if sudo systemctl is-active --quiet color360-app; then
        echo "✅ Активен"
    else
        echo "❌ Неактивен"
    fi
    
    # Процессы Node.js
    echo ""
    echo "💻 Node.js процессы:"
    NODE_COUNT=$(ps aux | grep -c "[n]ode.*server.js")
    if [ "$NODE_COUNT" -gt 0 ]; then
        echo "✅ Найдено $NODE_COUNT процесс(ов)"
        ps aux | grep "[n]ode.*server.js" | head -3
    else
        echo "❌ Node.js процессы не найдены"
    fi
    
    # Порт 3000
    echo ""
    echo "🌐 Порт 3000:"
    if netstat -tlnp | grep -q :3000; then
        echo "✅ Прослушивается"
        netstat -tlnp | grep :3000
    else
        echo "❌ Не прослушивается"
    fi
    
    # HTTP тест
    echo ""
    echo "🔗 HTTP доступность:"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ HTTP 200 OK"
    else
        echo "❌ HTTP $HTTP_CODE"
    fi
    
    # Память
    echo ""
    echo "💾 Использование памяти:"
    free -h | grep '^Mem:' | awk '{printf "Всего: %s, Используется: %s, Свободно: %s\n", $2, $3, $4}'
    
    # Диск
    echo ""
    echo "💿 Свободное место:"
    df -h / | tail -1 | awk '{printf "Используется: %s из %s (%s), Свободно: %s\n", $3, $2, $5, $4}'
    
    # Последние логи
    echo ""
    echo "📋 Последние логи (последние 3 строки):"
    sudo journalctl -u color360-app --no-pager -n 3 -o short-precise 2>/dev/null || echo "Логи недоступны"
    
    echo ""
    echo "Нажмите Ctrl+C для выхода, обновление через 10 секунд..."
    echo "=============================================="
    
    sleep 10
done