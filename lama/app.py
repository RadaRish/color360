import os
import io
import base64
import tempfile
import logging
from pathlib import Path

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import Response, JSONResponse
from PIL import Image
import uvicorn
import numpy as np
import cv2

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="LaMa Inpainting API", version="1.0.0")

# Глобальные переменные для модели
lama_model = None
model_loaded = False

def load_lama_model():
    """Загружает модель LaMa для inpainting"""
    global lama_model, model_loaded
    
    try:
        # Попытка загрузить модель LaMa
        import torch
        from lama_cleaner.model_manager import ModelManager
        from lama_cleaner.schema import Config
        
        logger.info("Загружаем модель LaMa...")
        
        # Настройка модели
        config = Config(
            ldm_steps=50,
            ldm_sampler='ddim',
            hd_strategy='Original',
            hd_strategy_crop_margin=32,
            hd_strategy_crop_trigger_size=512,
            hd_strategy_resize_limit=2048,
            prompt='',
            negative_prompt='',
            use_croper=False,
            croper_x=0,
            croper_y=0,
            croper_height=512,
            croper_width=512,
            sd_scale=1.0,
            sd_mask_blur=5,
            sd_strength=1.0,
            sd_steps=50,
            sd_guidance_scale=7.5,
            sd_sampler='ddim',
            sd_seed=42,
            sd_match_histograms=False,
            cv2_flag='INPAINT_NS',
            cv2_radius=5,
        )
        
        lama_model = ModelManager(
            name="lama",
            device="cpu",  # Используем CPU для стабильности на продакшене
            no_half=True,
            low_mem=True,
            cpu_offload=True,
            disable_nsfw=False,
            sd_cpu_textencoder=True,
            callback=None
        )
        
        model_loaded = True
        logger.info("✅ Модель LaMa успешно загружена")
        return True
        
    except ImportError as e:
        logger.warning(f"⚠️ LaMa модель недоступна: {e}")
        logger.info("Используем fallback OpenCV inpainting")
        model_loaded = False
        return False
    except Exception as e:
        logger.error(f"❌ Ошибка загрузки модели LaMa: {e}")
        model_loaded = False
        return False

def opencv_inpaint(image_array, mask_array):
    """Fallback inpainting с использованием OpenCV"""
    try:
        # Конвертируем в BGR для OpenCV
        if len(image_array.shape) == 3 and image_array.shape[2] == 3:
            image_bgr = cv2.cvtColor(image_array, cv2.COLOR_RGB2BGR)
        else:
            image_bgr = image_array
            
        # Убеждаемся, что маска одноканальная
        if len(mask_array.shape) == 3:
            mask_gray = cv2.cvtColor(mask_array, cv2.COLOR_RGB2GRAY)
        else:
            mask_gray = mask_array
            
        # Применяем inpainting
        result = cv2.inpaint(image_bgr, mask_gray, 3, cv2.INPAINT_TELEA)
        
        # Конвертируем обратно в RGB
        if len(result.shape) == 3 and result.shape[2] == 3:
            result_rgb = cv2.cvtColor(result, cv2.COLOR_BGR2RGB)
        else:
            result_rgb = result
            
        return result_rgb
        
    except Exception as e:
        logger.error(f"OpenCV inpainting error: {e}")
        # Возвращаем оригинальное изображение в случае ошибки
        return image_array

@app.on_event("startup")
async def startup_event():
    """Инициализация при запуске сервера"""
    logger.info("🚀 Запуск LaMa Inpainting сервиса...")
    load_lama_model()

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {
        "status": "ok",
        "model_loaded": model_loaded,
        "service": "LaMa Inpainting API",
        "version": "1.0.0"
    }

@app.post("/inpaint")
async def inpaint_endpoint(
    image: UploadFile = File(..., description="Исходное изображение"),
    mask: UploadFile = File(..., description="Маска для inpainting (белые области будут заполнены)")
):
    """
    Основной endpoint для inpainting
    
    - **image**: Исходное изображение (PNG, JPG, JPEG)
    - **mask**: Маска inpainting (PNG, белые области = удалить)
    """
    try:
        # Проверяем типы файлов
        if not image.content_type.startswith('image/'):
            raise HTTPException(status_code=400, detail="Файл изображения должен быть в формате image/*")
        
        if not mask.content_type.startswith('image/'):
            raise HTTPException(status_code=400, detail="Файл маски должен быть в формате image/*")
        
        # Читаем файлы
        image_data = await image.read()
        mask_data = await mask.read()
        
        logger.info(f"Получены файлы: изображение {len(image_data)} байт, маска {len(mask_data)} байт")
        
        # Конвертируем в PIL Images
        img_pil = Image.open(io.BytesIO(image_data)).convert('RGB')
        mask_pil = Image.open(io.BytesIO(mask_data)).convert('RGB')
        
        # Проверяем размеры
        if img_pil.size != mask_pil.size:
            # Изменяем размер маски под изображение
            mask_pil = mask_pil.resize(img_pil.size, Image.LANCZOS)
            logger.info(f"Размер маски изменен под изображение: {img_pil.size}")
        
        # Конвертируем в numpy arrays
        img_array = np.array(img_pil)
        mask_array = np.array(mask_pil)
        
        # Обрабатываем с помощью доступной модели
        if model_loaded and lama_model:
            try:
                logger.info("Используем LaMa модель для inpainting")
                # Используем LaMa модель
                result_array = lama_model(img_array, mask_array, config=None)
            except Exception as e:
                logger.warning(f"Ошибка LaMa модели, переключаемся на OpenCV: {e}")
                result_array = opencv_inpaint(img_array, mask_array)
        else:
            logger.info("Используем OpenCV inpainting")
            result_array = opencv_inpaint(img_array, mask_array)
        
        # Конвертируем результат обратно в PIL Image
        result_pil = Image.fromarray(result_array.astype(np.uint8))
        
        # Сохраняем в буфер
        output_buffer = io.BytesIO()
        result_pil.save(output_buffer, format='PNG', quality=95)
        output_buffer.seek(0)
        
        logger.info("✅ Inpainting выполнен успешно")
        
        # Возвращаем результат как изображение
        return Response(
            content=output_buffer.getvalue(),
            media_type="image/png",
            headers={
                "Content-Disposition": "inline; filename=inpainted.png",
                "Cache-Control": "no-cache"
            }
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Ошибка inpainting: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Ошибка обработки изображения: {str(e)}"
        )

@app.get("/")
async def root():
    """Корневой endpoint с информацией о сервисе"""
    return {
        "service": "LaMa Inpainting API",
        "version": "1.0.0",
        "model_loaded": model_loaded,
        "endpoints": {
            "health": "/health",
            "inpaint": "/inpaint (POST with image and mask files)",
        },
        "usage": "POST /inpaint with 'image' and 'mask' files"
    }

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5002))
    host = os.environ.get("HOST", "127.0.0.1")
    
    logger.info(f"🚀 Запуск LaMa сервиса на {host}:{port}")
    uvicorn.run(
        app, 
        host=host, 
        port=port,
        log_level="info",
        access_log=True
    )
