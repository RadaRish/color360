#!/bin/bash
# Color360 - Главный установщик для VPS
# Выбор типа установки

set -e

# Цвета
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${PURPLE}"
cat << "EOF"
   ____      _            _____  ____   ___  
  / ___|___ | | ___  _ __|___ / / ___|/ _ \ 
 | |   / _ \| |/ _ \| '__|  |_ \| |  | | | |
 | |__| (_) | | (_) | |  ___) | |__| |_| |
  \____\___/|_|\___/|_| |____/ \____\___/ 
                                          
EOF
echo -e "${NC}"

echo "🚀 Установщик Color360 для VPS"
echo "==============================="
echo "Домен: color360.ru"
echo ""

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Запустите с правами root: sudo bash $0${NC}"
    exit 1
fi

echo "Выберите тип установки:"
echo ""
echo -e "${GREEN}1)${NC} 🎨 Полная установка (основное приложение + AI сервис)"
echo "   - Панорамный редактор"
echo "   - AI удаление объектов (LaMa)"
echo "   - Все функции"
echo ""
echo -e "${BLUE}2)${NC} ⚡ Быстрая установка (только основное приложение)"
echo "   - Панорамный редактор"
echo "   - Без AI функций"
echo "   - Быстрая установка"
echo ""
echo -e "${YELLOW}3)${NC} 🔧 Только обновление существующей установки"
echo "   - Обновляет код с GitHub"
echo "   - Перезапускает сервисы"
echo ""

read -p "Введите номер (1-3): " choice

case $choice in
    1)
        echo ""
        echo -e "${GREEN}🎨 Запуск полной установки...${NC}"
        echo ""
        curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/install-fresh-vps.sh | bash
        ;;
    2)
        echo ""
        echo -e "${BLUE}⚡ Запуск быстрой установки...${NC}"
        echo ""
        curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/install-minimal.sh | bash
        ;;
    3)
        echo ""
        echo -e "${YELLOW}🔧 Запуск обновления...${NC}"
        echo ""
        
        # Простое обновление
        PROJECT_DIR="/var/www/color360"
        
        if [ ! -d "$PROJECT_DIR" ]; then
            echo -e "${RED}❌ Проект не найден в $PROJECT_DIR${NC}"
            echo "Используйте полную установку (вариант 1 или 2)"
            exit 1
        fi
        
        cd "$PROJECT_DIR"
        
        echo "🛑 Остановка сервисов..."
        systemctl stop color360-app color360-sd 2>/dev/null || true
        
        echo "📥 Обновление кода..."
        git stash push -m "Auto-stash before update $(date)" 2>/dev/null || true
        git pull origin main
        
        echo "📦 Обновление зависимостей..."
        npm install --production
        
        if [ -d "sd_env" ] && [ -f "sd/requirements.txt" ]; then
            echo "🐍 Обновление Python зависимостей..."
            source sd_env/bin/activate
            pip install --upgrade -r sd/requirements.txt
            deactivate
        fi
        
        echo "🚀 Запуск сервисов..."
        systemctl start color360-app
        if systemctl list-unit-files | grep -q "color360-sd.service"; then
            systemctl start color360-sd
        fi
        
        sleep 5
        
        if systemctl is-active --quiet color360-app; then
            echo -e "${GREEN}✅ Обновление завершено успешно!${NC}"
            
            commit_hash=$(git rev-parse --short HEAD)
            commit_msg=$(git log -1 --pretty=format:"%s")
            echo "📝 Текущий коммит: $commit_hash"
            echo "💬 Изменения: $commit_msg"
        else
            echo -e "${RED}❌ Ошибка при обновлении${NC}"
            systemctl status color360-app --no-pager
        fi
        ;;
    *)
        echo -e "${RED}❌ Неверный выбор${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${PURPLE}🎊 Готово!${NC}"