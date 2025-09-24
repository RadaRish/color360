#!/bin/bash
# Скрипт обновления Color360 на VPS сервере
# Автоматически загружает изменения с GitHub и перезапускает сервисы

set -e

# Конфигурация
PROJECT_DIR="/opt/color360"
GIT_REPO="https://github.com/RadaRish/color360.git"
BRANCH="main"
BACKUP_DIR="/opt/color360-backups"

echo "🔄 Обновление Color360 на VPS сервере..."

# Проверяем права
if [[ $EUID -eq 0 ]]; then
   echo "❌ Не запускайте скрипт от root. Используйте sudo для отдельных команд."
   exit 1
fi

# Создаем директорию для бэкапов
sudo mkdir -p "$BACKUP_DIR"
BACKUP_NAME="backup-$(date +%Y%m%d-%H%M%S)"

echo "📁 Создание бэкапа: $BACKUP_NAME"

# Бэкап текущей версии
sudo cp -r "$PROJECT_DIR" "$BACKUP_DIR/$BACKUP_NAME"
echo "✅ Бэкап создан: $BACKUP_DIR/$BACKUP_NAME"

# Остановка сервисов
echo "🛑 Остановка сервисов..."
sudo systemctl stop color360-app color360-sd nginx || true

# Переходим в директорию проекта
cd "$PROJECT_DIR"

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
sudo -u color360 npm install --production

# Проверяем изменения в Python зависимостях
if [ -f "sd/requirements.txt" ]; then
    echo "🐍 Проверка Python зависимостей..."
    
    # Активируем виртуальное окружение и обновляем зависимости
    if [ -d "sd_env" ]; then
        echo "📦 Обновление Python пакетов..."
        sudo -u color360 bash -c "source sd_env/bin/activate && pip install --upgrade -r sd/requirements.txt"
    else
        echo "⚠️ Виртуальное окружение не найдено. Создаем новое..."
        sudo -u color360 python3 -m venv sd_env
        sudo -u color360 bash -c "source sd_env/bin/activate && pip install --upgrade pip && pip install -r sd/requirements.txt"
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
        sudo systemctl daemon-reload
        sudo systemctl enable color360-app color360-sd
    fi
fi

# Обновляем права доступа
echo "🔐 Обновление прав доступа..."
sudo chown -R color360:color360 "$PROJECT_DIR"
sudo chmod +x "$PROJECT_DIR"/*.sh 2>/dev/null || true

# Проверяем nginx конфигурацию
echo "🌐 Проверка nginx конфигурации..."
sudo nginx -t

# Запуск сервисов
echo "🚀 Запуск сервисов..."
sudo systemctl start color360-sd
sleep 5  # Даем время SD сервису запуститься

sudo systemctl start color360-app
sudo systemctl start nginx

# Проверяем статус сервисов
echo "✅ Проверка статуса сервисов..."
sleep 10

echo "📊 Статус color360-sd:"
sudo systemctl is-active color360-sd --quiet && echo "✅ Активен" || echo "❌ Неактивен"

echo "📊 Статус color360-app:"
sudo systemctl is-active color360-app --quiet && echo "✅ Активен" || echo "❌ Неактивен"

echo "📊 Статус nginx:"
sudo systemctl is-active nginx --quiet && echo "✅ Активен" || echo "❌ Неактивен"

# Тестирование endpoint-ов
echo "🔍 Тестирование приложения..."

if curl -f -s http://localhost:3000/ > /dev/null; then
    echo "✅ Основное приложение отвечает"
else
    echo "❌ Основное приложение не отвечает"
    echo "📜 Последние логи:"
    sudo journalctl -u color360-app --no-pager -n 10
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
echo "   📂 Бэкап: $BACKUP_DIR/$BACKUP_NAME"
echo "   🌿 Ветка: $BRANCH"
echo "   📝 Коммит: $(git rev-parse --short HEAD)"
echo ""
echo "📊 Полезные команды:"
echo "   sudo systemctl status color360-app"
echo "   sudo systemctl status color360-sd"
echo "   sudo journalctl -u color360-app -f"
echo "   sudo journalctl -u color360-sd -f"
echo ""
echo "🔄 Откат к предыдущей версии (если нужен):"
echo "   sudo systemctl stop color360-app color360-sd"
echo "   sudo rm -rf $PROJECT_DIR"
echo "   sudo mv $BACKUP_DIR/$BACKUP_NAME $PROJECT_DIR"
echo "   sudo systemctl start color360-sd color360-app"

# Очистка старых бэкапов (оставляем последние 5)
echo "🧹 Очистка старых бэкапов..."
cd "$BACKUP_DIR"
ls -t | tail -n +6 | sudo xargs -r rm -rf
echo "✅ Оставлено последние 5 бэкапов"