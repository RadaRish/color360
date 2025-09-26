# 🔄 Руководство по обновлению Color360 на VPS

## Быстрое обновление

### Уже склонированный репозиторий (скрипт из `scripts/`)

```bash
cd /var/www/color360    # путь до проекта
chmod +x scripts/vps-update-from-github.sh
./scripts/vps-update-from-github.sh
```

*Опционально:* можно переопределять параметры через переменные окружения или флаги, например:

```bash
APP_USER=www-data PROJECT_DIR=/opt/color360 ./scripts/vps-update-from-github.sh --skip-backup
```

### Linux VPS (Ubuntu/CentOS)

```bash
# Скачать и запустить скрипт обновления
wget https://raw.githubusercontent.com/RadaRish/color360/main/update-vps.sh
chmod +x update-vps.sh
./update-vps.sh
```

### Windows VPS

```powershell
# Скачать и запустить PowerShell скрипт
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/RadaRish/color360/main/update-vps.ps1" -OutFile "update-vps.ps1"
.\update-vps.ps1
```

## Ручное обновление

### 1. Остановка сервисов

**Linux:**
```bash
sudo systemctl stop color360-app color360-sd nginx
```

**Windows:**
```powershell
Get-Process -Name "node","python*" | Stop-Process -Force
```

### 2. Создание бэкапа

**Linux:**
```bash
sudo cp -r /opt/color360 /opt/color360-backup-$(date +%Y%m%d)
```

**Windows:**
```powershell
Copy-Item -Path "$env:USERPROFILE\color360" -Destination "$env:USERPROFILE\color360-backup-$(Get-Date -Format 'yyyyMMdd')" -Recurse
```

### 3. Обновление кода

```bash
cd /opt/color360  # Linux
# или
cd $env:USERPROFILE\color360  # Windows

git stash  # сохранить локальные изменения
git fetch origin
git reset --hard origin/main
```

### 4. Обновление зависимостей

**Node.js:**
```bash
npm install --production
```

**Python (если изменились):**
```bash
# Linux
source sd_env/bin/activate
pip install --upgrade -r sd/requirements.txt

# Windows
sd_env\Scripts\activate
pip install --upgrade -r sd\requirements.txt
```

### 5. Запуск сервисов

**Linux:**
```bash
sudo systemctl start color360-sd
sleep 10
sudo systemctl start color360-app
sudo systemctl start nginx
```

**Windows:**
```powershell
.\start-services.ps1
# или запустить отдельно:
.\start-sd-service.bat
.\start-app.bat
```

## Проверка обновления

### Тестирование endpoint-ов

```bash
# Основное приложение
curl http://localhost:3000/

# Статус AI сервисов
curl http://localhost:3000/api/ai-health

# Stable Diffusion сервис
curl http://localhost:5002/health
```

### Проверка логов

**Linux:**
```bash
# Логи основного приложения
sudo journalctl -u color360-app -f

# Логи Stable Diffusion
sudo journalctl -u color360-sd -f

# Статус всех сервисов
sudo systemctl status color360-app color360-sd nginx
```

**Windows:**
```powershell
# Проверка запущенных процессов
Get-Process -Name "node","python*"

# Тестирование доступности
Test-NetConnection -ComputerName localhost -Port 3000
Test-NetConnection -ComputerName localhost -Port 5002
```

## Откат к предыдущей версии

### В случае проблем

**Linux:**
```bash
sudo systemctl stop color360-app color360-sd
sudo rm -rf /opt/color360
sudo mv /opt/color360-backup-YYYYMMDD /opt/color360
sudo systemctl start color360-sd color360-app
```

**Windows:**
```powershell
Get-Process -Name "node","python*" | Stop-Process -Force
Remove-Item -Recurse -Force "$env:USERPROFILE\color360"
Move-Item "$env:USERPROFILE\color360-backup-YYYYMMDD" "$env:USERPROFILE\color360"
cd "$env:USERPROFILE\color360"
.\start-services.ps1
```

## Автоматизация обновлений

### Настройка cron (Linux)

```bash
# Добавить в crontab для еженедельных обновлений
crontab -e

# Добавить строку (каждое воскресенье в 3:00)
0 3 * * 0 /opt/color360/update-vps.sh >> /var/log/color360-update.log 2>&1
```

### Настройка Windows Task Scheduler

```powershell
# Создание задачи для еженедельных обновлений
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Users\YourUser\color360\update-vps.ps1"
$Trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Sunday -At 3AM
Register-ScheduledTask -TaskName "Color360-Update" -Action $Action -Trigger $Trigger
```

## Мониторинг после обновления

### Проверка производительности

```bash
# Использование CPU и памяти
top -p $(pgrep -f "node server.js|python sd_app.py")

# Дисковое пространство
df -h /opt/color360

# Логи ошибок
tail -f /var/log/nginx/error.log
```

### Проверка доступности

```bash
# Скрипт мониторинга
#!/bin/bash
while true; do
    if ! curl -f -s http://localhost:3000/ > /dev/null; then
        echo "$(date): Main app is down!" >> /var/log/color360-monitor.log
    fi
    if ! curl -f -s http://localhost:5002/health > /dev/null; then
        echo "$(date): SD service is down!" >> /var/log/color360-monitor.log
    fi
    sleep 60
done
```

## Поддержка и диагностика

### Типичные проблемы после обновления

1. **"Port already in use"**
   ```bash
   sudo lsof -i :3000  # найти процесс
   sudo kill -9 PID    # убить процесс
   ```

2. **"Module not found"**
   ```bash
   npm install --production  # переустановить зависимости
   ```

3. **"Permission denied"**
   ```bash
   sudo chown -R color360:color360 /opt/color360
   ```

### Контакты для поддержки

- 📧 GitHub Issues: [color360/issues](https://github.com/RadaRish/color360/issues)
- 📚 Документация: [README-STABLE-DIFFUSION.md](README-STABLE-DIFFUSION.md)
- 🔧 Диагностика: Приложите логи systemctl/journalctl

---

*Обновление Color360 - простое и безопасное развертывание новых функций* 🚀