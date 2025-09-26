#!/bin/bash
# Color360 LaMa Fix Script для быстрого исправления проблем на VPS

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

echo "🔧 Color360 LaMa Fix Script"
echo "=========================="

WORK_DIR="/var/www/color360"
cd ${WORK_DIR}

# 1. Остановка всех сервисов
log_info "Остановка сервисов..."
systemctl stop color360-app 2>/dev/null || true
systemctl stop color360-lama 2>/dev/null || true

# 2. Проверка Python окружения для LaMa
log_info "Проверка LaMa окружения..."
cd ${WORK_DIR}/sd

if [ ! -d "lama_env" ]; then
    log_info "Создание Python окружения..."
    python3 -m venv lama_env
fi

source lama_env/bin/activate
pip install --upgrade pip > /dev/null 2>&1
pip install -r requirements.txt > /dev/null 2>&1
deactivate

log_success "Python окружение готово"

# 3. Создание systemd сервиса для LaMa
log_info "Создание LaMa systemd сервиса..."
cat > /etc/systemd/system/color360-lama.service << 'EOF'
[Unit]
Description=Color360 LaMa Inpainting Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/color360/sd
Environment=PYTHONUNBUFFERED=1
Environment=PORT=5002
Environment=HOST=127.0.0.1
ExecStart=/var/www/color360/sd/lama_env/bin/python lama_service.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=color360-lama

[Install]
WantedBy=multi-user.target
EOF

# 4. Обновление основного сервиса
log_info "Обновление основного приложения сервиса..."
cat > /etc/systemd/system/color360-app.service << 'EOF'
[Unit]
Description=Color360 Main Application with LaMa Integration
After=network.target color360-lama.service

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/color360
Environment=NODE_ENV=production
Environment=LAMA_ENABLED=true
Environment=LAMA_PORT=5002
Environment=PORT=3000
ExecStart=/usr/local/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=color360-app

[Install]
WantedBy=multi-user.target
EOF

# 5. Настройка Nginx
log_info "Настройка Nginx..."
cat > /etc/nginx/sites-available/color360 << 'EOF'
server {
    listen 80;
    server_name _;
    
    client_max_body_size 50M;
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }
    
    # LaMa API endpoints
    location /api/lama-health {
        proxy_pass http://127.0.0.1:3000/api/lama-health;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    
    location /api/inpaint {
        proxy_pass http://127.0.0.1:3000/api/inpaint;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
    
    # Прямой доступ к LaMa для отладки
    location /lama/ {
        proxy_pass http://127.0.0.1:5002/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
    
    # Статические файлы
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|webp|mp4)$ {
        root /var/www/color360;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# Активация сайта
ln -sf /etc/nginx/sites-available/color360 /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Тест конфигурации Nginx
if nginx -t 2>/dev/null; then
    log_success "Nginx конфигурация валидна"
else
    log_error "Ошибка в конфигурации Nginx"
    nginx -t
fi

# 6. Перезагрузка systemd
systemctl daemon-reload

# 7. Включение автозапуска
systemctl enable color360-lama color360-app nginx

# 8. Запуск сервисов в правильном порядке
log_info "Запуск LaMa сервиса..."
systemctl start color360-lama
sleep 3

# Проверка LaMa
if systemctl is-active --quiet color360-lama; then
    log_success "LaMa сервис запущен ✓"
else
    log_error "LaMa сервис не запустился"
    journalctl -u color360-lama --no-pager -l | tail -10
    exit 1
fi

# Ждём загрузки LaMa
log_info "Ожидание готовности LaMa..."
for i in {1..30}; do
    if curl -s http://localhost:5002/health > /dev/null 2>&1; then
        log_success "LaMa API отвечает ✓"
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

# 9. Запуск основного приложения
log_info "Запуск основного приложения..."
systemctl start color360-app
sleep 3

if systemctl is-active --quiet color360-app; then
    log_success "Основное приложение запущено ✓"
else
    log_error "Основное приложение не запустилось"
    journalctl -u color360-app --no-pager -l | tail -10
    exit 1
fi

# 10. Перезапуск Nginx
log_info "Перезапуск Nginx..."
systemctl restart nginx

if systemctl is-active --quiet nginx; then
    log_success "Nginx запущен ✓"
else
    log_error "Nginx не запустился"
    exit 1
fi

# 11. Финальная проверка
log_info "Финальная проверка..."
sleep 5

# Проверка портов
PORTS_OK=0
if netstat -tuln | grep -q ":3000"; then
    log_success "Порт 3000 (основное приложение) ✓"
    ((PORTS_OK++))
fi

if netstat -tuln | grep -q ":5002"; then
    log_success "Порт 5002 (LaMa) ✓"
    ((PORTS_OK++))
fi

if netstat -tuln | grep -q ":80"; then
    log_success "Порт 80 (Nginx) ✓"
    ((PORTS_OK++))
fi

# Проверка API
API_OK=0
if curl -s http://localhost:3000 > /dev/null 2>&1; then
    log_success "Основное приложение отвечает ✓"
    ((API_OK++))
fi

if curl -s http://localhost:5002/health | grep -q "ok"; then
    log_success "LaMa API отвечает ✓"
    ((API_OK++))
fi

if curl -s http://localhost/api/lama-health > /dev/null 2>&1; then
    log_success "Nginx проксирование работает ✓"
    ((API_OK++))
else
    log_warning "Nginx проксирование может не работать"
fi

# Итоговый результат
echo ""
echo "🎉 Исправление завершено!"
echo "========================"
echo "📊 Статус:"
echo "   Порты: ${PORTS_OK}/3 работают"
echo "   API: ${API_OK}/3 отвечают"
echo ""
echo "🌐 Доступ:"
echo "   Сайт: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP')"
echo "   LaMa прямо: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP')/lama/health"
echo ""
echo "🛠️ Команды для проверки:"
echo "   systemctl status color360-app color360-lama nginx"
echo "   curl http://localhost/api/lama-health"
echo "   journalctl -u color360-app -f"
echo "   journalctl -u color360-lama -f"
echo ""

if [ $PORTS_OK -ge 2 ] && [ $API_OK -ge 2 ]; then
    log_success "✅ Color360 с LaMa успешно исправлен и работает!"
else
    log_warning "⚠️ Есть проблемы, проверьте логи выше"
fi