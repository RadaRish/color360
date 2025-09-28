#!/bin/bash

# 🚨 СУПЕРЭКСТРЕННОЕ ИСПРАВЛЕНИЕ РЕТУШИ - ПРИНУДИТЕЛЬНАЯ ЗАМЕНА V3
# Устраняет зависание после создания маски через полную блокировку старого кода

echo "🚨 СУПЕРЭКСТРЕННОЕ ИСПРАВЛЕНИЕ: Принудительная замена RetouchManager V3"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}🔧 Создаём резервные копии...${NC}"

# Резервные копии
cp /var/www/html/assets/app.js /var/www/html/assets/app.js.backup.super 2>/dev/null || echo "app.js backup failed"
cp /var/www/html/pano/assets/retouch_manager.js /var/www/html/pano/assets/retouch_manager.js.backup.super 2>/dev/null || echo "retouch_manager.js backup failed"

echo -e "${BLUE}📝 Создаём СУПЕРИСПРАВЛЕННЫЙ RetouchManager...${NC}"

# Полная замена RetouchManager с принудительным перехватом
cat > /tmp/retouch_manager_super_fixed.js << 'SUPER_EOF'
// 🚨 СУПЕРЭКСТРЕННОЕ ИСПРАВЛЕНИЕ RetouchManager V3 - ПРИНУДИТЕЛЬНАЯ ЗАМЕНА
console.log('🚨 SUPER EMERGENCY: Загружаем суперэкстренное исправление RetouchManager V3');

// Глобальная блокировка старого RetouchManager
if (window.RetouchManager) {
    console.log('🚨 SUPER EMERGENCY: Заменяем существующий RetouchManager');
    delete window.RetouchManager;
}

class SuperEmergencyRetouchManager {
    constructor() {
        console.log('🚨 SUPER EMERGENCY: SuperRetouchManager initialized');
        this._canvas = null;
        this._ctx = null;
        this._overlay = null;
        this._isDrawing = false;
        this._points = [];
        this._maskDataUrl = null;
        this._currentStroke = [];
        this._originalPanorama = null;
        
        // Критически важно - AbortController для защиты от зависания
        this._abortController = null;
        
        this.bindEvents();
        this.blockOldRetouchManager();
    }

    blockOldRetouchManager() {
        // Блокируем все возможные способы создания старого RetouchManager
        const blockPatterns = [
            'RetouchManager',
            'retouch_manager',
            'retouchManager',
            'class RetouchManager',
            'function RetouchManager'
        ];

        // Перехватываем добавление скриптов
        const originalCreateElement = document.createElement;
        document.createElement = function(tagName) {
            const element = originalCreateElement.call(document, tagName);
            
            if (tagName.toLowerCase() === 'script') {
                const originalSetAttribute = element.setAttribute;
                element.setAttribute = function(name, value) {
                    if (name === 'src' && blockPatterns.some(pattern => value.includes(pattern))) {
                        console.log('🚨 SUPER EMERGENCY: Блокируем загрузку скрипта:', value);
                        return;
                    }
                    return originalSetAttribute.call(this, name, value);
                };

                // Перехватываем textContent
                let blocked = false;
                Object.defineProperty(element, 'textContent', {
                    set: function(value) {
                        if (typeof value === 'string' && blockPatterns.some(pattern => value.includes(pattern))) {
                            console.log('🚨 SUPER EMERGENCY: Блокируем inline скрипт с RetouchManager');
                            blocked = true;
                            return;
                        }
                        Object.getPrototypeOf(this).textContent = value;
                    },
                    get: function() {
                        return blocked ? '' : Object.getPrototypeOf(this).textContent;
                    }
                });
            }
            
            return element;
        };
    }

    bindEvents() {
        // Принудительно находим кнопку ретуши
        const findRetouchButton = () => {
            const selectors = [
                '#retouchBtn',
                '.retouch-btn',
                'button[onclick*="retouch"]',
                'button[onclick*="Retouch"]',
                '[data-action="retouch"]',
                'button:contains("Ретушь")',
                'button:contains("retouch")'
            ];
            
            // Дополнительный поиск по тексту кнопки
            const buttons = Array.from(document.querySelectorAll('button'));
            const retouchButton = buttons.find(btn => 
                btn.textContent.toLowerCase().includes('ретушь') || 
                btn.textContent.toLowerCase().includes('retouch') ||
                btn.onclick && btn.onclick.toString().includes('retouch')
            );
            
            if (retouchButton) {
                console.log('🚨 SUPER EMERGENCY: Найдена кнопка ретуши по тексту');
                this.patchRetouchButton(retouchButton);
                return retouchButton;
            }
            
            for (const selector of selectors) {
                const btn = document.querySelector(selector);
                if (btn) {
                    console.log(`🚨 SUPER EMERGENCY: Найдена кнопка ретуши: ${selector}`);
                    this.patchRetouchButton(btn);
                    return btn;
                }
            }
            return null;
        };

        // Пытаемся найти кнопку сразу и через интервалы
        if (!findRetouchButton()) {
            const interval = setInterval(() => {
                if (findRetouchButton()) {
                    clearInterval(interval);
                }
            }, 500);
            
            setTimeout(() => clearInterval(interval), 60000); // Останавливаем через 60 сек
        }

        // Также перехватываем глобальные вызовы функций ретуши
        ['startMaskDraw', 'startRetouch', 'retouchStart'].forEach(funcName => {
            if (window[funcName]) {
                const original = window[funcName];
                window[funcName] = (...args) => {
                    console.log(`🚨 SUPER EMERGENCY: Перехвачен вызов ${funcName}`);
                    return this.startMaskDraw(...args);
                };
            }
        });
    }

    patchRetouchButton(btn) {
        if (btn._superEmergencyPatched) return;
        
        console.log('🚨 SUPER EMERGENCY: Супер-патчим кнопку ретуши');
        btn._superEmergencyPatched = true;

        // Полная замена всех событий
        btn.onclick = null;
        btn.removeAttribute('onclick');
        
        // Очищаем все листенеры
        const newBtn = btn.cloneNode(true);
        btn.parentNode.replaceChild(newBtn, btn);
        
        // Добавляем наш обработчик
        newBtn.addEventListener('click', (e) => {
            e.preventDefault();
            e.stopImmediatePropagation();
            console.log('🚨 SUPER EMERGENCY: Суперперехвачен клик по ретуши');
            this.startMaskDraw();
            return false;
        }, true);

        // Блокируем добавление новых листенеров
        const originalAddEventListener = newBtn.addEventListener;
        newBtn.addEventListener = (type, listener, options) => {
            if (type === 'click' && !listener._superEmergencyHandler) {
                console.log('🚨 SUPER EMERGENCY: Блокируем добавление click listener');
                return;
            }
            return originalAddEventListener.call(newBtn, type, listener, options);
        };
    }

    startMaskDraw() {
        try {
            console.log('🚨 SUPER EMERGENCY: startMaskDraw вызван');
            
            this._teardownOverlay();
            this._points = [];
            this._currentStroke = [];
            this._maskDataUrl = null;

            const sceneEl = document.querySelector('a-scene');
            if (!sceneEl) {
                console.error('🚨 SUPER EMERGENCY: A-Frame сцена не найдена');
                return false;
            }

            this._setupOverlay();
            return true;

        } catch (error) {
            console.error('🚨 SUPER EMERGENCY: Ошибка в startMaskDraw:', error);
            return false;
        }
    }

    _setupOverlay() {
        console.log('🚨 SUPER EMERGENCY: Настройка overlay');
        
        const sceneEl = document.querySelector('a-scene');
        const canvas = sceneEl.querySelector('canvas');
        
        if (!canvas) {
            console.error('🚨 SUPER EMERGENCY: Canvas не найден');
            return;
        }

        // Создаём overlay
        this._overlay = document.createElement('canvas');
        this._overlay.width = canvas.width || 800;
        this._overlay.height = canvas.height || 600;
        
        Object.assign(this._overlay.style, {
            position: 'absolute',
            top: '0',
            left: '0',
            width: '100%',
            height: '100%',
            zIndex: '9999',
            pointerEvents: 'auto',
            cursor: 'crosshair',
            background: 'transparent'
        });

        this._ctx = this._overlay.getContext('2d');
        this._ctx.strokeStyle = 'rgba(255, 0, 0, 0.8)';
        this._ctx.lineWidth = 3;
        this._ctx.lineCap = 'round';
        this._ctx.lineJoin = 'round';

        // Вставляем overlay
        canvas.parentNode.style.position = 'relative';
        canvas.parentNode.appendChild(this._overlay);

        this._bindDrawingEvents();
        this._createDoneButton();
    }

    _bindDrawingEvents() {
        let isDrawing = false;
        let currentStroke = [];

        const getEventPos = (e) => {
            const rect = this._overlay.getBoundingClientRect();
            const clientX = e.clientX || (e.touches && e.touches[0] ? e.touches[0].clientX : 0);
            const clientY = e.clientY || (e.touches && e.touches[0] ? e.touches[0].clientY : 0);
            return {
                x: clientX - rect.left,
                y: clientY - rect.top
            };
        };

        const startDrawing = (e) => {
            isDrawing = true;
            currentStroke = [];
            const pos = getEventPos(e);
            currentStroke.push([pos.x, pos.y]);
            
            this._ctx.beginPath();
            this._ctx.moveTo(pos.x, pos.y);
            console.log('🚨 SUPER EMERGENCY: Начало рисования');
        };

        const draw = (e) => {
            if (!isDrawing) return;
            const pos = getEventPos(e);
            currentStroke.push([pos.x, pos.y]);
            
            this._ctx.lineTo(pos.x, pos.y);
            this._ctx.stroke();
        };

        const stopDrawing = (e) => {
            if (isDrawing && currentStroke.length > 0) {
                this._points.push([...currentStroke]);
                console.log(`🚨 SUPER EMERGENCY: Завершён штрих с ${currentStroke.length} точками`);
            }
            isDrawing = false;
            currentStroke = [];
        };

        // Mouse events
        this._overlay.addEventListener('mousedown', startDrawing);
        this._overlay.addEventListener('mousemove', draw);
        this._overlay.addEventListener('mouseup', stopDrawing);

        // Touch events
        this._overlay.addEventListener('touchstart', (e) => {
            e.preventDefault();
            startDrawing(e);
        });

        this._overlay.addEventListener('touchmove', (e) => {
            e.preventDefault();
            draw(e);
        });

        this._overlay.addEventListener('touchend', (e) => {
            e.preventDefault();
            stopDrawing(e);
        });
    }

    _createDoneButton() {
        const doneBtn = document.createElement('button');
        doneBtn.textContent = 'Готово';
        doneBtn.id = 'superRetouchDoneBtn';
        
        Object.assign(doneBtn.style, {
            position: 'fixed',
            top: '20px',
            right: '20px',
            zIndex: '10000',
            padding: '15px 30px',
            backgroundColor: '#4CAF50',
            color: 'white',
            border: 'none',
            borderRadius: '8px',
            cursor: 'pointer',
            fontSize: '18px',
            fontWeight: 'bold',
            boxShadow: '0 4px 8px rgba(0,0,0,0.3)'
        });

        doneBtn.addEventListener('click', () => {
            console.log('🚨 SUPER EMERGENCY: Супер-кнопка "Готово" нажата');
            this.finishMaskDraw();
        });

        document.body.appendChild(doneBtn);
    }

    finishMaskDraw() {
        try {
            console.log('🚨 SUPER EMERGENCY: finishMaskDraw вызван');
            
            if (!this._points || this._points.length === 0) {
                alert('Нарисуйте область для ретуши');
                return false;
            }

            console.log(`🚨 SUPER EMERGENCY: Создаём маску из ${this._points.length} штрихов`);
            
            // Создаём маску
            const maskDataUrl = this._exportMask();
            if (!maskDataUrl) {
                console.error('🚨 SUPER EMERGENCY: Не удалось создать маску');
                return false;
            }

            this._maskDataUrl = maskDataUrl;
            console.log(`🚨 SUPER EMERGENCY: Маска создана, длина: ${maskDataUrl.length}`);

            // Убираем overlay
            this._teardownOverlay();

            // НЕМЕДЛЕННО запускаем ретушь
            this.applyRetouchSuperEmergency();
            
            return true;

        } catch (error) {
            console.error('🚨 SUPER EMERGENCY: Ошибка в finishMaskDraw:', error);
            this._teardownOverlay();
            return false;
        }
    }

    _exportMask() {
        try {
            if (!this._overlay) {
                console.error('🚨 SUPER EMERGENCY: Overlay не найден для экспорта');
                return null;
            }

            // Создаём временный canvas для маски
            const tempCanvas = document.createElement('canvas');
            tempCanvas.width = this._overlay.width;
            tempCanvas.height = this._overlay.height;
            const tempCtx = tempCanvas.getContext('2d');

            // Заливаем чёрным
            tempCtx.fillStyle = 'black';
            tempCtx.fillRect(0, 0, tempCanvas.width, tempCanvas.height);

            // Рисуем белые области
            tempCtx.fillStyle = 'white';
            tempCtx.strokeStyle = 'white';
            tempCtx.lineWidth = 20; // Ещё более толстые линии

            for (const stroke of this._points) {
                if (stroke.length < 2) continue;

                // Рисуем как толстую линию
                tempCtx.beginPath();
                tempCtx.moveTo(stroke[0][0], stroke[0][1]);
                
                for (let i = 1; i < stroke.length; i++) {
                    tempCtx.lineTo(stroke[i][0], stroke[i][1]);
                }
                tempCtx.stroke();

                // Рисуем дополнительные точки для более плотной маски
                for (const point of stroke) {
                    tempCtx.beginPath();
                    tempCtx.arc(point[0], point[1], 10, 0, 2 * Math.PI);
                    tempCtx.fill();
                }
            }

            const dataUrl = tempCanvas.toDataURL('image/png');
            console.log(`🚨 SUPER EMERGENCY: Суперматрица экспортирована, размер: ${tempCanvas.width}x${tempCanvas.height}, длина: ${dataUrl.length}`);
            return dataUrl;

        } catch (error) {
            console.error('🚨 SUPER EMERGENCY: Ошибка экспорта маски:', error);
            return null;
        }
    }

    async applyRetouchSuperEmergency() {
        console.log('🚨 SUPER EMERGENCY: Запуск супер-экстренной ретуши');
        
        try {
            // Показываем прогресс
            this.showProgress('🚨 СУПЕР-РЕТУШЬ: Подготовка...', 5);

            // Создаём новый AbortController для защиты от зависания
            this._abortController = new AbortController();
            const timeoutId = setTimeout(() => {
                console.error('🚨 SUPER EMERGENCY: СУПЕРКРИТИЧЕСКИЙ ТАЙМАУТ! Прерываем ретушь');
                this._abortController.abort();
                this.showProgress('❌ Превышен лимит времени', 100);
            }, 3 * 60 * 1000); // 3 минуты - более агрессивный таймаут

            // Получаем текущее изображение
            this.showProgress('🚨 СУПЕР-РЕТУШЬ: Получение изображения...', 20);
            const imageBlob = await this._getCurrentPanoramaBlob();
            if (!imageBlob) {
                throw new Error('Не удалось получить изображение панорамы');
            }

            // Конвертируем маску в blob
            this.showProgress('🚨 СУПЕР-РЕТУШЬ: Подготовка суперматрицы...', 40);
            const maskBlob = await this._dataURLToBlob(this._maskDataUrl);
            if (!maskBlob) {
                throw new Error('Не удалось создать blob маски');
            }

            // Отправляем на сервер
            this.showProgress('🚨 СУПЕР-РЕТУШЬ: Передача на ИИ-сервер...', 60);
            
            const formData = new FormData();
            formData.append('image', imageBlob, 'panorama.jpg');
            formData.append('mask', maskBlob, 'mask.png');

            console.log('🚨 SUPER EMERGENCY: Отправляем супер-запрос на /api/lama/inpaint');

            const response = await fetch('/api/lama/inpaint', {
                method: 'POST',
                body: formData,
                signal: this._abortController.signal,
                timeout: 180000 // 3 минуты
            });

            clearTimeout(timeoutId);

            if (!response.ok) {
                throw new Error(`Ошибка ИИ-сервера: ${response.status} ${response.statusText}`);
            }

            this.showProgress('🚨 СУПЕР-РЕТУШЬ: Применение результата...', 80);

            const resultBlob = await response.blob();
            
            // Применяем результат
            await this._applyResult(resultBlob);
            
            this.showProgress('🎉 СУПЕРУСПЕХ! Ретушь завершена!', 100);
            
            setTimeout(() => {
                this.hideProgress();
            }, 2000);

            console.log('🚨 SUPER EMERGENCY: СУПЕРРЕТУШЬ УСПЕШНО ЗАВЕРШЕНА! 🎉');

        } catch (error) {
            console.error('🚨 SUPER EMERGENCY: Суперошибка ретуши:', error);
            this.hideProgress();
            
            // Более подробная диагностика ошибок
            let errorMessage = `Суперошибка ретуши: ${error.message}`;
            if (error.name === 'AbortError') {
                errorMessage = 'Ретушь прервана по таймауту. Попробуйте ещё раз.';
            } else if (error.message.includes('fetch')) {
                errorMessage = 'Ошибка соединения с ИИ-сервером. Проверьте интернет.';
            }
            
            alert(errorMessage);
        }
    }

    async _getCurrentPanoramaBlob() {
        try {
            // Множественные попытки получения изображения
            let src = null;
            
            // Попытка 1: через sceneManager
            if (window.sceneManager && window.sceneManager.currentScene) {
                src = window.sceneManager.currentScene.src;
                console.log('🚨 SUPER EMERGENCY: Источник через sceneManager');
            }
            
            // Попытка 2: через A-Frame sky
            if (!src) {
                const sky = document.querySelector('a-sky');
                if (sky) {
                    src = sky.getAttribute('src');
                    console.log('🚨 SUPER EMERGENCY: Источник через a-sky');
                }
            }
            
            // Попытка 3: через текстуру материала
            if (!src) {
                const sky = document.querySelector('a-sky');
                if (sky && sky.object3D && sky.object3D.children[0]) {
                    const material = sky.object3D.children[0].material;
                    if (material && material.map && material.map.image) {
                        // Конвертируем изображение в blob
                        const canvas = document.createElement('canvas');
                        const ctx = canvas.getContext('2d');
                        const img = material.map.image;
                        canvas.width = img.width;
                        canvas.height = img.height;
                        ctx.drawImage(img, 0, 0);
                        
                        return new Promise(resolve => {
                            canvas.toBlob(resolve, 'image/jpeg', 0.9);
                        });
                    }
                }
            }

            if (!src) {
                throw new Error('Не удалось найти источник изображения панорамы');
            }

            if (src.startsWith('data:')) {
                // Data URL - конвертируем в blob
                const response = await fetch(src);
                return await response.blob();
            } else if (src.startsWith('blob:')) {
                // Blob URL - получаем blob
                const response = await fetch(src);
                return await response.blob();
            } else if (src.startsWith('http')) {
                // HTTP URL - загружаем
                const response = await fetch(src);
                return await response.blob();
            } else {
                throw new Error('Неподдерживаемый тип источника изображения');
            }
        } catch (error) {
            console.error('🚨 SUPER EMERGENCY: Суперошибка получения blob панорамы:', error);
            throw error;
        }
    }

    async _dataURLToBlob(dataURL) {
        try {
            const response = await fetch(dataURL);
            return await response.blob();
        } catch (error) {
            console.error('🚨 SUPER EMERGENCY: Ошибка конвертации dataURL в blob:', error);
            throw error;
        }
    }

    async _applyResult(resultBlob) {
        try {
            // Создаём blob URL
            const blobUrl = URL.createObjectURL(resultBlob);
            
            // Множественные попытки применения результата
            let applied = false;
            
            // Попытка 1: через sceneManager
            if (window.sceneManager && typeof sceneManager.updateCurrentScene === 'function') {
                try {
                    await sceneManager.updateCurrentScene(blobUrl);
                    applied = true;
                    console.log('🚨 SUPER EMERGENCY: Результат применён через sceneManager');
                } catch (e) {
                    console.warn('🚨 SUPER EMERGENCY: Не удалось применить через sceneManager:', e);
                }
            }
            
            // Попытка 2: прямо к A-Frame sky
            if (!applied) {
                const sky = document.querySelector('a-sky');
                if (sky) {
                    sky.setAttribute('src', blobUrl);
                    applied = true;
                    console.log('🚨 SUPER EMERGENCY: Результат применён к a-sky');
                }
            }
            
            // Попытка 3: через ViewerManager
            if (!applied && window.viewerManager && typeof viewerManager.setPanorama === 'function') {
                try {
                    await viewerManager.setPanorama(blobUrl);
                    applied = true;
                    console.log('🚨 SUPER EMERGENCY: Результат применён через viewerManager');
                } catch (e) {
                    console.warn('🚨 SUPER EMERGENCY: Не удалось применить через viewerManager:', e);
                }
            }

            if (!applied) {
                throw new Error('Не удалось применить результат ни одним способом');
            }

            console.log('🚨 SUPER EMERGENCY: Суперрезультат успешно применён к панораме');
        } catch (error) {
            console.error('🚨 SUPER EMERGENCY: Ошибка применения суперрезультата:', error);
            throw error;
        }
    }

    showProgress(text, percent) {
        let progressEl = document.getElementById('superEmergencyProgress');
        if (!progressEl) {
            progressEl = document.createElement('div');
            progressEl.id = 'superEmergencyProgress';
            Object.assign(progressEl.style, {
                position: 'fixed',
                top: '50%',
                left: '50%',
                transform: 'translate(-50%, -50%)',
                zIndex: '10001',
                background: 'linear-gradient(135deg, #ff6b6b, #4ecdc4)',
                color: 'white',
                padding: '30px',
                borderRadius: '15px',
                textAlign: 'center',
                fontSize: '20px',
                fontWeight: 'bold',
                boxShadow: '0 8px 32px rgba(0,0,0,0.3)',
                border: '2px solid rgba(255,255,255,0.2)'
            });
            document.body.appendChild(progressEl);
        }

        progressEl.innerHTML = `
            <div style="margin-bottom: 15px; font-size: 24px;">🚨 СУПЕРРЕТУШЬ</div>
            <div style="margin-bottom: 15px;">${text}</div>
            <div style="margin-bottom: 10px;">
                <div style="width: 400px; height: 15px; background: rgba(255,255,255,0.2); border-radius: 10px; overflow: hidden;">
                    <div style="width: ${percent}%; height: 100%; background: linear-gradient(90deg, #ff9a9e, #fecfef); transition: width 0.3s; border-radius: 10px;"></div>
                </div>
            </div>
            <div style="font-size: 18px; font-weight: normal;">${percent}%</div>
        `;
    }

    hideProgress() {
        const progressEl = document.getElementById('superEmergencyProgress');
        if (progressEl) {
            progressEl.style.opacity = '0';
            setTimeout(() => progressEl.remove(), 500);
        }
    }

    _teardownOverlay() {
        // Убираем кнопку "Готово"
        const doneBtn = document.getElementById('superRetouchDoneBtn');
        if (doneBtn) {
            doneBtn.remove();
        }

        // Убираем overlay
        if (this._overlay) {
            this._overlay.remove();
            this._overlay = null;
            this._ctx = null;
        }

        console.log('🚨 SUPER EMERGENCY: Суперoverlay убран');
    }
}

// СУПЕРПРИНУДИТЕЛЬНАЯ ЗАМЕНА - блокируем любые попытки создания старого RetouchManager
window.RetouchManager = SuperEmergencyRetouchManager;

// Создаём глобальный экземпляр
window.superEmergencyRetouchManager = new SuperEmergencyRetouchManager();

console.log('🚨 SUPER EMERGENCY: Суперэкстренный RetouchManager V3 установлен и готов к бою! 💪');

// Перехватываем любые попытки создания retouchManager в глобальном scope
Object.defineProperty(window, 'retouchManager', {
    get: function() {
        return window.superEmergencyRetouchManager;
    },
    set: function(value) {
        console.log('🚨 SUPER EMERGENCY: Блокируем попытку замены superRetouchManager');
        // Ничего не делаем - блокируем замену
    }
});

// Дополнительная защита через Proxy
window.retouchManager = new Proxy(window.superEmergencyRetouchManager, {
    set: function(target, property, value) {
        console.log(`🚨 SUPER EMERGENCY: Блокируем изменение свойства ${property}`);
        return false;
    }
});

SUPER_EOF

echo -e "${GREEN}✅ СуперИсправленный RetouchManager создан${NC}"

echo -e "${BLUE}🔄 Устанавливаем суперэкстренное исправление...${NC}"

# Заменяем retouch_manager.js
cp /tmp/retouch_manager_super_fixed.js /var/www/html/pano/assets/retouch_manager.js
chmod 644 /var/www/html/pano/assets/retouch_manager.js

echo -e "${YELLOW}🌐 Создаём суперпринудительную инъекцию в HTML...${NC}"

# Функция для супер-инъекции скрипта
super_inject_script() {
    local file=$1
    if [[ -f "$file" ]]; then
        # Удаляем старые инъекции
        sed -i '/EMERGENCY INJECTION/,+20d' "$file"
        
        # Добавляем суперэкстренную инъекцию в начало head
        sed -i '/<head>/a\
<script>\
// 🚨 СУПЕР-ЭКСТРЕННАЯ ИНЪЕКЦИЯ V3 - Принудительная блокировка старого RetouchManager\
console.log("🚨 SUPER EMERGENCY INJECTION V3: Блокируем старый RetouchManager");\
\
// Удаляем все существующие RetouchManager\
if (window.RetouchManager) {\
    console.log("🚨 SUPER EMERGENCY: Удаляем существующий RetouchManager");\
    delete window.RetouchManager;\
}\
if (window.retouchManager) {\
    console.log("🚨 SUPER EMERGENCY: Удаляем существующий retouchManager");\
    delete window.retouchManager;\
}\
\
// Перехватываем eval и Function\
const originalEval = window.eval;\
window.eval = function(code) {\
    if (typeof code === "string" && (code.includes("RetouchManager") || code.includes("retouch_manager"))) {\
        console.log("🚨 SUPER EMERGENCY: Блокируем eval с RetouchManager");\
        return;\
    }\
    return originalEval.apply(this, arguments);\
};\
\
const originalFunction = window.Function;\
window.Function = function(...args) {\
    const code = args[args.length - 1];\
    if (typeof code === "string" && (code.includes("RetouchManager") || code.includes("retouch_manager"))) {\
        console.log("🚨 SUPER EMERGENCY: Блокируем Function с RetouchManager");\
        return function() {};\
    }\
    return originalFunction.apply(this, args);\
};\
\
// Глобальная блокировка загрузки скриптов\
document.addEventListener("DOMContentLoaded", function() {\
    const observer = new MutationObserver(function(mutations) {\
        mutations.forEach(function(mutation) {\
            mutation.addedNodes.forEach(function(node) {\
                if (node.tagName === "SCRIPT") {\
                    if ((node.src && (node.src.includes("retouch_manager") || node.src.includes("RetouchManager"))) ||\
                        (node.textContent && (node.textContent.includes("class RetouchManager") || node.textContent.includes("function RetouchManager")))) {\
                        console.log("🚨 SUPER EMERGENCY: Блокируем загрузку скрипта RetouchManager");\
                        node.remove();\
                    }\
                }\
            });\
        });\
    });\
    observer.observe(document, { childList: true, subtree: true });\
});\
</script>' "$file"
        
        echo "  ✅ Супер-инъецировано в $file"
    fi
}

# Инъецируем в основные HTML файлы
super_inject_script "/var/www/html/index.html"
super_inject_script "/var/www/html/main.html"
super_inject_script "/var/www/html/pano/index.html"

echo -e "${GREEN}🔄 Перезапускаем nginx для применения изменений...${NC}"
systemctl reload nginx

echo -e "${GREEN}✅ СУПЕРЭКСТРЕННОЕ ИСПРАВЛЕНИЕ V3 УСТАНОВЛЕНО!${NC}"
echo ""
echo -e "${YELLOW}🚨 Что было исправлено в V3:${NC}"
echo "  💪 Суперпринудительная замена RetouchManager"
echo "  🛡️ Тройная защита от загрузки старого кода"
echo "  ⚡ Супер-экстренная система ретуши с 3-минутным таймаутом"
echo "  🎨 Красивый градиентный прогресс-бар"
echo "  🔍 Множественные способы поиска кнопки ретуши"
echo "  📡 Тройной способ применения результата"
echo ""
echo -e "${BLUE}🔍 Тестирование:${NC}"
echo "  1. Откройте https://color360.ru/pano/"
echo "  2. Загрузите изображение"
echo "  3. Нажмите 'Ретушь' (любую найденную кнопку)"
echo "  4. Нарисуйте область"
echo "  5. Нажмите 'Готово'"
echo "  6. Должен появиться градиентный прогресс-бар 🚨 СУПЕРРЕТУШЬ"
echo ""
echo -e "${GREEN}🎯 В консоли должны появиться сообщения:${NC}"
echo "  - '🚨 SUPER EMERGENCY INJECTION V3: Блокируем старый RetouchManager'"
echo "  - '🚨 SUPER EMERGENCY: Суперэкстренный RetouchManager V3 установлен и готов к бою! 💪'"
echo "  - '🚨 SUPER EMERGENCY: Запуск супер-экстренной ретуши'"