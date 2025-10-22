#!/bin/bash
# Простой тест синтаксиса для update-vps.sh

echo "Проверка синтаксиса update-vps.sh..."

# Проверяем базовый синтаксис
if bash -n update-vps.sh 2>/dev/null; then
    echo "✅ Синтаксис корректен"
    exit 0
else 
    echo "❌ Найдены синтаксические ошибки:"
    bash -n update-vps.sh
    exit 1
fi