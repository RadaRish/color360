#!/bin/bash
# Color360 Docker Entrypoint
# Подготовка и запуск всех сервисов

set -e

# Цвета для логов
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "🐳 Color360 Docker Container Starting..."
echo "======================================="

# Проверка окружения
log_info "Проверка окружения..."
echo "Node.js: $(node --version)"
echo "Python: $(python3 --version)"
echo "Working directory: $(pwd)"

# Проверка файлов проекта
log_info "Проверка файлов проекта..."
required_files=(
    "server.js"
    "package.json"
    "index.html"
    "lama/service.py"
    "lama/requirements.txt"
)

for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        log_success "✓ $file"
    else
        log_error "✗ $file отсутствует"
        exit 1
    fi
done

# Проверка Python окружения
log_info "Проверка LaMa окружения..."
if [ -d "lama/lama_env" ]; then
    log_success "Python окружение найдено"
    
    # Тест импорта ключевых модулей
    cd lama
    if ./lama_env/bin/python -c "import torch, lama_cleaner, fastapi; print('All modules OK')" 2>/dev/null; then
        log_success "Все Python модули доступны"
    else
        log_warning "Проблемы с Python модулями, но продолжаем..."
    fi
    cd ..
else
    log_error "Python окружение не найдено"
    exit 1
fi

# Создание необходимых директорий
log_info "Создание директорий..."
mkdir -p temp avatars news_images pano logs
chmod 755 temp avatars news_images pano

# Очистка логов supervisor
rm -f /var/log/supervisor/*.log

# Настройка прав доступа
log_info "Настройка прав доступа..."
chown -R root:root /app
chmod -R 755 /app
chmod 644 /app/*.html /app/*.js

# Предварительная проверка портов
log_info "Проверка доступности портов..."
if netstat -tlnp | grep -q ":3000\|:5002"; then
    log_warning "Порты уже заняты, освобождаем..."
    fuser -k 3000/tcp 2>/dev/null || true
    fuser -k 5002/tcp 2>/dev/null || true
    sleep 2
fi

# Тест LaMa сервиса перед основным запуском
log_info "Предварительный тест LaMa сервиса..."
cd lama
timeout 30 ./lama_env/bin/python -c "
import sys
sys.path.append('.')
try:
    from service import app
    print('LaMa service import OK')
except Exception as e:
    print(f'Import error: {e}')
    sys.exit(1)
" || {
    log_error "LaMa сервис не может быть импортирован"
    exit 1
}
cd ..

log_success "Предварительные проверки пройдены"

# Настройка Nginx
log_info "Настройка Nginx..."
nginx -t || {
    log_error "Конфигурация Nginx невалидна"
    exit 1
}

# Создание health check endpoint
log_info "Настройка health check..."
cat > /app/health.html << 'EOF'
<!DOCTYPE html>
<html><head><title>Color360 Health</title></head>
<body><h1>Color360 is Running</h1>
<p>Status: <span style="color:green">Healthy</span></p>
<p>Time: <script>document.write(new Date().toISOString())</script></p>
</body></html>
EOF

# Информация о запуске
echo ""
log_info "🚀 Запуск Color360..."
echo "Порты: 80 (Nginx), 3000 (App), 5002 (LaMa)"
echo "Supervisor будет управлять всеми процессами"
echo ""

# Финальная проверка
log_info "Последняя проверка перед запуском..."
if [ ! -f "/etc/supervisor/conf.d/color360.conf" ]; then
    log_error "Supervisor конфигурация не найдена"
    exit 1
fi

log_success "🎉 Готов к запуску!"

# Передача управления supervisor или выполнение команды
if [ "$1" = "supervisord" ]; then
    log_info "Запуск через Supervisor..."
    exec "$@"
elif [ "$1" = "bash" ] || [ "$1" = "sh" ]; then
    log_info "Запуск shell для отладки..."
    exec "$@"
else
    log_info "Выполнение команды: $*"
    exec "$@"
fi