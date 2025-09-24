#!/bin/bash
# Скрипт для освобождения места на VPS сервере

echo "🧹 Освобождение места на диске VPS..."

# Проверяем место на диске
echo "📊 Текущее использование диска:"
df -h /

echo ""
echo "🔍 Поиск больших файлов и директорий..."

# Удаляем все бэкапы и старые версии
echo "🗑️ Удаление бэкапов и старых версий..."
rm -rf /var/www/color360-backups* 2>/dev/null || true
rm -rf /var/www/color360-* 2>/dev/null || true
rm -rf /opt/color360* 2>/dev/null || true
rm -rf /home/*/color360* 2>/dev/null || true
rm -rf /tmp/color360* 2>/dev/null || true
echo "✅ Старые версии и бэкапы удалены"

# Очищаем системные логи
echo "📜 Очистка системных логов..."
journalctl --vacuum-time=7d
journalctl --vacuum-size=100M

# Очищаем apt кэш
echo "📦 Очистка apt кэша..."
apt-get autoremove -y
apt-get autoclean
apt-get clean

# Очищаем временные файлы
echo "🗂️ Очистка временных файлов..."
rm -rf /tmp/*
rm -rf /var/tmp/*
find /var/log -name "*.log" -type f -size +50M -delete
find /var/log -name "*.gz" -delete

# Очищаем Docker если установлен
if command -v docker &> /dev/null; then
    echo "🐳 Очистка Docker..."
    docker system prune -af --volumes || true
fi

# Очищаем pip кэш
echo "🐍 Очистка pip кэша..."
if [ -d "/root/.cache/pip" ]; then
    rm -rf /root/.cache/pip/*
fi

# Очищаем npm кэш
echo "📦 Очистка npm кэша..."
if command -v npm &> /dev/null; then
    npm cache clean --force || true
fi

# Очистка Color360 специфичных файлов
echo "🎨 Очистка файлов Color360..."
if [ -d "/var/www/color360" ]; then
    cd /var/www/color360
    # Очищаем временные файлы обработки
    rm -rf temp/* 2>/dev/null || true
    # Очищаем загруженные аватары (кроме админских)
    find avatars/ -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" | grep -v "admin" | head -50 | xargs rm -f 2>/dev/null || true
    # Очищаем старые изображения новостей
    find news_images/ -name "*.jpg" -o -name "*.png" -mtime +30 | head -20 | xargs rm -f 2>/dev/null || true
    # Очищаем кэш сессий
    rm -rf sessions/* 2>/dev/null || true
    echo "✅ Файлы Color360 очищены"
fi

echo ""
echo "📊 Место после очистки:"
df -h /

echo ""
echo "🔍 Самые большие директории в /var/www/color360:"
cd /var/www/color360
du -sh * 2>/dev/null | sort -hr | head -10

echo ""
echo "✅ Очистка завершена!"
echo ""
echo "💡 Рекомендации:"
echo "   - Если sd_env занимает много места, можно пересоздать виртуальное окружение"
echo "   - Настройте логротацию для предотвращения переполнения"
echo "   - Рассмотрите увеличение размера диска VPS"