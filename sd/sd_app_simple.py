#!/usr/bin/env python3
"""
Простой Stable Diffusion Inpainting Service
Облегченная версия для локальной разработки без GPU
"""

import os
import io
import logging
from typing import Optional
from PIL import Image
from fastapi import FastAPI, File, UploadFile, HTTPException, Form
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Simple SD Inpainting Service",
    description="Упрощенный сервис для разработки",
    version="1.0.0"
)

def simulate_inpainting(original_image: Image.Image, mask_image: Image.Image) -> Image.Image:
    """
    Простая имитация inpainting - заполняет замаскированные области
    средним цветом окружающих пикселей
    """
    import numpy as np
    from PIL import ImageFilter
    
    # Конвертируем в RGB если нужно
    if original_image.mode != 'RGB':
        original_image = original_image.convert('RGB')
    if mask_image.mode != 'RGB':
        mask_image = mask_image.convert('RGB')
    
    # Приводим к одинаковому размеру
    mask_image = mask_image.resize(original_image.size)
    
    # Конвертируем в numpy массивы
    img_array = np.array(original_image)
    mask_array = np.array(mask_image)
    
    # Создаем маску (белые области = удаляемые)
    white_mask = np.all(mask_array > 200, axis=2)
    
    # Создаем копию изображения
    result_array = img_array.copy()
    
    # Улучшенное заполнение замаскированных областей
    if np.any(white_mask):
        # Многоуровневое размытие для более естественного результата
        blur1 = original_image.filter(ImageFilter.GaussianBlur(radius=3))
        blur2 = original_image.filter(ImageFilter.GaussianBlur(radius=8))
        blur3 = original_image.filter(ImageFilter.GaussianBlur(radius=15))
        
        blur1_array = np.array(blur1)
        blur2_array = np.array(blur2)
        blur3_array = np.array(blur3)
        
        # Смешиваем разные уровни размытия для естественности
        mixed_blur = (blur1_array * 0.5 + blur2_array * 0.3 + blur3_array * 0.2).astype(np.uint8)
        
        # Применяем смешанное размытие в замаскированных областях
        result_array[white_mask] = mixed_blur[white_mask]
        
        # Легкое затемнение для видимости изменений
        result_array[white_mask] = (result_array[white_mask] * 0.9).astype(np.uint8)
    
    return Image.fromarray(result_array)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
async def health_check():
    """Проверка состояния сервиса"""
    return {
        "status": "healthy",
        "service": "sd-inpainting-simple",
        "mode": "development",
        "device": "cpu"
    }

@app.post("/inpaint")
async def inpaint_image(
    image: UploadFile = File(...),
    mask: UploadFile = File(...),
    prompt: str = Form("high quality, detailed"),
    negative_prompt: str = Form("low quality, blurry"),
    num_inference_steps: int = Form(20),
    guidance_scale: float = Form(7.5),
    strength: float = Form(1.0)
):
    """
    Обработка изображения (упрощенная версия для разработки)
    В режиме разработки просто возвращаем оригинальное изображение
    """
    try:
        logger.info(f"🎨 Получен запрос на inpainting: {image.filename}")
        logger.info(f"📝 Параметры: prompt='{prompt[:50]}...', steps={num_inference_steps}, guidance={guidance_scale}")
        
        # Читаем изображения
        image_bytes = await image.read()
        mask_bytes = await mask.read()
        
        # Имитируем inpainting - применяем маску к изображению
        original_image = Image.open(io.BytesIO(image_bytes))
        mask_image = Image.open(io.BytesIO(mask_bytes))
        
        # Простая имитация inpainting - заполняем замаскированные области нейтральным цветом
        result_image = simulate_inpainting(original_image, mask_image)
        
        # Конвертируем результат в bytes
        img_byte_arr = io.BytesIO()
        result_image.save(img_byte_arr, format='PNG', quality=95)
        img_byte_arr.seek(0)
        
        logger.info("✅ Имитация inpainting завершена")
        
        return Response(
            content=img_byte_arr.getvalue(),
            media_type="image/png",
            headers={
                "X-Processing-Mode": "simulation",
                "X-Service": "sd-simple"
            }
        )
        
    except Exception as e:
        logger.error(f"❌ Ошибка обработки: {e}")
        raise HTTPException(status_code=500, detail=f"Ошибка обработки: {str(e)}")

if __name__ == "__main__":
    # Получаем настройки из переменных окружения
    host = os.getenv('HOST', '127.0.0.1')
    port = int(os.getenv('PORT', 5000))
    
    logger.info(f"🚀 Запуск простого SD сервиса на {host}:{port}")
    logger.info("⚠️ Режим разработки: возвращаем оригинальные изображения")
    
    uvicorn.run(
        app,
        host=host,
        port=port,
        log_level="info"
    )