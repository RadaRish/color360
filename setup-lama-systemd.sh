#!/bin/bash

# Создание systemd сервиса для LaMa
echo "🔧 СОЗДАНИЕ SYSTEMD СЕРВИСА ДЛЯ LAMA"
echo "===================================="

# Определяем пути
LAMA_DIR="/var/www/color360/lama"
SERVICE_NAME="lama-inpainting"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo "ℹ️  Создание systemd unit файла..."

# Создаем systemd сервис файл
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=LaMa AI Inpainting Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$LAMA_DIR
Environment=PATH=$LAMA_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin
ExecStartPre=/bin/bash -c 'cd $LAMA_DIR && source venv/bin/activate'
ExecStart=$LAMA_DIR/venv/bin/python service.py
Restart=always
RestartSec=10
StandardOutput=append:$LAMA_DIR/lama_systemd.log
StandardError=append:$LAMA_DIR/lama_systemd.log

# Настройки безопасности
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

echo "✅ Создан файл сервиса: $SERVICE_FILE"

echo ""
echo "ℹ️  Настройка systemd..."

# Перезагружаем systemd
systemctl daemon-reload

# Включаем автозапуск
systemctl enable $SERVICE_NAME

echo "✅ Автозапуск включен"

echo ""
echo "🛑 Останавливаем старые процессы..."
pkill -f service.py 2>/dev/null || true
sleep 2

echo ""
echo "🚀 Запуск сервиса через systemd..."
systemctl start $SERVICE_NAME

echo ""
echo "⏳ Ждем запуска (10 секунд)..."
sleep 10

echo ""
echo "📊 Статус сервиса:"
systemctl status $SERVICE_NAME --no-pager

echo ""
echo "🧪 Проверка API:"
if curl -s --connect-timeout 3 "http://localhost:8080/health" >/dev/null 2>&1; then
    echo "✅ API доступен"
    curl -s "http://localhost:8080/health"
else
    echo "❌ API недоступен"
    echo "Последние строки лога:"
    tail -10 $LAMA_DIR/lama_systemd.log
fi

echo ""
echo "🏁 НАСТРОЙКА ЗАВЕРШЕНА"
echo "====================="
echo "Команды управления сервисом:"
echo "  systemctl start $SERVICE_NAME    - запуск"
echo "  systemctl stop $SERVICE_NAME     - остановка"
echo "  systemctl restart $SERVICE_NAME  - перезапуск"
echo "  systemctl status $SERVICE_NAME   - статус"
echo "  journalctl -u $SERVICE_NAME -f   - просмотр логов"
echo ""
echo "Лог файл: $LAMA_DIR/lama_systemd.log"
echo "API: http://localhost:8080 и http://color360.online:8080"