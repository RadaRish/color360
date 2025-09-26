# 🚀 ГОТОВЫЕ РАБОЧИЕ СКРИПТЫ Color360

## ⚡ Быстрый старт

### Вариант 1: Интерактивный выбор (рекомендуется)
```bash
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/install-color360.sh | sudo bash
```

### Вариант 2: Полная установка с AI
```bash
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/install-working-vps.sh | sudo bash
```

### Вариант 3: Быстрая установка без AI
```bash
curl -fsSL https://raw.githubusercontent.com/RadaRish/color360/main/install-simple-working.sh | sudo bash
```

## ✅ Что исправлено в рабочих скриптах

### 🔧 Проблемы Node.js решены:
- ❌ **Была ошибка**: Конфликт libnode-dev с nodejs
- ✅ **Исправлено**: Удаление конфликтующих пакетов + установка через NVM
- ✅ **Результат**: Стабильная работа Node.js 20

### 📦 Улучшенная установка:
- ✅ **Полная очистка** перед установкой
- ✅ **NVM для Node.js** - избегает конфликтов пакетов
- ✅ **Проверенные зависимости** из рабочих скриптов
- ✅ **SSL автоматически** для color360.ru
- ✅ **Без резервных копий** (как просили)

### 🎯 Основано на проверенных скриптах:
- `deploy-clean-install.sh` - база для полной установки
- `install-color360-lama.sh` - проверенная LaMa интеграция
- Все конфликты Node.js устранены

## 🌍 После установки

Color360 будет доступен:
- **HTTPS**: https://color360.ru
- **Локально**: http://localhost:3000

## 🔧 Управление

```bash
# Статус
systemctl status color360-app
systemctl status color360-lama  # если установлен AI

# Перезапуск
systemctl restart color360-app
systemctl restart color360-lama  # если установлен AI

# Логи
journalctl -u color360-app -f
journalctl -u color360-lama -f  # если установлен AI
```

## 📋 Различия скриптов

| Скрипт | AI | Время | Node.js | Размер |
|--------|----|----|---------|--------|
| `install-working-vps.sh` | ✅ LaMa | ~5 мин | NVM 20 | Полный |
| `install-simple-working.sh` | ❌ | ~2 мин | NVM 20 | Минимум |

## 🆘 Если что-то не работает

1. **Проверьте DNS**: color360.ru должен указывать на ваш сервер
2. **Логи**: `journalctl -u color360-app -f`
3. **Переустановка**: Скрипты сами очищают систему, просто запустите заново

---

> **⚡ Рекомендация**: Используйте интерактивный установщик для выбора подходящего варианта