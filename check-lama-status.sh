#!/bin/bash
# Диагностика LaMa AI сервиса

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

echo ""
echo -e "${BLUE}🔍 ДИАГНОСТИКА LAMA AI СЕРВИСА${NC}"
echo "=================================="

# 1. Проверка файлов
log_info "📁 Проверка файловой структуры..."

if [ -f "/var/www/color360/lama/service.py" ]; then
    log_success "service.py найден"
else
    log_error "service.py не найден"
fi

if [ -f "/var/www/color360/lama/requirements.txt" ]; then
    log_success "requirements.txt найден"
else
    log_error "requirements.txt не найден"
fi

if [ -d "/var/www/color360/lama/lama_env" ]; then
    log_success "Python окружение найдено"
else
    log_error "Python окружение НЕ найдено"
fi

# 2. Проверка systemd сервиса
log_info "⚙️ Проверка systemd сервиса..."

if [ -f "/etc/systemd/system/color360-lama.service" ]; then
    log_success "Systemd сервис найден"
else
    log_error "Systemd сервис НЕ найден"
fi

# Статус сервиса
if systemctl is-enabled --quiet color360-lama 2>/dev/null; then
    log_success "Сервис включен (enabled)"
else
    log_warning "Сервис НЕ включен"
fi

if systemctl is-active --quiet color360-lama 2>/dev/null; then
    log_success "Сервис активен (запущен)"
else
    log_error "Сервис НЕ активен (остановлен)"
fi

# 3. Проверка портов
log_info "🌐 Проверка портов..."

if ss -tlnp | grep :5002 >/dev/null 2>&1; then
    log_success "Порт 5002 слушается"
    PORT_PROCESS=$(ss -tlnp | grep :5002)
    echo "   $PORT_PROCESS"
else
    log_error "Порт 5002 НЕ слушается"
fi

# 4. Проверка API
log_info "🔗 Проверка LaMa API..."

if curl -s --connect-timeout 5 http://localhost:5002/health >/dev/null 2>&1; then
    HEALTH_RESPONSE=$(curl -s http://localhost:5002/health 2>/dev/null)
    log_success "LaMa API отвечает"
    echo "   Ответ: $HEALTH_RESPONSE"
else
    log_error "LaMa API НЕ отвечает"
fi

# 5. Проверка Python зависимостей
log_info "🐍 Проверка Python зависимостей..."

if [ -f "/var/www/color360/lama/lama_env/bin/python" ]; then
    cd /var/www/color360/lama
    source lama_env/bin/activate 2>/dev/null
    
    # Проверяем основные пакеты
    if python -c "import lama_cleaner" 2>/dev/null; then
        LAMA_VER=$(python -c "import lama_cleaner; print(lama_cleaner.__version__)" 2>/dev/null || echo "unknown")
        log_success "LaMa Cleaner: $LAMA_VER"
    else
        log_error "LaMa Cleaner НЕ установлен"
    fi
    
    if python -c "import torch" 2>/dev/null; then
        TORCH_VER=$(python -c "import torch; print(torch.__version__)" 2>/dev/null || echo "unknown")
        log_success "PyTorch: $TORCH_VER"
    else
        log_error "PyTorch НЕ установлен"
    fi
    
    if python -c "import fastapi" 2>/dev/null; then
        FASTAPI_VER=$(python -c "import fastapi; print(fastapi.__version__)" 2>/dev/null || echo "unknown")
        log_success "FastAPI: $FASTAPI_VER"
    else
        log_error "FastAPI НЕ установлен"
    fi
    
    deactivate 2>/dev/null || true
else
    log_error "Python окружение недоступно"
fi

# 6. Проверка логов
log_info "📋 Последние логи сервиса..."

if systemctl is-active --quiet color360-lama 2>/dev/null; then
    echo "--- Последние 10 строк логов ---"
    journalctl -u color360-lama --no-pager -n 10
else
    log_warning "Сервис не запущен - логи недоступны"
fi

# 7. Итоговая диагностика
echo ""
echo -e "${BLUE}📊 ИТОГОВАЯ ДИАГНОСТИКА:${NC}"

ISSUES=0

if [ ! -d "/var/www/color360/lama/lama_env" ]; then
    log_error "Проблема: Python окружение не создано"
    echo "   Решение: bash install-lama-ai.sh"
    ISSUES=$((ISSUES + 1))
fi

if ! systemctl is-active --quiet color360-lama 2>/dev/null; then
    log_error "Проблема: LaMa сервис не запущен"
    echo "   Решение: systemctl start color360-lama"
    ISSUES=$((ISSUES + 1))
fi

if ! ss -tlnp | grep :5002 >/dev/null 2>&1; then
    log_error "Проблема: Порт 5002 не слушается"
    echo "   Решение: Проверьте логи - journalctl -u color360-lama -f"
    ISSUES=$((ISSUES + 1))
fi

if ! curl -s --connect-timeout 5 http://localhost:5002/health >/dev/null 2>&1; then
    log_error "Проблема: LaMa API недоступен"
    echo "   Решение: systemctl restart color360-lama"
    ISSUES=$((ISSUES + 1))
fi

if [ $ISSUES -eq 0 ]; then
    log_success "🎉 LaMa AI работает корректно!"
else
    log_warning "Найдено проблем: $ISSUES"
fi

echo ""
echo -e "${YELLOW}🔧 КОМАНДЫ ДЛЯ ИСПРАВЛЕНИЯ:${NC}"
echo "   Установка:     bash install-lama-ai.sh"
echo "   Запуск:        systemctl start color360-lama"
echo "   Перезапуск:    systemctl restart color360-lama"
echo "   Логи:          journalctl -u color360-lama -f"
echo "   Статус:        systemctl status color360-lama"