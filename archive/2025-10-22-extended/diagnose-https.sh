#!/bin/bash

# ДИАГНОСТИКА HTTPS ДЛЯ COLOR360.RU
echo "🔍 ДИАГНОСТИКА HTTPS COLOR360.RU"
echo "==============================="

DOMAIN="color360.ru"
WWW_DOMAIN="www.color360.ru"

echo "🌐 1. ПРОВЕРКА ДОСТУПНОСТИ ДОМЕНОВ"
echo "=================================="

echo "Проверка DNS резолва:"
for domain in $DOMAIN $WWW_DOMAIN; do
    echo -n "$domain: "
    if IP=$(dig +short $domain A | head -1); then
        if [[ -n "$IP" ]]; then
            echo "✅ $IP"
        else
            echo "❌ Не резолвится"
        fi
    else
        echo "❌ DNS ошибка"
    fi
done

echo ""
echo "🔌 2. ПРОВЕРКА ПОРТОВ"
echo "===================="

echo "Проверка открытых портов на сервере:"
for port in 80 443; do
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        echo "✅ Порт $port слушается"
    else
        echo "❌ Порт $port не слушается!"
    fi
done

echo ""
echo "Проверка доступности портов извне:"
for domain in $DOMAIN $WWW_DOMAIN; do
    for port in 80 443; do
        echo -n "$domain:$port - "
        if timeout 10 bash -c "echo >/dev/tcp/$domain/$port" 2>/dev/null; then
            echo "✅ Доступен"
        else
            echo "❌ Недоступен"
        fi
    done
done

echo ""
echo "🔒 3. ПРОВЕРКА SSL СЕРТИФИКАТОВ"
echo "==============================="

echo "Сертификаты Certbot:"
if command -v certbot >/dev/null 2>&1; then
    certbot certificates 2>/dev/null | grep -A 5 "$DOMAIN" || echo "❌ Сертификат для $DOMAIN не найден"
else
    echo "❌ Certbot не установлен"
fi

echo ""
echo "Проверка файлов сертификата:"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
for file in fullchain.pem privkey.pem; do
    if [[ -f "$CERT_PATH/$file" ]]; then
        echo "✅ $CERT_PATH/$file существует"
        ls -la "$CERT_PATH/$file"
    else
        echo "❌ $CERT_PATH/$file отсутствует"
    fi
done

echo ""
echo "SSL тест подключения:"
for domain in $DOMAIN $WWW_DOMAIN; do
    echo "Тест $domain:"
    if SSL_INFO=$(timeout 10 openssl s_client -connect $domain:443 -servername $domain </dev/null 2>/dev/null); then
        echo "$SSL_INFO" | grep -E "(subject|issuer|verify return code)" | sed 's/^/  /'
        
        # Проверка срока действия
        if EXPIRE_DATE=$(echo "$SSL_INFO" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2); then
            echo "  Срок действия: $EXPIRE_DATE"
            if EXPIRE_EPOCH=$(date -d "$EXPIRE_DATE" +%s 2>/dev/null); then
                CURRENT_EPOCH=$(date +%s)
                DAYS_LEFT=$(( ($EXPIRE_EPOCH - $CURRENT_EPOCH) / 86400 ))
                if [[ $DAYS_LEFT -gt 0 ]]; then
                    echo "  ✅ Действителен еще $DAYS_LEFT дней"
                else
                    echo "  ❌ Сертификат истек $((0-$DAYS_LEFT)) дней назад!"
                fi
            fi
        fi
    else
        echo "  ❌ SSL подключение невозможно"
    fi
    echo ""
done

echo ""
echo "🔧 4. ПРОВЕРКА NGINX КОНФИГУРАЦИИ"
echo "================================="

echo "Статус nginx:"
if systemctl is-active --quiet nginx; then
    echo "✅ Nginx активен"
else
    echo "❌ Nginx неактивен!"
fi

echo ""
echo "Проверка синтаксиса конфигурации:"
if nginx -t 2>/dev/null; then
    echo "✅ Конфигурация корректна"
else
    echo "❌ Ошибки в конфигурации:"
    nginx -t
fi

echo ""
echo "Активные сайты:"
if ls /etc/nginx/sites-enabled/ >/dev/null 2>&1; then
    ls -la /etc/nginx/sites-enabled/ | grep color360
    
    echo ""
    echo "SSL настройки в конфигурации:"
    grep -r "ssl_certificate\|listen 443" /etc/nginx/sites-enabled/ 2>/dev/null || echo "SSL настройки не найдены"
else
    echo "❌ Директория sites-enabled недоступна"
fi

echo ""
echo "🌐 5. HTTP/HTTPS ТЕСТЫ"
echo "====================="

echo "Тестирование HTTP доступности:"
for domain in $DOMAIN $WWW_DOMAIN; do
    echo -n "http://$domain/ - "
    if HTTP_CODE=$(curl -s -w "%{http_code}" -m 10 "http://$domain/" -o /dev/null); then
        case $HTTP_CODE in
            200) echo "✅ HTTP 200 (работает)" ;;
            301|302) echo "🔄 HTTP $HTTP_CODE (редирект на HTTPS)" ;;
            404) echo "❌ HTTP 404 (не найден)" ;;
            403) echo "❌ HTTP 403 (запрещен)" ;;
            500|502|503) echo "❌ HTTP $HTTP_CODE (серверная ошибка)" ;;
            *) echo "⚠️ HTTP $HTTP_CODE" ;;
        esac
    else
        echo "❌ Недоступен"
    fi
done

echo ""
echo "Тестирование HTTPS доступности:"
for domain in $DOMAIN $WWW_DOMAIN; do
    echo -n "https://$domain/ - "
    if HTTPS_CODE=$(curl -s -w "%{http_code}" -m 10 "https://$domain/" -o /dev/null -k); then
        case $HTTPS_CODE in
            200) echo "✅ HTTPS 200 (работает)" ;;
            404) echo "❌ HTTPS 404 (не найден)" ;;
            403) echo "❌ HTTPS 403 (запрещен)" ;;
            500|502|503) echo "❌ HTTPS $HTTPS_CODE (серверная ошибка)" ;;
            *) echo "⚠️ HTTPS $HTTPS_CODE" ;;
        esac
    else
        echo "❌ Недоступен"
    fi
done

echo ""
echo "Тестирование панорамы:"
for protocol in http https; do
    echo -n "$protocol://$DOMAIN/pano/ - "
    if PANO_CODE=$(curl -s -w "%{http_code}" -m 10 "$protocol://$DOMAIN/pano/" -o /dev/null -k); then
        case $PANO_CODE in
            200) echo "✅ $PANO_CODE (работает)" ;;
            301|302) echo "🔄 $PANO_CODE (редирект)" ;;
            *) echo "❌ $PANO_CODE" ;;
        esac
    else
        echo "❌ Недоступен"
    fi
done

echo ""
echo "🔗 6. ТЕСТ РЕДИРЕКТОВ HTTP → HTTPS"
echo "=================================="

for domain in $DOMAIN $WWW_DOMAIN; do
    echo "Тест $domain:"
    if REDIRECT_INFO=$(curl -s -I -m 10 "http://$domain/"); then
        if echo "$REDIRECT_INFO" | grep -q "301\|302"; then
            LOCATION=$(echo "$REDIRECT_INFO" | grep -i "location:" | cut -d' ' -f2- | tr -d '\r')
            if [[ "$LOCATION" == https://* ]]; then
                echo "  ✅ Корректный редирект: $LOCATION"
            else
                echo "  ⚠️ Редирект не на HTTPS: $LOCATION"
            fi
        else
            echo "  ❌ Нет редиректа на HTTPS"
        fi
    else
        echo "  ❌ Ошибка при проверке редиректа"
    fi
done

echo ""
echo "📋 7. АНАЛИЗ ЛОГОВ"
echo "=================="

echo "Последние ошибки nginx:"
if [[ -f "/var/log/nginx/error.log" ]]; then
    echo "=== Общие ошибки ==="
    tail -10 /var/log/nginx/error.log | grep -E "(SSL|ssl|certificate|cert)" || echo "SSL ошибок не найдено"
    
    echo ""
    echo "=== Ошибки Color360 ==="
    if [[ -f "/var/log/nginx/color360_error.log" ]]; then
        tail -10 /var/log/nginx/color360_error.log || echo "Лог color360 пуст"
    else
        echo "Лог color360_error.log не найден"
    fi
else
    echo "❌ Лог nginx недоступен"
fi

echo ""
echo "📊 8. РЕЗЮМЕ ДИАГНОСТИКИ"
echo "========================"

# Подсчет проблем
ISSUES=0

# Проверка основных компонентов
if ! systemctl is-active --quiet nginx; then
    echo "❌ Nginx не запущен"
    ((ISSUES++))
fi

if ! nginx -t >/dev/null 2>&1; then
    echo "❌ Ошибки в конфигурации nginx"
    ((ISSUES++))
fi

if [[ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
    echo "❌ SSL сертификат отсутствует"
    ((ISSUES++))
fi

# Проверка доступности
HTTPS_MAIN_TEST=$(curl -s -w "%{http_code}" -m 10 "https://$DOMAIN/" -o /dev/null -k 2>/dev/null)
if [[ "$HTTPS_MAIN_TEST" != "200" ]]; then
    echo "❌ HTTPS сайт недоступен (код: $HTTPS_MAIN_TEST)"
    ((ISSUES++))
fi

if [[ $ISSUES -eq 0 ]]; then
    echo ""
    echo "🎉 ВСЕ В ПОРЯДКЕ! HTTPS работает корректно"
    echo ""
    echo "✅ Доступные URL:"
    echo "   https://color360.ru/"
    echo "   https://color360.ru/pano/"
    echo "   https://www.color360.ru/"
else
    echo ""
    echo "⚠️ НАЙДЕНО $ISSUES проблем(ы)"
    echo ""
    echo "🛠️ Рекомендуемые действия:"
    
    if ! systemctl is-active --quiet nginx; then
        echo "1. Запустить nginx: systemctl start nginx"
    fi
    
    if [[ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
        echo "2. Получить SSL сертификат: bash setup-https-complete.sh"
    fi
    
    if ! nginx -t >/dev/null 2>&1; then
        echo "3. Исправить конфигурацию nginx"
    fi
    
    if [[ "$HTTPS_MAIN_TEST" != "200" ]]; then
        echo "4. Проверить доступность сервера и DNS"
    fi
fi

echo ""
echo "🔧 Полезные команды для исправления:"
echo "- bash setup-https-complete.sh (полная настройка HTTPS)"
echo "- systemctl restart nginx (перезапуск nginx)"
echo "- certbot renew (обновление сертификата)"
echo "- ufw allow 443/tcp (открытие HTTPS порта)"