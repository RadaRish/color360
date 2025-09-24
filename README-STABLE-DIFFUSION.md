# Интеграция Stable Diffusion в Color360

## 🎨 Обзор

Проект интегрирует **Stable Diffusion Inpainting** для продвинутой ретуши изображений в редакторе панорам Color360. Система поддерживает как локальное развертывание, так и развертывание на VPS с полной автоматизацией.

## 🚀 Быстрый старт

### Локальная установка (Windows)

1. **Установка зависимостей Python:**
   ```powershell
   .\setup-stable-diffusion.ps1
   ```

2. **Запуск сервисов:**
   ```bash
   # Терминал 1: Stable Diffusion сервис
   cd sd
   python sd_app.py

   # Терминал 2: Node.js сервер
   node server.js
   ```

3. **Доступ:**
   - Основное приложение: http://localhost:3000
   - Панорамный редактор: http://localhost:3000/pano
   - Stable Diffusion API: http://localhost:5002

### Развертывание на VPS

```bash
# Полное развертывание (Ubuntu/CentOS)
chmod +x deploy-full-vps.sh
sudo ./deploy-full-vps.sh

# Или только Stable Diffusion
chmod +x setup-stable-diffusion.sh
./setup-stable-diffusion.sh
```

### Docker развертывание

```bash
# CPU версия
docker-compose up -d

# GPU версия (с NVIDIA GPU)
docker-compose -f docker-compose.gpu.yml up -d
```

## 🔧 Архитектура

### Компоненты системы

1. **Node.js Backend** (`server.js`)
   - Express API сервер
   - Управление Stable Diffusion процессами
   - Прокси для AI сервисов
   - Обработка файлов и сессий

2. **Stable Diffusion Service** (`sd/sd_app.py`)
   - FastAPI сервер
   - Stable Diffusion Inpainting pipeline
   - Автоматическое управление GPU/CPU
   - Health monitoring

3. **Frontend** (`pano/index.html`)
   - Панорамный 360° редактор
   - Интерфейс для ретуши
   - Настройки AI параметров
   - Real-time превью

### API Endpoints

| Endpoint | Метод | Описание |
|----------|--------|-----------|
| `/api/ai-health` | GET | Статус AI сервисов |
| `/api/sd-health` | GET | Статус Stable Diffusion |
| `/api/retouch` | POST | Обработка изображения |
| `/health` | GET | Health check SD сервиса |
| `/inpaint` | POST | Прямой SD inpainting |

## ⚙️ Конфигурация

### Переменные окружения

```bash
# Node.js сервер
PORT=3000                    # Порт основного сервера
NODE_ENV=production         # Режим работы
SD_HOST=127.0.0.1          # Хост SD сервиса
SD_PORT=5002               # Порт SD сервиса
SD_DISABLED=false          # Отключить SD сервис

# Stable Diffusion сервис
PORT=5002                   # Порт SD сервиса
HOST=127.0.0.1             # Хост для привязки
PYTHONUNBUFFERED=1         # Логирование Python
```

### Параметры Stable Diffusion

Настройки доступны в UI панорамного редактора:

- **Промпт** (`prompt`): Описание желаемого результата
- **Негативный промпт** (`negative_prompt`): Что исключить
- **Сила направления** (`guidance_scale`): 1.0-20.0 (по умолчанию 7.5)
- **Шаги обработки** (`num_inference_steps`): 10-50 (по умолчанию 20)
- **Сила эффекта** (`strength`): 0.1-1.0 (по умолчанию 1.0)

## 🖥️ Системные требования

### Минимальные

- **CPU**: 4+ ядра
- **RAM**: 8GB+
- **Storage**: 20GB свободного места
- **Python**: 3.8+
- **Node.js**: 16+

### Рекомендуемые

- **CPU**: 8+ ядер
- **RAM**: 16GB+
- **GPU**: NVIDIA RTX 3060+ с 8GB+ VRAM
- **Storage**: 50GB+ SSD

### Поддерживаемые платформы

- ✅ **Windows 10/11** (CPU/GPU)
- ✅ **Linux** (Ubuntu 20.04+, CentOS 8+)
- ✅ **macOS** (CPU/Apple Silicon)
- 🐳 **Docker** (Linux containers)

## 🔍 Диагностика

### Проверка статуса

```bash
# Проверка основного сервера
curl http://localhost:3000/api/ai-health

# Проверка SD сервиса
curl http://localhost:5002/health

# Логи systemd (Linux)
sudo journalctl -u color360-app -f
sudo journalctl -u color360-sd -f
```

### Типичные проблемы

1. **"ModuleNotFoundError: No module named 'torch'"**
   ```bash
   # Переустановка PyTorch
   pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
   ```

2. **"CUDA out of memory"**
   ```python
   # В sd_app.py, добавить:
   CONFIG['torch_dtype'] = torch.float32  # Вместо float16
   ```

3. **"Connection refused"**
   - Проверить запуск SD сервиса
   - Проверить порты и firewall
   - Проверить переменные окружения

## 📊 Производительность

### Время обработки (приблизительно)

| Устройство | Размер | Шаги | Время |
|------------|---------|------|-------|
| RTX 4090 | 512x512 | 20 | ~3-5s |
| RTX 3070 | 512x512 | 20 | ~8-12s |
| CPU Intel i7 | 512x512 | 20 | ~60-120s |

### Оптимизация

1. **GPU оптимизации** (автоматически):
   - Memory efficient attention
   - Model CPU offloading
   - Mixed precision (FP16)

2. **CPU оптимизации**:
   - Уменьшить размер изображения
   - Снизить количество шагов (10-15)
   - Использовать FP32 вместо FP16

## 🔒 Безопасность

### Production настройки

1. **Systemd сервисы**:
   - Изолированные пользователи
   - Ограниченные права файловой системы
   - Автоматический перезапуск

2. **Nginx конфигурация**:
   - SSL/TLS шифрование
   - Rate limiting
   - Security headers

3. **Firewall**:
   - Закрытые внутренние порты
   - Только необходимые публичные порты

## 📚 Дополнительная документация

- [Установка на VPS](INSTALL-VPS.md)
- [Docker развертывание](DOCKER.md)
- [API документация](API.md)
- [Troubleshooting](TROUBLESHOOTING.md)

## 🤝 Поддержка

Для получения помощи:

1. Проверьте [Issues](https://github.com/RadaRish/color360/issues)
2. Создайте новый Issue с описанием проблемы
3. Приложите логи и конфигурацию

---

*Color360 + Stable Diffusion - Профессиональная ретушь панорам с искусственным интеллектом* 🎨✨