#!/usr/bin/env bash
set -euo pipefail

# Быстрое развёртывание/обновление Color360 (Node backend + LaMa service) на VPS
# УСЛОВИЯ:
#  - Домен: www.color360.ru (можно переопределить переменной DOMAIN)
#  - Чистое обновление: старая директория удаляется без бэкапов
#  - Systemd юниты: color360-app (Node) и color360-lama (LaMa / FastAPI)
#  - Репозиторий: https://github.com/RadaRish/color360.git

REPO_URL="https://github.com/RadaRish/color360.git"
APP_DIR="/var/www/color360"
DOMAIN="${DOMAIN:-www.color360.ru}"
NODE_ENV=production
NODE_BIN="/usr/bin/node"
PYTHON_BIN="python3"

echo "==> Обновление Color360 для домена ${DOMAIN}" 

if ! command -v git >/dev/null 2>&1; then
  echo "Устанавливаю git..."; apt-get update -y && apt-get install -y git;
fi
if ! command -v $PYTHON_BIN >/dev/null 2>&1; then
  echo "Устанавливаю Python..."; apt-get update -y && apt-get install -y python3 python3-venv python3-pip;
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "Устанавливаю Node.js (LTS)..."; curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && apt-get install -y nodejs;
fi

systemctl stop color360-app 2>/dev/null || true
systemctl stop color360-lama 2>/dev/null || true

rm -rf "${APP_DIR}.new"
git clone --depth 1 "$REPO_URL" "${APP_DIR}.new"

cd "${APP_DIR}.new"
echo "==> Установка JS зависимостей (production)"
if [ -f package.json ]; then
  npm ci --omit=dev || npm install --production
fi

echo "==> Настройка Python окружения для LaMa"
cd lama
${PYTHON_BIN} -m venv lama_env
source lama_env/bin/activate
pip install --upgrade pip
if [ -f requirements.txt ]; then
  pip install -r requirements.txt
fi
deactivate
cd ..

echo "==> Создание systemd юнитов"
cat > /etc/systemd/system/color360-app.service <<EOF
[Unit]
Description=Color360 Node.js Backend
After=network.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
Environment=NODE_ENV=production
ExecStart=${NODE_BIN} server.js
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/color360-lama.service <<EOF
[Unit]
Description=Color360 LaMa Inpainting Service
After=network.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}/lama
ExecStart=${APP_DIR}/lama/lama_env/bin/python service.py
Restart=on-failure
RestartSec=8
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

echo "==> Атомарная замена директории"
rm -rf "${APP_DIR}"
mv "${APP_DIR}.new" "${APP_DIR}"

echo "==> Перезагрузка systemd и запуск сервисов"
systemctl daemon-reload
systemctl enable --now color360-lama.service
systemctl enable --now color360-app.service

echo "==> Проверка статуса"
systemctl --no-pager status color360-lama.service | sed -n '1,12p' || true
systemctl --no-pager status color360-app.service   | sed -n '1,12p' || true

echo "==> Готово. Прокси (nginx) должен направлять /api/retouch и /api/retouch-json на 127.0.0.1:3000"
echo "==> Проверь: curl -k https://${DOMAIN}/api/lama-health"
