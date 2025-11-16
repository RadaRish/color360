#!/bin/bash

################################################################################
# Скрипт установки SSL сертификата для PanoBro
# Требования: домен должен быть привязан к IP 72.56.82.203
################################################################################

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    log_error "Запустите скрипт с правами root: sudo bash setup-ssl.sh"
    exit 1
fi

echo "🔐 Настройка SSL сертификата для PanoBro"
echo "========================================"
echo ""

# Запрос домена
read -p "Введите ваш домен (например, panobro.ru): " DOMAIN
read -p "Добавить www поддомен? (y/n): " ADD_WWW

if [ -z "$DOMAIN" ]; then
    log_error "Домен не может быть пустым!"
    exit 1
fi

# Формирование списка доменов
DOMAINS="-d $DOMAIN"
if [ "$ADD_WWW" = "y" ] || [ "$ADD_WWW" = "Y" ]; then
    DOMAINS="$DOMAINS -d www.$DOMAIN"
fi

log_info "Будут настроены домены: $DOMAIN$([ "$ADD_WWW" = "y" ] && echo ", www.$DOMAIN")"

# Запрос email
read -p "Введите email для уведомлений Let's Encrypt: " EMAIL

if [ -z "$EMAIL" ]; then
    log_error "Email не может быть пустым!"
    exit 1
fi

# Установка Certbot
log_info "Установка Certbot..."
apt-get update
apt-get install -y certbot python3-certbot-nginx

# Обновление конфигурации Nginx
log_info "Обновление конфигурации Nginx..."
sed -i "s/server_name 72.56.82.203;/server_name $DOMAIN$([ "$ADD_WWW" = "y" ] && echo " www.$DOMAIN");/" /etc/nginx/sites-available/panobro

# Проверка конфигурации
nginx -t

# Перезагрузка Nginx
systemctl reload nginx

# Получение сертификата
log_info "Получение SSL сертификата..."
certbot --nginx $DOMAINS --email $EMAIL --agree-tos --non-interactive --redirect

# Настройка автоматического обновления
log_info "Настройка автоматического обновления сертификата..."

# Создание cronjob для обновления
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/certbot renew --quiet && systemctl reload nginx") | crontab -

# Тест обновления
certbot renew --dry-run

echo ""
echo "========================================"
log_info "✅ SSL сертификат успешно установлен!"
echo "========================================"
echo ""
echo "🌐 Ваш сайт теперь доступен по HTTPS:"
echo "   https://$DOMAIN/"
echo "   https://$DOMAIN/pano/"
if [ "$ADD_WWW" = "y" ]; then
    echo "   https://www.$DOMAIN/"
fi
echo ""
log_info "Сертификат будет автоматически обновляться каждые 60 дней"
echo ""
