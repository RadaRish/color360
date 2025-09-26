#!/bin/bash
# Быстрое обновление Color360 с исправлениями ретуши

set -e

# Конфигурация
PROJECT_DIR="/var/www/color360"
GIT_REPO="https://github.com/RadaRish/color360.git"
BRANCH="main"

echo "⚡ Быстрое обновление Color360 с исправлениями ретуши..."

# Проверяем права и определяем режим работы
IS_ROOT=false
if [[ $EUID -eq 0 ]]; then
    echo "⚠️ Запуск от root пользователя."
    IS_ROOT=true
fi

# Остановка сервисов
echo "🛑 Остановка сервисов..."
if [ "$IS_ROOT" = true ]; then
    systemctl stop color360-app color360-sd || true
else
    sudo systemctl stop color360-app color360-sd || true
fi

# Переходим в директорию проекта
cd "$PROJECT_DIR"

# Исправляем проблему с правами Git репозитория
if [ "$IS_ROOT" = true ]; then
    git config --global --add safe.directory "$PROJECT_DIR"
fi

# Создаем stash для локальных изменений (если есть)
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "💾 Сохранение локальных изменений в stash..."
    git stash push -m "Auto-stash before quick update $(date)"
fi

# Получаем обновления
echo "📥 Загрузка обновлений с GitHub..."
git fetch origin
git reset --hard origin/$BRANCH

# Обновляем Node.js зависимости только если изменился package.json
if git diff --name-only HEAD~1 | grep -q "package.json"; then
    echo "📦 Обновление Node.js зависимостей..."
    if [ "$IS_ROOT" = true ]; then
        chown -R color360:color360 "$PROJECT_DIR"
        sudo -u color360 npm install --production
    else
        sudo -u color360 npm install --production
    fi
else
    echo "📦 Зависимости Node.js не изменились, пропускаем..."
fi

# Проверяем изменения в Python зависимостях
if git diff --name-only HEAD~1 | grep -q "sd/requirements.txt"; then
    echo "🐍 Обновление Python зависимостей..."
    if [ -d "sd_env" ]; then
        if [ "$IS_ROOT" = true ]; then
            sudo -u color360 bash -c "source sd_env/bin/activate && pip install --upgrade -r sd/requirements.txt"
        else
            sudo -u color360 bash -c "source sd_env/bin/activate && pip install --upgrade -r sd/requirements.txt"
        fi
    fi
else
    echo "🐍 Зависимости Python не изменились, пропускаем..."
fi

# Обновляем права доступа
echo "🔐 Обновление прав доступа..."
if [ "$IS_ROOT" = true ]; then
    chown -R color360:color360 "$PROJECT_DIR"
    chmod +x "$PROJECT_DIR"/*.sh 2>/dev/null || true
else
    sudo chown -R color360:color360 "$PROJECT_DIR"
    sudo chmod +x "$PROJECT_DIR"/*.sh 2>/dev/null || true
fi

# Запуск сервисов
echo "🚀 Запуск сервисов..."
if [ "$IS_ROOT" = true ]; then
    systemctl start color360-sd
    sleep 5
    systemctl start color360-app
else
    sudo systemctl start color360-sd
    sleep 5
    sudo systemctl start color360-app
fi

# Проверяем статус сервисов
echo "✅ Проверка статуса сервисов..."
sleep 5

echo "📊 Статус color360-sd:"
if [ "$IS_ROOT" = true ]; then
    systemctl is-active color360-sd --quiet && echo "✅ Активен" || echo "❌ Неактивен"
else
    sudo systemctl is-active color360-sd --quiet && echo "✅ Активен" || echo "❌ Неактивен"
fi

echo "📊 Статус color360-app:"
if [ "$IS_ROOT" = true ]; then
    systemctl is-active color360-app --quiet && echo "✅ Активен" || echo "❌ Неактивен"
else
    sudo systemctl is-active color360-app --quiet && echo "✅ Активен" || echo "❌ Неактивен"
fi

# Тестирование endpoint-ов
echo "🔍 Тестирование приложения..."

if curl -f -s http://localhost:3000/ > /dev/null; then
    echo "✅ Основное приложение отвечает"
else
    echo "❌ Основное приложение не отвечает"
fi

if curl -f -s http://localhost:5002/health > /dev/null; then
    echo "✅ Stable Diffusion сервис работает"
else
    echo "⚠️ Stable Diffusion сервис не отвечает (может еще загружаться)"
fi

echo ""
echo "⚡ Быстрое обновление завершено!"
echo ""
echo "📋 Информация об обновлении:"
echo "   📅 Время: $(date)"
echo "   🌿 Ветка: $BRANCH"
echo "   📝 Коммит: $(git rev-parse --short HEAD)"
echo ""
echo "🎨 Новые улучшения ретуши:"
echo "   ✓ Исправлены ошибки HTTP заголовков"
echo "   ✓ Добавлена симуляция удаления объектов"
echo "   ✓ Улучшена обработка недоступности AI"
echo "   ✓ Лучшие уведомления пользователю"
echo ""
echo "📱 Полезные команды:"
echo "   sudo journalctl -u color360-app -f  # Логи в реальном времени"
echo "   sudo systemctl restart color360-app # Перезапуск сервиса"
echo "   ./monitor-vps.sh                    # Мониторинг системы"
echo ""
echo "💡 Для полного обновления с бэкапом используйте: ./update-vps.sh"