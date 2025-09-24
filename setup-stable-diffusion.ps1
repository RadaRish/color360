# Скрипт установки Stable Diffusion для Windows
# Требует PowerShell 5.1 или выше

param(
    [switch]$InstallCUDA,
    [switch]$SkipGPUCheck
)

Write-Host "🚀 Установка Stable Diffusion на Windows..." -ForegroundColor Green

# Проверяем права администратора
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "❌ Требуются права администратора. Запустите PowerShell от имени администратора." -ForegroundColor Red
    exit 1
}

# Проверяем версию Python
try {
    $pythonVersion = python --version 2>&1
    if ($pythonVersion -match "Python (\d+\.\d+)") {
        $version = [version]$Matches[1]
        if ($version -lt [version]"3.8") {
            Write-Host "❌ Требуется Python 3.8 или выше. Текущая версия: $($Matches[1])" -ForegroundColor Red
            Write-Host "Скачайте Python с https://www.python.org/downloads/" -ForegroundColor Yellow
            exit 1
        }
        Write-Host "✅ Python $($Matches[1]) обнаружен" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Python не найден. Установите Python 3.8+ с https://www.python.org/downloads/" -ForegroundColor Red
    exit 1
}

# Проверяем наличие GPU
$hasNVIDIA = $false
if (-not $SkipGPUCheck) {
    try {
        $gpuInfo = Get-WmiObject -Class Win32_VideoController | Where-Object {$_.Name -match "NVIDIA"}
        if ($gpuInfo) {
            $hasNVIDIA = $true
            Write-Host "🎮 NVIDIA GPU обнаружена: $($gpuInfo.Name)" -ForegroundColor Green
        } else {
            Write-Host "💻 NVIDIA GPU не обнаружена, будет использоваться CPU" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "⚠️ Не удалось определить тип GPU" -ForegroundColor Yellow
    }
}

# Создаем директорию проекта
$projectDir = "$env:USERPROFILE\color360"
if (-not (Test-Path $projectDir)) {
    Write-Host "📁 Создание директории проекта: $projectDir" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
}

Set-Location $projectDir

# Создаем директорию для SD
$sdDir = "$projectDir\sd"
if (-not (Test-Path $sdDir)) {
    New-Item -ItemType Directory -Path $sdDir -Force | Out-Null
}

# Создаем виртуальное окружение
Write-Host "🔧 Создание виртуального окружения Python..." -ForegroundColor Cyan
if (-not (Test-Path "$projectDir\sd_env")) {
    python -m venv sd_env
}

# Активируем окружение
Write-Host "📦 Активация виртуального окружения..." -ForegroundColor Cyan
& "$projectDir\sd_env\Scripts\Activate.ps1"

# Обновляем pip
Write-Host "📦 Обновление pip..." -ForegroundColor Cyan
python -m pip install --upgrade pip setuptools wheel

# Устанавливаем PyTorch
Write-Host "🔥 Установка PyTorch..." -ForegroundColor Cyan
if ($hasNVIDIA -or $InstallCUDA) {
    Write-Host "🎮 Устанавливаем PyTorch с поддержкой CUDA..." -ForegroundColor Green
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
} else {
    Write-Host "💻 Устанавливаем PyTorch только для CPU..." -ForegroundColor Yellow
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
}

# Создаем requirements.txt если не существует
$requirementsPath = "$sdDir\requirements.txt"
if (-not (Test-Path $requirementsPath)) {
    Write-Host "📝 Создание requirements.txt..." -ForegroundColor Cyan
    @"
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
"@ | Out-File -FilePath $requirementsPath -Encoding UTF8
}

# Устанавливаем зависимости
Write-Host "🎨 Установка Stable Diffusion зависимостей..." -ForegroundColor Cyan
pip install -r $requirementsPath

# Проверяем установку
Write-Host "✅ Проверка установки..." -ForegroundColor Cyan
$checkScript = @"
import torch
import diffusers
import transformers
print(f'✅ PyTorch: {torch.__version__}')
print(f'✅ Diffusers: {diffusers.__version__}') 
print(f'✅ Transformers: {transformers.__version__}')
print(f'✅ CUDA доступна: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'✅ GPU: {torch.cuda.get_device_name(0)}')
"@
python -c $checkScript

# Предварительная загрузка модели
$downloadModel = Read-Host "📥 Хотите загрузить модель Stable Diffusion сейчас? (y/N)"
if ($downloadModel -eq 'y' -or $downloadModel -eq 'Y') {
    Write-Host "📥 Загрузка модели Stable Diffusion Inpainting..." -ForegroundColor Cyan
    $downloadScript = @"
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
"@
    python -c $downloadScript
}

# Создаем bat-файл для запуска
$startScript = @"
@echo off
cd /d "$projectDir"
call sd_env\Scripts\activate.bat
cd sd
set PORT=5002
set HOST=127.0.0.1
set PYTHONUNBUFFERED=1
python sd_app.py
pause
"@
$startScript | Out-File -FilePath "$projectDir\start-sd-service.bat" -Encoding ASCII

# Создаем PowerShell скрипт для запуска как сервиса
$serviceScript = @"
# Запуск Stable Diffusion как фонового процесса
`$projectDir = "$projectDir"
Set-Location `$projectDir
& "sd_env\Scripts\Activate.ps1"
Set-Location sd
`$env:PORT = "5002"
`$env:HOST = "127.0.0.1"
`$env:PYTHONUNBUFFERED = "1"
Start-Process -FilePath python -ArgumentList "sd_app.py" -WindowStyle Hidden
"@
$serviceScript | Out-File -FilePath "$projectDir\start-sd-background.ps1" -Encoding UTF8

Write-Host ""
Write-Host "🎉 Установка Stable Diffusion завершена!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Следующие шаги:" -ForegroundColor Cyan
Write-Host "1. Скопируйте файл sd_app.py в $sdDir\" -ForegroundColor White
Write-Host "2. Запустите сервис: $projectDir\start-sd-service.bat" -ForegroundColor White
Write-Host "3. Или как фоновый процесс: $projectDir\start-sd-background.ps1" -ForegroundColor White
Write-Host ""
Write-Host "🔗 Тестирование:" -ForegroundColor Cyan
Write-Host "curl http://localhost:5002/health" -ForegroundColor White
Write-Host ""
Write-Host "⚙️ Конфигурация:" -ForegroundColor Cyan
Write-Host "- Рабочая директория: $projectDir" -ForegroundColor White
Write-Host "- Python окружение: $projectDir\sd_env" -ForegroundColor White
Write-Host "- Стартовый скрипт: $projectDir\start-sd-service.bat" -ForegroundColor White
Write-Host "- Порт: 5002" -ForegroundColor White
Write-Host "- Хост: 127.0.0.1" -ForegroundColor White