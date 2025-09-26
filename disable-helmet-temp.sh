#!/bin/bash

echo "🚀 Временное отключение всех заголовков безопасности для диагностики..."

# Создаем backup
cp /var/www/color360/server.js /var/www/color360/server.js.backup.$(date +%Y%m%d_%H%M%S)

# Временно заменяем helmet на минимальный вариант
sed -i '/app.use(helmet(/,/}));/c\
// Временно отключен helmet для диагностики HTTPS редиректов\
app.use((req, res, next) => {\
  // Только базовые заголовки без форсирования HTTPS\
  res.setHeader("X-Content-Type-Options", "nosniff");\
  res.setHeader("X-Frame-Options", "DENY");\
  next();\
});' /var/www/color360/server.js

echo "✅ Helmet временно отключен"
echo "🔄 Перезапускаем приложение..."

systemctl restart color360-app

echo "🧪 Тестируем заголовки:"
curl -I http://color360.ru/ | grep -E "(Strict-Transport|Cross-Origin|upgrade-insecure)"

echo ""
echo "📝 Для возврата helmet:"
echo "cp /var/www/color360/server.js.backup.* /var/www/color360/server.js"