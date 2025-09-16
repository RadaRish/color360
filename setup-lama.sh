#!/bin/bash

# Скрипт установки и настройки LaMa inpainting сервиса
echo "🚀 Настройка LaMa inpainting сервиса..."

# Переходим в директорию lama
cd "$(dirname "$0")/lama"

# Проверяем наличие Python
if ! command -v python3 &> /dev/null; then
    echo "❌ Python3 не найден. Установите Python 3.8+ перед продолжением."
    exit 1
fi

echo "✅ Python3 найден: $(python3 --version)"

# Создаем виртуальное окружение
echo "📦 Создание виртуального окружения..."
python3 -m venv venv

# Активируем виртуальное окружение
echo "🔧 Активация виртуального окружения..."
source venv/bin/activate

# Обновляем pip
echo "⬆️ Обновление pip..."
pip install --upgrade pip

# Устанавливаем базовые зависимости
echo "📚 Установка базовых зависимостей..."
pip install -r requirements.txt

# Проверяем установку
echo "🔍 Проверка установки..."
python3 -c "import fastapi, uvicorn, PIL, numpy, cv2; print('✅ Все базовые зависимости установлены')"

echo ""
echo "🎉 Базовая настройка завершена!"
echo ""
echo "📋 Следующие шаги:"
echo "   1. Для улучшенной производительности установите LaMa модель:"
echo "      pip install torch torchvision lama-cleaner"
echo ""
echo "   2. Запуск сервиса:"
echo "      source lama/venv/bin/activate"
echo "      python3 lama/app.py"
echo ""
echo "   3. Или используйте PM2:"
echo "      pm2 start ecosystem.config.json"
echo ""
echo "⚠️  Внимание: Без LaMa модели будет использоваться OpenCV inpainting (базовое качество)"
echo "   Для полной функциональности установите torch и lama-cleaner"