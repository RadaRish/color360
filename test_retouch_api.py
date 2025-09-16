#!/usr/bin/env python3
# Простой тест API endpoint /api/retouch

import requests
import io
from PIL import Image, ImageDraw
import numpy as np

def create_test_image(size=(512, 512)):
    """Создает тестовое изображение"""
    img = Image.new('RGB', size, color='lightblue')
    draw = ImageDraw.Draw(img)
    
    # Рисуем красный круг в центре
    center_x, center_y = size[0] // 2, size[1] // 2
    radius = 50
    draw.ellipse([
        center_x - radius, center_y - radius,
        center_x + radius, center_y + radius
    ], fill='red', outline='darkred', width=3)
    
    # Добавляем текст
    draw.text((10, 10), "Test Image", fill='black')
    
    return img

def create_test_mask(size=(512, 512)):
    """Создает тестовую маску (белый круг на черном фоне)"""
    mask = Image.new('RGB', size, color='black')
    draw = ImageDraw.Draw(mask)
    
    # Белый круг в центре - область для удаления
    center_x, center_y = size[0] // 2, size[1] // 2
    radius = 50
    draw.ellipse([
        center_x - radius, center_y - radius,
        center_x + radius, center_y + radius
    ], fill='white')
    
    return mask

def test_retouch_api():
    """Тестирует API endpoint /api/retouch"""
    print("🧪 Тестирование API /api/retouch...")
    
    # Создаем тестовые изображения
    test_img = create_test_image()
    test_mask = create_test_mask()
    
    # Конвертируем в bytes
    img_buffer = io.BytesIO()
    test_img.save(img_buffer, format='PNG')
    img_buffer.seek(0)
    
    mask_buffer = io.BytesIO()
    test_mask.save(mask_buffer, format='PNG')
    mask_buffer.seek(0)
    
    try:
        # Отправляем запрос
        print("📤 Отправка запроса в /api/retouch...")
        response = requests.post(
            'http://localhost:3000/api/retouch',
            files={
                'image': ('test.png', img_buffer.getvalue(), 'image/png'),
                'mask': ('mask.png', mask_buffer.getvalue(), 'image/png')
            },
            timeout=30
        )
        
        print(f"📊 Статус ответа: {response.status_code}")
        print(f"📋 Заголовки: {dict(response.headers)}")
        
        if response.status_code == 200:
            # Сохраняем результат
            result_img = Image.open(io.BytesIO(response.content))
            result_img.save('test_result.png')
            print("✅ Тест прошел успешно! Результат сохранен в test_result.png")
            
            # Проверяем статус обработки
            retouch_status = response.headers.get('X-Retouch-Status', 'unknown')
            retouch_method = response.headers.get('X-Retouch-Method', 'unknown')
            print(f"🎨 Статус обработки: {retouch_status}")
            print(f"🔧 Метод обработки: {retouch_method}")
            
        else:
            print(f"❌ Ошибка: {response.status_code}")
            print(f"📄 Ответ: {response.text}")
            
    except Exception as e:
        print(f"❌ Ошибка запроса: {e}")

if __name__ == "__main__":
    test_retouch_api()