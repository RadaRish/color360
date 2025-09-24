#!/usr/bin/env python3
"""
Stable Diffusion Inpainting Service
Сервис для обработки изображений с использованием Stable Diffusion
"""

import os
import io
import gc
import torch
import logging
import asyncio
from pathlib import Path
from typing import Optional, Dict, Any
from contextlib import asynccontextmanager

import numpy as np
from PIL import Image
from fastapi import FastAPI, File, UploadFile, HTTPException, Form
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

from diffusers import StableDiffusionInpaintPipeline
from diffusers.utils import logging as diffusers_logging

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Отключаем избыточные логи diffusers
diffusers_logging.set_verbosity_error()

# Глобальные переменные
pipeline = None
device = None

# Конфигурация
CONFIG = {
    'model_id': 'runwayml/stable-diffusion-inpainting',
    'torch_dtype': torch.float16 if torch.cuda.is_available() else torch.float32,
    'safety_checker': None,  # Отключаем для скорости
    'requires_safety_checker': False,
    'low_cpu_mem_usage': True,
    'use_safetensors': True,
}

def get_device():
    """Определяет оптимальное устройство для вычислений"""
    if torch.cuda.is_available():
        return "cuda"
    elif hasattr(torch.backends, 'mps') and torch.backends.mps.is_available():
        return "mps"
    else:
        return "cpu"

async def load_model():
    """Загружает модель Stable Diffusion"""
    global pipeline, device
    
    try:
        device = get_device()
        logger.info(f"Загрузка Stable Diffusion на устройство: {device}")
        
        # Освобождаем память если есть существующая модель
        if pipeline is not None:
            del pipeline
            gc.collect()
            if device == "cuda":
                torch.cuda.empty_cache()
        
        # Загружаем модель
        pipeline = StableDiffusionInpaintPipeline.from_pretrained(
            CONFIG['model_id'],
            torch_dtype=CONFIG['torch_dtype'],
            safety_checker=CONFIG['safety_checker'],
            requires_safety_checker=CONFIG['requires_safety_checker'],
            low_cpu_mem_usage=CONFIG['low_cpu_mem_usage'],
            use_safetensors=CONFIG['use_safetensors']
        )
        
        pipeline = pipeline.to(device)
        
        # Оптимизация для различных устройств
        if device == "cuda":
            pipeline.enable_model_cpu_offload()
            pipeline.enable_xformers_memory_efficient_attention()
        elif device == "mps":
            pipeline.enable_model_cpu_offload()
        
        logger.info("Модель Stable Diffusion успешно загружена")
        return True
        
    except Exception as e:
        logger.error(f"Ошибка загрузки модели: {e}")
        return False

def preprocess_image(image: Image.Image, target_size: tuple = (512, 512)) -> Image.Image:
    """Предварительная обработка изображения"""
    # Конвертируем в RGB если необходимо
    if image.mode != 'RGB':
        image = image.convert('RGB')
    
    # Изменяем размер с сохранением пропорций
    image.thumbnail(target_size, Image.Resampling.LANCZOS)
    
    # Создаем новое изображение с целевым размером и вставляем по центру
    result = Image.new('RGB', target_size, (255, 255, 255))
    offset = ((target_size[0] - image.size[0]) // 2, 
              (target_size[1] - image.size[1]) // 2)
    result.paste(image, offset)
    
    return result

def preprocess_mask(mask: Image.Image, target_size: tuple = (512, 512)) -> Image.Image:
    """Предварительная обработка маски"""
    # Конвертируем в L (grayscale) если необходимо
    if mask.mode != 'L':
        mask = mask.convert('L')
    
    # Изменяем размер
    mask = mask.resize(target_size, Image.Resampling.LANCZOS)
    
    # Бинаризуем маску
    mask_array = np.array(mask)
    mask_array = (mask_array > 128).astype(np.uint8) * 255
    
    return Image.fromarray(mask_array, mode='L')

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Управление жизненным циклом приложения"""
    # Startup
    logger.info("Запуск Stable Diffusion сервиса...")
    success = await load_model()
    if not success:
        logger.error("Не удалось загрузить модель!")
        raise RuntimeError("Ошибка инициализации модели")
    
    yield
    
    # Shutdown
    logger.info("Завершение работы сервиса...")
    global pipeline
    if pipeline is not None:
        del pipeline
        gc.collect()
        if device == "cuda":
            torch.cuda.empty_cache()

# Создаем приложение FastAPI
app = FastAPI(
    title="Stable Diffusion Inpainting Service",
    description="Сервис для обработки изображений с использованием Stable Diffusion",
    version="1.0.0",
    lifespan=lifespan
)

# Настраиваем CORS
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
    global pipeline
    status = "ok" if pipeline is not None else "loading"
    return {
        "status": status,
        "device": device,
        "model": CONFIG['model_id'],
        "torch_available": torch.cuda.is_available() if device == "cuda" else True
    }

@app.post("/inpaint")
async def inpaint_image(
    image: UploadFile = File(..., description="Исходное изображение"),
    mask: UploadFile = File(..., description="Маска для инпейнтинга"),
    prompt: str = Form("high quality, detailed", description="Промпт для генерации"),
    negative_prompt: str = Form("low quality, blurry, distorted", description="Негативный промпт"),
    num_inference_steps: int = Form(20, description="Количество шагов инференса"),
    guidance_scale: float = Form(7.5, description="Масштаб руководства"),
    strength: float = Form(1.0, description="Сила применения эффекта")
):
    """Выполняет инпейнтинг изображения"""
    global pipeline
    
    if pipeline is None:
        raise HTTPException(status_code=503, detail="Модель еще не загружена")
    
    try:
        logger.info(f"Начало обработки изображения с промптом: '{prompt}'")
        
        # Загружаем и обрабатываем изображения
        image_bytes = await image.read()
        mask_bytes = await mask.read()
        
        original_image = Image.open(io.BytesIO(image_bytes))
        mask_image = Image.open(io.BytesIO(mask_bytes))
        
        # Предобработка
        processed_image = preprocess_image(original_image)
        processed_mask = preprocess_mask(mask_image)
        
        # Параметры генерации
        generator = torch.Generator(device=device).manual_seed(42)
        
        # Выполняем инпейнтинг
        with torch.no_grad():
            result = pipeline(
                prompt=prompt,
                image=processed_image,
                mask_image=processed_mask,
                negative_prompt=negative_prompt,
                num_inference_steps=num_inference_steps,
                guidance_scale=guidance_scale,
                strength=strength,
                generator=generator
            )
        
        # Получаем результат
        output_image = result.images[0]
        
        # Конвертируем в bytes
        img_byte_arr = io.BytesIO()
        output_image.save(img_byte_arr, format='PNG', quality=95)
        img_byte_arr.seek(0)
        
        logger.info("Изображение успешно обработано")
        
        return Response(
            content=img_byte_arr.getvalue(),
            media_type="image/png",
            headers={
                "Content-Disposition": "inline; filename=inpainted.png"
            }
        )
        
    except Exception as e:
        logger.error(f"Ошибка при обработке изображения: {e}")
        raise HTTPException(status_code=500, detail=f"Ошибка обработки: {str(e)}")
    
    finally:
        # Очистка памяти
        if device == "cuda":
            torch.cuda.empty_cache()

@app.get("/models")
async def get_model_info():
    """Возвращает информацию о модели"""
    return {
        "current_model": CONFIG['model_id'],
        "device": device,
        "dtype": str(CONFIG['torch_dtype']),
        "available_models": [
            "runwayml/stable-diffusion-inpainting",
            "stabilityai/stable-diffusion-2-inpainting",
        ]
    }

@app.post("/reload")
async def reload_model():
    """Перезагружает модель"""
    try:
        success = await load_model()
        if success:
            return {"status": "success", "message": "Модель успешно перезагружена"}
        else:
            raise HTTPException(status_code=500, detail="Ошибка перезагрузки модели")
    except Exception as e:
        logger.error(f"Ошибка перезагрузки модели: {e}")
        raise HTTPException(status_code=500, detail=f"Ошибка: {str(e)}")

if __name__ == "__main__":
    # Настройки сервера
    host = os.getenv("HOST", "127.0.0.1")
    port = int(os.getenv("PORT", "5002"))
    
    logger.info(f"Запуск Stable Diffusion сервера на {host}:{port}")
    
    uvicorn.run(
        app,
        host=host,
        port=port,
        log_level="info",
        access_log=True
    )