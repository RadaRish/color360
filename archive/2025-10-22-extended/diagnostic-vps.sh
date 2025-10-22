#!/bin/bash

echo "🔍 Диагностика Color360 VPS..."
echo "================================"

echo ""
echo "1. Проверка nginx статуса:"
systemctl status nginx --no-pager -l | head -10

echo ""
echo "2. Проверка приложения:"
systemctl status color360-app --no-pager -l | head -10

echo ""
echo "3. Проверка портов:"
ss -tlnp | grep -E ':80|:443|:3000'

echo ""
echo "4. Проверка nginx конфига:"
nginx -t

echo ""
echo "5. Локальные тесты:"
echo "HTTP статика:"
curl -I http://localhost/assets/styles.css 2>/dev/null | head -5

echo ""
echo "HTTP главная:"
curl -I http://localhost/ 2>/dev/null | head -5

echo ""
echo "6. Внешние тесты:"
echo "HTTP статика извне:"
curl -I http://color360.ru/assets/styles.css 2>/dev/null | head -5

echo ""
echo "HTTP главная извне:" 
curl -I http://color360.ru/ 2>/dev/null | head -5

echo ""
echo "7. Проверка HSTS проблемы:"
echo "HTTPS попытка (должна фейлить):"
curl -I https://color360.ru/ 2>&1 | head -3

echo ""
echo "8. Логи nginx (последние ошибки):"
tail -20 /var/log/nginx/error.log 2>/dev/null || echo "Нет ошибок nginx"

echo ""
echo "9. Логи приложения (последние):"
journalctl -u color360-app -n 10 --no-pager 2>/dev/null || echo "Нет логов приложения"

echo ""
echo "10. Проверка файлов:"
ls -la /var/www/color360/assets/styles.css 2>/dev/null || echo "CSS файл не найден"
ls -la /var/www/color360/index.html 2>/dev/null || echo "HTML файл не найден"

echo ""
echo "Диагностика завершена!"