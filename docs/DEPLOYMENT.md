# Инструкции по развертыванию Color360 на VPS TimeWeb

## Требования к серверу

- Ubuntu 20.04/22.04 LTS
- Минимум 2GB RAM
- Минимум 20GB свободного места
- Root доступ или sudo права

## Быстрое развертывание

### 1. Подготовка файлов на сервере

```bash
# Загрузите проект на сервер (используйте git, scp или другой способ)
git clone https://github.com/your-repo/color360.git
cd color360

# Или загрузите архив
wget https://your-domain.com/color360.zip
unzip color360.zip
cd color360
```

### 2. Настройка окружения

```bash
# Скопируйте файл конфигурации
cp .env.example .env

# Отредактируйте .env файл
nano .env
```

Обязательно измените:
- `JWT_SECRET` - на уникальный секретный ключ
- `ADMIN_PASSWORD` - на надежный пароль администратора
- `CORS_ORIGINS` - на ваш домен

### 3. Запуск автоматического развертывания

```bash
# Сделайте скрипт исполняемым
chmod +x deploy-vps.sh

# Запустите развертывание
sudo ./deploy-vps.sh
```

## Ручная настройка

### 1. Установка Node.js

```bash
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs
```

### 2. Установка зависимостей

```bash
npm install --production
```

### 3. Установка PM2

```bash
sudo npm install -g pm2
```

### 4. Настройка PM2

```bash
pm2 start ecosystem.config.json
pm2 save
pm2 startup
```

### 5. Установка и настройка Nginx

```bash
sudo apt install -y nginx
sudo cp nginx.conf /etc/nginx/sites-available/color360.ru
sudo ln -s /etc/nginx/sites-available/color360.ru /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

### 6. Установка SSL сертификата

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d color360.ru -d www.color360.ru
```

## Управление приложением

### PM2 команды

```bash
# Статус приложений
pm2 status

# Перезапуск
pm2 restart color360-app

# Просмотр логов
pm2 logs color360-app

# Мониторинг
pm2 monit
```

### Nginx команды

```bash
# Проверка конфигурации
sudo nginx -t

# Перезагрузка
sudo systemctl reload nginx

# Статус
sudo systemctl status nginx
```

## Обновление приложения

```bash
# Остановить приложение
pm2 stop color360-app

# Обновить код (через git или загрузку файлов)
git pull

# Установить новые зависимости (если есть)
npm install --production

# Запустить приложение
pm2 start color360-app
```

## Резервное копирование

Автоматические резервные копии создаются ежедневно в 2:00 AM и сохраняются в `/var/backups/color360/`.

Ручное создание резервной копии:
```bash
sudo /usr/local/bin/color360-backup.sh
```

## Мониторинг

### Логи приложения
```bash
pm2 logs color360-app
```

### Логи Nginx
```bash
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### Системные ресурсы
```bash
htop
df -h
free -h
```

## Безопасность

- Регулярно обновляйте систему: `sudo apt update && sudo apt upgrade`
- Следите за логами на предмет подозрительной активности
- Используйте сильные пароли
- Ограничьте SSH доступ только для необходимых IP
- Рассмотрите возможность установки fail2ban

## Поддержка

В случае проблем проверьте:
1. Статус PM2: `pm2 status`
2. Статус Nginx: `sudo systemctl status nginx`
3. Логи приложения: `pm2 logs`
4. Доступность портов: `netstat -tlnp | grep :3000`

## Переменные окружения

Основные переменные в `.env`:

```env
NODE_ENV=production
JWT_SECRET=your-super-secure-secret
PORT=3000
ADMIN_EMAIL=admin@color360.ru
ADMIN_PASSWORD=your-secure-password
CORS_ORIGINS=https://color360.ru,https://www.color360.ru
```