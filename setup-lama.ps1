# Скрипт установки и настройки LaMa inpainting сервиса для Windows
Write-Host "🚀 Настройка LaMa inpainting сервиса..." -ForegroundColor Green

# Переходим в директорию lama
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location "$scriptPath\lama"

# Проверяем наличие Python
try {
    $pythonVersion = python --version 2>&1
    Write-Host "✅ Python найден: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Python не найден. Установите Python 3.8+ перед продолжением." -ForegroundColor Red
    exit 1
}

# Создаем виртуальное окружение
Write-Host "📦 Создание виртуального окружения..." -ForegroundColor Yellow
python -m venv venv

# Активируем виртуальное окружение
Write-Host "🔧 Активация виртуального окружения..." -ForegroundColor Yellow
& ".\venv\Scripts\Activate.ps1"

# Обновляем pip
Write-Host "⬆️ Обновление pip..." -ForegroundColor Yellow
python -m pip install --upgrade pip

# Устанавливаем базовые зависимости
Write-Host "📚 Установка базовых зависимостей..." -ForegroundColor Yellow
pip install -r requirements.txt

# Проверяем установку
Write-Host "🔍 Проверка установки..." -ForegroundColor Yellow
try {
    python -c "import fastapi, uvicorn, PIL, numpy, cv2; print('✅ Все базовые зависимости установлены')"
    Write-Host "✅ Проверка прошла успешно!" -ForegroundColor Green
} catch {
    Write-Host "❌ Ошибка при проверке зависимостей" -ForegroundColor Red
}

Write-Host ""
Write-Host "🎉 Базовая настройка завершена!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Следующие шаги:" -ForegroundColor Cyan
Write-Host "   1. Для улучшенной производительности установите LaMa модель:" -ForegroundColor White
Write-Host "      pip install torch torchvision lama-cleaner" -ForegroundColor Gray
Write-Host ""
Write-Host "   2. Запуск сервиса:" -ForegroundColor White
Write-Host "      .\lama\venv\Scripts\Activate.ps1" -ForegroundColor Gray
Write-Host "      python lama\app.py" -ForegroundColor Gray
Write-Host ""
Write-Host "   3. Или используйте основной сервер (который автоматически запустит LaMa):" -ForegroundColor White
Write-Host "      node server.js" -ForegroundColor Gray
Write-Host ""
Write-Host "⚠️  Внимание: Без LaMa модели будет использоваться OpenCV inpainting (базовое качество)" -ForegroundColor Yellow
Write-Host "   Для полной функциональности установите torch и lama-cleaner" -ForegroundColor Yellow