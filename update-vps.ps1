# Скрипт обновления Color360 на Windows VPS
# Автоматически загружает изменения с GitHub и перезапускает сервисы

param(
    [string]$ProjectDir = "$env:USERPROFILE\color360",
    [string]$Branch = "main",
    [switch]$SkipBackup
)

Write-Host "🔄 Обновление Color360 на Windows..." -ForegroundColor Green

# Проверяем существование проекта
if (-not (Test-Path $ProjectDir)) {
    Write-Host "❌ Проект не найден: $ProjectDir" -ForegroundColor Red
    Write-Host "Сначала выполните первоначальную установку" -ForegroundColor Yellow
    exit 1
}

# Создаем бэкап
if (-not $SkipBackup) {
    $BackupDir = "$env:USERPROFILE\color360-backups"
    $BackupName = "backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    Write-Host "📁 Создание бэкапа: $BackupName" -ForegroundColor Cyan
    
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }
    
    Copy-Item -Path $ProjectDir -Destination "$BackupDir\$BackupName" -Recurse -Force
    Write-Host "✅ Бэкап создан: $BackupDir\$BackupName" -ForegroundColor Green
}

# Останавливаем процессы Node.js и Python
Write-Host "🛑 Остановка запущенных процессов..." -ForegroundColor Yellow

try {
    Get-Process -Name "node" -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Host "✅ Node.js процессы остановлены" -ForegroundColor Green
} catch {
    Write-Host "ℹ️ Node.js процессы не найдены" -ForegroundColor Gray
}

try {
    Get-Process -Name "python*" -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Host "✅ Python процессы остановлены" -ForegroundColor Green
} catch {
    Write-Host "ℹ️ Python процессы не найдены" -ForegroundColor Gray
}

# Переходим в директорию проекта
Set-Location $ProjectDir

# Проверяем Git статус
Write-Host "📊 Проверка Git статуса..." -ForegroundColor Cyan
git status

# Сохраняем локальные изменения
$gitStatus = git status --porcelain
if ($gitStatus) {
    Write-Host "💾 Сохранение локальных изменений..." -ForegroundColor Yellow
    git stash push -m "Auto-stash before update $(Get-Date)"
}

# Получаем обновления
Write-Host "📥 Загрузка обновлений с GitHub..." -ForegroundColor Cyan
git fetch origin
git reset --hard origin/$Branch

# Обновляем Node.js зависимости
Write-Host "📦 Обновление Node.js зависимостей..." -ForegroundColor Cyan
npm install --production

# Проверяем Python зависимости
if (Test-Path "sd\requirements.txt") {
    Write-Host "🐍 Проверка Python зависимостей..." -ForegroundColor Cyan
    
    if (Test-Path "sd_env") {
        Write-Host "📦 Обновление Python пакетов..." -ForegroundColor Cyan
        & "$ProjectDir\sd_env\Scripts\Activate.ps1"
        pip install --upgrade -r sd\requirements.txt
        deactivate
    } else {
        Write-Host "⚠️ Виртуальное окружение не найдено. Создаем новое..." -ForegroundColor Yellow
        python -m venv sd_env
        & "$ProjectDir\sd_env\Scripts\Activate.ps1"
        pip install --upgrade pip
        pip install -r sd\requirements.txt
        deactivate
    }
}

# Создаем/обновляем стартовые скрипты
Write-Host "🔧 Обновление стартовых скриптов..." -ForegroundColor Cyan

# Скрипт запуска SD сервиса
$sdStartScript = @"
@echo off
cd /d "$ProjectDir"
call sd_env\Scripts\activate.bat
cd sd
set PORT=5002
set HOST=127.0.0.1
set PYTHONUNBUFFERED=1
echo Запуск Stable Diffusion сервиса...
python sd_app.py
pause
"@
$sdStartScript | Out-File -FilePath "$ProjectDir\start-sd-service.bat" -Encoding ASCII

# Скрипт запуска основного приложения
$appStartScript = @"
@echo off
cd /d "$ProjectDir"
set NODE_ENV=production
set PORT=3000
set SD_HOST=127.0.0.1
set SD_PORT=5002
echo Запуск Color360 приложения...
node server.js
pause
"@
$appStartScript | Out-File -FilePath "$ProjectDir\start-app.bat" -Encoding ASCII

# PowerShell скрипт для фонового запуска
$backgroundScript = @"
# Фоновый запуск Color360 сервисов
`$projectDir = "$ProjectDir"

# Запуск SD сервиса в фоне
Write-Host "🎨 Запуск Stable Diffusion сервиса..." -ForegroundColor Green
Set-Location `$projectDir
& "sd_env\Scripts\Activate.ps1"
Set-Location sd
`$env:PORT = "5002"
`$env:HOST = "127.0.0.1"
`$env:PYTHONUNBUFFERED = "1"
`$sdProcess = Start-Process -FilePath python -ArgumentList "sd_app.py" -WindowStyle Hidden -PassThru

# Ждем запуска SD сервиса
Start-Sleep -Seconds 10

# Запуск основного приложения
Write-Host "🚀 Запуск основного приложения..." -ForegroundColor Green
Set-Location `$projectDir
`$env:NODE_ENV = "production"
`$env:PORT = "3000"
`$env:SD_HOST = "127.0.0.1"
`$env:SD_PORT = "5002"
`$appProcess = Start-Process -FilePath node -ArgumentList "server.js" -WindowStyle Hidden -PassThru

Write-Host "✅ Сервисы запущены!" -ForegroundColor Green
Write-Host "📊 SD Process ID: `$(`$sdProcess.Id)" -ForegroundColor Cyan
Write-Host "📊 App Process ID: `$(`$appProcess.Id)" -ForegroundColor Cyan
Write-Host ""
Write-Host "🔗 Ссылки:" -ForegroundColor Yellow
Write-Host "   Основное приложение: http://localhost:3000" -ForegroundColor White
Write-Host "   Панорамный редактор: http://localhost:3000/pano" -ForegroundColor White
Write-Host "   Stable Diffusion API: http://localhost:5002" -ForegroundColor White
Write-Host ""
Write-Host "🛑 Остановка сервисов:" -ForegroundColor Yellow
Write-Host "   Stop-Process -Id `$(`$sdProcess.Id) -Force" -ForegroundColor White
Write-Host "   Stop-Process -Id `$(`$appProcess.Id) -Force" -ForegroundColor White
"@
$backgroundScript | Out-File -FilePath "$ProjectDir\start-services.ps1" -Encoding UTF8

Write-Host "✅ Стартовые скрипты обновлены" -ForegroundColor Green

# Запуск сервисов
Write-Host "🚀 Запуск обновленных сервисов..." -ForegroundColor Green

# Запуск через PowerShell скрипт
& "$ProjectDir\start-services.ps1"

# Ожидание запуска
Write-Host "⏳ Ожидание запуска сервисов..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

# Тестирование
Write-Host "🔍 Тестирование приложения..." -ForegroundColor Cyan

try {
    $response = Invoke-WebRequest -Uri "http://localhost:3000/" -UseBasicParsing -TimeoutSec 10
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ Основное приложение работает" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Основное приложение не отвечает" -ForegroundColor Red
}

try {
    $response = Invoke-WebRequest -Uri "http://localhost:5002/health" -UseBasicParsing -TimeoutSec 10
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ Stable Diffusion сервис работает" -ForegroundColor Green
    }
} catch {
    Write-Host "⚠️ Stable Diffusion сервис не отвечает (может еще загружаться)" -ForegroundColor Yellow
}

# Информация об обновлении
Write-Host ""
Write-Host "🎉 Обновление завершено!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Информация об обновлении:" -ForegroundColor Cyan
Write-Host "   📅 Время: $(Get-Date)" -ForegroundColor White
if (-not $SkipBackup) {
    Write-Host "   📂 Бэкап: $BackupDir\$BackupName" -ForegroundColor White
}
Write-Host "   🌿 Ветка: $Branch" -ForegroundColor White
$currentCommit = git rev-parse --short HEAD
Write-Host "   📝 Коммит: $currentCommit" -ForegroundColor White
Write-Host ""
Write-Host "🔗 Доступные ссылки:" -ForegroundColor Cyan
Write-Host "   http://localhost:3000 - Основное приложение" -ForegroundColor White
Write-Host "   http://localhost:3000/pano - Панорамный редактор" -ForegroundColor White
Write-Host "   http://localhost:5002 - Stable Diffusion API" -ForegroundColor White
Write-Host ""
Write-Host "📊 Управление сервисами:" -ForegroundColor Cyan
Write-Host "   Запуск: .\start-services.ps1" -ForegroundColor White
Write-Host "   SD сервис: .\start-sd-service.bat" -ForegroundColor White
Write-Host "   Основное приложение: .\start-app.bat" -ForegroundColor White

if (-not $SkipBackup) {
    Write-Host ""
    Write-Host "🔄 Откат к предыдущей версии (если нужен):" -ForegroundColor Yellow
    Write-Host "   Remove-Item -Recurse -Force '$ProjectDir'" -ForegroundColor White
    Write-Host "   Move-Item '$BackupDir\$BackupName' '$ProjectDir'" -ForegroundColor White
}

# Очистка старых бэкапов
if (-not $SkipBackup -and (Test-Path $BackupDir)) {
    Write-Host ""
    Write-Host "🧹 Очистка старых бэкапов..." -ForegroundColor Cyan
    $backups = Get-ChildItem $BackupDir | Sort-Object CreationTime -Descending
    if ($backups.Count -gt 5) {
        $backups | Select-Object -Skip 5 | Remove-Item -Recurse -Force
        Write-Host "✅ Оставлено последние 5 бэкапов" -ForegroundColor Green
    }
}