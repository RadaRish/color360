#!/usr/bin/env python3
"""
LaMa Inpainting Service для Color360
Профессиональное удаление объектов с панорам
Оптимизировано для VPS с 2GB RAM
"""

import os
import io
import logging
import traceback
from typing import Optional
import asyncio
from PIL import Image
import numpy as np
import cv2
from fastapi import FastAPI, File, UploadFile, HTTPException, Form
from fastapi.responses import Response, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("LaMa-Service")

app = FastAPI(
    title="LaMa Inpainting Service",
    description="Профессиональное удаление объектов для Color360",
    version="2.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Глобальные переменные
LAMA_MODEL = None
LAMA_AVAILABLE = False
DEVICE = "cpu"

def check_system_resources():
    """Проверка системных ресурсов"""
    try:
        import psutil
        memory = psutil.virtual_memory()
        logger.info(f"💾 Доступно памяти: {memory.available // 1024 // 1024} MB")
        logger.info(f"🔧 Использовано памяти: {memory.percent}%")
        return True
    except ImportError:
        logger.warning("psutil недоступен для мониторинга памяти")
        return True

def init_lama_model():
    """Инициализация LaMa модели"""
    global LAMA_MODEL, LAMA_AVAILABLE
    
    try:
        logger.info("🎯 Попытка загрузки LaMa модели...")
        
        from lama_cleaner.model_manager import ModelManager
        
        LAMA_MODEL = ModelManager(
            name="lama",
            device=DEVICE,
            no_half=True,
            cpu_offload=True,
            disable_nsfw=True,
            sd_cpu_textencoder=True,
            enable_xformers=False,
            cpu_textencoder=True,
        )
        
        LAMA_AVAILABLE = True
        logger.info("✅ LaMa модель успешно загружена")
        return True
        
    except ImportError as e:
        logger.error(f"❌ LaMa Cleaner не установлен: {e}")
        LAMA_AVAILABLE = False
        return False
    except Exception as e:
        logger.error(f"❌ Ошибка инициализации LaMa: {e}")
        logger.error(traceback.format_exc())
        LAMA_AVAILABLE = False
        return False

def lama_inpainting(image: Image.Image, mask: Image.Image) -> Image.Image:
    """Профессиональный inpainting через LaMa"""
    if not LAMA_AVAILABLE or LAMA_MODEL is None:
        raise Exception("LaMa модель недоступна")
    
    try:
        from lama_cleaner.schema import Config
        
        # Конвертация в RGB
        if image.mode != 'RGB':
            image = image.convert('RGB')
        if mask.mode != 'L':
            mask = mask.convert('L')
        
        # Приведение размеров
        if image.size != mask.size:
            mask = mask.resize(image.size, Image.Resampling.LANCZOS)
        
        # Конвертация в numpy
        img_array = np.array(image)
        mask_array = np.array(mask)
        
        # Бинаризация маски
        mask_array = np.where(mask_array > 128, 255, 0).astype(np.uint8)
        
        logger.info(f"🎨 LaMa обработка: изображение {img_array.shape}, маска {mask_array.shape}")
        
        # Конфигурация LaMa
        config = Config(
            ldm_steps=20,
            ldm_sampler="ddim",
            hd_strategy="Resize",
            hd_strategy_crop_margin=32,
            hd_strategy_crop_trigger_size=512,
            hd_strategy_resize_limit=1024,
            prompt="",
            negative_prompt="",
            use_croper=False,
        )
        
        # Применение LaMa
        result_array = LAMA_MODEL(img_array, mask_array, config)
        
        logger.info("✅ LaMa обработка завершена")
        return Image.fromarray(result_array)
        
    except Exception as e:
        logger.error(f"❌ Ошибка LaMa inpainting: {e}")
        raise

def opencv_inpainting(image: Image.Image, mask: Image.Image) -> Image.Image:
    """Fallback через OpenCV"""
    try:
        img_array = cv2.cvtColor(np.array(image.convert('RGB')), cv2.COLOR_RGB2BGR)
        mask_array = np.array(mask.convert('L'))
        
        if img_array.shape[:2] != mask_array.shape:
            mask_array = cv2.resize(mask_array, (img_array.shape[1], img_array.shape[0]))
        
        mask_array = np.where(mask_array > 128, 255, 0).astype(np.uint8)
        
        logger.info("🔧 OpenCV inpainting fallback")
        result = cv2.inpaint(img_array, mask_array, 5, cv2.INPAINT_TELEA)
        result_rgb = cv2.cvtColor(result, cv2.COLOR_BGR2RGB)
        
        return Image.fromarray(result_rgb)
        
    except Exception as e:
        logger.error(f"❌ Ошибка OpenCV inpainting: {e}")
        raise

@app.on_event("startup")
async def startup_event():
    """Инициализация при запуске"""
    logger.info("🚀 Запуск LaMa Inpainting Service v2.0")
    
    check_system_resources()
    
    # Попытка инициализации LaMa в фоновом режиме
    try:
        init_lama_model()
    except Exception as e:
        logger.warning(f"⚠️ LaMa не инициализирована при запуске: {e}")
        logger.info("🔄 LaMa будет загружена при первом запросе")
    
    logger.info("✅ Сервис готов к работе")

@app.get("/")
async def root():
    """Главная страница"""
    return {
        "service": "LaMa Inpainting Service",
        "version": "2.0.0",
        "status": "running",
        "lama_available": LAMA_AVAILABLE,
        "device": DEVICE
    }

@app.get("/health")
async def health_check():
    """Проверка состояния"""
    try:
        # Проверка памяти
        memory_info = {}
        try:
            import psutil
            memory = psutil.virtual_memory()
            memory_info = {
                "available_mb": memory.available // 1024 // 1024,
                "used_percent": memory.percent
            }
        except:
            pass
        
        return {
            "status": "healthy" if LAMA_AVAILABLE else "degraded",
            "service": "lama-inpainting",
            "version": "2.0.0",
            "lama_available": LAMA_AVAILABLE,
            "device": DEVICE,
            "memory": memory_info,
            "features": {
                "lama_inpainting": LAMA_AVAILABLE,
                "opencv_fallback": True,
                "memory_optimized": True
            }
        }
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"status": "error", "error": str(e)}
        )

@app.post("/inpaint")
async def inpaint_image(
    image: UploadFile = File(..., description="Исходное изображение"),
    mask: UploadFile = File(..., description="Маска для удаления"),
    prompt: str = Form("remove object completely", description="Промпт"),
    negative_prompt: str = Form("artifacts, blurry", description="Негативный промпт"),
    num_inference_steps: int = Form(20, description="Шаги инференса"),
    guidance_scale: float = Form(7.5, description="Масштаб направления"),
    strength: float = Form(1.0, description="Сила применения")
):
    """
    Профессиональное удаление объектов
    
    Автоматически выбирает лучший доступный метод:
    1. LaMa AI (лучшее качество)
    2. OpenCV (быстрый fallback)
    """
    method_used = "unknown"
    processing_time = "unknown"
    
    try:
        # Загрузка файлов
        logger.info(f"📥 Получен запрос inpainting")
        
        img_bytes = await image.read()
        mask_bytes = await mask.read()
        
        pil_image = Image.open(io.BytesIO(img_bytes))
        pil_mask = Image.open(io.BytesIO(mask_bytes))
        
        logger.info(f"🖼️ Изображение: {pil_image.size}, Маска: {pil_mask.size}")
        
        result = None
        
        # Попытка LaMa
        if not LAMA_AVAILABLE:
            logger.info("⚡ Попытка загрузки LaMa по требованию...")
            init_lama_model()
        
        if LAMA_AVAILABLE and LAMA_MODEL:
            try:
                logger.info("🎯 Использование LaMa AI...")
                result = lama_inpainting(pil_image, pil_mask)
                method_used = "lama"
                processing_time = "optimized"
                
            except Exception as e:
                logger.warning(f"⚠️ LaMa не сработала: {e}")
        
        # Fallback на OpenCV
        if result is None:
            try:
                logger.info("🔧 Fallback на OpenCV...")
                result = opencv_inpainting(pil_image, pil_mask)
                method_used = "opencv"
                processing_time = "fast"
                
            except Exception as e:
                logger.warning(f"⚠️ OpenCV не сработала: {e}")
        
        # Последний fallback - возврат оригинала
        if result is None:
            logger.warning("⚠️ Все методы не сработали, возврат оригинала")
            result = pil_image
            method_used = "original"
            processing_time = "instant"
        
        # Подготовка ответа
        output_buffer = io.BytesIO()
        
        if result.mode != 'RGB':
            result = result.convert('RGB')
            
        result.save(output_buffer, format='JPEG', quality=92, optimize=True)
        output_buffer.seek(0)
        
        logger.info(f"✅ Обработка завершена: {method_used}")
        
        return Response(
            content=output_buffer.getvalue(),
            media_type="image/jpeg",
            headers={
                "X-Inpaint-Method": method_used,
                "X-Inpaint-Status": "success",
                "X-Processing-Time": processing_time,
                "X-Service-Version": "2.0.0"
            }
        )
        
    except Exception as e:
        logger.error(f"❌ Критическая ошибка: {e}")
        logger.error(traceback.format_exc())
        
        raise HTTPException(
            status_code=500,
            detail=f"Ошибка обработки: {str(e)}"
        )

@app.get("/status")
async def status():
    """Подробный статус сервиса"""
    try:
        import psutil
        process = psutil.Process()
        
        return {
            "service": "LaMa Inpainting",
            "version": "2.0.0", 
            "status": "running",
            "lama_available": LAMA_AVAILABLE,
            "memory_mb": process.memory_info().rss // 1024 // 1024,
            "cpu_percent": process.cpu_percent(),
            "uptime_seconds": int(process.create_time())
        }
    except:
        return {
            "service": "LaMa Inpainting",
            "version": "2.0.0",
            "status": "running",
            "lama_available": LAMA_AVAILABLE
        }

if __name__ == "__main__":
    port = int(os.getenv("PORT", 5002))
    host = os.getenv("HOST", "127.0.0.1")
    
    logger.info(f"🚀 Запуск LaMa Service на {host}:{port}")
    logger.info("🎯 Поддерживаемые методы: LaMa AI, OpenCV Fallback")
    
    uvicorn.run(
        app,
        host=host,
        port=port,
        log_level="info",
        access_log=True,
        loop="asyncio"
    )