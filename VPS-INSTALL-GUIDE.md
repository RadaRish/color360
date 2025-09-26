# 🚀 Установка Color360 на VPS - Краткое руководство

## 🎯 Для домена color360.ru

### 1️⃣ Интерактивная установка (рекомендуется)
```bash
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/install-color360.sh | sudo bash
```
**Что делает:** Показывает меню выбора типа установки

### 2️⃣ Полная автоматическая установка
```bash
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/install-fresh-vps.sh | sudo bash
```
**Включает:**
- ✅ Полную очистку системы от предыдущих версий
- ✅ Основное приложение (панорамный редактор)
- ✅ AI сервис для удаления объектов (LaMa)
- ✅ Nginx с SSL сертификатом
- ✅ Настройку firewall

### 3️⃣ Быстрая минимальная установка
```bash
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/install-minimal.sh | sudo bash
```
**Включает:**
- ✅ Только основное приложение
- ✅ Без AI функций
- ✅ Быстрая установка за 2-3 минуты

## 🔄 Обновление существующих установок

### Простое обновление кода
```bash
cd /var/www/color360
git pull origin main
systemctl restart color360-app
```

### Обновление с проверками
```bash
# Выберите вариант 3 в интерактивном установщике
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/install-color360.sh | sudo bash
```

## ⚙️ Управление после установки

### Проверка статуса
```bash
systemctl status color360-app
systemctl status color360-sd  # если установлен AI
systemctl status nginx
```

### Просмотр логов
```bash
journalctl -u color360-app -f
journalctl -u color360-sd -f   # если установлен AI
```

### Перезапуск сервисов
```bash
systemctl restart color360-app
systemctl restart color360-sd  # если установлен AI
systemctl restart nginx
```

## 🌍 Доступ к приложению

После установки Color360 будет доступен по адресам:
- **HTTPS**: https://color360.ru (основной)
- **HTTP**: http://color360.ru (перенаправляется на HTTPS)
- **Локально**: http://localhost:3000

## 📋 Что автоматически настраивается

### Полная установка (`install-fresh-vps.sh`)
1. **Системные пакеты**: Node.js 20, Python 3, Nginx, Certbot
2. **Приложение**: Клонирование с GitHub, установка зависимостей
3. **Systemd сервисы**: color360-app, color360-sd (AI)
4. **Nginx**: Reverse proxy, SSL, настройки для больших файлов
5. **Firewall**: UFW с правилами для SSH, HTTP, HTTPS
6. **SSL**: Автоматический Let's Encrypt для color360.ru
7. **Пользователи**: Создание пользователя color360

### Минимальная установка (`install-minimal.sh`)
1. **Только основное**: Node.js, Nginx, основное приложение
2. **Без AI**: Нет Python зависимостей и AI сервиса
3. **Быстро**: Установка за 2-3 минуты
4. **SSL**: Автоматический Let's Encrypt

## 🆘 Диагностика проблем

### Если что-то не работает
```bash
# Диагностика системы
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/diagnostic-system.sh | bash

# Проверка портов
netstat -tlnp | grep -E ':3000|:5002|:80|:443'

# Проверка процессов
ps aux | grep -E 'node|python.*lama|nginx'
```

### Полная переустановка
Если нужно начать заново, просто запустите любой из скриптов установки - они автоматически удалят предыдущие версии.

## 💡 Рекомендации

1. **Для продакшена**: Используйте полную установку с AI
2. **Для тестов**: Используйте минимальную установку
3. **Для разработки**: Клонируйте репозиторий вручную
4. **DNS**: Убедитесь что color360.ru указывает на ваш сервер перед запуском SSL
5. **Firewall**: Скрипты настраивают UFW автоматически

---

> **⚡ Быстрый старт**: `curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/install-color360.sh | sudo bash`