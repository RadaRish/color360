#!/bin/bash

# ЭКСТРЕННОЕ ИСПРАВЛЕНИЕ ПРОБЛЕМ ПОСЛЕ ПЕРВОГО ЗАПУСКА
echo "🚨 ЭКСТРЕННОЕ ИСПРАВЛЕНИЕ ПРОБЛЕМ РЕТУШИ"
echo "======================================="

echo ""
echo "🔍 1. СОЗДАНИЕ НЕДОСТАЮЩИХ СКРИПТОВ"
echo "==================================="

echo "Загружаем недостающие файлы из репозитория..."

# Создаем diagnose-retouch-freeze.sh
echo "Создание diagnose-retouch-freeze.sh..."
cat > diagnose-retouch-freeze.sh << 'DIAGEOF'
#!/bin/bash

# ДИАГНОСТИКА ЗАВИСАНИЯ РЕДАКТОРА РЕТУШИ
echo "🔧 ДИАГНОСТИКА ЗАВИСАНИЯ РЕДАКТОРА РЕТУШИ"
echo "========================================="

echo "🔍 1. ПРОВЕРКА СТАТУСА LAMA СЕРВИСА"
echo "==================================="

echo "Поиск процессов LaMa:"
LAMA_PID=$(pgrep -f "lama_cleaner\|service.py\|lama-service" | head -1)
if [[ -n "$LAMA_PID" ]]; then
    echo "✅ LaMa процесс найден (PID: $LAMA_PID)"
    ps aux | grep -E "lama_cleaner|service.py|lama" | grep -v grep
else
    echo "❌ LaMa процесс не найден!"
fi

echo ""
echo "Проверка порта 8080 (LaMa API):"
if netstat -tuln 2>/dev/null | grep -q ":8080 "; then
    echo "✅ Порт 8080 слушается"
    netstat -tuln | grep ":8080"
else
    echo "❌ Порт 8080 не слушается!"
fi

echo ""
echo "🌐 2. ТЕСТИРОВАНИЕ LAMA API"
echo "==========================="

echo "Тест доступности API локально:"
LOCAL_API_TEST=$(curl -s -w "%{http_code}" -m 10 "http://127.0.0.1:8080/api/v1/info" -o /dev/null 2>/dev/null)
if [[ "$LOCAL_API_TEST" == "200" ]]; then
    echo "✅ LaMa API доступен локально (HTTP $LOCAL_API_TEST)"
else
    echo "❌ LaMa API недоступен локально (HTTP $LOCAL_API_TEST)"
fi

echo ""
echo "Тест через nginx proxy:"
PROXY_API_TEST=$(curl -s -w "%{http_code}" -m 10 "https://color360.ru/api/retouch" -o /dev/null -k 2>/dev/null)
if [[ "$PROXY_API_TEST" == "200" || "$PROXY_API_TEST" == "405" ]]; then
    echo "✅ Nginx proxy работает (HTTP $PROXY_API_TEST)"
else
    echo "❌ Nginx proxy не работает (HTTP $PROXY_API_TEST)"
fi

echo ""
echo "📋 3. ПОИСК LAMA УСТАНОВКИ"
echo "=========================="

echo "Поиск LaMa установки в системе:"
find /usr -name "*lama*" -type f 2>/dev/null | head -10
find /opt -name "*lama*" -type f 2>/dev/null | head -10
find /home -name "*lama*" -type d 2>/dev/null | head -5

echo ""
echo "Поиск Python пакетов:"
pip list | grep -i lama 2>/dev/null || echo "pip не найден или LaMa не установлен"
pip3 list | grep -i lama 2>/dev/null || echo "pip3 не найден или LaMa не установлен"

echo "Проверка systemd сервисов:"
systemctl list-units --all | grep -i lama || echo "Systemd сервисы LaMa не найдены"

echo ""
echo "🔧 4. АВТОМАТИЧЕСКОЕ ИСПРАВЛЕНИЕ"
echo "==============================="

if [[ "$LOCAL_API_TEST" != "200" ]]; then
    echo "❌ LaMa API недоступен, попытка запуска..."
    
    # Поиск и запуск LaMa
    if command -v lama-cleaner >/dev/null 2>&1; then
        echo "Найден lama-cleaner, запускаем..."
        nohup lama-cleaner --model=lama --device=cpu --port=8080 --host=127.0.0.1 > /tmp/lama.log 2>&1 &
        echo "LaMa запущен в фоне"
        sleep 5
    elif [[ -f "/tmp/lama/service.py" ]]; then
        echo "Найден service.py, запускаем..."
        cd /tmp/lama
        nohup python3 service.py > /tmp/lama.log 2>&1 &
        echo "LaMa service.py запущен"
        sleep 5
    else
        echo "❌ LaMa не найден в системе!"
    fi
fi

echo "✅ Диагностика завершена"
DIAGEOF

chmod +x diagnose-retouch-freeze.sh

# Создаем fix-retouch-frontend.sh
echo "Создание fix-retouch-frontend.sh..."
cat > fix-retouch-frontend.sh << 'FRONTEOF'
#!/bin/bash

# ИСПРАВЛЕНИЕ FRONTEND РЕДАКТОРА
echo "🎯 ИСПРАВЛЕНИЕ FRONTEND РЕДАКТОРА РЕТУШИ"
echo "========================================"

WEBROOT="/var/www/color360"
BACKUP_DIR="/tmp/frontend-backup-$(date +%Y%m%d-%H%M%S)"

echo "📁 Создание резервной копии..."
mkdir -p "$BACKUP_DIR"
[[ -d "$WEBROOT/assets" ]] && cp -r "$WEBROOT/assets" "$BACKUP_DIR/" 2>/dev/null
echo "Резервная копия: $BACKUP_DIR"

echo ""
echo "🔧 1. СОЗДАНИЕ УЛУЧШЕННОГО RETOUCH MANAGER"
echo "=========================================="

mkdir -p "$WEBROOT/assets"

# Создаем улучшенный retouch_manager.js
cat > "$WEBROOT/assets/retouch_manager.js" << 'RETOUCHJS'
/**
 * Улучшенный менеджер ретуши с защитой от зависаний
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
        this.abortController = new AbortController();
        
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
                throw new Error('Request timeout - try with a smaller image');
            }
            throw error;
        }
    }

    // Проверка размера файла
    validateFile(file) {
        if (!file) throw new Error('No file selected');
        if (file.size > this.maxFileSize) {
            throw new Error(`File too large. Maximum size is ${this.maxFileSize / 1024 / 1024}MB`);
        }
        if (!file.type.startsWith('image/')) throw new Error('File must be an image');
        return true;
    }

    // Создание FormData
    createFormData(imageFile, maskCanvas) {
        this.validateFile(imageFile);
        
        const formData = new FormData();
        formData.append('image', imageFile);
        
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

    // Основная функция ретуши
    async processRetouch(imageFile, maskCanvas, progressCallback = null) {
        if (this.isProcessing) throw new Error('Retouch already in progress');
        
        console.log('🚀 Starting retouch process...');
        this.isProcessing = true;
        
        try {
            if (progressCallback) progressCallback(10, 'Preparing files...');
            
            const formData = await this.createFormData(imageFile, maskCanvas);
            
            if (progressCallback) progressCallback(30, 'Uploading to server...');
            
            const response = await this.fetchWithTimeout(this.apiUrl, {
                method: 'POST',
                body: formData,
                headers: { 'Accept': 'image/*,*/*' }
            });
            
            if (progressCallback) progressCallback(70, 'Processing image...');
            
            if (!response.ok) {
                let errorMsg = `Server error: ${response.status}`;
                try {
                    const errorText = await response.text();
                    errorMsg += ` - ${errorText}`;
                } catch (e) {}
                throw new Error(errorMsg);
            }
            
            if (progressCallback) progressCallback(90, 'Downloading result...');
            
            const resultBlob = await response.blob();
            const resultUrl = URL.createObjectURL(resultBlob);
            
            if (progressCallback) progressCallback(100, 'Complete!');
            
            console.log('✅ Retouch completed successfully');
            return resultUrl;
            
        } catch (error) {
            console.error('❌ Retouch failed:', error);
            throw error;
        } finally {
            this.isProcessing = false;
            this.abortController = null;
            
            if (progressCallback) {
                setTimeout(() => progressCallback(0, ''), 1000);
            }
        }
    }

    // Отмена операции
    cancelRetouch() {
        if (this.abortController) {
            console.log('🛑 Cancelling retouch operation...');
            this.abortController.abort();
        }
        this.isProcessing = false;
    }

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
console.log('✅ Enhanced RetouchManager loaded successfully');
RETOUCHJS

echo "✅ Создан retouch_manager.js"

echo ""
echo "🔧 2. СОЗДАНИЕ UI КОМПОНЕНТА"
echo "============================"

# Создаем retouch_ui.js (упрощенная версия)
cat > "$WEBROOT/assets/retouch_ui.js" << 'UIJS'
/**
 * UI компонент для ретуши
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
        
        if (this.container) {
            this.init();
            console.log('🎨 RetouchUI initialized');
        }
    }

    init() {
        this.createUI();
        this.bindEvents();
    }

    createUI() {
        this.container.innerHTML = `
            <div class="retouch-editor" style="max-width:100%;font-family:Arial,sans-serif;">
                <div class="editor-toolbar" style="display:flex;gap:10px;padding:10px;background:#f5f5f5;border-radius:8px;margin-bottom:10px;">
                    <input type="range" id="brush-size" min="5" max="50" value="20" style="width:100px;">
                    <span id="brush-size-value">20px</span>
                    <button id="clear-mask" style="padding:5px 10px;">Clear</button>
                    <button id="process-btn" style="padding:8px 16px;background:#28a745;color:white;border:none;border-radius:4px;cursor:pointer;">Remove Objects</button>
                    <button id="cancel-btn" style="display:none;padding:8px 16px;background:#dc3545;color:white;border:none;border-radius:4px;cursor:pointer;">Cancel</button>
                </div>
                
                <div class="canvas-container" style="position:relative;border:2px solid #ddd;border-radius:8px;display:inline-block;">
                    <canvas id="main-canvas" style="display:block;max-width:100%;"></canvas>
                    <canvas id="mask-canvas" style="position:absolute;top:0;left:0;opacity:0.7;"></canvas>
                </div>
                
                <div class="progress-container" style="display:none;margin:20px 0;padding:15px;background:#f8f9fa;border-radius:8px;">
                    <div class="progress-bar" style="width:100%;height:20px;background:#e9ecef;border-radius:10px;overflow:hidden;margin-bottom:10px;">
                        <div class="progress-fill" style="height:100%;background:#007bff;transition:width 0.3s;width:0%;"></div>
                    </div>
                    <div class="progress-text" style="text-align:center;font-weight:bold;">Processing...</div>
                </div>
                
                <div class="result-container" style="display:none;margin-top:20px;text-align:center;">
                    <img id="result-image" style="max-width:100%;border:2px solid #28a745;border-radius:8px;margin-bottom:15px;">
                    <div>
                        <button id="download-result" style="padding:8px 16px;margin:5px;background:#007bff;color:white;border:none;border-radius:4px;cursor:pointer;">Download</button>
                        <button id="new-edit" style="padding:8px 16px;margin:5px;background:#6c757d;color:white;border:none;border-radius:4px;cursor:pointer;">New Edit</button>
                    </div>
                </div>
            </div>
        `;
        
        this.canvas = document.getElementById('main-canvas');
        this.ctx = this.canvas.getContext('2d');
        this.maskCanvas = document.getElementById('mask-canvas');
        this.maskCtx = this.maskCanvas.getContext('2d');
        
        this.maskCtx.globalCompositeOperation = 'source-over';
        this.maskCtx.lineCap = 'round';
        this.maskCtx.lineJoin = 'round';
        this.maskCtx.fillStyle = 'red';
        this.maskCtx.strokeStyle = 'red';
    }

    bindEvents() {
        document.getElementById('brush-size').addEventListener('input', (e) => {
            this.brushSize = parseInt(e.target.value);
            document.getElementById('brush-size-value').textContent = this.brushSize + 'px';
        });
        
        document.getElementById('clear-mask').addEventListener('click', () => {
            this.clearMask();
        });
        
        this.maskCanvas.addEventListener('mousedown', this.startDrawing.bind(this));
        this.maskCanvas.addEventListener('mousemove', this.draw.bind(this));
        this.maskCanvas.addEventListener('mouseup', this.stopDrawing.bind(this));
        
        document.getElementById('process-btn').addEventListener('click', () => {
            this.processImage();
        });
        
        document.getElementById('cancel-btn').addEventListener('click', () => {
            this.cancelProcess();
        });
        
        document.getElementById('download-result').addEventListener('click', () => {
            this.downloadResult();
        });
        
        document.getElementById('new-edit').addEventListener('click', () => {
            this.startNewEdit();
        });
    }

    async loadImage(imageFile) {
        return new Promise((resolve, reject) => {
            const img = new Image();
            img.onload = () => {
                this.currentImage = imageFile;
                
                this.canvas.width = img.width;
                this.canvas.height = img.height;
                this.maskCanvas.width = img.width;
                this.maskCanvas.height = img.height;
                
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
            this.showProgress();
            
            const processBtn = document.getElementById('process-btn');
            const cancelBtn = document.getElementById('cancel-btn');
            processBtn.disabled = true;
            processBtn.style.display = 'none';
            cancelBtn.style.display = 'inline-block';
            
            const resultUrl = await window.retouchManager.processRetouch(
                this.currentImage, 
                this.maskCanvas, 
                this.updateProgress.bind(this)
            );
            
            this.showResult(resultUrl);
            
        } catch (error) {
            console.error('Processing failed:', error);
            alert(`Processing failed: ${error.message}`);
        } finally {
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
        
        if (fill) fill.style.width = percent + '%';
        if (text) text.textContent = message || `Processing... ${percent}%`;
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

window.RetouchUI = RetouchUI;
console.log('✅ Enhanced RetouchUI loaded successfully');
UIJS

echo "✅ Создан retouch_ui.js"

# Установка прав
chown -R www-data:www-data "$WEBROOT/assets" 2>/dev/null || true
chmod 644 "$WEBROOT/assets"/*.js 2>/dev/null || true

echo "✅ Frontend файлы созданы и права установлены"
FRONTEOF

chmod +x fix-retouch-frontend.sh

echo "✅ Недостающие скрипты созданы"

echo ""
echo "🔧 2. ИСПРАВЛЕНИЕ LAMA СЕРВИСА"
echo "=============================="

# Запускаем диагностику
echo "Запуск диагностики..."
bash diagnose-retouch-freeze.sh

echo ""
echo "🔧 3. УСТАНОВКА И ЗАПУСК LAMA"
echo "============================"

# Проверяем есть ли LaMa
if ! command -v lama-cleaner >/dev/null 2>&1; then
    echo "LaMa-cleaner не найден, устанавливаем..."
    
    # Проверяем Python
    if command -v python3 >/dev/null 2>&1; then
        echo "Установка LaMa через pip..."
        pip3 install lama-cleaner[cpu] 2>/dev/null || pip install lama-cleaner[cpu] 2>/dev/null
        
        if command -v lama-cleaner >/dev/null 2>&1; then
            echo "✅ LaMa-cleaner установлен"
        else
            echo "❌ Ошибка установки LaMa"
        fi
    else
        echo "❌ Python3 не найден!"
    fi
else
    echo "✅ LaMa-cleaner уже установлен"
fi

echo ""
echo "🚀 4. ЗАПУСК LAMA СЕРВИСА"
echo "========================"

# Останавливаем существующие процессы
pkill -f "lama_cleaner" 2>/dev/null
pkill -f "service.py" 2>/dev/null
sleep 2

# Запускаем LaMa
if command -v lama-cleaner >/dev/null 2>&1; then
    echo "Запуск lama-cleaner..."
    nohup lama-cleaner --model=lama --device=cpu --port=8080 --host=127.0.0.1 --no-gui > /tmp/lama.log 2>&1 &
    LAMA_PID=$!
    echo "LaMa запущен с PID: $LAMA_PID"
elif [[ -f "/tmp/lama/service.py" ]]; then
    echo "Запуск service.py..."
    cd /tmp/lama
    nohup python3 service.py > /tmp/lama.log 2>&1 &
    LAMA_PID=$!
    echo "LaMa service запущен с PID: $LAMA_PID"
else
    echo "❌ LaMa не найден!"
fi

echo ""
echo "⏱️ 5. ОЖИДАНИЕ ЗАПУСКА И ТЕСТИРОВАНИЕ"
echo "====================================="

echo "Ожидание запуска LaMa (15 секунд)..."
sleep 15

# Тестирование
echo "Тест LaMa API:"
API_TEST=$(curl -s -w "%{http_code}" -m 15 "http://127.0.0.1:8080" -o /dev/null 2>/dev/null)
if [[ "$API_TEST" == "200" ]]; then
    echo "✅ LaMa API работает (HTTP $API_TEST)"
else
    echo "❌ LaMa API не отвечает (HTTP $API_TEST)"
    echo "Проверяем лог:"
    tail -10 /tmp/lama.log 2>/dev/null || echo "Лог недоступен"
fi

echo ""
echo "🔧 6. ИСПРАВЛЕНИЕ FRONTEND"
echo "========================="

bash fix-retouch-frontend.sh

echo ""
echo "🧪 7. ФИНАЛЬНАЯ ПРОВЕРКА"
echo "======================="

echo "Frontend файлы:"
WEBROOT="/var/www/color360"
for file in retouch_manager.js retouch_ui.js; do
    if [[ -f "$WEBROOT/assets/$file" ]]; then
        size=$(stat -c%s "$WEBROOT/assets/$file" 2>/dev/null || echo "0")
        echo "✅ $file ($size байт)"
    else
        echo "❌ $file отсутствует"
    fi
done

echo ""
echo "LaMa API:"
FINAL_API_TEST=$(curl -s -w "%{http_code}" -m 10 "http://127.0.0.1:8080" -o /dev/null 2>/dev/null)
if [[ "$FINAL_API_TEST" == "200" ]]; then
    echo "✅ LaMa API работает"
else
    echo "❌ LaMa API не работает (код: $FINAL_API_TEST)"
fi

echo ""
echo "🎯 РЕЗУЛЬТАТЫ ЭКСТРЕННОГО ИСПРАВЛЕНИЯ"
echo "===================================="

SUCCESS=0
if [[ -f "$WEBROOT/assets/retouch_manager.js" ]]; then ((SUCCESS++)); fi
if [[ -f "$WEBROOT/assets/retouch_ui.js" ]]; then ((SUCCESS++)); fi
if [[ "$FINAL_API_TEST" == "200" ]]; then ((SUCCESS++)); fi

if [[ $SUCCESS -eq 3 ]]; then
    echo ""
    echo "🎉 ВСЕ ИСПРАВЛЕНО УСПЕШНО!"
    echo ""
    echo "✅ Что работает:"
    echo "   🎯 LaMa API отвечает на порту 8080"
    echo "   💻 Frontend файлы созданы"
    echo "   🛡️ Защита от зависания добавлена"
    echo ""
    echo "🧪 ТЕСТИРУЙТЕ РЕДАКТОР:"
    echo "1. Откройте https://color360.ru/pano/"
    echo "2. Перейдите в редактор"
    echo "3. Загрузите небольшое изображение"
    echo "4. Выделите область"
    echo "5. Нажмите 'Remove Objects'"
    echo "6. Следите за прогресс-баром"
else
    echo ""
    echo "⚠️ ЧАСТИЧНО ИСПРАВЛЕНО ($SUCCESS/3)"
    echo ""
    if [[ ! -f "$WEBROOT/assets/retouch_manager.js" ]]; then
        echo "❌ Frontend файлы не созданы"
    fi
    if [[ "$FINAL_API_TEST" != "200" ]]; then
        echo "❌ LaMa API не работает"
        echo "   Лог: tail -f /tmp/lama.log"
    fi
fi

echo ""
echo "📋 Мониторинг:"
echo "- tail -f /tmp/lama.log (логи LaMa)"
echo "- ps aux | grep lama (процессы)"
echo "- curl http://127.0.0.1:8080 (тест API)"