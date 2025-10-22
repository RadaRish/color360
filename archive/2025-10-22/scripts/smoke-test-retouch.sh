#!/usr/bin/env bash
# Быстрый smoke-тест ретуши для Color360
set -e
API_URL="${API_URL:-https://www.color360.ru}"
IMG="${IMG:-sample.jpg}"
MASK="${MASK:-mask.png}"

if [ ! -f "$IMG" ]; then
  echo "Нет файла $IMG, создаю тестовый..."
  convert -size 512x256 xc:skyblue "$IMG"
fi
if [ ! -f "$MASK" ]; then
  echo "Нет файла $MASK, создаю тестовую маску..."
  convert -size 512x256 xc:black -draw "circle 256,128 256,64" -fill white -draw "circle 256,128 256,64" "$MASK"
fi

echo "==> Проверка /api/lama-health"
curl -k "$API_URL/api/lama-health"

echo "==> Проверка /api/retouch (multipart)"
curl -k -X POST "$API_URL/api/retouch" -F "image=@$IMG" -F "mask=@$MASK" -o out.jpg
file out.jpg

echo "==> Проверка /api/retouch-json (JSON fallback)"
IMG_B64=$(base64 -w0 "$IMG")
MASK_B64=$(base64 -w0 "$MASK")
JSON_BODY="{\"imageData\":\"data:image/jpeg;base64,$IMG_B64\",\"maskData\":\"data:image/png;base64,$MASK_B64\"}"
curl -k -X POST "$API_URL/api/retouch-json" -H "Content-Type: application/json" -d "$JSON_BODY" -o out_json.jpg
file out_json.jpg

echo "==> Smoke-тест завершён. Проверь out.jpg и out_json.jpg."
