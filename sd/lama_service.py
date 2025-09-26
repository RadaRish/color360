#!/usr/bin/env python3
"""
LaMa Inpainting Service для Color360
Профессиональное удаление объектов с панорам
"""

import os
import io
import logging
import traceback
from PIL import Image
import numpy as np
import cv2
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
    title="LaMa Inpainting Service",
    description="Профессиональное удаление объектов через LaMa для Color360",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Глобальная переменная для модели LaMa
LAMA_PREDICTOR = None
LAMA_AVAILABLE = False

def check_dependencies():
    """Проверяем доступность зависимостей"""
    try:
        import torch
        logger.info(f"✅ PyTorch доступен: {torch.__version__}")
    except ImportError:
        logger.warning("⚠️ PyTorch не установлен")
        return False
    
    try:
        from lama_cleaner.model_manager import ModelManager
        logger.info("✅ LaMa Cleaner доступен")
        return True
    except ImportError:
        logger.warning("⚠️ LaMa Cleaner не установлен")
        return False

def setup_lama():
    """Инициализация LaMa"""
    global LAMA_PREDICTOR, LAMA_AVAILABLE
    
    if not check_dependencies():
        logger.error("❌ Необходимые зависимости не установлены")
        return False
    
    try:
        from lama_cleaner.model_manager import ModelManager
        
        logger.info("🚀 Загрузка LaMa модели...")
        
        LAMA_PREDICTOR = ModelManager(
            name="lama",
            device="cpu",
            no_half=True,
            cpu_offload=False,
            disable_nsfw=True,
            sd_cpu_textencoder=False,
            enable_xformers=False,
            cpu_textencoder=False,
        )
        
        LAMA_AVAILABLE = True
        logger.info("✅ LaMa модель успешно загружена")
        return True
        
    except Exception as e:
        logger.error(f"❌ Ошибка загрузки LaMa: {e}")
        logger.error(traceback.format_exc())
        LAMA_AVAILABLE = False
        return False

def lama_inpainting(image: Image.Image, mask: Image.Image) -> Image.Image:
    """Профессиональный inpainting через LaMa"""
    if not LAMA_AVAILABLE or LAMA_PREDICTOR is None:
        raise Exception("LaMa модель недоступна")
    
    try:
        from lama_cleaner.schema import Config
        
        # Конвертируем в RGB формат
        if image.mode != 'RGB':
            image = image.convert('RGB')
        if mask.mode != 'L':
            mask = mask.convert('L')
        
        # Приводим маску к размеру изображения
        if image.size != mask.size:
            mask = mask.resize(image.size, Image.Resampling.LANCZOS)
        
        # Конвертируем в numpy
        img_array = np.array(image)
        mask_array = np.array(mask)
        
        # Приводим маску к бинарному виду (белое = удаляемая область)
        mask_array = np.where(mask_array > 128, 255, 0).astype(np.uint8)
        
        logger.info(f"🎨 LaMa обработка: {img_array.shape}, маска: {mask_array.shape}")
        
        # Настройки LaMa для лучшего качества
        config = Config(
            ldm_steps=25,
            ldm_sampler="ddim",
            hd_strategy="Resize",
            hd_strategy_crop_margin=32,
            hd_strategy_crop_trigger_size=512,
            hd_strategy_resize_limit=2048,
            prompt="",
            negative_prompt="",
            use_croper=False,
            croper_x=0,
            croper_y=0,
            croper_height=512,
            croper_width=512
        )
        
        # Применяем LaMa inpainting
        result_array = LAMA_PREDICTOR(img_array, mask_array, config)
        
        logger.info("✅ LaMa обработка завершена успешно")
        return Image.fromarray(result_array)
        
    except Exception as e:
        logger.error(f"❌ Ошибка LaMa inpainting: {e}")
        raise

def opencv_inpainting(image: Image.Image, mask: Image.Image) -> Image.Image:
    """Быстрый fallback через OpenCV"""
    try:
        # Конвертируем в OpenCV формат
        img_array = cv2.cvtColor(np.array(image.convert('RGB')), cv2.COLOR_RGB2BGR)
        mask_array = np.array(mask.convert('L'))
        
        # Приводим к размеру изображения
        if img_array.shape[:2] != mask_array.shape:
            mask_array = cv2.resize(mask_array, (img_array.shape[1], img_array.shape[0]))
        
        # Бинаризация маски
        mask_array = np.where(mask_array > 128, 255, 0).astype(np.uint8)
        
        logger.info(f"🔧 OpenCV inpainting: {img_array.shape}")
        
        # Применяем inpainting
        result = cv2.inpaint(img_array, mask_array, 5, cv2.INPAINT_TELEA)
        
        # Конвертируем обратно в RGB
        result_rgb = cv2.cvtColor(result, cv2.COLOR_BGR2RGB)
        
        logger.info("✅ OpenCV обработка завершена")
        return Image.fromarray(result_rgb)
        
    except Exception as e:
        logger.error(f"❌ Ошибка OpenCV inpainting: {e}")
        raise

def enhanced_blur_inpainting(image: Image.Image, mask: Image.Image) -> Image.Image:
    """Улучшенное размытие как последний fallback"""
    try:
        # Конвертируем в numpy
        img_array = np.array(image.convert('RGB'))
        mask_array = np.array(mask.convert('L'))
        
        # Приводим к размеру
        if img_array.shape[:2] != mask_array.shape:
            from PIL import Image as PILImage
            mask_resized = PILImage.fromarray(mask_array).resize((img_array.shape[1], img_array.shape[0]))
            mask_array = np.array(mask_resized)
        
        # Создаем маску белых областей
        white_mask = mask_array > 128
        
        if not np.any(white_mask):
            return image
        
        result_array = img_array.copy()
        
        # Многослойное размытие
        from PIL import ImageFilter
        for radius in [5, 15, 25]:
            blurred = image.filter(ImageFilter.GaussianBlur(radius=radius))
            blurred_array = np.array(blurred)
            
            # Смешиваем
            alpha = 0.3
            result_array[white_mask] = (
                result_array[white_mask] * (1 - alpha) + 
                blurred_array[white_mask] * alpha
            ).astype(np.uint8)
        
        logger.info("✅ Blur fallback завершен")
        return Image.fromarray(result_array)
        
    except Exception as e:
        logger.error(f"❌ Ошибка blur inpainting: {e}")
        return image  # Возвращаем оригинал в крайнем случае

@app.on_event("startup")
async def startup_event():
    """Инициализация при запуске"""
    logger.info("🚀 Запуск LaMa Inpainting Service для Color360...")
    
    # Проверяем системные ресурсы
    try:
        import psutil
        memory = psutil.virtual_memory()
        logger.info(f"💾 Доступно памяти: {memory.available // 1024 // 1024} MB")
    except:
        pass
    
    # Пробуем загрузить LaMa
    lama_success = setup_lama()
    
    if lama_success:
        logger.info("✅ Сервис готов с LaMa AI")
    else:
        logger.info("✅ Сервис готов с OpenCV fallback")

@app.get("/")
async def root():
    """Корневая страница"""
    return {
        "service": "Color360 LaMa Inpainting",
        "status": "running",
        "lama_available": LAMA_AVAILABLE
    }

@app.get("/health")
async def health_check():
    """Проверка состояния сервиса"""
    return {
        "status": "healthy",
        "service": "lama-inpainting",
        "lama_available": LAMA_AVAILABLE,
        "opencv_available": True,
        "device": "cpu",
        "memory_efficient": True,
        "version": "1.0.0"
    }

@app.post("/inpaint")
async def inpaint_image(
    image: UploadFile = File(...),
    mask: UploadFile = File(...),
    prompt: str = Form("remove object completely, natural background"),
    negative_prompt: str = Form("artifacts, blurry, seams"),
    num_inference_steps: int = Form(25),
    guidance_scale: float = Form(7.5),
    strength: float = Form(1.0)
):
    """
    Профессиональное удаление объектов
    Автоматически выбирает лучший доступный метод
    """
    method_used = "unknown"
    processing_status = "unknown"
    
    try:
        # Загружаем изображения
        img_bytes = await image.read()
        mask_bytes = await mask.read()
        
        logger.info(f"📥 Получены файлы: image={len(img_bytes)} bytes, mask={len(mask_bytes)} bytes")
        
        pil_image = Image.open(io.BytesIO(img_bytes))
        pil_mask = Image.open(io.BytesIO(mask_bytes))
        
        logger.info(f"🖼️ Размеры: image={pil_image.size}, mask={pil_mask.size}")
        
        # Пробуем методы в порядке предпочтения
        result = None
        
        # 1. LaMa (лучшее качество)
        if LAMA_AVAILABLE and LAMA_PREDICTOR:
            try:
                logger.info("🎯 Пробуем LaMa inpainting...")
                result = lama_inpainting(pil_image, pil_mask)
                method_used = "lama"
                processing_status = "success"
                
            except Exception as e:
                logger.warning(f"⚠️ LaMa failed: {e}")
        
        # 2. OpenCV fallback
        if result is None:
            try:
                logger.info("🔧 Используем OpenCV inpainting...")
                result = opencv_inpainting(pil_image, pil_mask)
                method_used = "opencv"
                processing_status = "opencv_fallback"
                
            except Exception as e:
                logger.warning(f"⚠️ OpenCV failed: {e}")
        
        # 3. Blur fallback
        if result is None:
            try:
                logger.info("🌀 Используем blur fallback...")
                result = enhanced_blur_inpainting(pil_image, pil_mask)
                method_used = "blur"
                processing_status = "blur_fallback"
                
            except Exception as e:
                logger.warning(f"⚠️ Blur failed: {e}")
        
        # 4. Аварийный возврат оригинала
        if result is None:
            logger.warning("⚠️ Все методы не сработали, возвращаем оригинал")
            result = pil_image
            method_used = "original"
            processing_status = "emergency_fallback"
        
        # Сохраняем результат
        output_buffer = io.BytesIO()
        
        # Конвертируем в RGB если нужно
        if result.mode != 'RGB':
            result = result.convert('RGB')
            
        result.save(output_buffer, format='JPEG', quality=95, optimize=True)
        output_buffer.seek(0)
        
        logger.info(f"✅ Обработка завершена: метод={method_used}, статус={processing_status}")
        
        return Response(
            content=output_buffer.getvalue(),
            media_type="image/jpeg",
            headers={
                "X-Inpaint-Method": method_used,
                "X-Inpaint-Status": processing_status,
                "X-Processing-Time": "optimized",
                "X-Service-Version": "1.0.0"
            }
        )
        
    except Exception as e:
        logger.error(f"❌ Критическая ошибка: {e}")
        logger.error(traceback.format_exc())
        
        raise HTTPException(
            status_code=500, 
            detail=f"Inpainting service error: {str(e)}"
        )

if __name__ == "__main__":
    port = int(os.getenv("PORT", 5002))
    host = os.getenv("HOST", "127.0.0.1")
    
    logger.info(f"🚀 Запуск LaMa сервиса на {host}:{port}")
    logger.info("🎯 Поддерживаемые методы: LaMa AI, OpenCV, Enhanced Blur")
    
    uvicorn.run(
        app, 
        host=host, 
        port=port,
        log_level="info",
        access_log=True
    )