# ❓ FAQ по обновлению Color360

## Общие вопросы

### Q: Как часто нужно обновлять систему?
**A:** Рекомендуется обновляться при появлении новых версий на GitHub. Критические обновления безопасности следует устанавливать немедленно.

### Q: Безопасно ли автоматическое обновление?
**A:** Да, скрипт создает бэкап перед обновлением и позволяет легко откатиться к предыдущей версии.

### Q: Что делать, если обновление прошло с ошибками?
**A:** Используйте команды отката из инструкции или восстановите из бэкапа. Проверьте логи для диагностики проблемы.

## Технические вопросы

### Q: "git: command not found"
**A:** Установите Git:
```bash
# Ubuntu/Debian
sudo apt install git

# CentOS/RHEL  
sudo yum install git

# Windows
# Скачайте с https://git-scm.com/download/win
```

### Q: "Permission denied" при обновлении
**A:** Проверьте права доступа:
```bash
# Linux
sudo chown -R color360:color360 /opt/color360
sudo chmod +x /opt/color360/update-vps.sh

# Windows - запустите PowerShell от администратора
```

### Q: "Port 3000 already in use"
**A:** Остановите существующий процесс:
```bash
# Linux
sudo lsof -i :3000
sudo kill -9 PID

# Windows  
netstat -ano | findstr :3000
taskkill /F /PID PID_NUMBER
```

### Q: Stable Diffusion сервис не запускается
**A:** Проверьте зависимости Python:
```bash
# Переустановка окружения
rm -rf sd_env
python3 -m venv sd_env
source sd_env/bin/activate
pip install --upgrade pip
pip install -r sd/requirements.txt
```

### Q: "ModuleNotFoundError: No module named 'torch'"
**A:** PyTorch не установлен или поврежден:
```bash
# CPU версия
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

# GPU версия (CUDA)
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
```

## Проблемы с производительностью

### Q: Система стала медленнее после обновления
**A:** Проверьте использование ресурсов:
```bash
# Мониторинг процессов
top -p $(pgrep -f "node server.js|python sd_app.py")

# Проверка диска
df -h

# Проверка памяти  
free -h
```

### Q: Stable Diffusion работает очень медленно
**A:** Возможные оптимизации:
1. **Уменьшите качество**: В настройках UI установите меньше шагов (10-15)
2. **Проверьте GPU**: `nvidia-smi` для NVIDIA карт
3. **Освободите память**: Перезапустите SD сервис
4. **CPU режим**: Для слабых GPU может быть быстрее CPU

### Q: "CUDA out of memory" 
**A:** GPU памяти недостаточно:
```python
# В sd_app.py измените:
CONFIG['torch_dtype'] = torch.float32  # Вместо float16

# Или уменьшите размер изображений в preprocess_image()
target_size = (384, 384)  # Вместо (512, 512)
```

## Проблемы с сетью

### Q: Сайт недоступен извне после обновления
**A:** Проверьте nginx и firewall:
```bash
# Статус nginx
sudo systemctl status nginx

# Проверка конфигурации
sudo nginx -t

# Firewall
sudo ufw status
sudo firewall-cmd --list-all
```

### Q: SSL сертификат не работает
**A:** Обновите Let's Encrypt сертификат:
```bash
sudo certbot renew
sudo systemctl reload nginx
```

### Q: API endpoints возвращают 502/504 ошибки
**A:** Проверьте backend сервисы:
```bash
# Статус сервисов
sudo systemctl status color360-app color360-sd

# Перезапуск
sudo systemctl restart color360-app color360-sd
```

## Проблемы с обновлением

### Q: Git конфликты при обновлении
**A:** Сохраните изменения и сбросьте до последней версии:
```bash
git stash push -m "Local changes before update"
git fetch origin
git reset --hard origin/main
# При необходимости: git stash pop
```

### Q: npm install завершается с ошибками
**A:** Очистите кэш и переустановите:
```bash
rm -rf node_modules package-lock.json
npm cache clean --force
npm install --production
```

### Q: Python пакеты не устанавливаются
**A:** Обновите pip и переустановите:
```bash
source sd_env/bin/activate
pip install --upgrade pip setuptools wheel
pip install -r sd/requirements.txt --force-reinstall
```

## Docker проблемы

### Q: Docker контейнеры не запускаются после обновления
**A:** Пересоберите контейнеры:
```bash
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### Q: "No space left on device" в Docker
**A:** Очистите Docker:
```bash
docker system prune -a
docker volume prune
```

### Q: GPU не работает в Docker
**A:** Проверьте nvidia-docker:
```bash
# Установка nvidia-container-toolkit
curl -s -L https://nvidia.github.io/nvidia-container-runtime/gpgkey | sudo apt-key add -
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-container-runtime/$distribution/nvidia-container-runtime.list | sudo tee /etc/apt/sources.list.d/nvidia-container-runtime.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker
```

## Мониторинг и диагностика

### Q: Как проверить, что все работает правильно?
**A:** Используйте скрипт диагностики:
```bash
chmod +x check-system.sh
./check-system.sh
```

### Q: Где посмотреть логи ошибок?
**A:** Основные источники логов:
```bash
# Systemd сервисы
sudo journalctl -u color360-app -f
sudo journalctl -u color360-sd -f

# Nginx
sudo tail -f /var/log/nginx/error.log

# Системные логи
sudo tail -f /var/log/syslog
```

### Q: Как настроить мониторинг?
**A:** Создайте простой скрипт мониторинга:
```bash
#!/bin/bash
# monitor.sh
while true; do
    if ! curl -f -s http://localhost:3000/ > /dev/null; then
        echo "$(date): App down!" | mail -s "Color360 Alert" admin@example.com
    fi
    sleep 300  # Проверка каждые 5 минут
done
```

## Резервное копирование

### Q: Как настроить автоматические бэкапы?
**A:** Создайте cron задачу:
```bash
# Откройте crontab
crontab -e

# Добавьте (ежедневный бэкап в 2:00)
0 2 * * * /usr/bin/rsync -av /opt/color360/ /backup/color360-$(date +\%Y\%m\%d)/
```

### Q: Что включать в бэкап?
**A:** Обязательно:
- Весь код проекта `/opt/color360/`
- Базы данных (если используются)
- SSL сертификаты `/etc/letsencrypt/`
- Nginx конфигурация `/etc/nginx/sites-available/`
- Systemd сервисы `/etc/systemd/system/color360-*`

## Контакты поддержки

### 🆘 Если ничего не помогает:

1. **Создайте Issue на GitHub**: 
   - Перейдите на https://github.com/RadaRish/color360/issues
   - Опишите проблему подробно
   - Приложите логи и скриншоты

2. **Соберите диагностическую информацию**:
   ```bash
   # Запустите и приложите результат
   ./check-system.sh > diagnostic-report.txt
   
   # Также соберите:
   systemctl status color360-app color360-sd > service-status.txt
   journalctl -u color360-app --no-pager -n 100 > app-logs.txt
   journalctl -u color360-sd --no-pager -n 100 > sd-logs.txt
   ```

3. **Укажите в запросе**:
   - Версию ОС
   - Версию Node.js и Python
   - Конфигурацию сервера (CPU, RAM, GPU)
   - Шаги для воспроизведения проблемы

---

*Color360 FAQ - Ответы на все вопросы по обновлению и эксплуатации* 🔧