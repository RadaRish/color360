# 🔄 Краткая справка по обновлению Color360

## 🚀 Команды для быстрого обновления

### Автоматическое полное обновление
```bash
# Стандартный скрипт (с отдельным пользователем)
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/update-vps.sh | sudo bash

# Упрощенный скрипт (от root, если есть проблемы с sudo)
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/update-vps-root.sh | sudo bash
```

### Быстрое обновление (только код)
```bash
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/quick-update.sh | sudo bash
```

### Обновление с кастомными параметрами
```bash
# Другая директория
export PROJECT_DIR="/custom/path"
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/update-vps.sh | sudo -E bash

# Другая ветка Git
export BRANCH="development"
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/update-vps.sh | sudo -E bash

# Принудительное обновление (игнорирует конфликты)
export FORCE_UPDATE="true"
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/update-vps.sh | sudo -E bash
```

## 🔍 Проверка статуса

```bash
# Статус всех сервисов
systemctl status color360-app color360-sd nginx

# Проверка доступности
curl http://localhost:3000/
curl http://localhost:5002/health

# Текущая версия
cd /var/www/color360 && git log -1 --oneline
```

## 🆘 Быстрое решение проблем

```bash
# Перезапуск сервисов
sudo systemctl restart color360-app color360-sd nginx

# Просмотр логов
sudo journalctl -u color360-app -f
sudo journalctl -u color360-sd -f

# Сброс к последней версии GitHub
cd /var/www/color360
sudo -u color360 git reset --hard origin/main
sudo systemctl restart color360-app color360-sd
```

## ⚠️ Важно

- **Резервные копии НЕ создаются автоматически**
- При необходимости создавайте бэкапы вручную перед обновлением
- Используйте тестовую среду для проверки обновлений

## 📖 Полная документация

[INSTALL-UPDATE-GUIDE.md](INSTALL-UPDATE-GUIDE.md) — подробные инструкции и диагностика