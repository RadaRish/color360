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
        logger.info(f"📝 Параметры: prompt='{prompt}', steps={num_inference_steps}")
        
        # Читаем оригинальное изображение
        image_bytes = await image.read()
        
        # В режиме разработки возвращаем оригинал
        logger.info("✅ Возвращаем оригинальное изображение (dev mode)")
        
        return Response(
            content=image_bytes,
            media_type="image/png",
            headers={
                "X-Processing-Mode": "development",
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