# Color360 Production Deployment (www.color360.ru)

## Стек
- Node.js backend (server.js) порт 3000
- LaMa FastAPI service (lama/service.py) порт 8080 (или переменная PORT)
- Nginx reverse proxy (HTTPS, exact locations /api/retouch /api/retouch-json)

## Быстрое обновление на VPS
```bash
bash scripts/deploy/update-production.sh
```
Скрипт:
- Останавливает сервисы
- Клонирует свежий репозиторий
- Устанавливает зависимости Node (prod)
- Создаёт venv и ставит Python зависимости
- Переустанавливает systemd юниты
- Запускает сервисы

## Пример nginx server { }
```
server {
    listen 443 ssl http2;
    server_name www.color360.ru;
    root /var/www/color360;

    # SSL директивы ... (сертификаты)

    location = /api/retouch { proxy_pass http://127.0.0.1:3000/api/retouch; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto $scheme; client_max_body_size 250M; }
    location = /api/retouch-json { proxy_pass http://127.0.0.1:3000/api/retouch-json; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto $scheme; client_max_body_size 250M; }

    location / { try_files $uri /index.html; }
}
```

## Проверка после развёртывания
```
curl -k https://www.color360.ru/api/lama-health
curl -k -X POST https://www.color360.ru/api/retouch -F "image=@sample.jpg" -F "mask=@mask.png"
```

## Чистка логов (опционально)
```
truncate -s0 /var/log/nginx/access.log
truncate -s0 /var/log/nginx/error.log
```

## Переменные среды
- LAMA_PORT (default 8080)
- PORT (backend, default 3000)
- JWT_SECRET (поменять в проде)

