#!/bin/bash
# Полный скрипт развертывания Color360 с Stable Diffusion на VPS
# Поддерживает Ubuntu 20.04+, CentOS 8+, и другие Linux дистрибутивы

set -e

# Конфигурация
DOMAIN=${DOMAIN:-""}
NODE_VERSION=${NODE_VERSION:-"18"}
PROJECT_DIR="/opt/color360"
GIT_REPO="https://github.com/RadaRish/color360.git"
BRANCH=${BRANCH:-"main"}
SSL_EMAIL=${SSL_EMAIL:-""}

echo "🚀 Полное развертывание Color360 с Stable Diffusion на VPS..."
echo "📋 Конфигурация:"
echo "   - Домен: ${DOMAIN:-"(не указан)"}"
echo "   - Node.js версия: $NODE_VERSION"
echo "   - Директория: $PROJECT_DIR"
echo "   - Ветка: $BRANCH"
echo "   - Email для SSL: ${SSL_EMAIL:-"(не указан)"}"

# Определяем дистрибутив Linux
if [ -f /etc/lsb-release ]; then
    source /etc/lsb-release
    OS=$DISTRIB_ID
elif [ -f /etc/redhat-release ]; then
    OS="CentOS"
else
    OS=$(uname -s)
fi

echo "📋 Система: $OS"

# Обновляем систему и устанавливаем базовые пакеты
echo "📦 Обновление системы..."
if [[ "$OS" == "Ubuntu" ]]; then
    sudo apt-get update -y
    sudo apt-get install -y curl wget git build-essential python3 python3-pip python3-venv
    
    # Устанавливаем Node.js через NodeSource
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo -E bash -
    sudo apt-get install -y nodejs
    
    # Nginx
    sudo apt-get install -y nginx
    
    # Certbot для SSL (если нужен домен)
    if [ -n "$DOMAIN" ]; then
        sudo apt-get install -y certbot python3-certbot-nginx
    fi
    
    # CUDA если есть GPU
    if command -v nvidia-smi &> /dev/null; then
        echo "🎮 NVIDIA GPU обнаружена, устанавливаем CUDA..."
        sudo apt-get install -y nvidia-cuda-toolkit
    fi
    
elif [[ "$OS" == "CentOS" ]]; then
    sudo yum update -y
    sudo yum install -y curl wget git gcc gcc-c++ make python3 python3-pip
    
    # Node.js
    curl -fsSL https://rpm.nodesource.com/setup_${NODE_VERSION}.x | sudo bash -
    sudo yum install -y nodejs
    
    # Nginx
    sudo yum install -y nginx
    
    # Certbot
    if [ -n "$DOMAIN" ]; then
        sudo yum install -y certbot python3-certbot-nginx
    fi
    
    # CUDA если есть GPU
    if command -v nvidia-smi &> /dev/null; then
        echo "🎮 NVIDIA GPU обнаружена, устанавливаем CUDA..."
        sudo yum install -y cuda-toolkit
    fi
fi

# Проверяем установку Node.js
echo "✅ Проверка установки Node.js..."
node --version
npm --version

# Создаем пользователя для приложения
if ! id "color360" &>/dev/null; then
    echo "👤 Создание пользователя color360..."
    sudo useradd --system --create-home --shell /bin/bash color360
fi

# Создаем директорию проекта
echo "📁 Создание директории проекта..."
sudo mkdir -p "$PROJECT_DIR"
sudo chown color360:color360 "$PROJECT_DIR"

# Клонируем репозиторий
echo "📥 Клонирование репозитория..."
if [ -d "$PROJECT_DIR/.git" ]; then
    echo "🔄 Обновление существующего репозитория..."
    sudo -u color360 git -C "$PROJECT_DIR" fetch origin
    sudo -u color360 git -C "$PROJECT_DIR" reset --hard origin/$BRANCH
else
    sudo -u color360 git clone --branch $BRANCH "$GIT_REPO" "$PROJECT_DIR"
fi

cd "$PROJECT_DIR"

# Устанавливаем Node.js зависимости
echo "📦 Установка Node.js зависимостей..."
sudo -u color360 npm install --production

# Настраиваем Python окружение для Stable Diffusion
echo "🐍 Настройка Python окружения для Stable Diffusion..."
sudo -u color360 python3 -m venv sd_env
sudo -u color360 bash -c "source sd_env/bin/activate && pip install --upgrade pip setuptools wheel"

# Устанавливаем PyTorch
echo "🔥 Установка PyTorch..."
if command -v nvidia-smi &> /dev/null; then
    echo "🎮 PyTorch с поддержкой CUDA..."
    sudo -u color360 bash -c "source sd_env/bin/activate && pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118"
else
    echo "💻 PyTorch для CPU..."
    sudo -u color360 bash -c "source sd_env/bin/activate && pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu"
fi

# Устанавливаем Stable Diffusion зависимости
echo "🎨 Установка Stable Diffusion зависимостей..."
if [ -f "sd/requirements.txt" ]; then
    sudo -u color360 bash -c "source sd_env/bin/activate && pip install -r sd/requirements.txt"
fi

# Предварительная загрузка модели
echo "📥 Предварительная загрузка модели Stable Diffusion..."
sudo -u color360 bash -c "
source sd_env/bin/activate
python -c '
from diffusers import StableDiffusionInpaintPipeline
import torch
print(\"Загрузка модели...\")
pipeline = StableDiffusionInpaintPipeline.from_pretrained(
    \"runwayml/stable-diffusion-inpainting\",
    torch_dtype=torch.float16 if torch.cuda.is_available() else torch.float32,
    low_cpu_mem_usage=True,
    use_safetensors=True
)
print(\"✅ Модель успешно загружена и кэширована\")
'
"

# Создаем systemd сервисы
echo "🔧 Создание systemd сервисов..."

# Сервис для Node.js приложения
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

# Сервис для Stable Diffusion
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

# Настраиваем Nginx
echo "🌐 Настройка Nginx..."
sudo tee /etc/nginx/sites-available/color360 > /dev/null << EOF
server {
    listen 80;
    server_name ${DOMAIN:-localhost};

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Main application
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Увеличиваем таймауты для AI обработки
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }

    # Increase max body size for image uploads
    client_max_body_size 50M;
    
    # Static files caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# Включаем сайт
if [ -d "/etc/nginx/sites-enabled" ]; then
    sudo ln -sf /etc/nginx/sites-available/color360 /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
fi

# Тестируем конфигурацию Nginx
sudo nginx -t

# Настраиваем SSL если указан домен
if [ -n "$DOMAIN" ] && [ -n "$SSL_EMAIL" ]; then
    echo "🔒 Настройка SSL сертификата..."
    sudo certbot --nginx -d "$DOMAIN" --email "$SSL_EMAIL" --agree-tos --non-interactive
fi

# Настраиваем firewall
echo "🔥 Настройка firewall..."
if command -v ufw &> /dev/null; then
    sudo ufw --force enable
    sudo ufw allow 22/tcp
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
elif command -v firewall-cmd &> /dev/null; then
    sudo firewall-cmd --permanent --add-service=ssh
    sudo firewall-cmd --permanent --add-service=http
    sudo firewall-cmd --permanent --add-service=https
    sudo firewall-cmd --reload
fi

# Перезагружаем и запускаем сервисы
echo "🚀 Запуск сервисов..."
sudo systemctl daemon-reload
sudo systemctl enable color360-sd color360-app nginx
sudo systemctl restart color360-sd color360-app nginx

# Ожидаем запуска сервисов
echo "⏳ Ожидание запуска сервисов..."
sleep 10

# Проверяем статус
echo "✅ Проверка статуса сервисов..."
sudo systemctl status color360-sd --no-pager -l
sudo systemctl status color360-app --no-pager -l
sudo systemctl status nginx --no-pager -l

# Финальная проверка
echo "🔍 Тестирование работы приложения..."
if curl -f -s http://localhost:3000/ > /dev/null; then
    echo "✅ Node.js приложение работает"
else
    echo "❌ Node.js приложение не отвечает"
fi

if curl -f -s http://localhost:5002/health > /dev/null; then
    echo "✅ Stable Diffusion сервис работает"
else
    echo "⚠️ Stable Diffusion сервис не отвечает (может еще загружаться)"
fi

echo ""
echo "🎉 Развертывание Color360 завершено!"
echo ""
echo "📋 Информация о системе:"
echo "   🌐 Домен: ${DOMAIN:-"http://$(curl -s ifconfig.me || echo 'localhost')"}"
echo "   📁 Директория: $PROJECT_DIR"
echo "   👤 Пользователь: color360"
echo "   🔧 Node.js порт: 3000"
echo "   🎨 Stable Diffusion порт: 5002"
echo ""
echo "📊 Управление сервисами:"
echo "   sudo systemctl start|stop|restart color360-app"
echo "   sudo systemctl start|stop|restart color360-sd"
echo "   sudo systemctl status color360-app"
echo "   sudo systemctl status color360-sd"
echo ""
echo "📜 Просмотр логов:"
echo "   sudo journalctl -u color360-app -f"
echo "   sudo journalctl -u color360-sd -f"
echo ""
echo "🔧 Конфигурационные файлы:"
echo "   Nginx: /etc/nginx/sites-available/color360"
echo "   Systemd: /etc/systemd/system/color360-*.service"