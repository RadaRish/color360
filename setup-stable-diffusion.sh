#!/bin/bash
# Скрипт установки и настройки Stable Diffusion для VPS
# Поддерживает Ubuntu 20.04+ и CentOS 8+

set -e

echo "🚀 Установка Stable Diffusion на VPS..."

# Определяем дистрибутив Linux
if [ -f /etc/lsb-release ]; then
    source /etc/lsb-release
    OS=$DISTRIB_ID
elif [ -f /etc/redhat-release ]; then
    OS="CentOS"
else
    OS=$(uname -s)
fi

echo "📋 Обнаружена система: $OS"

# Обновляем систему и устанавливаем базовые пакеты
echo "📦 Обновление системы..."
if [[ "$OS" == "Ubuntu" ]]; then
    sudo apt-get update -y
    sudo apt-get install -y python3 python3-pip python3-venv git curl wget build-essential
    # Устанавливаем NVIDIA драйверы если есть GPU
    if command -v nvidia-smi &> /dev/null; then
        echo "🎮 NVIDIA GPU обнаружена, устанавливаем CUDA..."
        sudo apt-get install -y nvidia-cuda-toolkit
    fi
elif [[ "$OS" == "CentOS" ]]; then
    sudo yum update -y
    sudo yum install -y python3 python3-pip git curl wget gcc gcc-c++ make
    # Устанавливаем NVIDIA драйверы если есть GPU
    if command -v nvidia-smi &> /dev/null; then
        echo "🎮 NVIDIA GPU обнаружена, устанавливаем CUDA..."
        sudo yum install -y cuda-toolkit
    fi
fi

# Проверяем версию Python
PYTHON_VERSION=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1,2)
echo "🐍 Версия Python: $PYTHON_VERSION"

if [[ $(echo "$PYTHON_VERSION 3.8" | awk '{print ($1 >= $2)}') -eq 0 ]]; then
    echo "❌ Требуется Python 3.8 или выше. Текущая версия: $PYTHON_VERSION"
    exit 1
fi

# Создаем директорию для проекта (если еще не существует)
PROJECT_DIR="/opt/color360"
if [ ! -d "$PROJECT_DIR" ]; then
    echo "📁 Создание директории проекта: $PROJECT_DIR"
    sudo mkdir -p "$PROJECT_DIR"
    sudo chown $USER:$USER "$PROJECT_DIR"
fi

cd "$PROJECT_DIR"

# Создаем виртуальное окружение для Stable Diffusion
echo "🔧 Создание виртуального окружения Python..."
if [ ! -d "sd_env" ]; then
    python3 -m venv sd_env
fi

# Активируем окружение
source sd_env/bin/activate

# Обновляем pip
echo "📦 Обновление pip..."
pip install --upgrade pip setuptools wheel

# Устанавливаем PyTorch (с поддержкой CUDA если доступна)
echo "🔥 Установка PyTorch..."
if command -v nvidia-smi &> /dev/null; then
    echo "🎮 Устанавливаем PyTorch с поддержкой CUDA..."
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
else
    echo "💻 Устанавливаем PyTorch только для CPU..."
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
fi

# Устанавливаем зависимости Stable Diffusion
echo "🎨 Установка Stable Diffusion зависимостей..."
if [ -f "sd/requirements.txt" ]; then
    pip install -r sd/requirements.txt
else
    echo "📝 Создание requirements.txt для Stable Diffusion..."
    cat > sd_requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
diffusers==0.24.0
transformers==4.35.2
accelerate==0.24.1
safetensors==0.4.0
Pillow==10.1.0
opencv-python==4.8.1.78
numpy==1.24.3
scipy==1.11.4
python-multipart==0.0.6
aiofiles==23.2.1
psutil==5.9.6
imageio==2.31.5
imageio-ffmpeg==0.4.9
EOF
    pip install -r sd_requirements.txt
fi

# Проверяем установку
echo "✅ Проверка установки..."
python -c "
import torch
import diffusers
import transformers
print(f'✅ PyTorch: {torch.__version__}')
print(f'✅ Diffusers: {diffusers.__version__}') 
print(f'✅ Transformers: {transformers.__version__}')
print(f'✅ CUDA доступна: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'✅ GPU: {torch.cuda.get_device_name(0)}')
"

# Предварительная загрузка модели (опционально)
echo "📥 Хотите загрузить модель Stable Diffusion сейчас? (y/N)"
read -r DOWNLOAD_MODEL
if [[ "$DOWNLOAD_MODEL" =~ ^[Yy]$ ]]; then
    echo "📥 Загрузка модели Stable Diffusion Inpainting..."
    python -c "
from diffusers import StableDiffusionInpaintPipeline
import torch

print('Загрузка модели...')
pipeline = StableDiffusionInpaintPipeline.from_pretrained(
    'runwayml/stable-diffusion-inpainting',
    torch_dtype=torch.float16 if torch.cuda.is_available() else torch.float32,
    low_cpu_mem_usage=True,
    use_safetensors=True
)
print('✅ Модель успешно загружена и кэширована')
"
fi

# Создаем systemd сервис для автозапуска
echo "🔧 Создание systemd сервиса..."
sudo tee /etc/systemd/system/color360-sd.service > /dev/null << EOF
[Unit]
Description=Color360 Stable Diffusion Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$PROJECT_DIR/sd
Environment=PATH=$PROJECT_DIR/sd_env/bin
ExecStart=$PROJECT_DIR/sd_env/bin/python sd_app.py
Restart=always
RestartSec=10

# Environment variables
Environment=PORT=5002
Environment=HOST=127.0.0.1
Environment=PYTHONUNBUFFERED=1

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$PROJECT_DIR

[Install]
WantedBy=multi-user.target
EOF

# Перезагружаем systemd и включаем сервис
sudo systemctl daemon-reload
sudo systemctl enable color360-sd.service

echo "🎉 Установка Stable Diffusion завершена!"
echo ""
echo "📋 Следующие шаги:"
echo "1. Скопируйте файл sd_app.py в $PROJECT_DIR/sd/"
echo "2. Запустите сервис: sudo systemctl start color360-sd"
echo "3. Проверьте статус: sudo systemctl status color360-sd"
echo "4. Проверьте логи: sudo journalctl -u color360-sd -f"
echo ""
echo "🔗 Тестирование:"
echo "curl http://localhost:5002/health"
echo ""
echo "⚙️ Конфигурация:"
echo "- Рабочая директория: $PROJECT_DIR"
echo "- Python окружение: $PROJECT_DIR/sd_env"
echo "- Systemd сервис: color360-sd.service"
echo "- Порт: 5002"
echo "- Хост: 127.0.0.1"

deactivate