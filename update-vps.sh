#!/bin/bash
# Скрипт обновления Color360 на VPS сервере
# Автоматически загружает изменения с GitHub и перезапускает сервисы

set -e

# Конфигурация
PROJECT_DIR="/var/www/color360"
GIT_REPO="https://github.com/RadaRish/color360.git"
BRANCH="main"
BACKUP_DIR="/var/www/color360-backups"

echo "🔄 Обновление Color360 на VPS сервере..."

# Проверяем место на диске
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 85 ]; then
    echo "⚠️ Предупреждение: Диск заполнен на ${DISK_USAGE}%"
    echo "💡 Рекомендуется очистить диск перед обновлением:"
    echo "   wget https://raw.githubusercontent.com/RadaRish/color360/main/clean-vps-disk.sh && chmod +x clean-vps-disk.sh && ./clean-vps-disk.sh"
    if [ "$DISK_USAGE" -gt 95 ]; then
        echo "❌ Критически мало места (${DISK_USAGE}%). Обновление прервано."
        echo "🔧 Сначала освободите место на диске."
        exit 1
    fi
fi

# Проверяем права и определяем режим работы
IS_ROOT=false
if [[ $EUID -eq 0 ]]; then
    echo "⚠️ Запуск от root пользователя. Будут использованы системные команды."
    IS_ROOT=true
    # Проверяем существование пользователя color360
    if ! id "color360" &>/dev/null; then
        echo "📝 Создание пользователя color360..."
        useradd -r -s /bin/bash -d "$PROJECT_DIR" color360 || true
    fi
fi

echo "🧹 Очистка старых файлов и директорий..."

# Очистка временных файлов и кэшей
if [ "$IS_ROOT" = true ]; then
    rm -rf "$PROJECT_DIR/temp/*" 2>/dev/null || true
    rm -rf "$PROJECT_DIR/.cache/*" 2>/dev/null || true
    rm -rf "$PROJECT_DIR/node_modules/.cache" 2>/dev/null || true
    rm -rf "$PROJECT_DIR"/*.log 2>/dev/null || true
else
    sudo rm -rf "$PROJECT_DIR/temp/*" 2>/dev/null || true
    sudo rm -rf "$PROJECT_DIR/.cache/*" 2>/dev/null || true
    sudo rm -rf "$PROJECT_DIR/node_modules/.cache" 2>/dev/null || true
    sudo rm -rf "$PROJECT_DIR"/*.log 2>/dev/null || true
fi

# Удаление старых бэкапов если они есть
if [ -d "$BACKUP_DIR" ]; then
    echo "🗑️ Удаление старых бэкапов..."
    if [ "$IS_ROOT" = true ]; then
        rm -rf "$BACKUP_DIR"/* 2>/dev/null || true
    else
        sudo rm -rf "$BACKUP_DIR"/* 2>/dev/null || true
    fi
fi

# Очистка старых версий сайта и редактора
echo "🗂️ Очистка старых версий..."
CLEANUP_DIRS=(
    "/var/www/html/color360*"
    "/var/www/color360-*"
    "/opt/color360*"
    "/home/*/color360*"
    "/tmp/color360*"
)

for dir_pattern in "${CLEANUP_DIRS[@]}"; do
    if [ "$IS_ROOT" = true ]; then
        rm -rf $dir_pattern 2>/dev/null || true
    else
        sudo rm -rf $dir_pattern 2>/dev/null || true
    fi
done

echo "✅ Очистка завершена"

# Остановка сервисов
echo "🛑 Остановка сервисов..."
if [ "$IS_ROOT" = true ]; then
    systemctl stop color360-app color360-sd nginx || true
else
    sudo systemctl stop color360-app color360-sd nginx || true
fi

# Переходим в директорию проекта
cd "$PROJECT_DIR"

# Исправляем проблему с правами Git репозитория
if [ "$IS_ROOT" = true ]; then
    git config --global --add safe.directory "$PROJECT_DIR"
fi

# Проверяем git статус
echo "📊 Проверка Git статуса..."
git status

# Создаем stash для локальных изменений (если есть)
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "💾 Сохранение локальных изменений в stash..."
    git stash push -m "Auto-stash before update $(date)"
fi

# Получаем обновления
echo "📥 Загрузка обновлений с GitHub..."
git fetch origin
git reset --hard origin/$BRANCH

# Обновляем Node.js зависимости
echo "📦 Обновление Node.js зависимостей..."
if [ "$IS_ROOT" = true ]; then
    # Устанавливаем права на проект для пользователя color360
    chown -R color360:color360 "$PROJECT_DIR"
    sudo -u color360 npm install --production
else
    sudo -u color360 npm install --production
fi

# Проверяем изменения в Python зависимостях
if [ -f "sd/requirements.txt" ]; then
    echo "🐍 Проверка Python зависимостей..."
    
    # Активируем виртуальное окружение и обновляем зависимости
    if [ -d "sd_env" ]; then
        echo "📦 Обновление Python пакетов..."
        if [ "$IS_ROOT" = true ]; then
            sudo -u color360 bash -c "source sd_env/bin/activate && pip install --upgrade -r sd/requirements.txt"
        else
            sudo -u color360 bash -c "source sd_env/bin/activate && pip install --upgrade -r sd/requirements.txt"
        fi
    else
        echo "⚠️ Виртуальное окружение не найдено. Создаем новое..."
        if [ "$IS_ROOT" = true ]; then
            sudo -u color360 python3 -m venv sd_env
            sudo -u color360 bash -c "source sd_env/bin/activate && pip install --upgrade pip && pip install -r sd/requirements.txt"
        else
            sudo -u color360 python3 -m venv sd_env
            sudo -u color360 bash -c "source sd_env/bin/activate && pip install --upgrade pip && pip install -r sd/requirements.txt"
        fi
    fi
fi

# Проверяем конфигурационные файлы
echo "⚙️ Проверка конфигурации..."

# Обновляем systemd сервисы если изменились
if [ -f "deploy-full-vps.sh" ]; then
    echo "🔧 Проверка systemd сервисов..."
    
    # Проверяем, нужно ли обновить сервисы
    NEED_RELOAD=false
    
    if ! sudo systemctl is-enabled color360-app >/dev/null 2>&1; then
        echo "📝 Создание systemd сервиса для основного приложения..."
        sudo tee /etc/systemd/system/color360-app.service > /dev/null << EOF
[Unit]
Description=Color360 Main Application
After=network.target
Wants=color360-sd.service

[Service]
Type=simple
User=color360
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5

# Environment
Environment=NODE_ENV=production
Environment=PORT=3000
Environment=SD_PORT=5002
Environment=SD_HOST=127.0.0.1

# Security
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$PROJECT_DIR
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
        NEED_RELOAD=true
    fi
    
    if ! sudo systemctl is-enabled color360-sd >/dev/null 2>&1; then
        echo "📝 Создание systemd сервиса для Stable Diffusion..."
        sudo tee /etc/systemd/system/color360-sd.service > /dev/null << EOF
[Unit]
Description=Color360 Stable Diffusion Service
After=network.target

[Service]
Type=simple
User=color360
WorkingDirectory=$PROJECT_DIR/sd
Environment=PATH=$PROJECT_DIR/sd_env/bin
ExecStart=$PROJECT_DIR/sd_env/bin/python sd_app.py
Restart=always
RestartSec=10

# Environment
Environment=PORT=5002
Environment=HOST=127.0.0.1
Environment=PYTHONUNBUFFERED=1

# Security
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$PROJECT_DIR
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
        NEED_RELOAD=true
    fi
    
    if [ "$NEED_RELOAD" = true ]; then
        if [ "$IS_ROOT" = true ]; then
            systemctl daemon-reload
            systemctl enable color360-app color360-sd
        else
            sudo systemctl daemon-reload
            sudo systemctl enable color360-app color360-sd
        fi
    fi
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

# Проверяем nginx конфигурацию
echo "🌐 Проверка nginx конфигурации..."
if [ "$IS_ROOT" = true ]; then
    nginx -t
else
    sudo nginx -t
fi

# Запуск сервисов
echo "🚀 Запуск сервисов..."
if [ "$IS_ROOT" = true ]; then
    systemctl start color360-sd
    sleep 5  # Даем время SD сервису запуститься
    
    systemctl start color360-app
    systemctl start nginx
else
    sudo systemctl start color360-sd
    sleep 5  # Даем время SD сервису запуститься
    
    sudo systemctl start color360-app
    sudo systemctl start nginx
fi

# Проверяем статус сервисов
echo "✅ Проверка статуса сервисов..."
sleep 10

echo "📊 Статус color360-sd:"
if [ "$IS_ROOT" = true ]; then
    systemctl is-active color360-sd --quiet && echo "✅ Активен" || echo "❌ Неактивен"
else
    sudo systemctl is-active color360-sd --quiet && echo "✅ Активен" || echo "❌ Неактивен"
fi

echo "📊 Статус color360-app:"
if [ "$IS_ROOT" = true ]; then
    if systemctl is-active color360-app --quiet; then
        echo "✅ Активен"
    else
        echo "❌ Неактивен - проверяем логи..."
        systemctl status color360-app --no-pager -l || true
    fi
else
    if sudo systemctl is-active color360-app --quiet; then
        echo "✅ Активен"
    else
        echo "❌ Неактивен - проверяем логи..."
        sudo systemctl status color360-app --no-pager -l || true
    fi
fi

echo "📊 Статус nginx:"
if [ "$IS_ROOT" = true ]; then
    systemctl is-active nginx --quiet && echo "✅ Активен" || echo "❌ Неактивен"
else
    sudo systemctl is-active nginx --quiet && echo "✅ Активен" || echo "❌ Неактивен"
fi

# Тестирование endpoint-ов
echo "🔍 Тестирование приложения..."

if curl -f -s http://localhost:3000/ > /dev/null; then
    echo "✅ Основное приложение отвечает"
else
    echo "❌ Основное приложение не отвечает"
    echo "📜 Последние логи:"
    if [ "$IS_ROOT" = true ]; then
        journalctl -u color360-app --no-pager -n 10
    else
        sudo journalctl -u color360-app --no-pager -n 10
    fi
fi

if curl -f -s http://localhost:5002/health > /dev/null; then
    echo "✅ Stable Diffusion сервис работает"
else
    echo "⚠️ Stable Diffusion сервис не отвечает (может еще загружаться)"
fi

# Показываем информацию о бэкапе
echo ""
echo "🎉 Обновление завершено!"
echo ""
echo "📋 Информация об обновлении:"
echo "   📅 Время: $(date)"
echo "   🌿 Ветка: $BRANCH"
echo "   📝 Коммит: $(git rev-parse --short HEAD)"
echo ""
echo "📊 Полезные команды для мониторинга:"
echo "   systemctl status color360-app color360-sd"
echo "   journalctl -u color360-app -f"
echo "   journalctl -u color360-sd -f"
echo ""
echo "🔄 Управление сервисами:"
echo "   systemctl restart color360-app color360-sd"
echo "   systemctl stop color360-app color360-sd"
echo "   systemctl start color360-app color360-sd"

# Финальная очистка системы
echo "🧹 Финальная очистка системы..."
if [ "$IS_ROOT" = true ]; then
    # Очистка npm кэша
    npm cache clean --force 2>/dev/null || true
    # Очистка логов старше 7 дней
    find /var/log -name "*.log" -mtime +7 -delete 2>/dev/null || true
    # Очистка временных файлов
    find /tmp -name "*color360*" -mtime +1 -delete 2>/dev/null || true
else
    sudo npm cache clean --force 2>/dev/null || true
    sudo find /var/log -name "*.log" -mtime +7 -delete 2>/dev/null || true
    sudo find /tmp -name "*color360*" -mtime +1 -delete 2>/dev/null || true
fi
echo "✅ Система очищена"