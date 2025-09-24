# Multi-stage Dockerfile для Stable Diffusion сервиса
FROM python:3.11-slim as base

# Устанавливаем системные зависимости
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Создаем пользователя для безопасности
RUN useradd --create-home --shell /bin/bash app
USER app
WORKDIR /home/app

# Копируем requirements и устанавливаем зависимости
COPY --chown=app:app sd/requirements.txt ./
RUN pip install --user --no-cache-dir -r requirements.txt

# Копируем исходный код
COPY --chown=app:app sd/ ./

# Проверяем установку
RUN python -c "import torch, diffusers, transformers; print('Dependencies OK')"

# Экспонируем порт
EXPOSE 5002

# Настраиваем переменные окружения
ENV PORT=5002
ENV HOST=0.0.0.0
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/home/app/.local/lib/python3.11/site-packages

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5m --retries=3 \
    CMD curl -f http://localhost:5002/health || exit 1

# Запускаем приложение
CMD ["python", "sd_app.py"]


# Для продакшена с CUDA
FROM nvidia/cuda:11.8-runtime-ubuntu22.04 as cuda

# Устанавливаем Python и зависимости
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    git \
    curl \
    libgl1-mesa-glx \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Создаем пользователя
RUN useradd --create-home --shell /bin/bash app
USER app
WORKDIR /home/app

# Создаем виртуальное окружение
RUN python3 -m venv venv
ENV PATH="/home/app/venv/bin:$PATH"

# Устанавливаем PyTorch с CUDA
RUN pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# Копируем requirements и устанавливаем остальные зависимости
COPY --chown=app:app sd/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Копируем исходный код
COPY --chown=app:app sd/ ./

# Проверяем CUDA
RUN python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"

# Экспонируем порт
EXPOSE 5002

# Настройки
ENV PORT=5002
ENV HOST=0.0.0.0
ENV PYTHONUNBUFFERED=1

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5m --retries=3 \
    CMD curl -f http://localhost:5002/health || exit 1

# Запуск
CMD ["python", "sd_app.py"]