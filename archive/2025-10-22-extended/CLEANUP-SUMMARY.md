# Расширенная чистка репозитория — 22 октября 2025

## Архивированные скрипты (emergency/diagnostic/nuclear)

Следующие 12 скриптов перемещены в `archive/2025-10-22-extended/` для сохранения порядка и безопасности:

### Emergency scripts
- `emergency-restore.sh`
- `emergency-retouch-fix.sh`
- `emergency-site-restore.sh`
- `super-emergency-retouch-fix.sh`

### Diagnostic scripts
- `diagnose-https.sh`
- `diagnose-lama-service.sh`
- `diagnose-retouch-freeze.sh`
- `diagnose-retouch-issues.sh`
- `diagnostic-repair.sh`
- `diagnostic-system.sh`
- `diagnostic-vps.sh`

### Nuclear scripts
- `nuclear-cleanup-nodejs.sh`

## Перенесённая документация

### В `docs/` (актуальная)
- `DEPLOYMENT.md`
- `DEPLOYMENT-PRODUCTION.md`
- `PRODUCTION-INSTALL-GUIDE.md`
- `LAMA-SETUP.md`
- `AI-SETUP-GUIDE.md`
- `ARROW_ICON_CHANGES.md`
- `TRIAL-VERSION-GUIDE.md`
- `pano/INSTALL.md` → `docs/INSTALL.md`
- `pano/DEPLOY.md` → `docs/DEPLOY.md`
- `pano/ARCHITECTURE_PLAN.md` → `docs/ARCHITECTURE_PLAN.md`

### В `docs/legacy/` (устаревшие/справочные)
- `INSTALL-RU.md`
- `INSTALL-REG-RU.md`
- `INSTALL-UPDATE-GUIDE.md`
- `LAMA-SETUP-GUIDE.md`
- `FAQ-UPDATE.md`

**Всего перемещено:** 15 документов

## Обратимость

Все изменения обратимы:
- Скрипты можно вернуть из `archive/2025-10-22-extended/` в корень.
- Документация может быть перемещена обратно из `docs/` и `docs/legacy/`.

## README.md

Обновлён с указателями на новую структуру `docs/`.

## Результат

Корень репозитория теперь чище и проще в навигации:
- Emergency/diagnostic скрипты архивированы с возможностью восстановления.
- Документация структурирована по назначению (актуальная vs устаревшая).
- Актуальные установочные скрипты остаются доступными в корне.
