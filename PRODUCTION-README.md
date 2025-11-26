# Color360 / PanoBro - Production Deployment Guide

## 📋 Оглавление
- [Структура проекта](#структура-проекта)
- [Требования](#требования)
- [Быстрый старт](#быстрый-старт)
- [Деплой на VPS](#деплой-на-vps)
- [Настройка SSL](#настройка-ssl)
- [Обновление](#обновление)
- [Безопасность](#безопасность)

## 📁 Структура проекта

```
color360/
├── assets/              # Статические ресурсы сайта (CSS, JS, изображения, видео)
├── pano/                # Редактор панорамных туров (PanoBro)
│   ├── core/            # Основная логика редактора
│   ├── ui/              # UI компоненты редактора
│   ├── config/          # Конфигурация редактора
│   ├── scripts/         # Вспомогательные скрипты
│   └── index.html       # Точка входа редактора
├── lama/                # AI-сервис для ретуши (LaMa)
│   ├── service.py       # Python сервис для обработки изображений
│   └── requirements.txt # Python зависимости
├── sd/                  # Stable Diffusion сервис (опционально)
├── docs/                # Документация проекта
├── scripts/             # Вспомогательные скрипты деплоя
├── server.js            # Node.js сервер (Express)
├── package.json         # Node.js зависимости
├── nginx.conf           # Конфигурация Nginx
├── Dockerfile           # Docker образ для разработки
├── Dockerfile.production # Docker образ для продакшена
├── docker-compose.yml   # Docker Compose для разработки
├── docker-compose.production.yml # Docker Compose для продакшена
├── ecosystem.config.json # PM2 конфигурация
├── .env.production      # Переменные окружения для продакшена
├── deploy-timeweb.sh    # Скрипт автоматической установки на VPS
├── deploy-production.sh # Скрипт деплоя для продакшена (Linux)
├── deploy-production.ps1 # Скрипт деплоя для продакшена (Windows)
├── setup-ssl.sh         # Скрипт настройки SSL/HTTPS
├── update-vps.sh        # Скрипт обновления на VPS
├── README.md            # Основная документация
├── QUICKSTART.md        # Быстрый старт
└── DEPLOY-TIMEWEB-GUIDE.md # Полное руководство по деплою
```

## 🔧 Требования

### Минимальные требования сервера:
- **OS**: Ubuntu 20.04/22.04 или Debian 10/11
- **RAM**: 2GB (рекомендуется 4GB для AI-сервисов)
- **CPU**: 2 cores (рекомендуется 4 cores)
- **Диск**: 20GB свободного места
- **Домен**: с A-записью, указывающей на IP сервера

### Программное обеспечение:
- Node.js 18+ (LTS)
- Nginx 1.18+
- Python 3.8+ (для AI-сервисов)
- PM2 (для управления процессами)
- Git
- Certbot (для SSL)

## 🚀 Быстрый старт

### 1. Автоматическая установка на новый VPS (рекомендуется)

```bash
# Скачайте и запустите скрипт автоматической установки
wget https://raw.githubusercontent.com/RadaRish/color360/main/deploy-timeweb.sh
chmod +x deploy-timeweb.sh
sudo ./deploy-timeweb.sh
```

Скрипт автоматически:
- Установит все необходимое ПО (Node.js, Nginx, PM2, Python)
- Клонирует репозиторий
- Настроит Nginx
- Установит зависимости
- Запустит приложение через PM2
- Настроит автозапуск
- Создаст swap (если нужно)
- Настроит firewall (UFW) и Fail2Ban

**Доступ после установки:**
- Сайт: `http://ваш-домен-или-ip`
- Редактор: `http://ваш-домен-или-ip/pano`

### 2. Настройка SSL/HTTPS

После успешной установки запустите скрипт настройки SSL:

```bash
cd /var/www/color360
sudo ./setup-ssl.sh
```

Скрипт:
- Установит Certbot
- Получит SSL сертификат от Let's Encrypt
- Настроит Nginx для HTTPS
- Настроит автоматическое обновление сертификата

**Доступ после настройки SSL:**
- Сайт: `https://ваш-домен`
- Редактор: `https://ваш-домен/pano`

## 📦 Деплой на VPS

### Метод 1: Автоматический деплой (рекомендуется)

См. раздел [Быстрый старт](#быстрый-старт)

### Метод 2: Ручная установка

#### Шаг 1: Подготовка сервера

```bash
# Обновление системы
sudo apt update && sudo apt upgrade -y

# Установка необходимых пакетов
sudo apt install -y git curl build-essential nginx ufw fail2ban

# Установка Node.js 18 LTS
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Установка PM2
sudo npm install -g pm2

# Установка Python и pip (для AI-сервисов)
sudo apt install -y python3 python3-pip python3-venv
```

#### Шаг 2: Клонирование репозитория

```bash
# Создание директории для проекта
sudo mkdir -p /var/www
cd /var/www

# Клонирование репозитория
sudo git clone https://github.com/RadaRish/color360.git
cd color360

# Установка Node.js зависимостей
npm install --production
```

#### Шаг 3: Настройка переменных окружения

```bash
# Копирование примера конфигурации
cp .env.production .env

# Редактирование переменных (замените секреты!)
nano .env
```

Замените:
- `JWT_SECRET` - на случайную строку (минимум 32 символа)
- `SESSION_SECRET` - на случайную строку (минимум 32 символа)

#### Шаг 4: Настройка Nginx

```bash
# Копирование конфигурации Nginx
sudo cp nginx.conf /etc/nginx/sites-available/color360

# Создание символической ссылки
sudo ln -s /etc/nginx/sites-available/color360 /etc/nginx/sites-enabled/

# Удаление дефолтной конфигурации
sudo rm /etc/nginx/sites-enabled/default

# Проверка конфигурации
sudo nginx -t

# Перезапуск Nginx
sudo systemctl restart nginx
```

#### Шаг 5: Запуск приложения через PM2

```bash
# Запуск приложения
pm2 start ecosystem.config.json --env production

# Сохранение конфигурации PM2
pm2 save

# Настройка автозапуска PM2
pm2 startup
# Выполните команду, которую выдаст PM2
```

#### Шаг 6: Настройка Firewall

```bash
# Настройка UFW
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
```

#### Шаг 7: Настройка SSL (опционально, но рекомендуется)

```bash
cd /var/www/color360
sudo ./setup-ssl.sh
```

## 🔒 Настройка SSL

### Автоматическая настройка

```bash
cd /var/www/color360
sudo ./setup-ssl.sh
```

### Ручная настройка

```bash
# Установка Certbot
sudo apt install -y certbot python3-certbot-nginx

# Получение сертификата (замените your-domain.com на ваш домен)
sudo certbot --nginx -d your-domain.com -d www.your-domain.com

# Проверка автоматического обновления
sudo certbot renew --dry-run
```

## 🔄 Обновление

### Автоматическое обновление

```bash
cd /var/www/color360
sudo ./update-vps.sh
```

Скрипт:
- Создает бэкап текущей версии
- Получает последние изменения из Git
- Обновляет зависимости
- Перезапускает приложение через PM2
- Перезагружает Nginx

### Ручное обновление

```bash
cd /var/www/color360

# Получение последних изменений
git pull origin main

# Обновление зависимостей
npm install --production

# Перезапуск приложения
pm2 restart color360-app

# Перезагрузка Nginx
sudo nginx -s reload
```

## 🔐 Безопасность

### 1. Обязательные меры безопасности

- **Замените секреты** в `.env` файле на уникальные случайные строки
- **Настройте SSL/HTTPS** для защиты данных в пути
- **Настройте Fail2Ban** для защиты от brute-force атак
- **Обновляйте систему** регулярно: `sudo apt update && sudo apt upgrade`
- **Ограничьте SSH доступ** только с определенных IP (если возможно)
- **Используйте SSH ключи** вместо паролей для входа на сервер

### 2. Настройка Fail2Ban

```bash
# Установка Fail2Ban
sudo apt install -y fail2ban

# Копирование конфигурации
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# Редактирование конфигурации
sudo nano /etc/fail2ban/jail.local
```

Добавьте/раскомментируйте секции:
```ini
[sshd]
enabled = true
port = 22
logpath = %(sshd_log)s
maxretry = 3
bantime = 3600

[nginx-http-auth]
enabled = true
```

```bash
# Перезапуск Fail2Ban
sudo systemctl restart fail2ban
sudo systemctl enable fail2ban
```

### 3. Настройка автоматических обновлений безопасности

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

## 📊 Мониторинг и логи

### Просмотр логов PM2

```bash
# Все логи
pm2 logs

# Логи конкретного приложения
pm2 logs color360-app

# Только ошибки
pm2 logs --err
```

### Просмотр логов Nginx

```bash
# Access log
sudo tail -f /var/log/nginx/access.log

# Error log
sudo tail -f /var/log/nginx/error.log
```

### Мониторинг процессов PM2

```bash
# Статус процессов
pm2 status

# Детальная информация
pm2 show color360-app

# Мониторинг в реальном времени
pm2 monit
```

## 🐛 Устранение неполадок

### Приложение не запускается

```bash
# Проверка статуса PM2
pm2 status

# Просмотр логов
pm2 logs color360-app --lines 50

# Перезапуск приложения
pm2 restart color360-app
```

### Nginx показывает 502 Bad Gateway

```bash
# Проверка, что приложение запущено
pm2 status

# Проверка конфигурации Nginx
sudo nginx -t

# Просмотр логов Nginx
sudo tail -f /var/log/nginx/error.log

# Перезапуск Nginx
sudo systemctl restart nginx
```

### SSL сертификат не обновляется

```bash
# Проверка статуса сертификата
sudo certbot certificates

# Принудительное обновление
sudo certbot renew --force-renewal

# Тестовый запуск обновления
sudo certbot renew --dry-run
```

## 📚 Дополнительная документация

- **QUICKSTART.md** - Быстрое руководство по одной команде
- **DEPLOY-TIMEWEB-GUIDE.md** - Полное руководство по деплою на TimeWeb
- **docs/AI-SETUP-GUIDE.md** - Настройка AI-сервисов (LaMa, Stable Diffusion)
- **docs/LAMA-SETUP.md** - Настройка LaMa для ретуши
- **docs/PRODUCTION-INSTALL-GUIDE.md** - Детальное руководство по установке
- **docs/TRIAL-VERSION-GUIDE.md** - Настройка триальной версии редактора

## 🤝 Поддержка

Если у вас возникли вопросы или проблемы:
1. Проверьте раздел [Устранение неполадок](#устранение-неполадок)
2. Просмотрите логи: `pm2 logs` и `/var/log/nginx/error.log`
3. Создайте Issue в GitHub репозитории

## 📝 Лицензия

Проект разработан для компании Color360.
