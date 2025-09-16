# 🚀 Обновление Color360 на TimeWeb VPS

## Краткое руководство по обновлению

### 📋 Ситуация
- **Текущая установка**: `/var/www/color` (старая версия)
- **Новая установка**: `/var/www/color360` (обновленная версия)
- **VPS**: TimeWeb хостинг

### 🎯 Способы обновления

## Способ 1: Автоматическая миграция (рекомендуется)

```bash
# Подключиться к серверу
ssh root@your-timeweb-server

# Скачать скрипт миграции
wget https://raw.githubusercontent.com/RadaRish/color360/main/migrate-from-old-version.sh
chmod +x migrate-from-old-version.sh

# Запустить миграцию
sudo ./migrate-from-old-version.sh
```

**Что произойдет:**
- ✅ Автоматическое обнаружение старой установки в `/var/www/color`
- ✅ Создание полной резервной копии
- ✅ Миграция пользовательских данных (uploads, настройки)
- ✅ Обновление Nginx конфигурации
- ✅ Настройка новых сервисов (LaMa AI, согласие на обработку данных)
- ✅ Запуск обновленной системы

## Способ 2: Использование основного скрипта развертывания

```bash
# Скачать обновленный скрипт
wget https://raw.githubusercontent.com/RadaRish/color360/main/deploy-production.sh
chmod +x deploy-production.sh

# Запустить с автоматическим обнаружением миграции
sudo ./deploy-production.sh --migrate -d color360.ru -e admin@color360.ru
```

## Способ 3: Ручная миграция

### Шаг 1: Подготовка
```bash
# Создать бэкап
sudo cp -r /var/www/color /var/backups/color-backup-$(date +%Y%m%d)

# Остановить сервисы
sudo systemctl stop nginx
sudo pkill -f "node.*color"
```

### Шаг 2: Обновление
```bash
# Клонировать новую версию
sudo git clone https://github.com/RadaRish/color360.git /var/www/color360
cd /var/www/color360

# Установить зависимости
sudo npm install
cd pano && sudo npm install && cd ..

# Настроить Python для LaMa
cd lama
sudo python3 -m venv venv
sudo source venv/bin/activate
sudo pip install -r requirements.txt
sudo deactivate
cd ..
```

### Шаг 3: Миграция данных
```bash
# Копировать пользовательские данные
sudo cp -r /var/www/color/uploads /var/www/color360/
sudo cp -r /var/www/color/user_data /var/www/color360/ 2>/dev/null || true
sudo cp /var/www/color/.env /var/www/color360/.env.old 2>/dev/null || true

# Создать новый .env на основе примера
sudo cp .env.example .env
# Отредактировать .env с нужными настройками

# Установить права
sudo chown -R www-data:www-data /var/www/color360
sudo chmod -R 755 /var/www/color360
```

### Шаг 4: Настройка сервисов
```bash
# Обновить Nginx конфигурацию
sudo wget -O /etc/nginx/sites-available/color360 \
  https://raw.githubusercontent.com/RadaRish/color360/main/nginx.conf

sudo ln -sf /etc/nginx/sites-available/color360 /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Настроить PM2
sudo npm install -g pm2
cd /var/www/color360
sudo -u www-data pm2 start ecosystem.config.js
sudo -u www-data pm2 save
sudo pm2 startup

# Запустить сервисы
sudo systemctl start nginx
sudo systemctl enable nginx
```

## 🔍 Проверка после обновления

### Основные URL для тестирования:
- **Главная**: https://color360.ru/
- **Редактор**: https://color360.ru/pano/
- **API**: https://color360.ru/api/health
- **Админка**: https://color360.ru/admin-dashboard.html

### Команды проверки:
```bash
# Статус сервисов
sudo systemctl status nginx
sudo pm2 status

# Проверка портов
sudo netstat -tlnp | grep -E ":80|:443|:3000|:5000"

# Проверка логов
sudo tail -f /var/log/nginx/access.log
sudo pm2 logs

# Тест API
curl -I https://color360.ru/api/health
```

## 🆕 Новые функции в обновлении

### 1. Согласие на обработку персональных данных
- ✅ Обязательный чекбокс в форме регистрации
- ✅ Политика конфиденциальности по ФЗ-152
- ✅ Валидация на клиенте и сервере

### 2. LaMa AI система удаления объектов
- ✅ Интегрированная система ИИ удаления объектов
- ✅ API endpoint `/api/retouch`
- ✅ Fallback на OpenCV при недоступности ИИ

### 3. Улучшенная безопасность
- ✅ Обновленные заголовки безопасности
- ✅ Улучшенная валидация форм
- ✅ Защита от CSRF атак

### 4. Мониторинг и логирование
- ✅ Улучшенное логирование всех компонентов
- ✅ Health check endpoints
- ✅ PM2 кластерный режим

## 🔧 Файлы конфигурации

### Обновить .env файл
```bash
# Скопировать настройки из старого .env
cp /var/www/color/.env.example /var/www/color360/.env

# Добавить новые переменные:
echo "LAMA_PORT=5000" >> /var/www/color360/.env
echo "LAMA_HOST=127.0.0.1" >> /var/www/color360/.env
echo "DOMAIN=color360.ru" >> /var/www/color360/.env
```

### Важные переменные в .env:
- `OLD_INSTALL_PATH=/var/www/color` - путь к старой установке
- `NEW_INSTALL_PATH=/var/www/color360` - путь к новой установке
- `LAMA_PORT=5000` - порт для LaMa сервиса
- `DOMAIN=color360.ru` - ваш домен

## 🆘 Откат к предыдущей версии

В случае проблем:

```bash
# Остановить новые сервисы
sudo systemctl stop nginx
sudo pm2 kill

# Восстановить старую версию
sudo rm -rf /var/www/color360
sudo mv /var/backups/color-backup-YYYYMMDD /var/www/color

# Восстановить старую конфигурацию Nginx
sudo cp /var/backups/nginx.conf.old /etc/nginx/sites-available/color
sudo ln -sf /etc/nginx/sites-available/color /etc/nginx/sites-enabled/

# Запустить старые сервисы
sudo systemctl start nginx
cd /var/www/color && sudo -u www-data pm2 start server.js
```

## 📞 Поддержка

При возникновении проблем:
- 📧 Email: admin@color360.ru
- 📋 Issues: https://github.com/RadaRish/color360/issues
- 📖 Документация: см. файлы `DEPLOYMENT-PRODUCTION.md` и `LAMA-SETUP.md`

---

**Рекомендация**: Используйте автоматическую миграцию (Способ 1) для безопасного и быстрого обновления.