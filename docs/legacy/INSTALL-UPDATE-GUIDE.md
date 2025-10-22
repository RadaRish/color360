# 🚀 Инструкция по установке обновлений Color360

## 📋 Оглавление
- [Быстрая установка](#быстрая-установка)
- [Ручная установка](#ручная-установка)
- [Расширенные опции](#расширенные-опции)
- [Диагностика проблем](#диагностика-проблем)
- [Откат изменений](#откат-изменений)

## 🎯 Быстрая установка

### Автоматическое обновление (рекомендуется)
```bash
# Загрузка и запуск стандартного скрипта обновления
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/update-vps.sh | sudo bash
```

### Альтернативный способ (если есть проблемы с sudo/пользователями)
```bash
# Улучшенный скрипт v2.0, работающий полностью от root
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/update-vps-root.sh | sudo bash
```

### Ручное скачивание и запуск
```bash
# Скачивание стандартного скрипта
wget https://raw.githubusercontent.com/RadaRish/color360/main/update-vps.sh
chmod +x update-vps.sh
sudo ./update-vps.sh

# Или упрощенного скрипта
wget https://raw.githubusercontent.com/RadaRish/color360/main/update-vps-root.sh
chmod +x update-vps-root.sh
sudo ./update-vps-root.sh
```

## 🔧 Ручная установка

### 1. Подготовка системы
```bash
# Обновление системы
sudo apt update && sudo apt upgrade -y

# Установка необходимых пакетов
sudo apt install -y git nodejs npm python3 python3-pip python3-venv nginx curl
```

### 2. Клонирование проекта
```bash
# Создание директории проекта
sudo mkdir -p /var/www/color360

# Клонирование репозитория
sudo git clone https://github.com/RadaRish/color360.git /var/www/color360

# Установка прав доступа
sudo chown -R color360:color360 /var/www/color360
```

### 3. Установка зависимостей
```bash
cd /var/www/color360

# Node.js зависимости
sudo -u color360 npm install --production

# Python зависимости (если нужен AI)
sudo -u color360 python3 -m venv sd_env
sudo -u color360 bash -c "source sd_env/bin/activate && pip install -r sd/requirements.txt"
```

### 4. Настройка сервисов
```bash
# Создание systemd сервисов (автоматически при запуске update-vps.sh)
sudo systemctl daemon-reload
sudo systemctl enable color360-app color360-sd nginx
sudo systemctl start color360-app color360-sd nginx
```

## ⚙️ Расширенные опции

### Кастомизация переменных окружения
```bash
# Изменение директории установки
export PROJECT_DIR="/custom/path/color360"

# Изменение пользователя
export APP_USER="myuser"

# Изменение ветки Git
export BRANCH="development"

# Принудительное обновление (игнорирует конфликты)
export FORCE_UPDATE="true"

# Запуск с кастомными параметрами
sudo -E ./update-vps.sh
```

### Обновление конкретных сервисов
```bash
# Обновление только основного приложения
export SERVICES="color360-app nginx"
sudo -E ./update-vps.sh

# Обновление без AI сервиса
export SERVICES="color360-app nginx"
sudo -E ./update-vps.sh
```

## 🩺 Диагностика проблем

### Проверка статуса сервисов
```bash
# Статус всех сервисов
systemctl status color360-app color360-sd nginx

# Проверка логов
journalctl -u color360-app -f
journalctl -u color360-sd -f
journalctl -u nginx -f
```

### Проверка доступности
```bash
# Проверка основного приложения
curl http://localhost:3000/

# Проверка AI сервиса
curl http://localhost:5002/health

# Проверка через nginx
curl http://your-domain.com/
```

### Решение частых проблем

#### 🚨 Ошибка "Permission denied" или проблемы с sudo
```bash
# Исправление прав доступа
sudo chown -R color360:color360 /var/www/color360
sudo chmod -R 755 /var/www/color360

# Если проблемы с sudo для пользователя color360:
# Используйте упрощенный скрипт от root
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/update-vps-root.sh | sudo bash

# Или настройте sudoers (осторожно!)
echo "color360 ALL=(ALL) NOPASSWD: /usr/local/bin/npm, /usr/bin/npm" | sudo tee -a /etc/sudoers.d/color360
```

#### 🚨 Ошибка "Port already in use"
```bash
# Поиск процессов на порту
sudo lsof -i :3000
sudo lsof -i :5002

# Остановка всех сервисов
sudo systemctl stop color360-app color360-sd nginx

# Перезапуск
sudo systemctl start color360-app color360-sd nginx
```

#### 🚨 Git конфликты
```bash
cd /var/www/color360

# Сброс к последней версии (осторожно!)
sudo -u color360 git stash
sudo -u color360 git reset --hard origin/main
sudo -u color360 git pull origin main
```

#### 🚨 Нехватка места на диске
```bash
# Очистка системы
sudo ./clean-vps-disk.sh

# Или ручная очистка
sudo apt autoremove -y
sudo apt autoclean
sudo docker system prune -f
sudo find /var/log -name "*.log" -mtime +7 -delete
```

## 🔄 Откат изменений

### Быстрый откат к предыдущей версии
```bash
cd /var/www/color360

# Просмотр последних коммитов
sudo -u color360 git log --oneline -10

# Откат к конкретному коммиту
sudo -u color360 git reset --hard <commit-hash>

# Перезапуск сервисов
sudo systemctl restart color360-app color360-sd
```

### Восстановление стабильной версии
```bash
# Переключение на stable ветку (если есть)
cd /var/www/color360
sudo -u color360 git checkout stable
sudo -u color360 git pull origin stable

# Переустановка зависимостей
sudo -u color360 npm ci --production
sudo systemctl restart color360-app color360-sd
```

## 📊 Мониторинг обновлений

### Автоматическое обновление через cron
```bash
# Открыть crontab
sudo crontab -e

# Добавить строку для обновления каждую ночь в 3:00
0 3 * * * /bin/bash -c "curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/update-vps.sh | bash" >> /var/log/color360-update.log 2>&1
```

### Проверка версии
```bash
cd /var/www/color360

# Текущий коммит
git rev-parse --short HEAD

# Информация о коммите
git log -1 --pretty=format:"%h - %an, %ar: %s"

# Сравнение с remote
git fetch
git status
```

### Комплексная диагностика системы
```bash
# Полная диагностика Color360 (новый инструмент)
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/diagnostic-system.sh | bash

# Мониторинг в реальном времени
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/monitor-vps.sh | bash
```

## 🆘 Контакты и поддержка

- **GitHub Issues**: https://github.com/RadaRish/color360/issues
- **Документация**: https://github.com/RadaRish/color360/wiki

### Полезные команды для диагностики
```bash
# Полная информация о системе
./diagnostic-vps.sh

# Мониторинг ресурсов
htop
df -h
free -h
systemctl status

# Логи в реальном времени
tail -f /var/log/syslog
journalctl -f
```

---

> **⚠️ Важно**: Всегда делайте резервную копию критических данных перед обновлением в продакшене!

> **💡 Совет**: Используйте тестовую среду для проверки обновлений перед применением на продакшене.