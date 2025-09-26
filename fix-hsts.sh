#!/bin/bash

echo "🔧 Исправление HSTS проблемы для Color360..."
echo "============================================="

# Backup nginx config
cp /etc/nginx/sites-available/color360 /etc/nginx/sites-available/color360.backup.$(date +%Y%m%d_%H%M%S)

echo "1. Временно отключаем HSTS заголовок в nginx..."

# Remove HSTS header temporarily
sed -i '/add_header Strict-Transport-Security/s/^/#/' /etc/nginx/sites-available/color360

echo "2. Проверяем конфигурацию nginx..."
nginx -t

if [ $? -eq 0 ]; then
    echo "3. Перезагружаем nginx..."
    systemctl reload nginx
    
    echo "4. Проверяем результат:"
    echo "HTTP заголовки без HSTS:"
    curl -I http://color360.ru/ 2>/dev/null | grep -i "strict-transport\|server\|content-type"
    
    echo ""
    echo "✅ HSTS временно отключен."
    echo "⚠️  Теперь браузер должен работать по HTTP."
    echo "📝 После настройки HTTPS раскомментируй HSTS обратно."
else
    echo "❌ Ошибка в конфигурации nginx!"
    # Restore backup
    cp /etc/nginx/sites-available/color360.backup.$(date +%Y%m%d)* /etc/nginx/sites-available/color360 2>/dev/null
fi

echo ""
echo "Для возврата HSTS после настройки TLS:"
echo "sed -i '/^#.*add_header Strict-Transport-Security/s/^#//' /etc/nginx/sites-available/color360"