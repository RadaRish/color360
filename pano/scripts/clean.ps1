# Очистка временных артефактов
$ErrorActionPreference = "Stop"

Write-Host "==> Очистка node_modules и lock-файла" -ForegroundColor Yellow
Remove-Item -Recurse -Force node_modules -ErrorAction SilentlyContinue
Remove-Item -Force package-lock.json -ErrorAction SilentlyContinue

Write-Host "Готово." -ForegroundColor Green
