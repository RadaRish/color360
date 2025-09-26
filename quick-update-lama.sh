#!/bin/bash
# Color360 LaMa Quick Update Script для VPS
# Быстрое обновление без переустановки зависимостей

set -e

WORK_DIR="/var/www/color360"
BRANCH="main"

# Цвета
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

echo "🔄 Color360 LaMa Quick Update"
echo "============================"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Запустите с правами root: sudo bash $0"
    exit 1
fi

# Переход в рабочую директорию
cd ${WORK_DIR}

# Остановка сервисов
log_info "Остановка сервисов..."
systemctl stop color360-app color360-lama

# Обновление кода
log_info "Обновление кода из GitHub..."
git fetch origin
git reset --hard origin/${BRANCH}
git clean -fd

# Обновление Node.js зависимостей (если изменился package.json)
if git diff HEAD~1 --name-only | grep -q "package.json"; then
    log_info "Обновление Node.js зависимостей..."
    npm install > /dev/null 2>&1
fi

# Обновление Python зависимостей (если изменился requirements.txt)
if git diff HEAD~1 --name-only | grep -q "sd/requirements.txt"; then
    log_info "Обновление Python зависимостей..."
    cd ${WORK_DIR}/sd
    source lama_env/bin/activate
    pip install -r requirements.txt > /dev/null 2>&1
    deactivate
    cd ${WORK_DIR}
fi

# Перезагрузка systemd если изменились файлы сервисов
systemctl daemon-reload

# Запуск сервисов
log_info "Запуск сервисов..."
systemctl start color360-lama
sleep 3
systemctl start color360-app
sleep 2

# Проверка статуса
if systemctl is-active --quiet color360-app && systemctl is-active --quiet color360-lama; then
    log_success "Обновление завершено успешно!"
    echo "🌐 Сайт: http://$(curl -s ifconfig.me)"
    echo "🎯 LaMa: curl http://localhost/api/lama-health"
else
    echo "❌ Ошибка запуска сервисов"
    systemctl status color360-app color360-lama --no-pager
    exit 1
fi