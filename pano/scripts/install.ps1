# Авто-установка и запуск для Windows PowerShell
# Требуется: Node.js 18+

$ErrorActionPreference = "Stop"

Write-Host "==> Установка зависимостей (npm ci)..." -ForegroundColor Cyan
if (Test-Path package-lock.json) {
  npm ci
} else {
  npm install
}

Write-Host "==> Линт и форматирование..." -ForegroundColor Cyan
npx eslint "**/*.js" --fix
npx prettier --write "**/*.{js,css,html,json}"

Write-Host "==> Валидация HTML..." -ForegroundColor Cyan
npx html-validate index.html

Write-Host "==> Запуск live-server на http://localhost:5500/index.html" -ForegroundColor Green
npx live-server --port=5500 --host=localhost --open=/index.html
