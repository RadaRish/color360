# Интеграция AI LaMa (Inpainting) через Docker Compose

## Сервисы
- frontend (React) — /app
- backend (Node/Express) — /api
- lama (FastAPI) — /ai
- nginx — reverse proxy

## Запуск
1. Убедитесь, что Docker и Docker Compose установлены.
2. Соберите и запустите:

```powershell
# из корня репозитория
docker compose build
docker compose up -d
```

3. Откройте в браузере:
- UI: http://<SERVER>/app/
- API: http://<SERVER>/api/health
- AI: http://<SERVER>/ai/health

## Поток
- UI загружает изображение и рисует маску на canvas, отправляет оба файла на `/api/retouch`.
- Backend проксирует multipart на `/ai/inpaint`.
- LaMa возвращает результат (в заглушке — исходное изображение base64), backend отдаёт обратно UI.

## Замена заглушки LaMa
Сервис `lama` сейчас — минимальная заглушка. Для реальной LaMa/IOPaint:
- Установите зависимости модели и замените `app.py` на вызов реального инференса.
- Или используйте официальный `iopaint`:
  - В Dockerfile поставить `pip install iopaint` и запускать `iopaint start --model=lama --port 5000` (нужен entrypoint/command).

## Переменные окружения
- backend:
  - `PORT` (по умолчанию 3001)
  - `LAMA_URL` (по умолчанию http://lama:5000)
- lama:
  - `PORT` (по умолчанию 5000)

## Nginx маршруты
- `/app/` -> frontend:3000
- `/api/` -> backend:3001
- `/ai/` -> lama:5000
- `/pano/` и корень `/` сохраняют текущую маршрутизацию Color360
