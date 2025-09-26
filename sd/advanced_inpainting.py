#!/usr/bin/env python3
"""
Умный AI Inpainting Service для Color360
Комбинирует несколько алгоритмов для лучшего результата
"""

import os
import io
import logging
import asyncio
from typing import Optional, Tuple
from PIL import Image, ImageFilter
import numpy as np
from fastapi import FastAPI, File, UploadFile, HTTPException, Form
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Advanced AI Inpainting Service",
    description="Умный сервис удаления объектов с панорам",
    version="2.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Глобальные переменные для моделей
SD_PIPE = None
LAMA_MODEL = None
OPENCV_AVAILABLE = False

def setup_opencv_inpainting():
    """Настройка OpenCV для быстрого inpainting"""
    global OPENCV_AVAILABLE
    try:
        import cv2
        OPENCV_AVAILABLE = True
        logger.info("✅ OpenCV inpainting доступен")
    except ImportError:
        logger.warning("⚠️ OpenCV недоступен")

async def setup_lama_model():
    """Настройка LaMa модели"""
    global LAMA_MODEL
    try:
        from lama_cleaner.model_manager import ModelManager
        from lama_cleaner.schema import Config
        
        LAMA_MODEL = ModelManager(
            name="lama",
            device="cpu",
            no_half=True
        )
        logger.info("✅ LaMa модель загружена")
    except Exception as e:
        logger.warning(f"⚠️ LaMa недоступна: {e}")

async def setup_stable_diffusion():
    """Настройка Stable Diffusion"""
    global SD_PIPE
    try:
        from diffusers import StableDiffusionInpaintPipeline
        import torch
        
        model_id = "runwayml/stable-diffusion-inpainting"
        SD_PIPE = StableDiffusionInpaintPipeline.from_pretrained(
            model_id,
            torch_dtype=torch.float32,  # Используем float32 для CPU
            safety_checker=None,
            requires_safety_checker=False
        )
        
        # Оптимизация для CPU
        SD_PIPE.enable_attention_slicing()
        SD_PIPE.enable_sequential_cpu_offload()
        
        logger.info("✅ Stable Diffusion загружен")
    except Exception as e:
        logger.warning(f"⚠️ Stable Diffusion недоступен: {e}")

def opencv_inpainting(image: Image.Image, mask: Image.Image) -> Image.Image:
    """Быстрый inpainting через OpenCV"""
    if not OPENCV_AVAILABLE:
        raise Exception("OpenCV недоступен")
    
    import cv2
    
    # Конвертируем в OpenCV формат
    img_array = np.array(image.convert('RGB'))
    mask_array = np.array(mask.convert('L'))
    
    # OpenCV inpainting
    result = cv2.inpaint(img_array, mask_array, 3, cv2.INPAINT_TELEA)
    
    return Image.fromarray(result)

def lama_inpainting(image: Image.Image, mask: Image.Image) -> Image.Image:
    """Inpainting через LaMa"""
    if LAMA_MODEL is None:
        raise Exception("LaMa недоступна")
    
    from lama_cleaner.schema import Config
    
    # Конвертируем изображения
    img_array = np.array(image.convert('RGB'))
    mask_array = np.array(mask.convert('L'))
    
    # Настройки LaMa
    config = Config(
        ldm_steps=20,
        hd_strategy="Original",
        hd_strategy_crop_margin=32,
        hd_strategy_crop_trigger_size=512,
        hd_strategy_resize_limit=2048
    )
    
    # Применяем LaMa
    result = LAMA_MODEL(img_array, mask_array, config)
    
    return Image.fromarray(result)

def stable_diffusion_inpainting(image: Image.Image, mask: Image.Image, prompt: str, negative_prompt: str) -> Image.Image:
    """Inpainting через Stable Diffusion"""
    if SD_PIPE is None:
        raise Exception("Stable Diffusion недоступен")
    
    # Приводим к размеру кратному 64
    width, height = image.size
    new_width = (width // 64) * 64
    new_height = (height // 64) * 64
    
    if new_width != width or new_height != height:
        image = image.resize((new_width, new_height))
        mask = mask.resize((new_width, new_height))
    
    result = SD_PIPE(
        prompt=prompt,
        negative_prompt=negative_prompt,
        image=image,
        mask_image=mask,
        num_inference_steps=50,
        guidance_scale=15.0,
        strength=1.0
    ).images[0]
    
    # Возвращаем к оригинальному размеру если нужно
    if new_width != width or new_height != height:
        result = result.resize((width, height))
    
    return result

def enhanced_simulation(image: Image.Image, mask: Image.Image) -> Image.Image:
    """Улучшенная симуляция inpainting"""
    # Конвертируем в numpy
    img_array = np.array(image.convert('RGB'))
    mask_array = np.array(mask.convert('L'))
    
    # Создаем маску белых областей
    white_mask = mask_array > 200
    
    if not np.any(white_mask):
        return image
    
    result_array = img_array.copy()
    
    # Многослойное заполнение
    for radius in [3, 8, 15, 25]:
        blurred = image.filter(ImageFilter.GaussianBlur(radius=radius))
        blurred_array = np.array(blurred)
        
        # Смешиваем с разными весами
        weight = 1.0 / (radius / 3)
        result_array[white_mask] = (
            result_array[white_mask] * (1 - weight) + 
            blurred_array[white_mask] * weight
        ).astype(np.uint8)
    
    return Image.fromarray(result_array)

def choose_best_method(image: Image.Image, mask: Image.Image) -> str:
    """Выбирает лучший метод в зависимости от сложности"""
    mask_array = np.array(mask.convert('L'))
    white_pixels = np.sum(mask_array > 200)
    total_pixels = mask_array.size
    mask_ratio = white_pixels / total_pixels
    
    width, height = image.size
    total_area = width * height
    
    # Логика выбора метода
    if SD_PIPE and mask_ratio > 0.1 and total_area > 500000:  # Большая область, высокое разрешение
        return "stable_diffusion"
    elif LAMA_MODEL and mask_ratio > 0.05:  # Средняя область
        return "lama"
    elif OPENCV_AVAILABLE and mask_ratio < 0.05:  # Маленькая область
        return "opencv"
    else:
        return "simulation"

@app.on_event("startup")
async def startup_event():
    """Инициализация при запуске"""
    logger.info("🚀 Запуск Advanced AI Inpainting Service...")
    
    setup_opencv_inpainting()
    
    # Асинхронная загрузка моделей
    tasks = [
        setup_lama_model(),
        setup_stable_diffusion()
    ]
    
    await asyncio.gather(*tasks, return_exceptions=True)
    
    logger.info("✅ Сервис готов к работе")

@app.get("/health")
async def health_check():
    """Проверка состояния сервиса"""
    available_methods = []
    
    if SD_PIPE:
        available_methods.append("stable_diffusion")
    if LAMA_MODEL:
        available_methods.append("lama")
    if OPENCV_AVAILABLE:
        available_methods.append("opencv")
    
    available_methods.append("simulation")
    
    return {
        "status": "healthy",
        "service": "advanced-ai-inpainting",
        "available_methods": available_methods,
        "recommended_method": available_methods[0] if available_methods else "simulation"
    }

@app.post("/inpaint")
async def inpaint_image(
    image: UploadFile = File(...),
    mask: UploadFile = File(...),
    prompt: str = Form("remove object, fill with natural background, seamless blend"),
    negative_prompt: str = Form("object, artifacts, seams, blurry, distorted"),
    method: str = Form("auto")  # auto, stable_diffusion, lama, opencv, simulation
):
    """
    Умное удаление объектов с выбором лучшего алгоритма
    """
    try:
        # Загружаем изображения
        img_bytes = await image.read()
        mask_bytes = await mask.read()
        
        pil_image = Image.open(io.BytesIO(img_bytes)).convert('RGB')
        pil_mask = Image.open(io.BytesIO(mask_bytes)).convert('L')
        
        logger.info(f"🎨 Обработка изображения {pil_image.size}, маска {pil_mask.size}")
        
        # Выбираем метод
        if method == "auto":
            chosen_method = choose_best_method(pil_image, pil_mask)
        else:
            chosen_method = method
        
        logger.info(f"🔧 Выбранный метод: {chosen_method}")
        
        # Применяем выбранный метод
        try:
            if chosen_method == "stable_diffusion":
                result = stable_diffusion_inpainting(pil_image, pil_mask, prompt, negative_prompt)
                status = "success_sd"
            elif chosen_method == "lama":
                result = lama_inpainting(pil_image, pil_mask)
                status = "success_lama"
            elif chosen_method == "opencv":
                result = opencv_inpainting(pil_image, pil_mask)
                status = "success_opencv"
            else:
                result = enhanced_simulation(pil_image, pil_mask)
                status = "success_simulation"
        
        except Exception as method_error:
            logger.warning(f"⚠️ Ошибка метода {chosen_method}: {method_error}")
            # Fallback к симуляции
            result = enhanced_simulation(pil_image, pil_mask)
            status = "fallback_simulation"
        
        # Возвращаем результат
        output_buffer = io.BytesIO()
        result.save(output_buffer, format='JPEG', quality=95)
        output_buffer.seek(0)
        
        return Response(
            content=output_buffer.getvalue(),
            media_type="image/jpeg",
            headers={
                "X-Inpaint-Method": chosen_method,
                "X-Inpaint-Status": status
            }
        )
        
    except Exception as e:
        logger.error(f"❌ Ошибка inpainting: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    port = int(os.getenv("PORT", 5002))
    host = os.getenv("HOST", "127.0.0.1")
    
    logger.info(f"🚀 Запуск сервера на {host}:{port}")
    uvicorn.run(app, host=host, port=port)