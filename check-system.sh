#!/bin/bash
# Скрипт диагностики Color360 после обновления
# Проверяет все компоненты системы и выдает отчет о состоянии

set -e

PROJECT_DIR="/opt/color360"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Диагностика Color360 системы${NC}"
echo "======================================"

# Функция проверки сервиса
check_service() {
    local service=$1
    local port=$2
    local url=$3
    
    echo -n "📊 $service: "
    
    # Проверка systemd статуса
    if systemctl is-active --quiet $service; then
        echo -n -e "${GREEN}Активен${NC}"
    else
        echo -n -e "${RED}Неактивен${NC}"
        return 1
    fi
    
    # Проверка порта
    if ss -tuln | grep -q ":$port "; then
        echo -n -e " | ${GREEN}Порт $port открыт${NC}"
    else
        echo -n -e " | ${RED}Порт $port закрыт${NC}"
        return 1
    fi
    
    # Проверка HTTP ответа
    if [ ! -z "$url" ]; then
        if curl -f -s "$url" > /dev/null 2>&1; then
            echo -e " | ${GREEN}HTTP OK${NC}"
        else
            echo -e " | ${RED}HTTP Error${NC}"
            return 1
        fi
    else
        echo ""
    fi
    
    return 0
}

# Проверка директории проекта
echo "📁 Проверка файловой системы:"
if [ -d "$PROJECT_DIR" ]; then
    echo -e "   ✅ Директория проекта: ${GREEN}$PROJECT_DIR${NC}"
    
    # Проверка основных файлов
    files=("server.js" "package.json" "sd/sd_app.py" "sd/requirements.txt")
    for file in "${files[@]}"; do
        if [ -f "$PROJECT_DIR/$file" ]; then
            echo -e "   ✅ $file: ${GREEN}Существует${NC}"
        else
            echo -e "   ❌ $file: ${RED}Отсутствует${NC}"
        fi
    done
else
    echo -e "   ❌ Директория проекта: ${RED}Не найдена${NC}"
    exit 1
fi

echo ""

# Проверка Git статуса
echo "📋 Git репозиторий:"
cd "$PROJECT_DIR"
if [ -d ".git" ]; then
    current_branch=$(git branch --show-current)
    current_commit=$(git rev-parse --short HEAD)
    echo -e "   🌿 Ветка: ${BLUE}$current_branch${NC}"
    echo -e "   📝 Коммит: ${BLUE}$current_commit${NC}"
    
    # Проверка на незакоммиченные изменения
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo -e "   ⚠️  Статус: ${YELLOW}Есть незакоммиченные изменения${NC}"
    else
        echo -e "   ✅ Статус: ${GREEN}Чистый${NC}"
    fi
else
    echo -e "   ❌ Git: ${RED}Не инициализован${NC}"
fi

echo ""

# Проверка systemd сервисов
echo "🔧 Системные сервисы:"

# Color360 SD Service
if check_service "color360-sd" "5002" "http://localhost:5002/health"; then
    echo -e "   ✅ Stable Diffusion: ${GREEN}Работает корректно${NC}"
else
    echo -e "   ❌ Stable Diffusion: ${RED}Проблемы${NC}"
    echo "   📜 Последние логи:"
    systemctl status color360-sd --no-pager -l -n 3 | sed 's/^/      /'
fi

echo ""

# Color360 App Service  
if check_service "color360-app" "3000" "http://localhost:3000/"; then
    echo -e "   ✅ Основное приложение: ${GREEN}Работает корректно${NC}"
else
    echo -e "   ❌ Основное приложение: ${RED}Проблемы${NC}"
    echo "   📜 Последние логи:"
    systemctl status color360-app --no-pager -l -n 3 | sed 's/^/      /'
fi

echo ""

# Nginx
if systemctl is-active --quiet nginx; then
    echo -e "   ✅ Nginx: ${GREEN}Активен${NC}"
else
    echo -e "   ❌ Nginx: ${RED}Неактивен${NC}"
fi

echo ""

# Проверка API endpoints
echo "🌐 API Endpoints:"

# AI Health
response=$(curl -s -w "HTTPSTATUS:%{http_code}" http://localhost:3000/api/ai-health 2>/dev/null || echo "HTTPSTATUS:000")
http_code=$(echo $response | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
if [ "$http_code" = "200" ]; then
    echo -e "   ✅ /api/ai-health: ${GREEN}$http_code${NC}"
else
    echo -e "   ❌ /api/ai-health: ${RED}$http_code${NC}"
fi

# SD Health
response=$(curl -s -w "HTTPSTATUS:%{http_code}" http://localhost:3000/api/sd-health 2>/dev/null || echo "HTTPSTATUS:000")
http_code=$(echo $response | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
if [ "$http_code" = "200" ]; then
    echo -e "   ✅ /api/sd-health: ${GREEN}$http_code${NC}"
else
    echo -e "   ❌ /api/sd-health: ${RED}$http_code${NC}"
fi

# Retouch API (только проверка доступности, не отправляем файлы)
response=$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST http://localhost:3000/api/retouch 2>/dev/null || echo "HTTPSTATUS:000")
http_code=$(echo $response | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
if [ "$http_code" = "400" ]; then  # 400 ожидаемо без файлов
    echo -e "   ✅ /api/retouch: ${GREEN}Доступен (400)${NC}"
elif [ "$http_code" = "200" ]; then
    echo -e "   ✅ /api/retouch: ${GREEN}$http_code${NC}"
else
    echo -e "   ❌ /api/retouch: ${RED}$http_code${NC}"
fi

echo ""

# Проверка ресурсов системы
echo "💻 Системные ресурсы:"

# CPU и память для наших процессов
node_pid=$(pgrep -f "node server.js" | head -1)
python_pid=$(pgrep -f "python.*sd_app.py" | head -1)

if [ ! -z "$node_pid" ]; then
    node_cpu=$(ps -p $node_pid -o %cpu --no-headers | xargs)
    node_mem=$(ps -p $node_pid -o %mem --no-headers | xargs)
    echo -e "   📊 Node.js (PID $node_pid): ${BLUE}CPU: $node_cpu%, RAM: $node_mem%${NC}"
else
    echo -e "   ❌ Node.js процесс: ${RED}Не найден${NC}"
fi

if [ ! -z "$python_pid" ]; then
    python_cpu=$(ps -p $python_pid -o %cpu --no-headers | xargs)
    python_mem=$(ps -p $python_pid -o %mem --no-headers | xargs)
    echo -e "   📊 Python SD (PID $python_pid): ${BLUE}CPU: $python_cpu%, RAM: $python_mem%${NC}"
else
    echo -e "   ❌ Python SD процесс: ${RED}Не найден${NC}"
fi

# Дисковое пространство
disk_usage=$(df -h "$PROJECT_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$disk_usage" -lt 80 ]; then
    echo -e "   📊 Диск: ${GREEN}${disk_usage}% используется${NC}"
elif [ "$disk_usage" -lt 90 ]; then
    echo -e "   📊 Диск: ${YELLOW}${disk_usage}% используется${NC}"
else
    echo -e "   📊 Диск: ${RED}${disk_usage}% используется (мало места!)${NC}"
fi

# Общая загрузка системы
load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
echo -e "   📊 Нагрузка: ${BLUE}$load_avg${NC}"

echo ""

# Проверка логов на ошибки
echo "📜 Анализ логов (последние 50 строк):"

error_count=0

# Проверяем логи color360-app на ошибки
app_errors=$(journalctl -u color360-app --no-pager -n 50 | grep -i -c "error\|failed\|exception" || echo "0")
if [ "$app_errors" -gt 0 ]; then
    echo -e "   ⚠️  App логи: ${YELLOW}$app_errors ошибок найдено${NC}"
    error_count=$((error_count + app_errors))
else
    echo -e "   ✅ App логи: ${GREEN}Ошибок не найдено${NC}"
fi

# Проверяем логи color360-sd на ошибки  
sd_errors=$(journalctl -u color360-sd --no-pager -n 50 | grep -i -c "error\|failed\|exception" || echo "0")
if [ "$sd_errors" -gt 0 ]; then
    echo -e "   ⚠️  SD логи: ${YELLOW}$sd_errors ошибок найдено${NC}"
    error_count=$((error_count + sd_errors))
else
    echo -e "   ✅ SD логи: ${GREEN}Ошибок не найдено${NC}"
fi

# Проверяем логи nginx на ошибки
if [ -f "/var/log/nginx/error.log" ]; then
    nginx_errors=$(tail -50 /var/log/nginx/error.log | grep -c "error" || echo "0")
    if [ "$nginx_errors" -gt 0 ]; then
        echo -e "   ⚠️  Nginx логи: ${YELLOW}$nginx_errors ошибок найдено${NC}"
        error_count=$((error_count + nginx_errors))
    else
        echo -e "   ✅ Nginx логи: ${GREEN}Ошибок не найдено${NC}"
    fi
fi

echo ""
echo "======================================"

# Итоговый статус
if [ "$error_count" -eq 0 ] && systemctl is-active --quiet color360-app && systemctl is-active --quiet color360-sd; then
    echo -e "${GREEN}🎉 Система работает отлично!${NC}"
    echo "📊 Все сервисы активны и без ошибок"
elif [ "$error_count" -lt 5 ]; then
    echo -e "${YELLOW}⚠️  Система работает с незначительными проблемами${NC}"
    echo "📊 Найдено $error_count ошибок в логах"
    echo "💡 Рекомендуется проверить логи: journalctl -u color360-app -f"
else
    echo -e "${RED}❌ Система имеет серьезные проблемы${NC}"
    echo "📊 Найдено $error_count ошибок"
    echo "🚨 Требуется немедленное вмешательство"
fi

echo ""
echo "🔗 Полезные команды:"
echo "   journalctl -u color360-app -f     # Логи основного приложения"
echo "   journalctl -u color360-sd -f      # Логи SD сервиса" 
echo "   systemctl restart color360-app    # Перезапуск приложения"
echo "   systemctl restart color360-sd     # Перезапуск SD сервиса"
echo "   ./update-vps.sh                   # Обновление системы"