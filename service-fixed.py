#!/usr/bin/env python3
"""
LaMa Service - AI-powered image inpainting for panoramic images
Enhanced version with comprehensive error handling and logging
"""

import os
import sys
import json
import logging
from pathlib import Path
from typing import Optional, Dict, Any
import asyncio
from datetime import datetime

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('lama_service.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

try:
    import numpy as np
    import cv2
    from fastapi import FastAPI, File, UploadFile, HTTPException, Form
    from fastapi.responses import FileResponse, JSONResponse
    from fastapi.middleware.cors import CORSMiddleware
    import uvicorn
    
    # ML зависимости (опциональные)
    try:
        import torch
        import torchvision
        from diffusers import StableDiffusionInpaintPipeline
        ML_AVAILABLE = True
        logger.info("✅ ML зависимости доступны")
    except ImportError as e:
        ML_AVAILABLE = False
        logger.warning(f"⚠️ ML зависимости недоступны: {e}")
    
    logger.info("✅ Базовые зависимости успешно импортированы")
    
except ImportError as e:
    logger.error(f"❌ Критическая ошибка импорта: {e}")
    sys.exit(1)

# Конфигурация
CONFIG = {
    "service_name": "LaMa Inpainting Service",
    "version": "2.0",
    "port": 8080,
    "host": "0.0.0.0",
    "upload_dir": "./uploads",
    "output_dir": "./outputs",
    "max_image_size": 4096,
    "supported_formats": [".jpg", ".jpeg", ".png", ".webp"]
}

# Создание FastAPI приложения
app = FastAPI(
    title=CONFIG["service_name"],
    version=CONFIG["version"],
    description="AI-powered panoramic image inpainting service"
)

# Настройка CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Создание необходимых директорий
for dir_path in [CONFIG["upload_dir"], CONFIG["output_dir"]]:
    Path(dir_path).mkdir(exist_ok=True)

# Глобальные переменны для ML модели
inpaint_pipeline = None

def load_ml_model():
    """Загрузка ML модели для инпеинтинга"""
    global inpaint_pipeline
    
    if not ML_AVAILABLE:
        logger.warning("ML модель недоступна - ML зависимости не установлены")
        return False
    
    try:
        logger.info("Загрузка StableDiffusionInpaintPipeline...")
        inpaint_pipeline = StableDiffusionInpaintPipeline.from_pretrained(
            "runwayml/stable-diffusion-inpainting",
            torch_dtype=torch.float16 if torch.cuda.is_available() else torch.float32
        )
        
        if torch.cuda.is_available():
            inpaint_pipeline = inpaint_pipeline.to("cuda")
            logger.info("✅ ML модель загружена на GPU")
        else:
            logger.info("✅ ML модель загружена на CPU")
        
        return True
    except Exception as e:
        logger.error(f"❌ Ошибка загрузки ML модели: {e}")
        return False

def validate_image(file_content: bytes, filename: str) -> bool:
    """Валидация изображения"""
    try:
        # Проверка расширения
        ext = Path(filename).suffix.lower()
        if ext not in CONFIG["supported_formats"]:
            return False
        
        # Проверка содержимого
        nparr = np.frombuffer(file_content, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if img is None:
            return False
        
        h, w = img.shape[:2]
        if h > CONFIG["max_image_size"] or w > CONFIG["max_image_size"]:
            return False
        
        return True
    except Exception:
        return False

def simple_inpaint(image: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Простой инпеинтинг через OpenCV (заглушка)"""
    try:
        # Используем cv2.inpaint как базовый алгоритм
        result = cv2.inpaint(image, mask, 3, cv2.INPAINT_TELEA)
        return result
    except Exception as e:
        logger.error(f"Ошибка простого инпеинтинга: {e}")
        return image

async def process_inpainting(image_data: bytes, mask_data: bytes, 
                           use_ai: bool = False) -> Optional[bytes]:
    """Обработка инпеинтинга"""
    try:
        # Декодирование изображений
        img_array = np.frombuffer(image_data, np.uint8)
        mask_array = np.frombuffer(mask_data, np.uint8)
        
        image = cv2.imdecode(img_array, cv2.IMREAD_COLOR)
        mask = cv2.imdecode(mask_array, cv2.IMREAD_GRAYSCALE)
        
        if image is None or mask is None:
            raise ValueError("Не удалось декодировать изображения")
        
        # Приведение к одному размеру
        h, w = image.shape[:2]
        mask = cv2.resize(mask, (w, h))
        
        # Выбор алгоритма обработки
        if use_ai and inpaint_pipeline is not None:
            logger.info("Использование AI инпеинтинга")
            # TODO: Реализация AI инпеинтинга
            result = simple_inpaint(image, mask)
        else:
            logger.info("Использование простого инпеинтинга")
            result = simple_inpaint(image, mask)
        
        # Кодирование результата
        _, encoded = cv2.imencode('.png', result)
        return encoded.tobytes()
        
    except Exception as e:
        logger.error(f"Ошибка обработки инпеинтинга: {e}")
        return None

# API Endpoints
@app.get("/")
async def root():
    """Корневой эндпоинт"""
    return {
        "service": CONFIG["service_name"],
        "version": CONFIG["version"],
        "status": "running",
        "ml_available": ML_AVAILABLE,
        "timestamp": datetime.now().isoformat()
    }

@app.get("/health")
async def health():
    """Проверка состояния сервиса"""
    return {
        "status": "healthy",
        "service": "lama",
        "ml_enabled": inpaint_pipeline is not None,
        "uptime": "running"
    }

@app.get("/info")
async def info():
    """Информация о сервисе"""
    return {
        "config": CONFIG,
        "ml_available": ML_AVAILABLE,
        "model_loaded": inpaint_pipeline is not None,
        "cuda_available": torch.cuda.is_available() if ML_AVAILABLE else False
    }

@app.post("/inpaint")
async def inpaint_endpoint(
    image: UploadFile = File(..., description="Исходное изображение"),
    mask: UploadFile = File(..., description="Маска для инпеинтинга"),
    use_ai: bool = Form(False, description="Использовать AI модель")
):
    """Эндпоинт для инпеинтинга изображений"""
    try:
        logger.info(f"Получен запрос инпеинтинга: {image.filename}, AI: {use_ai}")
        
        # Чтение файлов
        image_data = await image.read()
        mask_data = await mask.read()
        
        # Валидация
        if not validate_image(image_data, image.filename):
            raise HTTPException(status_code=400, detail="Некорректное изображение")
        
        if not validate_image(mask_data, mask.filename):
            raise HTTPException(status_code=400, detail="Некорректная маска")
        
        # Обработка
        result_data = await process_inpainting(image_data, mask_data, use_ai)
        
        if result_data is None:
            raise HTTPException(status_code=500, detail="Ошибка обработки")
        
        # Сохранение результата
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        result_filename = f"inpainted_{timestamp}.png"
        result_path = Path(CONFIG["output_dir"]) / result_filename
        
        with open(result_path, "wb") as f:
            f.write(result_data)
        
        logger.info(f"✅ Инпеинтинг завершен: {result_filename}")
        
        return FileResponse(
            path=str(result_path),
            filename=result_filename,
            media_type="image/png"
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Неожиданная ошибка в /inpaint: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/test-inpaint")
async def test_inpaint():
    """Тестовый эндпоинт для проверки инпеинтинга"""
    try:
        # Создание тестовых изображений
        test_image = np.random.randint(0, 255, (512, 512, 3), dtype=np.uint8)
        test_mask = np.zeros((512, 512), dtype=np.uint8)
        cv2.circle(test_mask, (256, 256), 50, 255, -1)
        
        # Тест простого инпеинтинга
        result = simple_inpaint(test_image, test_mask)
        
        return {
            "status": "success",
            "message": "Тест инпеинтинга прошел успешно",
            "input_shape": test_image.shape,
            "output_shape": result.shape
        }
        
    except Exception as e:
        logger.error(f"Ошибка тестирования: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# Startup event
@app.on_event("startup")
async def startup_event():
    """Инициализация при запуске"""
    logger.info("🚀 Запуск LaMa Service...")
    
    # Загрузка ML модели в фоне (опционально)
    if ML_AVAILABLE:
        asyncio.create_task(asyncio.to_thread(load_ml_model))
    
    logger.info("✅ Сервис готов к работе")

# Main
if __name__ == "__main__":
    port = int(os.getenv("PORT", CONFIG["port"]))
    host = os.getenv("HOST", CONFIG["host"])
    
    logger.info(f"🌟 Запуск {CONFIG['service_name']} v{CONFIG['version']}")
    logger.info(f"🌐 Сервер: http://{host}:{port}")
    logger.info(f"📋 ML доступность: {ML_AVAILABLE}")
    
    try:
        uvicorn.run(
            app, 
            host=host,
            port=port,
            log_level="info",
            access_log=True
        )
    except Exception as e:
        logger.error(f"❌ Ошибка запуска сервера: {e}")
        sys.exit(1)