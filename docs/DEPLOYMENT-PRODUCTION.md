# Color360 - Инструкции по развертыванию в продакшн

## Обзор системы

Color360 представляет собой комплексную платформу для создания и редактирования панорамных туров с интегрированной системой удаления объектов на базе ИИ (LaMa). Система включает:

- **Основной сайт** - витрина и управление
- **Редактор панорам** - инструмент создания туров  
- **LaMa система** - ИИ удаление объектов с изображений
- **API сервис** - REST API для интеграций

## Архитектура системы

```
┌─────────────────────────────────────────────────────────────┐
│                    color360.ru                              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │    Nginx    │  │   Node.js   │  │    Python LaMa      │  │
│  │   Proxy     │◄─┤   Express   │◄─┤    FastAPI          │  │
│  │   SSL/TLS   │  │   Server    │  │    AI Service       │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│           PM2 Process Manager + Monitoring                  │
└─────────────────────────────────────────────────────────────┘
```

## Файлы развертывания

### 1. Linux/Ubuntu Server
- **`deploy-production.sh`** - Полный скрипт развертывания для Linux
- Поддерживает: Ubuntu 18.04+, CentOS 7+, Debian 9+
- Автоматическая настройка Nginx, SSL, системных сервисов

### 2. Windows Server
- **`deploy-production.ps1`** - PowerShell скрипт для Windows
- Поддерживает: Windows Server 2016+, Windows 10 Pro+
- Автоматическая настройка IIS, Windows Services

## Развертывание на Linux (рекомендуется)

### Подготовка сервера

1. **Подключение к серверу**:
   ```bash
   ssh root@your-server-ip
   ```

2. **Обновление системы**:
   ```bash
   apt update && apt upgrade -y
   ```

3. **Загрузка скрипта развертывания**:
   ```bash
   wget https://raw.githubusercontent.com/RadaRish/color360/main/deploy-production.sh
   chmod +x deploy-production.sh
   ```

### Запуск развертывания

```bash
# Базовое развертывание
sudo ./deploy-production.sh

# С указанием домена
sudo ./deploy-production.sh -d color360.ru

# С указанием email для SSL
sudo ./deploy-production.sh -d color360.ru -e admin@color360.ru

# Полная настройка
sudo ./deploy-production.sh -d color360.ru -e admin@color360.ru -p /var/www/color360
```

### Параметры скрипта

- `-d, --domain` - Доменное имя (по умолчанию: color360.ru)
- `-e, --email` - Email для SSL сертификата
- `-p, --path` - Путь установки (по умолчанию: /var/www/color360)
- `-b, --backup` - Путь для резервных копий
- `--skip-ssl` - Пропустить настройку SSL
- `--skip-firewall` - Пропустить настройку UFW

## Развертывание на Windows

### Подготовка сервера

1. **Запуск PowerShell от администратора**
2. **Разрешение выполнения скриптов**:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
   ```

3. **Загрузка скрипта**:
   ```powershell
   Invoke-WebRequest -Uri "https://raw.githubusercontent.com/RadaRish/color360/main/deploy-production.ps1" -OutFile "deploy-production.ps1"
   ```

### Запуск развертывания

```powershell
# Базовое развертывание
.\deploy-production.ps1

# С параметрами
.\deploy-production.ps1 -Domain "color360.ru" -ProjectPath "C:\inetpub\wwwroot\color360"
```

## Что происходит во время развертывания

### 🔄 Этап 1: Подготовка
- ✅ Создание резервной копии существующей версии
- ✅ Остановка текущих сервисов
- ✅ Проверка системных требований

### 📦 Этап 2: Установка зависимостей
- ✅ Node.js 18+ и npm
- ✅ Python 3.8+ и pip
- ✅ PM2 для управления процессами
- ✅ Nginx (Linux) / IIS (Windows)

### 🛠️ Этап 3: Настройка системы
- ✅ Клонирование репозитория
- ✅ Установка Node.js зависимостей
- ✅ Настройка Python виртуального окружения для LaMa
- ✅ Создание конфигурационных файлов

### 🔒 Этап 4: Безопасность
- ✅ Настройка UFW/Windows Firewall
- ✅ SSL сертификаты (Let's Encrypt на Linux)
- ✅ Безопасные заголовки HTTP
- ✅ Ограничение скорости запросов

### 🚀 Этап 5: Запуск
- ✅ Регистрация системных сервисов
- ✅ Запуск всех компонентов
- ✅ Проверка работоспособности

## Проверка развертывания

После завершения скрипта проверьте доступность:

### Основные URL
- **Главная страница**: `https://color360.ru/`
- **Редактор панорам**: `https://color360.ru/pano/`
- **Административная панель**: `https://color360.ru/admin-dashboard.html`
- **API здоровья**: `https://color360.ru/api/health`

### Тест LaMa системы
```bash
curl -X POST https://color360.ru/api/retouch \
  -F "image=@test-image.jpg" \
  -F "mask=@test-mask.jpg"
```

### Логи системы

**Linux**:
```bash
# Основные логи
sudo tail -f /var/log/color360/app.log

# PM2 логи
pm2 logs

# Nginx логи
sudo tail -f /var/log/nginx/color360.access.log
```

**Windows**:
```powershell
# Основные логи
Get-Content "C:\Logs\color360\app.log" -Tail 50 -Wait

# PM2 логи
pm2 logs

# IIS логи
Get-Content "C:\inetpub\logs\LogFiles\W3SVC1\*.log" | Select-Object -Last 50
```

## Управление сервисами

### Linux (systemd)
```bash
# Управление основным сервисом
sudo systemctl start color360
sudo systemctl stop color360
sudo systemctl restart color360
sudo systemctl status color360

# Управление LaMa сервисом
sudo systemctl start color360-lama
sudo systemctl stop color360-lama
sudo systemctl restart color360-lama
```

### Windows (PM2)
```powershell
# Управление процессами
pm2 start ecosystem.production.json
pm2 stop all
pm2 restart all
pm2 status

# Управление Windows Service
Start-Service PM2
Stop-Service PM2
Restart-Service PM2
```

## Резервное копирование

### Автоматические бэкапы
Скрипт автоматически создает резервные копии в:
- **Linux**: `/var/backups/color360/YYYYMMDD_HHMMSS/`
- **Windows**: `C:\Backups\color360\YYYYMMDD_HHMMSS\`

### Ручное создание бэкапа
```bash
# Linux
sudo cp -r /var/www/color360 /var/backups/color360/manual_$(date +%Y%m%d_%H%M%S)

# Windows
Copy-Item -Path "C:\inetpub\wwwroot\color360" -Destination "C:\Backups\color360\manual_$(Get-Date -Format 'yyyyMMdd_HHmmss')" -Recurse
```

## Откат к предыдущей версии

### Linux
```bash
# Остановка сервисов
sudo systemctl stop color360 color360-lama nginx

# Восстановление из бэкапа
sudo rm -rf /var/www/color360
sudo cp -r /var/backups/color360/BACKUP_TIMESTAMP/project /var/www/color360

# Запуск сервисов
sudo systemctl start nginx color360 color360-lama
```

### Windows
```powershell
# Остановка сервисов
Stop-Service PM2
Stop-IISSite -Name "color360"

# Восстановление из бэкапа
Remove-Item -Path "C:\inetpub\wwwroot\color360" -Recurse -Force
Copy-Item -Path "C:\Backups\color360\BACKUP_TIMESTAMP\project" -Destination "C:\inetpub\wwwroot\color360" -Recurse

# Запуск сервисов
Start-IISSite -Name "color360"
Start-Service PM2
```

## Мониторинг и техническое обслуживание

### Мониторинг ресурсов
- **CPU и RAM**: `htop` (Linux) / Task Manager (Windows)
- **Дисковое пространство**: `df -h` (Linux) / Disk Management (Windows)
- **Сетевые подключения**: `netstat -tulpn` (Linux) / `netstat -an` (Windows)

### Ротация логов
Скрипт автоматически настраивает ротацию логов:
- **Linux**: logrotate для системных логов
- **Windows**: Scheduled Task для очистки старых логов

### Обновление системы
```bash
# Linux - ручное обновление
cd /var/www/color360
git pull origin main
npm install
pip install -r lama/requirements.txt
sudo systemctl restart color360 color360-lama

# Windows - ручное обновление
cd C:\inetpub\wwwroot\color360
git pull origin main
npm install
.\lama\venv\Scripts\Activate.ps1
pip install -r lama\requirements.txt
deactivate
pm2 restart all
```

## Решение проблем

### Проблема: Сервис не запускается
```bash
# Проверка логов
sudo journalctl -u color360 -f

# Проверка портов
sudo netstat -tulpn | grep :3000
```

### Проблема: LaMa не работает
```bash
# Проверка Python окружения
cd /var/www/color360/lama
source venv/bin/activate
python -c "import cv2, numpy, PIL; print('Зависимости OK')"

# Тест API
curl -X GET http://localhost:5000/health
```

### Проблема: SSL сертификат
```bash
# Обновление Let's Encrypt
sudo certbot renew --dry-run

# Ручное обновление
sudo certbot certonly --nginx -d color360.ru
```

## Контакты и поддержка

- **Документация**: [README.md](README.md)
- **LaMa система**: [LAMA-SETUP.md](LAMA-SETUP.md)
- **Issues**: GitHub Issues
- **Email поддержка**: admin@color360.ru

---

*Автоматическое развертывание Color360 с полной поддержкой существующих инсталляций и систем восстановления.*