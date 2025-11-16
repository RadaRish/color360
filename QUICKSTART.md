# 🚀 Быстрый старт - PanoBro на VPS TimeWeb

## Подключение к серверу
```bash
ssh root@72.56.82.203
```

## Установка (одна команда)
```bash
wget https://raw.githubusercontent.com/RadaRish/color360/main/deploy-timeweb.sh && chmod +x deploy-timeweb.sh && sudo bash deploy-timeweb.sh
```

## После установки

✅ Сайт доступен: http://72.56.82.203/  
✅ Редактор панорам: http://72.56.82.203/pano/

## Основные команды

### Обновление проекта
```bash
sudo update-panobro
```

### Просмотр логов
```bash
sudo tail -f /var/log/nginx/panobro-access.log
```

### Перезапуск Nginx
```bash
sudo systemctl restart nginx
```

## Настройка SSL (если есть домен)

```bash
wget https://raw.githubusercontent.com/RadaRish/color360/main/setup-ssl.sh && chmod +x setup-ssl.sh && sudo bash setup-ssl.sh
```

## Файлы проекта

📁 Директория: `/var/www/panobro`  
📄 Конфиг Nginx: `/etc/nginx/sites-available/panobro`  
📋 Логи: `/var/log/nginx/panobro-*.log`

---

📖 Полная инструкция: [DEPLOY-TIMEWEB-GUIDE.md](DEPLOY-TIMEWEB-GUIDE.md)
