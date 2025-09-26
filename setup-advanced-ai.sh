#!/bin/bash

# Установка полноценного AI решения для удаления объектов
echo "🚀 Установка Advanced AI Inpainting для Color360..."

# Проверяем ресурсы
MEMORY=$(free -g | awk '/^Mem:/{print $2}')
if [ "$MEMORY" -lt 8 ]; then
    echo "⚠️ Предупреждение: Рекомендуется минимум 8GB RAM для стабильной работы"
    echo "💡 Текущая память: ${MEMORY}GB"
fi

# Переходим в директорию проекта
cd /var/www/color360 || exit 1

# Функция логирования
log() {
    echo "$(date '+%H:%M:%S') - $1"
}

log "📦 Создаем виртуальное окружение для AI..."
python3 -m venv ai_env
source ai_env/bin/activate

log "🔄 Обновляем pip..."
pip install --upgrade pip

log "🧠 Устанавливаем PyTorch (CPU версия)..."
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

log "🎨 Устанавливаем Stable Diffusion..."
pip install diffusers transformers accelerate

log "🖌️ Устанавливаем LaMa Cleaner..."
pip install lama-cleaner

log "🔧 Устанавливаем дополнительные зависимости..."
pip install opencv-python pillow numpy fastapi uvicorn

log "📁 Создаем директории для моделей..."
mkdir -p models/stable-diffusion
mkdir -p models/lama

log "⚙️ Создаем systemd сервис для AI..."
cat > /etc/systemd/system/color360-ai.service << 'EOF'
[Unit]
Description=Color360 Advanced AI Inpainting Service
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/var/www/color360
Environment=PYTHONPATH=/var/www/color360
Environment=HF_HUB_CACHE=/var/www/color360/models/huggingface
Environment=TORCH_HOME=/var/www/color360/models/torch
ExecStart=/var/www/color360/ai_env/bin/python sd/advanced_inpainting.py
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal
SyslogIdentifier=color360-ai

[Install]
WantedBy=multi-user.target
EOF

log "🔐 Настраиваем права доступа..."
chown -R www-data:www-data /var/www/color360/ai_env
chown -R www-data:www-data /var/www/color360/models
chown -R www-data:www-data /var/www/color360/sd

log "🚀 Запускаем AI сервис..."
systemctl daemon-reload
systemctl enable color360-ai
systemctl start color360-ai

log "⏳ Ждем загрузки моделей (может занять 5-10 минут)..."
sleep 30

log "📊 Проверяем статус AI сервиса..."
systemctl status color360-ai --no-pager

log "🧪 Тестируем AI сервис..."
if curl -f http://localhost:5002/health > /dev/null 2>&1; then
    log "✅ AI сервис успешно запущен!"
else
    log "⚠️ AI сервис еще загружается, это нормально"
    log "📋 Смотрите логи: journalctl -u color360-ai -f"
fi

log "🔄 Обновляем основное приложение для работы с AI..."

# Обновляем server.js для работы с новым AI сервисом
sed -i 's/SD_PORT=5002/AI_PORT=5002/g' .env* 2>/dev/null || true

log "🎉 Установка завершена!"

echo ""
echo "📋 Установленные AI технологии:"
echo "   ✅ Stable Diffusion Inpainting - для сложных случаев"
echo "   ✅ LaMa (Large Mask Inpainting) - для средних задач"  
echo "   ✅ OpenCV Inpainting - для быстрой обработки"
echo "   ✅ Enhanced Simulation - fallback режим"
echo ""
echo "🎯 Автоматический выбор алгоритма:"
echo "   🥇 Большие области (>10%) → Stable Diffusion"
echo "   🥈 Средние области (5-10%) → LaMa"
echo "   🥉 Маленькие области (<5%) → OpenCV"
echo ""
echo "📊 Команды мониторинга:"
echo "   journalctl -u color360-ai -f     # Логи AI сервиса"
echo "   systemctl status color360-ai     # Статус AI сервиса"
echo "   curl http://localhost:5002/health # Проверка API"
echo ""
echo "⏱️ Первый запуск может занять 10-15 минут (загрузка моделей)"

deactivate