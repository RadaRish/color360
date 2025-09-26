#!/bin/bash
# ЧИСТАЯ УСТАНОВКА NODE.JS

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🟢 ЧИСТАЯ УСТАНОВКА NODE.JS${NC}"
echo "================================"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Запустите от root: sudo bash $0${NC}"
    exit 1
fi

NODE_VERSION="20.17.0"

echo "📥 Скачивание Node.js $NODE_VERSION..."
cd /tmp

# Удаляем старые файлы если есть
rm -rf node-v* 2>/dev/null || true

# Скачиваем
wget -q "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.xz" || {
    echo -e "${RED}❌ Ошибка скачивания${NC}"
    exit 1
}

echo "📦 Распаковка..."
tar -xf "node-v$NODE_VERSION-linux-x64.tar.xz"

echo "🔧 Установка в /usr/local..."
cp -rf "node-v$NODE_VERSION-linux-x64"/* /usr/local/

# Создаем симлинки
ln -sf /usr/local/bin/node /usr/bin/node 2>/dev/null || true
ln -sf /usr/local/bin/npm /usr/bin/npm 2>/dev/null || true

# Очистка
rm -rf node-v*

# Проверка
echo "🔍 Проверка установки..."

if /usr/local/bin/node --version >/dev/null 2>&1; then
    NODE_VER=$(/usr/local/bin/node --version)
    echo -e "${GREEN}✅ Node.js $NODE_VER установлен${NC}"
else
    echo -e "${RED}❌ Ошибка установки Node.js${NC}"
    exit 1
fi

if /usr/local/bin/npm --version >/dev/null 2>&1; then
    NPM_VER=$(/usr/local/bin/npm --version)
    echo -e "${GREEN}✅ NPM $NPM_VER установлен${NC}"
else
    echo -e "${RED}❌ Ошибка установки NPM${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 NODE.JS УСПЕШНО УСТАНОВЛЕН!${NC}"
echo ""
echo "Команды:"
echo "  node --version"
echo "  npm --version"
echo "  /usr/local/bin/node --version"
echo "  /usr/local/bin/npm --version"