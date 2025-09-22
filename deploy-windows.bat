@echo off
echo Деплой Color360 на Windows...

echo Остановка PM2 процессов...
pm2 stop color360-app 2>nul
pm2 delete color360-app 2>nul

echo Установка зависимостей...
call npm install

echo Запуск PM2 сервера...
pm2 start ecosystem.config.json

echo Проверка статуса...
pm2 status

echo Показать логи за последние 30 строк...
pm2 logs --lines 30

echo Деплой завершен!
pause