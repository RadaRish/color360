# Архитектура многопользовательского ColoR Tour Editor (план)

## Цели
- Онлайн-доступ: каждый пользователь работает со своими проектами
- Безопасное разделение данных и ресурсов (папки/облачное хранилище)
- Совместимость с текущим фронтендом (экспорт A-Frame)
- Масштабируемость: горизонтальное масштабирование API
- Возможность коллаборации (реалтайм) как расширение

## Слои
1. Клиент (SPA) – существующий редактор (ESModules) + авторизация + загрузка панорам.
2. API Gateway / Backend (Node.js + Fastify/Express) – REST/JSON + WebSocket (позже CRDT/OT для коллаборации).
3. Хранилище:
   - PostgreSQL (пользователи, проекты, сцены, хотспоты, версии)
   - Object Storage (S3 совместимый / MinIO / локально: панорамы, иконки, видео)
4. Сервис экспорта – воркер / очередь (BullMQ + Redis) генерирует zip асинхронно.
5. CDN / Edge Cache – раздача статичных экспортов.

## Основные сущности
- User: { id, email, password_hash, quota }
- Project: { id, user_id, title, created_at, updated_at, settings_json }
- Scene: { id, project_id, name, order_index, panorama_key, meta_json }
- Hotspot: { id, scene_id, type, position_json, target_scene_id, payload_json }
- Asset: { id, project_id, type(image|video|icon), key, meta_json }
- ExportJob: { id, project_id, status(pending|processing|done|error), result_key, error_message }

## API (MVP)
GET /api/projects
POST /api/projects
GET /api/projects/:id
PATCH /api/projects/:id
DELETE /api/projects/:id
POST /api/projects/:id/scenes
PATCH /api/scenes/:id
DELETE /api/scenes/:id
POST /api/scenes/:id/hotspots
PATCH /api/hotspots/:id
DELETE /api/hotspots/:id
POST /api/projects/:id/assets (multipart)
POST /api/projects/:id/export -> { jobId }
GET /api/export/:jobId -> status/result

## Экспорт воркер
1. Загружает все сцены, хотспоты, ассеты.
2. Конструирует JSON (TOUR_DATA)
3. Генерирует файлы, минифицирует (опционально), кладёт в object storage.
4. Обновляет ExportJob.status

## Авторизация
- JWT Access + Refresh; bcrypt для паролей.
- Роли (user, admin) – позже.

## Реалтайм (этап 2)
- WebSocket канал per project.
- Документы: проект, сцена, хотспот – CRDT (Y.js) или простые diff события.

## Квоты
- Таблица usage (bytes_used, last_calc)
- Проверка при загрузке ассета.

## Локальная разработка
- docker-compose: postgres, minio, redis.

## Безопасность
- Проверка типов файлов (MIME + магия)
- Ограничение размера (например, 25 MB/image)
- Sanitization текстов

## Логи и мониторинг
- pino + Loki / ELK
- health endpoint /metrics (Prometheus)

## Возможные оптимизации
- Прогрессивная загрузка панорам (multi-res / tiles)
- Генерация низкого качества превью
- WebP/AVIF конверсия в воркере

## Следующие шаги (MVP внедрение)
1. Создать backend папку /server.
2. Настроить package.json скрипты (dev:client + dev:server concurrently).
3. Модели (Prisma или knex) – начать с User/Project/Scene/Hotspot.
4. Auth endpoints.
5. CRUD проектов.
6. Загрузка ассетов -> S3.
7. Экспорт job + воркер.
8. Интеграция фронтенда: загрузка /api/projects/:id/full.

## Расширения
- Undo/Redo (хранить операции)
- Версионирование проекта (draft/published)
- Шеринг (public read token)
- Встраивание iframe с рантаймом.
