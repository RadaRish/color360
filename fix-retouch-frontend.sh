#!/bin/bash

# ИСПРАВЛЕНИЕ ЗАВИСАНИЙ FRONTEND РЕДАКТОРА
echo "🎯 ИСПРАВЛЕНИЕ ЗАВИСАНИЙ FRONTEND РЕДАКТОРА"
echo "=========================================="

WEBROOT="/var/www/color360"
BACKUP_DIR="/tmp/frontend-backup-$(date +%Y%m%d-%H%M%S)"

echo "📁 Создание резервной копии..."
mkdir -p "$BACKUP_DIR"
cp -r "$WEBROOT/assets" "$BACKUP_DIR/" 2>/dev/null || echo "Директория assets не найдена"
echo "Резервная копия: $BACKUP_DIR"

echo ""
echo "🔍 1. АНАЛИЗ ПРОБЛЕМ FRONTEND"
echo "============================"

echo "Поиск файлов редактора:"
find "$WEBROOT" -name "*retouch*" -o -name "*editor*" | head -10

echo ""
echo "Проверка JavaScript файлов:"
if [[ -f "$WEBROOT/assets/app.js" ]]; then
    echo "✅ app.js найден"
    APP_SIZE=$(stat -c%s "$WEBROOT/assets/app.js" 2>/dev/null || echo "0")
    echo "   Размер: $APP_SIZE байт"
else
    echo "❌ app.js не найден"
fi

echo ""
echo "🔧 2. СОЗДАНИЕ ИСПРАВЛЕННОГО RETOUCH MANAGER"
echo "==========================================="

# Создаем улучшенный retouch_manager.js с защитой от зависания
cat > "$WEBROOT/assets/retouch_manager.js" << 'EOF'
/**
 * Улучшенный менеджер ретуши с защитой от зависаний
 * Исправляет проблемы с timeout и обработкой ошибок
 */

class RetouchManager {
    constructor() {
        this.apiUrl = '/api/retouch';
        this.maxFileSize = 50 * 1024 * 1024; // 50MB
        this.timeout = 120000; // 2 минуты
        this.isProcessing = false;
        this.abortController = null;
        
        console.log('🎯 RetouchManager initialized with anti-freeze protection');
    }

    // Защищенный fetch с timeout и abort
    async fetchWithTimeout(url, options = {}) {
        // Создаем AbortController для отмены запроса
        this.abortController = new AbortController();
        
        // Таймаут для отмены запроса
        const timeoutId = setTimeout(() => {
            console.warn('⏰ Request timeout, aborting...');
            this.abortController.abort();
        }, this.timeout);

        try {
            const response = await fetch(url, {
                ...options,
                signal: this.abortController.signal
            });
            
            clearTimeout(timeoutId);
            return response;
        } catch (error) {
            clearTimeout(timeoutId);
            
            if (error.name === 'AbortError') {
                throw new Error('Request timeout - try with a smaller image or check your connection');
            }
            throw error;
        }
    }

    // Проверка размера файла
    validateFile(file) {
        if (!file) {
            throw new Error('No file selected');
        }
        
        if (file.size > this.maxFileSize) {
            throw new Error(`File too large. Maximum size is ${this.maxFileSize / 1024 / 1024}MB`);
        }
        
        if (!file.type.startsWith('image/')) {
            throw new Error('File must be an image');
        }
        
        return true;
    }

    // Создание FormData с валидацией
    createFormData(imageFile, maskCanvas) {
        this.validateFile(imageFile);
        
        const formData = new FormData();
        formData.append('image', imageFile);
        
        // Конвертируем canvas в blob
        return new Promise((resolve, reject) => {
            maskCanvas.toBlob((maskBlob) => {
                if (!maskBlob) {
                    reject(new Error('Failed to create mask'));
                    return;
                }
                
                formData.append('mask', maskBlob, 'mask.png');
                resolve(formData);
            }, 'image/png', 0.9);
        });
    }

    // Основная функция ретуши с полной защитой от зависания
    async processRetouch(imageFile, maskCanvas, progressCallback = null) {
        if (this.isProcessing) {
            throw new Error('Retouch already in progress');
        }
        
        console.log('🚀 Starting retouch process...');
        this.isProcessing = true;
        
        try {
            // Показываем прогресс
            if (progressCallback) progressCallback(0, 'Preparing files...');
            
            // Создаем FormData
            const formData = await this.createFormData(imageFile, maskCanvas);
            
            if (progressCallback) progressCallback(20, 'Uploading to server...');
            
            // Отправляем запрос с защитой от зависания
            const response = await this.fetchWithTimeout(this.apiUrl, {
                method: 'POST',
                body: formData,
                headers: {
                    'Accept': 'image/*,*/*'
                }
            });
            
            if (progressCallback) progressCallback(60, 'Processing image...');
            
            if (!response.ok) {
                let errorMsg = `Server error: ${response.status}`;
                try {
                    const errorText = await response.text();
                    errorMsg += ` - ${errorText}`;
                } catch (e) {
                    console.warn('Could not read error response');
                }
                throw new Error(errorMsg);
            }
            
            if (progressCallback) progressCallback(80, 'Downloading result...');
            
            // Получаем результат как blob
            const resultBlob = await response.blob();
            
            if (progressCallback) progressCallback(90, 'Creating result...');
            
            // Создаем URL для результата
            const resultUrl = URL.createObjectURL(resultBlob);
            
            if (progressCallback) progressCallback(100, 'Complete!');
            
            console.log('✅ Retouch completed successfully');
            return resultUrl;
            
        } catch (error) {
            console.error('❌ Retouch failed:', error);
            
            // Детальная информация об ошибке
            if (error.name === 'TypeError' && error.message.includes('fetch')) {
                throw new Error('Network error - check your connection and try again');
            } else if (error.name === 'AbortError') {
                throw new Error('Request was cancelled due to timeout');
            } else {
                throw error;
            }
        } finally {
            this.isProcessing = false;
            this.abortController = null;
            
            if (progressCallback) {
                // Небольшая задержка перед скрытием прогресса
                setTimeout(() => progressCallback(0, ''), 1000);
            }
        }
    }

    // Отмена текущей операции
    cancelRetouch() {
        if (this.abortController) {
            console.log('🛑 Cancelling retouch operation...');
            this.abortController.abort();
        }
        this.isProcessing = false;
    }

    // Проверка доступности API
    async checkApiHealth() {
        try {
            const response = await this.fetchWithTimeout('/api/retouch', {
                method: 'GET'
            });
            return response.status === 200 || response.status === 405; // 405 = Method Not Allowed это OK
        } catch (error) {
            console.warn('API health check failed:', error);
            return false;
        }
    }

    // Получение статуса
    getStatus() {
        return {
            isProcessing: this.isProcessing,
            timeout: this.timeout,
            maxFileSize: this.maxFileSize
        };
    }
}

// Глобальный экземпляр
window.retouchManager = new RetouchManager();

// Экспорт для использования в других модулях
if (typeof module !== 'undefined' && module.exports) {
    module.exports = RetouchManager;
}

console.log('✅ Enhanced RetouchManager loaded successfully');
EOF

echo "✅ Создан улучшенный retouch_manager.js"

echo ""
echo "🔧 3. СОЗДАНИЕ UI КОМПОНЕНТА РЕДАКТОРА С ЗАЩИТОЙ ОТ ЗАВИСАНИЯ"
echo "========================================================="

cat > "$WEBROOT/assets/retouch_ui.js" << 'EOF'
/**
 * UI компонент для ретуши с защитой от зависания
 */

class RetouchUI {
    constructor(container) {
        this.container = typeof container === 'string' ? document.querySelector(container) : container;
        this.canvas = null;
        this.ctx = null;
        this.maskCanvas = null;
        this.maskCtx = null;
        this.isDrawing = false;
        this.brushSize = 20;
        this.currentImage = null;
        
        this.init();
        console.log('🎨 RetouchUI initialized');
    }

    init() {
        this.createUI();
        this.bindEvents();
    }

    createUI() {
        this.container.innerHTML = `
            <div class="retouch-editor">
                <div class="editor-toolbar">
                    <button id="brush-tool" class="tool-btn active">🖌️ Brush</button>
                    <input type="range" id="brush-size" min="5" max="50" value="20">
                    <span id="brush-size-value">20px</span>
                    <button id="clear-mask">🗑️ Clear</button>
                    <button id="undo">↶ Undo</button>
                    <button id="process-btn" class="process-btn">✨ Remove Objects</button>
                    <button id="cancel-btn" class="cancel-btn" style="display:none;">❌ Cancel</button>
                </div>
                
                <div class="editor-workspace">
                    <div class="canvas-container">
                        <canvas id="main-canvas"></canvas>
                        <canvas id="mask-canvas"></canvas>
                    </div>
                </div>
                
                <div class="progress-container" style="display:none;">
                    <div class="progress-bar">
                        <div class="progress-fill"></div>
                    </div>
                    <div class="progress-text">Processing...</div>
                </div>
                
                <div class="result-container" style="display:none;">
                    <img id="result-image" alt="Processed result">
                    <div class="result-actions">
                        <button id="download-result">💾 Download</button>
                        <button id="new-edit">🔄 New Edit</button>
                    </div>
                </div>
            </div>
            
            <style>
            .retouch-editor {
                max-width: 100%;
                margin: 0 auto;
                font-family: Arial, sans-serif;
            }
            
            .editor-toolbar {
                display: flex;
                align-items: center;
                gap: 10px;
                padding: 10px;
                background: #f5f5f5;
                border-radius: 8px;
                margin-bottom: 10px;
                flex-wrap: wrap;
            }
            
            .tool-btn, .process-btn, .cancel-btn {
                padding: 8px 16px;
                border: 1px solid #ccc;
                border-radius: 4px;
                background: white;
                cursor: pointer;
                transition: all 0.2s;
            }
            
            .tool-btn.active, .tool-btn:hover {
                background: #007bff;
                color: white;
            }
            
            .process-btn {
                background: #28a745;
                color: white;
                font-weight: bold;
            }
            
            .process-btn:hover {
                background: #218838;
            }
            
            .process-btn:disabled {
                background: #6c757d;
                cursor: not-allowed;
            }
            
            .cancel-btn {
                background: #dc3545;
                color: white;
            }
            
            .canvas-container {
                position: relative;
                display: inline-block;
                border: 2px solid #ddd;
                border-radius: 8px;
                overflow: hidden;
            }
            
            #main-canvas, #mask-canvas {
                display: block;
                max-width: 100%;
                height: auto;
            }
            
            #mask-canvas {
                position: absolute;
                top: 0;
                left: 0;
                opacity: 0.7;
                pointer-events: none;
            }
            
            .progress-container {
                margin: 20px 0;
                padding: 15px;
                background: #f8f9fa;
                border-radius: 8px;
            }
            
            .progress-bar {
                width: 100%;
                height: 20px;
                background: #e9ecef;
                border-radius: 10px;
                overflow: hidden;
                margin-bottom: 10px;
            }
            
            .progress-fill {
                height: 100%;
                background: linear-gradient(90deg, #007bff, #0056b3);
                transition: width 0.3s ease;
                width: 0%;
            }
            
            .progress-text {
                text-align: center;
                font-weight: bold;
                color: #495057;
            }
            
            .result-container {
                margin-top: 20px;
                text-align: center;
            }
            
            #result-image {
                max-width: 100%;
                border: 2px solid #28a745;
                border-radius: 8px;
                margin-bottom: 15px;
            }
            
            .result-actions {
                display: flex;
                gap: 10px;
                justify-content: center;
            }
            
            @media (max-width: 768px) {
                .editor-toolbar {
                    flex-direction: column;
                    align-items: stretch;
                }
                
                .tool-btn, .process-btn, .cancel-btn {
                    width: 100%;
                    margin: 2px 0;
                }
            }
            </style>
        `;
        
        // Получаем элементы
        this.canvas = document.getElementById('main-canvas');
        this.ctx = this.canvas.getContext('2d');
        this.maskCanvas = document.getElementById('mask-canvas');
        this.maskCtx = this.maskCanvas.getContext('2d');
        
        // Настраиваем стиль рисования
        this.maskCtx.globalCompositeOperation = 'source-over';
        this.maskCtx.lineCap = 'round';
        this.maskCtx.lineJoin = 'round';
        this.maskCtx.fillStyle = 'red';
        this.maskCtx.strokeStyle = 'red';
    }

    bindEvents() {
        // Инструменты
        document.getElementById('brush-size').addEventListener('input', (e) => {
            this.brushSize = parseInt(e.target.value);
            document.getElementById('brush-size-value').textContent = this.brushSize + 'px';
        });
        
        document.getElementById('clear-mask').addEventListener('click', () => {
            this.clearMask();
        });
        
        // Рисование
        this.maskCanvas.addEventListener('mousedown', this.startDrawing.bind(this));
        this.maskCanvas.addEventListener('mousemove', this.draw.bind(this));
        this.maskCanvas.addEventListener('mouseup', this.stopDrawing.bind(this));
        this.maskCanvas.addEventListener('mouseout', this.stopDrawing.bind(this));
        
        // Touch события для мобильных
        this.maskCanvas.addEventListener('touchstart', (e) => {
            e.preventDefault();
            const touch = e.touches[0];
            const mouseEvent = new MouseEvent('mousedown', {
                clientX: touch.clientX,
                clientY: touch.clientY
            });
            this.maskCanvas.dispatchEvent(mouseEvent);
        });
        
        this.maskCanvas.addEventListener('touchmove', (e) => {
            e.preventDefault();
            const touch = e.touches[0];
            const mouseEvent = new MouseEvent('mousemove', {
                clientX: touch.clientX,
                clientY: touch.clientY
            });
            this.maskCanvas.dispatchEvent(mouseEvent);
        });
        
        this.maskCanvas.addEventListener('touchend', (e) => {
            e.preventDefault();
            const mouseEvent = new MouseEvent('mouseup', {});
            this.maskCanvas.dispatchEvent(mouseEvent);
        });
        
        // Процесс обработки
        document.getElementById('process-btn').addEventListener('click', () => {
            this.processImage();
        });
        
        document.getElementById('cancel-btn').addEventListener('click', () => {
            this.cancelProcess();
        });
        
        // Результат
        document.getElementById('download-result').addEventListener('click', () => {
            this.downloadResult();
        });
        
        document.getElementById('new-edit').addEventListener('click', () => {
            this.startNewEdit();
        });
    }

    loadImage(imageFile) {
        return new Promise((resolve, reject) => {
            const img = new Image();
            img.onload = () => {
                this.currentImage = imageFile;
                
                // Устанавливаем размеры canvas
                this.canvas.width = img.width;
                this.canvas.height = img.height;
                this.maskCanvas.width = img.width;
                this.maskCanvas.height = img.height;
                
                // Рисуем изображение
                this.ctx.drawImage(img, 0, 0);
                this.clearMask();
                
                resolve();
            };
            
            img.onerror = reject;
            img.src = URL.createObjectURL(imageFile);
        });
    }

    startDrawing(e) {
        this.isDrawing = true;
        this.draw(e);
    }

    draw(e) {
        if (!this.isDrawing) return;
        
        const rect = this.maskCanvas.getBoundingClientRect();
        const scaleX = this.maskCanvas.width / rect.width;
        const scaleY = this.maskCanvas.height / rect.height;
        
        const x = (e.clientX - rect.left) * scaleX;
        const y = (e.clientY - rect.top) * scaleY;
        
        this.maskCtx.lineWidth = this.brushSize;
        this.maskCtx.lineTo(x, y);
        this.maskCtx.stroke();
        this.maskCtx.beginPath();
        this.maskCtx.arc(x, y, this.brushSize / 2, 0, Math.PI * 2);
        this.maskCtx.fill();
        this.maskCtx.beginPath();
        this.maskCtx.moveTo(x, y);
    }

    stopDrawing() {
        if (this.isDrawing) {
            this.isDrawing = false;
            this.maskCtx.beginPath();
        }
    }

    clearMask() {
        this.maskCtx.clearRect(0, 0, this.maskCanvas.width, this.maskCanvas.height);
    }

    async processImage() {
        if (!this.currentImage) {
            alert('Please load an image first');
            return;
        }
        
        try {
            // Показываем прогресс
            this.showProgress();
            
            // Отключаем кнопку обработки
            const processBtn = document.getElementById('process-btn');
            const cancelBtn = document.getElementById('cancel-btn');
            processBtn.disabled = true;
            processBtn.style.display = 'none';
            cancelBtn.style.display = 'inline-block';
            
            // Запускаем обработку
            const resultUrl = await window.retouchManager.processRetouch(
                this.currentImage, 
                this.maskCanvas, 
                this.updateProgress.bind(this)
            );
            
            // Показываем результат
            this.showResult(resultUrl);
            
        } catch (error) {
            console.error('Processing failed:', error);
            alert(`Processing failed: ${error.message}`);
        } finally {
            // Восстанавливаем UI
            this.hideProgress();
            const processBtn = document.getElementById('process-btn');
            const cancelBtn = document.getElementById('cancel-btn');
            processBtn.disabled = false;
            processBtn.style.display = 'inline-block';
            cancelBtn.style.display = 'none';
        }
    }

    cancelProcess() {
        window.retouchManager.cancelRetouch();
        this.hideProgress();
        
        const processBtn = document.getElementById('process-btn');
        const cancelBtn = document.getElementById('cancel-btn');
        processBtn.disabled = false;
        processBtn.style.display = 'inline-block';
        cancelBtn.style.display = 'none';
    }

    showProgress() {
        document.querySelector('.progress-container').style.display = 'block';
        document.querySelector('.result-container').style.display = 'none';
    }

    hideProgress() {
        document.querySelector('.progress-container').style.display = 'none';
    }

    updateProgress(percent, message) {
        const fill = document.querySelector('.progress-fill');
        const text = document.querySelector('.progress-text');
        
        fill.style.width = percent + '%';
        text.textContent = message || `Processing... ${percent}%`;
    }

    showResult(imageUrl) {
        const resultImg = document.getElementById('result-image');
        resultImg.src = imageUrl;
        document.querySelector('.result-container').style.display = 'block';
        this.resultUrl = imageUrl;
    }

    downloadResult() {
        if (this.resultUrl) {
            const a = document.createElement('a');
            a.href = this.resultUrl;
            a.download = 'retouched_image.png';
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
        }
    }

    startNewEdit() {
        document.querySelector('.result-container').style.display = 'none';
        this.clearMask();
        if (this.resultUrl) {
            URL.revokeObjectURL(this.resultUrl);
            this.resultUrl = null;
        }
    }
}

// Глобальное создание UI
window.RetouchUI = RetouchUI;

console.log('✅ Enhanced RetouchUI loaded successfully');
EOF

echo "✅ Создан улучшенный retouch_ui.js"

echo ""
echo "🔧 4. ОБНОВЛЕНИЕ ОСНОВНОГО APP.JS"
echo "================================="

# Добавляем подключение новых модулей в app.js если он существует
if [[ -f "$WEBROOT/assets/app.js" ]]; then
    echo "Обновление существующего app.js..."
    
    # Проверяем, не добавлены ли уже наши модули
    if ! grep -q "retouch_manager.js" "$WEBROOT/assets/app.js"; then
        cat >> "$WEBROOT/assets/app.js" << 'EOF'

// Улучшенные модули ретуши с защитой от зависания
document.addEventListener('DOMContentLoaded', function() {
    console.log('🔧 Loading enhanced retouch modules...');
    
    // Загружаем модули ретуши если нужно
    if (typeof window.retouchManager === 'undefined') {
        const script1 = document.createElement('script');
        script1.src = '/assets/retouch_manager.js';
        script1.onload = () => console.log('✅ RetouchManager loaded');
        document.head.appendChild(script1);
    }
    
    if (typeof window.RetouchUI === 'undefined') {
        const script2 = document.createElement('script');
        script2.src = '/assets/retouch_ui.js';
        script2.onload = () => console.log('✅ RetouchUI loaded');
        document.head.appendChild(script2);
    }
    
    // Инициализация редактора ретуши если контейнер существует
    const retouchContainer = document.getElementById('retouch-editor-container');
    if (retouchContainer && typeof RetouchUI !== 'undefined') {
        window.retouchUI = new RetouchUI(retouchContainer);
        console.log('✅ Retouch editor initialized');
    }
    
    // Обработчик для файлового input
    const fileInput = document.getElementById('image-upload');
    if (fileInput && window.retouchUI) {
        fileInput.addEventListener('change', async function(e) {
            const file = e.target.files[0];
            if (file) {
                try {
                    await window.retouchUI.loadImage(file);
                    console.log('✅ Image loaded successfully');
                } catch (error) {
                    console.error('❌ Failed to load image:', error);
                    alert('Failed to load image: ' + error.message);
                }
            }
        });
    }
});
EOF
        echo "✅ app.js обновлен с новыми модулями"
    else
        echo "ℹ️ Модули уже добавлены в app.js"
    fi
else
    echo "⚠️ app.js не найден, создаем базовый"
    cat > "$WEBROOT/assets/app.js" << 'EOF'
// Основное приложение Color360 с поддержкой ретуши
console.log('🚀 Color360 App starting...');

document.addEventListener('DOMContentLoaded', function() {
    console.log('✅ DOM loaded, initializing components...');
    
    // Загрузка модулей ретуши
    const retouchContainer = document.getElementById('retouch-editor-container');
    if (retouchContainer) {
        // Инициализируем редактор ретуши когда модули загружены
        function initRetouchEditor() {
            if (typeof RetouchUI !== 'undefined') {
                window.retouchUI = new RetouchUI(retouchContainer);
                console.log('✅ Retouch editor initialized');
                
                // Обработчик загрузки изображений
                const fileInput = document.getElementById('image-upload');
                if (fileInput) {
                    fileInput.addEventListener('change', async function(e) {
                        const file = e.target.files[0];
                        if (file) {
                            try {
                                await window.retouchUI.loadImage(file);
                                console.log('✅ Image loaded for editing');
                            } catch (error) {
                                console.error('❌ Failed to load image:', error);
                                alert('Failed to load image: ' + error.message);
                            }
                        }
                    });
                }
            } else {
                // Повторяем попытку через 100мс
                setTimeout(initRetouchEditor, 100);
            }
        }
        
        initRetouchEditor();
    }
});
EOF
    echo "✅ Создан базовый app.js"
fi

echo ""
echo "🔧 5. УСТАНОВКА ПРАВИЛЬНЫХ ПРАВ"
echo "==============================="

chown -R www-data:www-data "$WEBROOT/assets"
chmod 644 "$WEBROOT/assets"/*.js

echo "✅ Права установлены"

echo ""
echo "🧪 6. ТЕСТИРОВАНИЕ FRONTEND ИСПРАВЛЕНИЙ"
echo "======================================"

echo "Проверка созданных файлов:"
for file in retouch_manager.js retouch_ui.js app.js; do
    if [[ -f "$WEBROOT/assets/$file" ]]; then
        size=$(stat -c%s "$WEBROOT/assets/$file")
        echo "✅ $file ($size байт)"
    else
        echo "❌ $file не найден"
    fi
done

echo ""
echo "🎯 7. ИТОГОВЫЕ РЕКОМЕНДАЦИИ"
echo "=========================="

echo ""
echo "✅ FRONTEND ИСПРАВЛЕНИЯ ПРИМЕНЕНЫ:"
echo "- Создан RetouchManager с защитой от timeout"
echo "- Добавлена система отмены запросов (AbortController)"
echo "- Улучшена обработка ошибок"
echo "- Добавлены индикаторы прогресса"
echo "- Исправлены проблемы с большими файлами"

echo ""
echo "🧪 СЛЕДУЮЩИЕ ШАГИ ДЛЯ ТЕСТИРОВАНИЯ:"
echo "1. Откройте редактор в браузере"
echo "2. Откройте консоль разработчика (F12)"
echo "3. Загрузите небольшое изображение (< 5MB)"
echo "4. Выделите область для удаления"
echo "5. Нажмите 'Готово' и следите за прогрессом"

echo ""
echo "🔍 ДИАГНОСТИКА ЕСЛИ ПРОБЛЕМА ОСТАЕТСЯ:"
echo "- Проверьте консоль браузера на JavaScript ошибки"
echo "- Убедитесь что LaMa API работает: bash diagnose-retouch-freeze.sh"
echo "- Попробуйте режим инкогнито"
echo "- Очистите кэш браузера (Ctrl+Shift+R)"

echo ""
echo "📋 Резервная копия сохранена в: $BACKUP_DIR"