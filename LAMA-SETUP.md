# 🎨 LaMa Object Removal System - Полная настройка

## 📋 Обзор системы

Color360 теперь включает полноценную систему удаления объектов на базе LaMa AI и OpenCV inpainting. Система работает в интегрированном режиме на одном сервере.

## 🏗️ Архитектура

```
color360.ru                    # Основной сайт
├── color360.ru/pano          # Панорамный редактор
├── /api/retouch              # API удаления объектов
└── LaMa Service (port 5000)  # Python AI сервис
```

## ⚙️ Компоненты системы

### 1. **Frontend (UI)**
- **Расположение**: `pano/ui/retouch_manager.js`
- **Функции**: 
  - Рисование маски поверх панорамы
  - Отправка изображения + маски на API
  - Система undo/redo для каждой сцены
- **Кнопки**: 
  - `🗑️ Удалить объект` - активирует режим рисования
  - `↶ Отменить` - откат изменений

### 2. **Backend API**
- **Endpoint**: `POST /api/retouch`
- **Файл**: `server.js`
- **Функции**:
  - Обработка multipart файлов (изображение + маска)
  - Интеграция с LaMa сервисом
  - Fallback на оригинальное изображение при ошибках

### 3. **LaMa AI Service**
- **Расположение**: `lama/app.py`
- **Порт**: 5000 (настраивается через `LAMA_PORT`)
- **Технологии**:
  - **Основная**: LaMa AI model (torch + lama-cleaner)
  - **Fallback**: OpenCV inpainting
- **API**: `POST /inpaint`

## 🚀 Установка и настройка

### Шаг 1: Установка Python зависимостей

```bash
# Базовые зависимости (обязательно)
cd lama/
pip install fastapi uvicorn pillow numpy opencv-python python-multipart

# Для улучшенного качества (опционально)
pip install torch torchvision lama-cleaner
```

**Windows PowerShell:**
```powershell
.\setup-lama.ps1
```

**Linux/Mac:**
```bash
./setup-lama.sh
```

### Шаг 2: Запуск сервиса

**Вариант 1: Интегрированный запуск (рекомендуется)**
```bash
# Node.js автоматически запускает LaMa сервис
node server.js
```

**Вариант 2: Раздельный запуск**
```bash
# Терминал 1: LaMa сервис
cd lama/
python app.py

# Терминал 2: Основной сервер  
LAMA_URL=http://localhost:5000 node server.js
```

**Вариант 3: PM2 управление**
```bash
# Оба процесса через PM2
pm2 start ecosystem.separate.config.json

# Или только основной (с интегрированным LaMa)
pm2 start ecosystem.config.json
```

## 🎯 Принцип работы

### Пользовательский workflow:

1. **Загрузка панорамы** в редактор
2. **Нажатие кнопки** "🗑️ Удалить объект"
3. **Рисование маски** поверх области для удаления
4. **Нажатие "Готово"** - автоматическая обработка
5. **Получение результата** с удаленными объектами
6. **Возможность отмены** через кнопку "↶ Отменить"

### Технический процесс:

```
1. UI: Пользователь рисует маску на canvas
2. Frontend: retouchManager.applyRetouch() → POST /api/retouch
3. Backend: Получение файлов → Отправка в LaMa сервис
4. LaMa: AI обработка (или OpenCV fallback)
5. Backend: Возврат обработанного изображения
6. Frontend: Замена панорамы + обновление undo stack
```

## 🔧 Конфигурация

### Переменные окружения:

```bash
# Основной сервер
PORT=3000                    # Порт основного сервера
NODE_ENV=production         # Режим работы

# LaMa сервис
LAMA_PORT=5000              # Порт LaMa сервиса
LAMA_HOST=127.0.0.1         # Хост LaMa сервиса
LAMA_URL=http://localhost:5000  # Полный URL (альтернатива)
```

### PM2 конфигурация:

**ecosystem.config.json** (интегрированный):
```json
{
  "apps": [{
    "name": "color360-app",
    "script": "server.js",
    "env": {
      "NODE_ENV": "production",
      "PORT": "3000",
      "LAMA_PORT": "5000"
    }
  }]
}
```

**ecosystem.separate.config.json** (раздельные процессы):
```json
{
  "apps": [
    {
      "name": "color360-app",
      "script": "server.js",
      "env": {"PORT": "3000", "LAMA_URL": "http://localhost:5000"}
    },
    {
      "name": "color360-lama", 
      "script": "python3",
      "args": "app.py",
      "cwd": "lama/",
      "env": {"PORT": "5000"}
    }
  ]
}
```

## 📊 Мониторинг и диагностика

### Проверка статуса:

```bash
# Проверка основного сервера
curl http://localhost:3000/health

# Проверка LaMa сервиса
curl http://localhost:5000/health

# Тест API удаления
python test_retouch_api.py
```

### Логи:

```bash
# PM2 логи
pm2 logs color360-app
pm2 logs color360-lama

# Прямые логи
tail -f /var/log/pm2/color360-*.log
```

### Заголовки ответа API:

```
X-Retouch-Status: success|fallback-lama-error|fallback-service-not-ready
X-Retouch-Method: lama-ai|opencv-fallback
X-Retouch-Error: [описание ошибки если есть]
```

## 🌐 Развертывание на color360.ru

### 1. Подготовка сервера:

```bash
# Установка зависимостей
sudo apt update
sudo apt install python3 python3-pip nodejs npm nginx

# Установка PM2
npm install -g pm2

# Клонирование проекта
git clone [repository] /var/www/color360
cd /var/www/color360
```

### 2. Настройка Python окружения:

```bash
cd /var/www/color360
./setup-lama.sh

# Для production с GPU поддержкой (опционально)
pip install torch torchvision lama-cleaner --index-url https://download.pytorch.org/whl/cu118
```

### 3. Настройка Nginx:

```nginx
# /etc/nginx/sites-available/color360
server {
    listen 80;
    server_name color360.ru www.color360.ru;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    
    location /api/retouch {
        proxy_pass http://localhost:3000;
        proxy_read_timeout 300s;  # Увеличенный timeout для AI обработки
        client_max_body_size 50M; # Для больших изображений
    }
}
```

### 4. Запуск производственного сервиса:

```bash
cd /var/www/color360

# Установка Node.js зависимостей
npm install

# Запуск через PM2
pm2 start ecosystem.config.json
pm2 save
pm2 startup
```

## 🛠️ Устранение неполадок

### Распространенные проблемы:

1. **"LaMa сервис недоступен"**
   ```bash
   # Проверка статуса
   curl http://localhost:5000/health
   
   # Перезапуск
   pm2 restart color360-lama
   ```

2. **"No module named 'torch'"**
   ```bash
   # Это нормально - используется OpenCV fallback
   # Для улучшения качества установите:
   pip install torch lama-cleaner
   ```

3. **"Port already in use"**
   ```bash
   # Изменить порт LaMa
   export LAMA_PORT=5001
   node server.js
   ```

4. **Медленная обработка**
   ```bash
   # Установка LaMa для лучшей производительности
   pip install torch torchvision lama-cleaner
   
   # GPU поддержка (если доступно)
   pip install torch torchvision --index-url https://download.pytorch.org/whl/cu118
   ```

## 📈 Производительность

### Режимы работы:

| Режим | Качество | Скорость | Требования |
|-------|----------|----------|------------|
| OpenCV Fallback | Базовое | Быстро (~1-2с) | CPU, минимальные |
| LaMa CPU | Высокое | Средне (~5-10с) | CPU, torch |
| LaMa GPU | Отличное | Быстро (~1-3с) | CUDA GPU, torch |

### Оптимизация:

- **Для CPU**: `low_mem=True` в настройках LaMa
- **Для GPU**: Установка CUDA версии torch
- **Кэширование**: Модель загружается один раз при старте

## ✅ Проверочный список готовности

- [ ] Python зависимости установлены
- [ ] LaMa сервис запускается без ошибок  
- [ ] Основной сервер подключается к LaMa
- [ ] API `/api/retouch` возвращает обработанные изображения
- [ ] UI кнопка "Удалить объект" активна
- [ ] Система undo/redo работает
- [ ] PM2 конфигурация настроена
- [ ] Nginx проксирует запросы корректно
- [ ] SSL сертификат настроен для color360.ru

## 🎉 Результат

**Полноценная система удаления объектов готова к работе на color360.ru!**

- ✅ **Frontend**: Интуитивный интерфейс рисования масок
- ✅ **Backend**: Надежный API с fallback механизмами  
- ✅ **AI**: LaMa + OpenCV для качественного inpainting
- ✅ **Deployment**: PM2 + Nginx для production
- ✅ **Monitoring**: Логи и health checks
- ✅ **Performance**: Оптимизировано для разных конфигураций

Пользователи могут легко удалять нежелательные объекты из панорамных изображений прямо в браузере! 🚀