#!/bin/bash
# ЯДЕРНАЯ ОЧИСТКА NODE.JS - убивает все Node.js на системе

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${PURPLE}💀 ЯДЕРНАЯ ОЧИСТКА NODE.JS 💀${NC}"
echo "======================================"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Запустите от root: sudo bash $0${NC}"
    exit 1
fi

# Убиваем все процессы
echo "🔪 Убиваем все Node.js процессы..."
pkill -9 -f "node\|npm\|nvm" 2>/dev/null || true

# Убираем блокировки
echo "🔓 Убираем блокировки dpkg..."
rm -f /var/lib/dpkg/lock*
rm -f /var/cache/apt/archives/lock
rm -f /var/lib/apt/lists/lock

# Настройка
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Исправляем прерванные операции
dpkg --configure -a 2>/dev/null || true

# ФИЗИЧЕСКОЕ УНИЧТОЖЕНИЕ
echo "💣 Физическое удаление файлов..."
rm -rf /usr/include/node* 2>/dev/null || true
rm -rf /usr/lib/node* 2>/dev/null || true  
rm -rf /usr/share/node* 2>/dev/null || true
rm -rf /var/lib/nodejs* 2>/dev/null || true
rm -rf ~/.nvm ~/.npm 2>/dev/null || true
rm -f /usr/local/bin/node /usr/local/bin/npm 2>/dev/null || true
rm -f /usr/bin/node /usr/bin/npm 2>/dev/null || true

# УДАЛЕНИЕ ВСЕХ Node пакетов
echo "🗑️ Удаление всех Node пакетов..."

# Получаем ВСЕ пакеты с node/npm
ALL_NODE_PACKAGES=$(dpkg -l | grep -E '(node|npm|libnode)' | awk '{print $2}' | tr '\n' ' ')

if [ -n "$ALL_NODE_PACKAGES" ]; then
    echo "Найдены пакеты: $ALL_NODE_PACKAGES"
    
    # Удаляем каждый пакет принудительно
    for pkg in $ALL_NODE_PACKAGES; do
        echo "Удаление $pkg..."
        
        # Принудительное удаление БЕЗ зависимостей
        dpkg --remove --force-all "$pkg" 2>/dev/null || true
        dpkg --purge --force-all "$pkg" 2>/dev/null || true
        
        # Удаляем через apt если есть
        apt-get remove --purge -y "$pkg" 2>/dev/null || true
    done
else
    echo "Node пакеты не найдены"
fi

# ГЛОБАЛЬНАЯ ОЧИСТКА APT
echo "🧹 Глобальная очистка apt..."
apt-get clean 2>/dev/null || true
apt-get autoclean 2>/dev/null || true
apt-get autoremove --purge -y 2>/dev/null || true

# Удаляем все кэши
rm -rf /var/lib/apt/lists/* 2>/dev/null || true
rm -rf /var/cache/apt/archives/* 2>/dev/null || true

# Обновляем базу
apt-get update -qq 2>/dev/null || true

# Исправляем сломанные зависимости
apt-get --fix-broken install -y 2>/dev/null || true

# Финальная очистка
apt-get autoremove --purge -y 2>/dev/null || true

echo ""
echo -e "${GREEN}✅ ЯДЕРНАЯ ОЧИСТКА ЗАВЕРШЕНА${NC}"
echo -e "${PURPLE}💀 ВСЕ Node.js ПОЛНОСТЬЮ УНИЧТОЖЕН 💀${NC}"
echo ""

# Проверяем что ничего не осталось
if command -v node >/dev/null 2>&1; then
    echo -e "${RED}⚠️ Node.js всё ещё найден!${NC}"
    which node
else
    echo -e "${GREEN}✅ Node.js полностью удален${NC}"
fi

if command -v npm >/dev/null 2>&1; then
    echo -e "${RED}⚠️ NPM всё ещё найден!${NC}"
    which npm
else
    echo -e "${GREEN}✅ NPM полностью удален${NC}"
fi

# Проверяем пакеты
REMAINING=$(dpkg -l | grep -E '(node|npm)' | wc -l)
echo "Оставшихся Node пакетов: $REMAINING"

echo ""
echo "Теперь можете устанавливать Node.js заново!"