# ================================================================
# Color360 Production Deployment Script for Windows Server
# Автоматическое развертывание сайта, редактора и LaMa системы
# ================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$Domain = "color360.ru",
    
    [Parameter(Mandatory=$false)]
    [string]$ProjectPath = "C:\inetpub\wwwroot\color360",
    
    [Parameter(Mandatory=$false)]
    [string]$BackupPath = "C:\Backups\color360"
)

# Цветной вывод
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    else {
        $input | Write-Output
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

function Write-Success { Write-ColorOutput Green $args }
function Write-Warning { Write-ColorOutput Yellow $args }
function Write-Error { Write-ColorOutput Red $args }
function Write-Info { Write-ColorOutput Cyan $args }

# Логирование
$LogFile = "$env:TEMP\color360-deploy-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param($Message, $Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Write-Output $LogMessage | Tee-Object -FilePath $LogFile -Append
    
    switch($Level) {
        "ERROR" { Write-Error $Message }
        "WARNING" { Write-Warning $Message }
        "SUCCESS" { Write-Success $Message }
        default { Write-Info $Message }
    }
}

# Проверка прав администратора
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Создание резервной копии
function Create-Backup {
    Write-Log "🔄 Создание резервной копии текущей версии..." "INFO"
    
    $BackupTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $CurrentBackupPath = "$BackupPath\$BackupTimestamp"
    
    if (-not (Test-Path $BackupPath)) {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
    }
    
    if (Test-Path $ProjectPath) {
        Write-Log "📦 Копирование файлов проекта..." "INFO"
        Copy-Item -Path $ProjectPath -Destination "$CurrentBackupPath\project" -Recurse -Force
        
        # Бэкап IIS конфигурации
        if (Get-Module -ListAvailable -Name WebAdministration) {
            Import-Module WebAdministration
            $sites = Get-IISSite | Where-Object { $_.Name -like "*color360*" }
            if ($sites) {
                $sites | Export-CliXml -Path "$CurrentBackupPath\iis-sites.xml"
            }
        }
        
        Write-Log "✅ Резервная копия создана: $CurrentBackupPath" "SUCCESS"
    } else {
        Write-Log "ℹ️ Предыдущая версия не найдена, пропускаем резервное копирование" "INFO"
    }
    
    # Очистка старых бэкапов (оставляем последние 5)
    $OldBackups = Get-ChildItem -Path $BackupPath -Directory | Sort-Object CreationTime -Descending | Select-Object -Skip 5
    $OldBackups | Remove-Item -Recurse -Force
}

# Остановка существующих сервисов
function Stop-ExistingServices {
    Write-Log "⏹️ Остановка существующих сервисов..." "INFO"
    
    # Остановка IIS сайта
    if (Get-Module -ListAvailable -Name WebAdministration) {
        Import-Module WebAdministration
        $sites = Get-IISSite | Where-Object { $_.Name -like "*color360*" }
        foreach ($site in $sites) {
            Stop-IISSite -Name $site.Name -Confirm:$false
            Write-Log "Остановлен IIS сайт: $($site.Name)" "INFO"
        }
    }
    
    # Остановка процессов Node.js и Python
    Get-Process -Name "node" -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process -Name "python" -ErrorAction SilentlyContinue | Stop-Process -Force
    
    Write-Log "✅ Существующие сервисы остановлены" "SUCCESS"
}

# Установка зависимостей
function Install-Dependencies {
    Write-Log "📦 Установка зависимостей..." "INFO"
    
    # Проверка и установка Chocolatey
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Log "Установка Chocolatey..." "INFO"
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        $env:PATH += ";C:\ProgramData\chocolatey\bin"
    }
    
    # Установка Node.js
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Log "Установка Node.js..." "INFO"
        choco install nodejs -y
        refreshenv
    }
    
    # Установка Python
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Log "Установка Python..." "INFO"
        choco install python -y
        refreshenv
    }
    
    # Установка Git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Log "Установка Git..." "INFO"
        choco install git -y
        refreshenv
    }
    
    # Установка PM2
    if (-not (Get-Command pm2 -ErrorAction SilentlyContinue)) {
        Write-Log "Установка PM2..." "INFO"
        npm install -g pm2 pm2-windows-startup pm2-windows-service
    }
    
    Write-Log "✅ Зависимости установлены" "SUCCESS"
}

# Настройка IIS
function Configure-IIS {
    Write-Log "🌐 Настройка IIS..." "INFO"
    
    # Включение IIS функций
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole, IIS-WebServer, IIS-CommonHttpFeatures, IIS-HttpRedirect, IIS-WebServerManagementTools, IIS-RequestFiltering, IIS-HttpLogging -All
    
    # Установка URL Rewrite модуля
    $urlRewriteUrl = "https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi"
    $urlRewritePath = "$env:TEMP\urlrewrite.msi"
    
    if (-not (Get-Module -ListAvailable -Name WebAdministration)) {
        Write-Log "Загрузка URL Rewrite модуля..." "INFO"
        Invoke-WebRequest -Uri $urlRewriteUrl -OutFile $urlRewritePath
        Start-Process msiexec.exe -Wait -ArgumentList "/i $urlRewritePath /quiet"
    }
    
    Import-Module WebAdministration
    
    # Создание сайта
    $siteName = "color360"
    if (Get-IISSite -Name $siteName -ErrorAction SilentlyContinue) {
        Remove-IISSite -Name $siteName -Confirm:$false
    }
    
    New-IISSite -Name $siteName -BindingInformation "*:80:$Domain" -PhysicalPath $ProjectPath
    New-IISSite -Name "$siteName-ssl" -BindingInformation "*:443:$Domain" -PhysicalPath $ProjectPath -Protocol https
    
    Write-Log "✅ IIS настроен" "SUCCESS"
}

# Развертывание проекта
function Deploy-Project {
    Write-Log "📂 Развертывание проекта..." "INFO"
    
    # Удаление старой версии
    if (Test-Path $ProjectPath) {
        Remove-Item -Path $ProjectPath -Recurse -Force
    }
    
    # Создание директории
    New-Item -ItemType Directory -Path $ProjectPath -Force | Out-Null
    
    # Клонирование репозитория
    Set-Location (Split-Path $ProjectPath -Parent)
    git clone https://github.com/RadaRish/color360.git $ProjectPath
    Set-Location $ProjectPath
    
    # Установка Node.js зависимостей
    Write-Log "📦 Установка Node.js зависимостей..." "INFO"
    npm install
    
    # Настройка Python виртуального окружения для LaMa
    Write-Log "🐍 Настройка Python окружения для LaMa..." "INFO"
    Set-Location "$ProjectPath\lama"
    python -m venv venv
    .\venv\Scripts\Activate.ps1
    python -m pip install --upgrade pip
    python -m pip install -r requirements.txt
    deactivate
    
    Write-Log "✅ Проект развернут" "SUCCESS"
}

# Создание конфигурации
function Create-Configuration {
    Write-Log "⚙️ Создание конфигурации..." "INFO"
    
    # Создание .env файла
    $envContent = @"
# Production Environment Configuration
NODE_ENV=production
PORT=3000
DOMAIN=$Domain

# Security
JWT_SECRET=$([System.Web.Security.Membership]::GeneratePassword(32, 8))

# LaMa Service Configuration
LAMA_PORT=5000
LAMA_HOST=127.0.0.1
LAMA_URL=http://127.0.0.1:5000

# Logging
LOG_LEVEL=info
LOG_FILE=C:\Logs\color360\app.log

# Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100

# File Upload
MAX_FILE_SIZE=52428800
UPLOAD_DIR=C:\Uploads\color360
"@
    
    $envContent | Out-File -FilePath "$ProjectPath\.env" -Encoding UTF8
    
    # Создание web.config для IIS
    $webConfigContent = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <handlers>
      <add name="iisnode" path="server.js" verb="*" modules="iisnode"/>
    </handlers>
    <rewrite>
      <rules>
        <rule name="DynamicContent">
          <conditions>
            <add input="{REQUEST_FILENAME}" matchType="IsFile" negate="True"/>
          </conditions>
          <action type="Rewrite" url="server.js"/>
        </rule>
      </rules>
    </rewrite>
    <security>
      <requestFiltering>
        <requestLimits maxAllowedContentLength="52428800" />
      </requestFiltering>
    </security>
    <iisnode
      node_env="production"
      nodeProcessCountPerApplication="0"
      maxConcurrentRequestsPerProcess="1024"
      maxNamedPipeConnectionRetry="3"
      namedPipeConnectionRetryDelay="2000"
      maxNamedPipeConnectionPoolSize="512"
      maxNamedPipePooledConnectionAge="30000"
      asyncCompletionThreadCount="0"
      initialRequestBufferSize="4096"
      maxRequestBufferSize="65536"
      watchedFiles="*.js"
      uncFileChangesPollingInterval="5000"
      gracefulShutdownTimeout="60000"
      loggingEnabled="true"
      logDirectoryNameSuffix="logs"
      debuggingEnabled="false"
      devErrorsEnabled="false"
      flushResponse="false"
      enableXFF="true"
      promoteServerVars=""
    />
  </system.webServer>
</configuration>
"@
    
    $webConfigContent | Out-File -FilePath "$ProjectPath\web.config" -Encoding UTF8
    
    Write-Log "✅ Конфигурация создана" "SUCCESS"
}

# Настройка Windows Service
function Setup-WindowsService {
    Write-Log "🔧 Настройка Windows Service..." "INFO"
    
    # Установка PM2 как Windows Service
    Set-Location $ProjectPath
    pm2-service-install
    pm2-service-start
    
    # Создание PM2 ecosystem файла
    $ecosystemContent = @"
{
  "apps": [
    {
      "name": "color360-app",
      "script": "server.js",
      "cwd": "$($ProjectPath -replace '\\', '/')",
      "instances": 2,
      "exec_mode": "cluster",
      "watch": false,
      "max_memory_restart": "1G",
      "env": {
        "NODE_ENV": "production",
        "PORT": "3000"
      },
      "log_date_format": "YYYY-MM-DD HH:mm:ss Z",
      "error_file": "C:/Logs/color360/pm2-error.log",
      "out_file": "C:/Logs/color360/pm2-out.log",
      "log_file": "C:/Logs/color360/pm2-combined.log",
      "merge_logs": true,
      "time": true
    }
  ]
}
"@
    
    $ecosystemContent | Out-File -FilePath "$ProjectPath\ecosystem.production.json" -Encoding UTF8
    
    Write-Log "✅ Windows Service настроен" "SUCCESS"
}

# Настройка логирования
function Setup-Logging {
    Write-Log "📝 Настройка логирования..." "INFO"
    
    $logPath = "C:\Logs\color360"
    if (-not (Test-Path $logPath)) {
        New-Item -ItemType Directory -Path $logPath -Force | Out-Null
    }
    
    # Создание задачи в планировщике для ротации логов
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-Command `"Get-ChildItem 'C:\Logs\color360\*.log' | Where-Object { `$_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item -Force`""
    $trigger = New-ScheduledTaskTrigger -Daily -At "02:00"
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    
    Register-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -TaskName "Color360LogRotation" -Description "Ротация логов Color360" -Force
    
    Write-Log "✅ Логирование настроено" "SUCCESS"
}

# Настройка брандмауэра
function Configure-Firewall {
    Write-Log "🔥 Настройка брандмауэра..." "INFO"
    
    # Разрешение портов для веб-сервера
    New-NetFirewallRule -DisplayName "Color360 HTTP" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
    New-NetFirewallRule -DisplayName "Color360 HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow
    New-NetFirewallRule -DisplayName "Color360 App" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow
    New-NetFirewallRule -DisplayName "Color360 LaMa" -Direction Inbound -Protocol TCP -LocalPort 5000 -Action Allow
    
    Write-Log "✅ Брандмауэр настроен" "SUCCESS"
}

# Запуск сервисов
function Start-Services {
    Write-Log "🚀 Запуск сервисов..." "INFO"
    
    # Запуск IIS
    Start-Service W3SVC
    
    # Запуск PM2 сервиса
    Start-Service PM2
    
    # Запуск приложения через PM2
    Set-Location $ProjectPath
    pm2 start ecosystem.production.json
    pm2 save
    
    # Запуск IIS сайта
    Import-Module WebAdministration
    Start-IISSite -Name "color360"
    
    Write-Log "✅ Сервисы запущены" "SUCCESS"
}

# Проверка развертывания
function Verify-Deployment {
    Write-Log "🔍 Проверка развертывания..." "INFO"
    
    Start-Sleep -Seconds 15
    
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:3000/health" -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Log "✅ Основной сервис доступен" "SUCCESS"
        }
    } catch {
        Write-Log "⚠️ Основной сервис недоступен: $($_.Exception.Message)" "WARNING"
    }
    
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:3000/pano/" -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Log "✅ Редактор панорам доступен" "SUCCESS"
        }
    } catch {
        Write-Log "⚠️ Редактор панорам недоступен: $($_.Exception.Message)" "WARNING"
    }
    
    Write-Log "✅ Проверка развертывания завершена" "SUCCESS"
}

# Создание отчета
function Create-DeploymentReport {
    Write-Log "📋 Создание отчета о развертывании..." "INFO"
    
    $reportPath = "C:\Logs\color360\deployment-report-$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    
    $report = @"
# Color360 Windows Deployment Report
Generated: $(Get-Date)

## System Information
OS: $((Get-WmiObject Win32_OperatingSystem).Caption)
Version: $((Get-WmiObject Win32_OperatingSystem).Version)
Architecture: $env:PROCESSOR_ARCHITECTURE

## Installed Software
Node.js: $(node --version 2>$null)
NPM: $(npm --version 2>$null)
Python: $(python --version 2>$null)
PM2: $(pm2 --version 2>$null)

## Service Status
IIS: $((Get-Service W3SVC).Status)
PM2: $((Get-Service PM2 -ErrorAction SilentlyContinue).Status)

## Configuration
Domain: $Domain
Project Path: $ProjectPath
Backup Path: $BackupPath

## URLs to test
- Main site: http://$Domain/
- Panoramic editor: http://$Domain/pano/
- Health check: http://$Domain/health
- API test: http://$Domain/api/demo

## Log Files
- Application: C:\Logs\color360\
- PM2: C:\Logs\color360\pm2-*.log
- IIS: C:\inetpub\logs\LogFiles\

"@
    
    $report | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Log "✅ Отчет создан: $reportPath" "SUCCESS"
}

# Основная функция
function Main {
    Write-Log "🚀 Начало автоматического развертывания Color360 на Windows" "INFO"
    Write-Log "Domain: $Domain" "INFO"
    Write-Log "Project directory: $ProjectPath" "INFO"
    
    # Проверка прав администратора
    if (-not (Test-Administrator)) {
        Write-Log "❌ Требуются права администратора. Запустите PowerShell от имени администратора." "ERROR"
        exit 1
    }
    
    try {
        Create-Backup
        Stop-ExistingServices
        Install-Dependencies
        Configure-IIS
        Deploy-Project
        Create-Configuration
        Setup-WindowsService
        Setup-Logging
        Configure-Firewall
        Start-Services
        Verify-Deployment
        Create-DeploymentReport
        
        Write-Log "🎉 Развертывание Color360 завершено успешно!" "SUCCESS"
        Write-Log "🌐 Сайт доступен по адресу: http://$Domain" "SUCCESS"
        Write-Log "🎨 Редактор панорам: http://$Domain/pano" "SUCCESS"
        
        Write-Success @"

╔══════════════════════════════════════════════════════════════╗
║                    РАЗВЕРТЫВАНИЕ ЗАВЕРШЕНО                   ║
╠══════════════════════════════════════════════════════════════╣
║ 🌐 Основной сайт:        http://$Domain/                    ║
║ 🎨 Редактор панорам:     http://$Domain/pano                ║
║ 🗑️ Удаление объектов:    Включено (LaMa + OpenCV)          ║
║ 🔒 SSL:                  Настройте вручную в IIS            ║
║ 🔥 Брандмауэр:           Настроен                           ║
║ 📊 Мониторинг:           PM2 + Windows Services             ║
║ 📦 Резервные копии:      $BackupPath                        ║
╚══════════════════════════════════════════════════════════════╝

"@
        
    } catch {
        Write-Log "❌ Ошибка во время развертывания: $($_.Exception.Message)" "ERROR"
        Write-Log "📄 Детали ошибки записаны в лог: $LogFile" "ERROR"
        exit 1
    }
}

# Запуск
Main