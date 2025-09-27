#!/bin/bash

# Восстановление файлов сайта из GitHub репозитория
echo "🔄 ВОССТАНОВЛЕНИЕ ФАЙЛОВ САЙТА ИЗ РЕПОЗИТОРИЯ"
echo "============================================="

WEBROOT="/var/www/color360"
BACKUP_DIR="/tmp/color360-backup-$(date +%Y%m%d-%H%M%S)"
REPO_URL="https://github.com/RadaRish/color360.git"
TEMP_REPO="/tmp/color360-restore"

echo "📁 Создание резервной копии текущих файлов..."
if [[ -d "$WEBROOT" ]]; then
    cp -r "$WEBROOT" "$BACKUP_DIR"
    echo "✅ Резервная копия создана: $BACKUP_DIR"
else
    echo "⚠️ Директория $WEBROOT не существует"
fi

echo ""
echo "📥 Загрузка свежих файлов из репозитория..."

# Очистка временной директории
rm -rf "$TEMP_REPO"
mkdir -p "$TEMP_REPO"

# Клонирование репозитория
if git clone "$REPO_URL" "$TEMP_REPO"; then
    echo "✅ Репозиторий загружен"
else
    echo "❌ Ошибка загрузки репозитория"
    exit 1
fi

echo ""
echo "📋 Восстановление основных файлов..."

# Создаем целевую директорию
mkdir -p "$WEBROOT"

# Копируем основные HTML файлы
for file in index.html main.html admin-dashboard.html profile.html privacy.html; do
    if [[ -f "$TEMP_REPO/$file" ]]; then
        cp "$TEMP_REPO/$file" "$WEBROOT/"
        echo "✅ Скопирован: $file"
    else
        echo "⚠️ Не найден: $file"
    fi
done

echo ""
echo "📁 Восстановление директорий assets..."

# Копируем директорию assets
if [[ -d "$TEMP_REPO/assets" ]]; then
    cp -r "$TEMP_REPO/assets" "$WEBROOT/"
    echo "✅ Директория assets скопирована"
else
    echo "⚠️ Директория assets не найдена в репозитории"
fi

# Копируем другие важные директории
for dir in avatars news_images temp; do
    if [[ -d "$TEMP_REPO/$dir" ]]; then
        cp -r "$TEMP_REPO/$dir" "$WEBROOT/"
        echo "✅ Директория $dir скопирована"
    else
        echo "⚠️ Директория $dir не найдена"
    fi
done

echo ""
echo "🎭 Восстановление панорамного просмотра..."

# Специальное восстановление pano директории
if [[ -d "$TEMP_REPO/pano" ]]; then
    cp -r "$TEMP_REPO/pano" "$WEBROOT/"
    echo "✅ Панорамный просмотр восстановлен"
    
    # Проверяем ключевые файлы pano
    for pano_file in index.html main.js style.css; do
        if [[ -f "$WEBROOT/pano/$pano_file" ]]; then
            echo "  ✅ $pano_file"
        else
            echo "  ❌ $pano_file отсутствует"
        fi
    done
    
    # Проверяем поддиректории pano
    for pano_dir in assets core ui styles scripts docs; do
        if [[ -d "$WEBROOT/pano/$pano_dir" ]]; then
            echo "  ✅ $pano_dir/"
        else
            echo "  ⚠️ $pano_dir/ отсутствует"
        fi
    done
else
    echo "❌ Директория pano не найдена в репозитории!"
fi

echo ""
echo "🔧 Установка правильных прав доступа..."

# Устанавливаем владельца и права
chown -R www-data:www-data "$WEBROOT"
find "$WEBROOT" -type d -exec chmod 755 {} \;
find "$WEBROOT" -type f -exec chmod 644 {} \;

echo "✅ Права доступа установлены"

echo ""
echo "🧪 Проверка восстановленных файлов..."

echo "Основные файлы:"
for file in index.html main.html; do
    if [[ -f "$WEBROOT/$file" ]]; then
        size=$(stat -c%s "$WEBROOT/$file" 2>/dev/null || echo "0")
        echo "  ✅ $file ($size байт)"
    else
        echo "  ❌ $file отсутствует"
    fi
done

echo ""
echo "Панорама:"
if [[ -f "$WEBROOT/pano/index.html" ]]; then
    size=$(stat -c%s "$WEBROOT/pano/index.html" 2>/dev/null || echo "0")
    echo "  ✅ pano/index.html ($size байт)"
else
    echo "  ❌ pano/index.html отсутствует"
fi

if [[ -f "$WEBROOT/pano/main.js" ]]; then
    size=$(stat -c%s "$WEBROOT/pano/main.js" 2>/dev/null || echo "0")
    echo "  ✅ pano/main.js ($size байт)"
else
    echo "  ❌ pano/main.js отсутствует"
fi

echo ""
echo "Assets:"
if [[ -d "$WEBROOT/assets" ]]; then
    asset_count=$(find "$WEBROOT/assets" -type f | wc -l)
    echo "  ✅ assets/ ($asset_count файлов)"
else
    echo "  ❌ assets/ отсутствует"
fi

echo ""
echo "🌐 Тест локальной доступности после восстановления..."

sleep 2

# Тест основного сайта
MAIN_TEST=$(curl -s -w "%{http_code}" -m 10 "http://localhost/")
MAIN_CODE="${MAIN_TEST: -3}"

if [[ "$MAIN_CODE" == "200" ]]; then
    echo "✅ Основной сайт доступен (HTTP $MAIN_CODE)"
else
    echo "❌ Основной сайт недоступен (HTTP $MAIN_CODE)"
fi

# Тест панорамы
PANO_TEST=$(curl -s -w "%{http_code}" -m 10 "http://localhost/pano/")
PANO_CODE="${PANO_TEST: -3}"

if [[ "$PANO_CODE" == "200" ]]; then
    echo "✅ Панорама доступна (HTTP $PANO_CODE)"
else
    echo "❌ Панорама недоступна (HTTP $PANO_CODE)"
fi

echo ""
echo "🧹 Очистка временных файлов..."
rm -rf "$TEMP_REPO"
echo "✅ Временные файлы удалены"

echo ""
echo "🏁 ВОССТАНОВЛЕНИЕ ЗАВЕРШЕНО"
echo "==========================="

if [[ "$MAIN_CODE" == "200" && "$PANO_CODE" == "200" ]]; then
    echo "✅ УСПЕХ! Сайт полностью восстановлен"
    echo ""
    echo "Доступные URL:"
    echo "- Основной сайт: http://color360.ru/"
    echo "- Панорама: http://color360.ru/pano/"
    echo ""
    echo "Резервная копия сохранена в: $BACKUP_DIR"
else
    echo "⚠️ Восстановление выполнено, но есть проблемы с доступностью"
    echo ""
    echo "Следующие шаги:"
    echo "1. Проверьте nginx: systemctl status nginx"
    echo "2. Проверьте логи: tail -f /var/log/nginx/error.log"
    echo "3. Перезапустите nginx: systemctl restart nginx"
    echo ""
    echo "Резервная копия сохранена в: $BACKUP_DIR"
fi