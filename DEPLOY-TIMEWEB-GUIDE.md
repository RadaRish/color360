# 🚀 Инструкция по развертыванию PanoBro на VPS TimeWeb

## Информация о сервере
- **IP адрес**: 72.56.82.203
- **Провайдер**: TimeWeb
- **ОС**: Ubuntu 20.04/22.04 LTS (рекомендуется)

---

## 📋 Быстрая установка (3 шага)

### Шаг 1: Подключение к серверу
```bash
ssh root@72.56.82.203
```

### Шаг 2: Скачивание и запуск скрипта установки
```bash
# Скачиваем скрипт напрямую с GitHub
wget https://raw.githubusercontent.com/RadaRish/color360/main/deploy-timeweb.sh

# Делаем скрипт исполняемым
chmod +x deploy-timeweb.sh

# Запускаем установку
sudo bash deploy-timeweb.sh
```

### Шаг 3: Проверка работы
После завершения установки откройте в браузере:
- Главная страница: http://72.56.82.203/
- Редактор панорам: http://72.56.82.203/pano/

---

## 🔧 Что устанавливает скрипт

1. **Системные пакеты**:
   - Git, curl, wget, nano, htop
   - Build tools для компиляции
   - UFW (файрвол)
   - Fail2Ban (защита от атак)

2. **Node.js & NPM**:
   - Последняя LTS версия Node.js
   - NPM для управления пакетами
   - PM2 (менеджер процессов)

3. **Nginx**:
   - Веб-сервер для раздачи статики
   - Настроенная конфигурация для проекта
   - Оптимизация кеширования

4. **Безопасность**:
   - Файрвол UFW (порты 22, 80, 443)
   - Fail2Ban для защиты SSH
   - Ограничение прав доступа

5. **Проект**:
   - Клонирование репозитория
   - Настройка прав доступа
   - Создание служебных скриптов

---

## 📁 Структура на сервере

```
/var/www/panobro/          # Корневая директория проекта
├── index.html             # Главная страница
├── pano/                  # Редактор панорам
│   ├── index.html
│   ├── core/
│   ├── ui/
│   └── styles/
├── assets/                # Статические файлы
└── SERVER_INFO.txt        # Информация о сервере
```

---

## 🔄 Обновление проекта

### Автоматическое обновление (рекомендуется)
```bash
sudo update-panobro
```

### Ручное обновление
```bash
cd /var/www/panobro
git pull origin main
sudo chown -R www-data:www-data /var/www/panobro
sudo systemctl reload nginx
```

---

## 🛡️ SSL сертификат (HTTPS)

После успешной установки настройте SSL:

```bash
# Установка Certbot
sudo apt-get install -y certbot python3-certbot-nginx

# Получение сертификата (замените на ваш домен)
sudo certbot --nginx -d panobro.ru -d www.panobro.ru

# Автоматическое обновление сертификата
sudo certbot renew --dry-run
```

**Если используете только IP адрес** - SSL настроить нельзя. Рекомендуется привязать домен.

---

## 📊 Полезные команды

### Управление Nginx
```bash
# Перезапуск
sudo systemctl restart nginx

# Проверка конфигурации
sudo nginx -t

# Просмотр логов
sudo tail -f /var/log/nginx/panobro-access.log
sudo tail -f /var/log/nginx/panobro-error.log
```

### Мониторинг системы
```bash
# Использование ресурсов
htop

# Дисковое пространство
df -h

# Статус файрвола
sudo ufw status

# Активные соединения
sudo netstat -tuln
```

### Git операции
```bash
cd /var/www/panobro

# Проверка статуса
git status

# Просмотр последних коммитов
git log --oneline -10

# Откат на предыдущую версию (если нужно)
git reset --hard HEAD~1
```

---

## 🚨 Решение проблем

### Проблема: Сайт не открывается

1. **Проверьте статус Nginx**:
   ```bash
   sudo systemctl status nginx
   ```

2. **Проверьте файрвол**:
   ```bash
   sudo ufw status
   # Должны быть открыты порты 80 и 443
   ```

3. **Проверьте логи**:
   ```bash
   sudo tail -50 /var/log/nginx/error.log
   ```

### Проблема: Ошибка 403 Forbidden

```bash
# Проверьте права доступа
ls -la /var/www/panobro/

# Исправьте права
sudo chown -R www-data:www-data /var/www/panobro
sudo chmod -R 755 /var/www/panobro
```

### Проблема: Ошибка 502 Bad Gateway

```bash
# Проверьте конфигурацию Nginx
sudo nginx -t

# Перезапустите Nginx
sudo systemctl restart nginx
```

### Проблема: Не загружаются большие панорамы

Отредактируйте конфигурацию Nginx:
```bash
sudo nano /etc/nginx/sites-available/panobro

# Найдите и увеличьте значение
client_max_body_size 1000M;  # Было 500M

# Сохраните и перезапустите
sudo systemctl restart nginx
```

---

## 🔐 Рекомендации по безопасности

### 1. Смена SSH порта
```bash
sudo nano /etc/ssh/sshd_config
# Измените Port 22 на Port 2222
sudo systemctl restart sshd

# Откройте новый порт в файрволе
sudo ufw allow 2222/tcp
```

### 2. Отключение root логина
```bash
sudo nano /etc/ssh/sshd_config
# PermitRootLogin no
sudo systemctl restart sshd
```

### 3. Настройка автоматических обновлений
```bash
sudo apt-get install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

### 4. Регулярные бэкапы
```bash
# Создайте cronjob для бэкапа
crontab -e

# Добавьте строку (бэкап каждый день в 3:00)
0 3 * * * tar -czf /backup/panobro-$(date +\%Y\%m\%d).tar.gz /var/www/panobro
```

---

## 📈 Оптимизация производительности

### Nginx кеширование
Уже настроено в скрипте для статических файлов (изображения, JS, CSS).

### Сжатие Gzip
Добавьте в `/etc/nginx/nginx.conf`:
```nginx
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_types text/plain text/css text/xml text/javascript 
           application/json application/javascript application/xml+rss 
           application/rss+xml font/truetype font/opentype 
           application/vnd.ms-fontobject image/svg+xml;
```

### Мониторинг
```bash
# Установка мониторинга
sudo apt-get install -y netdata

# Доступ к панели мониторинга
# http://72.56.82.203:19999
```

---

## 🌐 Настройка домена

### 1. Добавьте A-запись в DNS
```
Тип: A
Имя: @
Значение: 72.56.82.203
TTL: 3600
```

### 2. Обновите конфигурацию Nginx
```bash
sudo nano /etc/nginx/sites-available/panobro

# Замените
server_name 72.56.82.203;

# На
server_name panobro.ru www.panobro.ru;

# Перезапустите Nginx
sudo systemctl restart nginx
```

### 3. Установите SSL сертификат
```bash
sudo certbot --nginx -d panobro.ru -d www.panobro.ru
```

---

## 📞 Поддержка

- **GitHub**: https://github.com/RadaRish/color360
- **Issues**: https://github.com/RadaRish/color360/issues

---

## ✅ Чеклист после установки

- [ ] Сайт открывается по IP
- [ ] Редактор панорам работает
- [ ] Файрвол настроен
- [ ] SSL сертификат установлен (если есть домен)
- [ ] Настроены автоматические обновления безопасности
- [ ] Созданы бэкапы
- [ ] Проверены логи на ошибки
- [ ] Смена SSH порта (опционально)
- [ ] Настроен мониторинг (опционально)

---

**Дата создания инструкции**: 16 ноября 2025  
**Версия**: 1.0
