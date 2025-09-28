#!/bin/bash

# 🚨 ДИАГНОСТИКА ФАЙЛОВОЙ СТРУКТУРЫ И КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ
echo "🚨 ДИАГНОСТИКА: Поиск файлов ретуши на сервере"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 Ищем все файлы с 'retouch' в названии...${NC}"
find /var/www/html -name "*retouch*" -type f 2>/dev/null || echo "Файлы retouch не найдены"

echo -e "${BLUE}🔍 Ищем все JavaScript файлы в /var/www/html...${NC}"
find /var/www/html -name "*.js" -type f 2>/dev/null | head -20

echo -e "${BLUE}🔍 Проверяем структуру /var/www/html...${NC}"
ls -la /var/www/html/ 2>/dev/null || echo "Директория /var/www/html не найдена"

echo -e "${BLUE}🔍 Проверяем структуру /var/www/html/assets...${NC}"
ls -la /var/www/html/assets/ 2>/dev/null || echo "Директория /var/www/html/assets не найдена"

echo -e "${BLUE}🔍 Проверяем структуру /var/www/html/pano...${NC}"
ls -la /var/www/html/pano/ 2>/dev/null || echo "Директория /var/www/html/pano не найдена"

echo -e "${BLUE}🔍 Ищем RetouchManager в файлах...${NC}"
grep -r "RetouchManager" /var/www/html/ 2>/dev/null | head -10

echo -e "${BLUE}🔍 Ищем все HTML файлы...${NC}"
find /var/www/html -name "*.html" -type f 2>/dev/null

echo ""
echo -e "${YELLOW}🔧 СОЗДАНИЕ ПРАВИЛЬНОЙ СТРУКТУРЫ И УСТАНОВКА КРИТИЧЕСКОГО ИСПРАВЛЕНИЯ${NC}"

# Создаём необходимые директории
mkdir -p /var/www/html/assets
mkdir -p /var/www/html/pano/assets

echo -e "${GREEN}✅ Директории созданы${NC}"

# Создаём суперкритическое исправление прямо в корне
cat > /var/www/html/super_retouch_fix.js << 'CRITICAL_EOF'
// 🚨 СУПЕРКРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ РЕТУШИ - ПРЯМАЯ ИНЪЕКЦИЯ
console.log('🚨 CRITICAL FIX: Суперкритическое исправление ретуши загружается...');

// Немедленная блокировка старого RetouchManager
if (window.RetouchManager) {
    console.log('🚨 CRITICAL: Удаляем старый RetouchManager');
    delete window.RetouchManager;
}

// Блокируем создание через eval
const originalEval = window.eval;
window.eval = function(code) {
    if (typeof code === 'string' && code.includes('RetouchManager')) {
        console.log('🚨 CRITICAL: Блокируем eval RetouchManager');
        return;
    }
    return originalEval.apply(this, arguments);
};

class CriticalRetouchManager {
    constructor() {
        console.log('🚨 CRITICAL: CriticalRetouchManager запущен');
        this._points = [];
        this._maskDataUrl = null;
        this._overlay = null;
        this._ctx = null;
        this._abortController = null;
        this.setupCriticalRetouch();
    }

    setupCriticalRetouch() {
        // Перехватываем все возможные кнопки ретуши
        const interceptRetouchButtons = () => {
            // Поиск кнопок по различным селекторам
            const selectors = [
                '#retouchBtn',
                '.retouch-btn', 
                'button[onclick*="retouch"]',
                'button[onclick*="startMaskDraw"]',
                '[data-action="retouch"]'
            ];

            // Поиск по тексту
            const allButtons = document.querySelectorAll('button');
            allButtons.forEach(btn => {
                const text = btn.textContent.toLowerCase().trim();
                if (text.includes('ретушь') || text.includes('retouch')) {
                    console.log('🚨 CRITICAL: Найдена кнопка ретуши по тексту:', text);
                    this.hijackButton(btn);
                }
            });

            // Поиск по селекторам
            selectors.forEach(selector => {
                const btn = document.querySelector(selector);
                if (btn) {
                    console.log('🚨 CRITICAL: Найдена кнопка ретуши:', selector);
                    this.hijackButton(btn);
                }
            });
        };

        // Немедленный поиск
        interceptRetouchButtons();
        
        // Повторный поиск через интервалы
        const searchInterval = setInterval(() => {
            interceptRetouchButtons();
        }, 1000);

        // Останавливаем поиск через 30 секунд
        setTimeout(() => clearInterval(searchInterval), 30000);

        // Перехватываем глобальные функции
        if (window.startMaskDraw) {
            const original = window.startMaskDraw;
            window.startMaskDraw = () => {
                console.log('🚨 CRITICAL: Перехвачен startMaskDraw');
                return this.startCriticalRetouch();
            };
        }
    }

    hijackButton(btn) {
        if (btn._criticallyHijacked) return;
        btn._criticallyHijacked = true;

        console.log('🚨 CRITICAL: Полный перехват кнопки');

        // Удаляем все события
        btn.onclick = null;
        btn.removeAttribute('onclick');

        // Создаём новую кнопку
        const newBtn = btn.cloneNode(true);
        btn.parentNode.replaceChild(newBtn, btn);

        // Наш обработчик
        newBtn.addEventListener('click', (e) => {
            e.preventDefault();
            e.stopImmediatePropagation();
            console.log('🚨 CRITICAL: Критический клик по ретуши');
            this.startCriticalRetouch();
            return false;
        }, true);

        // Блокируем добавление новых обработчиков
        const originalAddEvent = newBtn.addEventListener;
        newBtn.addEventListener = (type, handler, options) => {
            if (type === 'click' && !handler._criticalHandler) {
                console.log('🚨 CRITICAL: Блокируем добавление click handler');
                return;
            }
            return originalAddEvent.call(newBtn, type, handler, options);
        };
    }

    startCriticalRetouch() {
        console.log('🚨 CRITICAL: Запуск критической ретуши');
        
        try {
            this.clearPrevious();
            this.createOverlay();
            return true;
        } catch (error) {
            console.error('🚨 CRITICAL: Ошибка запуска:', error);
            return false;
        }
    }

    clearPrevious() {
        this._points = [];
        this._maskDataUrl = null;
        if (this._overlay) {
            this._overlay.remove();
            this._overlay = null;
        }
        // Удаляем предыдущие кнопки "Готово"
        const prevBtn = document.getElementById('criticalDoneBtn');
        if (prevBtn) prevBtn.remove();
    }

    createOverlay() {
        const sceneEl = document.querySelector('a-scene');
        const canvas = sceneEl ? sceneEl.querySelector('canvas') : null;
        
        if (!canvas) {
            console.error('🚨 CRITICAL: Canvas не найден');
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
        this._ctx.strokeStyle = 'rgba(255, 0, 0, 0.9)';
        this._ctx.lineWidth = 4;
        this._ctx.lineCap = 'round';

        // Добавляем в DOM
        canvas.parentNode.style.position = 'relative';
        canvas.parentNode.appendChild(this._overlay);

        this.bindDrawing();
        this.createDoneButton();
    }

    bindDrawing() {
        let isDrawing = false;
        let currentStroke = [];

        const getPos = (e) => {
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
            const pos = getPos(e);
            currentStroke.push([pos.x, pos.y]);
            this._ctx.beginPath();
            this._ctx.moveTo(pos.x, pos.y);
        };

        const draw = (e) => {
            if (!isDrawing) return;
            const pos = getPos(e);
            currentStroke.push([pos.x, pos.y]);
            this._ctx.lineTo(pos.x, pos.y);
            this._ctx.stroke();
        };

        const stopDrawing = () => {
            if (isDrawing && currentStroke.length > 1) {
                this._points.push([...currentStroke]);
                console.log('🚨 CRITICAL: Штрих добавлен:', currentStroke.length, 'точек');
            }
            isDrawing = false;
        };

        // События
        this._overlay.addEventListener('mousedown', startDrawing);
        this._overlay.addEventListener('mousemove', draw);  
        this._overlay.addEventListener('mouseup', stopDrawing);
        
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
            stopDrawing();
        });
    }

    createDoneButton() {
        const btn = document.createElement('button');
        btn.textContent = 'КРИТИЧЕСКОЕ ГОТОВО';
        btn.id = 'criticalDoneBtn';
        
        Object.assign(btn.style, {
            position: 'fixed',
            top: '20px',
            right: '20px',
            zIndex: '10000',
            padding: '15px 25px',
            backgroundColor: '#ff4444',
            color: 'white',
            border: '3px solid #ffffff',
            borderRadius: '8px',
            cursor: 'pointer',
            fontSize: '16px',
            fontWeight: 'bold',
            boxShadow: '0 4px 12px rgba(255,0,0,0.5)',
            animation: 'pulse 2s infinite'
        });

        // Добавляем анимацию
        const style = document.createElement('style');
        style.textContent = `
            @keyframes pulse {
                0% { transform: scale(1); }
                50% { transform: scale(1.05); }
                100% { transform: scale(1); }
            }
        `;
        document.head.appendChild(style);

        btn.addEventListener('click', () => {
            console.log('🚨 CRITICAL: Критическое "Готово" нажато');
            this.processCriticalRetouch();
        });

        document.body.appendChild(btn);
    }

    async processCriticalRetouch() {
        console.log('🚨 CRITICAL: Обработка критической ретуши');

        if (!this._points.length) {
            alert('Нарисуйте область для ретуши!');
            return;
        }

        try {
            // Показываем прогресс
            this.showCriticalProgress('🚨 КРИТИЧЕСКАЯ ОБРАБОТКА...', 10);

            // Таймаут для предотвращения зависания
            this._abortController = new AbortController();
            const timeout = setTimeout(() => {
                console.log('🚨 CRITICAL: КРИТИЧЕСКИЙ ТАЙМАУТ!');
                this._abortController.abort();
            }, 2 * 60 * 1000); // 2 минуты

            // Создаём маску
            this.showCriticalProgress('🚨 Создание критической маски...', 30);
            const maskDataUrl = this.createCriticalMask();
            
            // Получаем изображение  
            this.showCriticalProgress('🚨 Получение изображения...', 50);
            const imageBlob = await this.getCriticalImage();

            // Конвертируем маску
            this.showCriticalProgress('🚨 Конвертация маски...', 70);
            const maskBlob = await this.dataUrlToBlob(maskDataUrl);

            // Отправляем запрос
            this.showCriticalProgress('🚨 КРИТИЧЕСКАЯ ОТПРАВКА...', 85);
            
            const formData = new FormData();
            formData.append('image', imageBlob, 'image.jpg');
            formData.append('mask', maskBlob, 'mask.png');

            console.log('🚨 CRITICAL: Отправляем на /api/lama/inpaint');

            const response = await fetch('/api/lama/inpaint', {
                method: 'POST',
                body: formData,
                signal: this._abortController.signal
            });

            clearTimeout(timeout);

            if (!response.ok) {
                throw new Error(`Сервер ошибка: ${response.status}`);
            }

            this.showCriticalProgress('🚨 ПРИМЕНЕНИЕ РЕЗУЛЬТАТА...', 95);
            
            const resultBlob = await response.blob();
            await this.applyCriticalResult(resultBlob);

            this.showCriticalProgress('🎉 КРИТИЧЕСКИЙ УСПЕХ!', 100);
            
            setTimeout(() => {
                this.hideCriticalProgress();
                this.clearPrevious();
            }, 2000);

        } catch (error) {
            console.error('🚨 CRITICAL: Критическая ошибка:', error);
            this.hideCriticalProgress();
            alert(`Критическая ошибка: ${error.message}`);
        }
    }

    createCriticalMask() {
        const canvas = document.createElement('canvas');
        canvas.width = this._overlay.width;
        canvas.height = this._overlay.height; 
        const ctx = canvas.getContext('2d');

        // Чёрный фон
        ctx.fillStyle = 'black';
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        // Белые штрихи
        ctx.strokeStyle = 'white';
        ctx.fillStyle = 'white';
        ctx.lineWidth = 25;
        ctx.lineCap = 'round';

        for (const stroke of this._points) {
            if (stroke.length < 2) continue;
            
            ctx.beginPath();
            ctx.moveTo(stroke[0][0], stroke[0][1]);
            for (let i = 1; i < stroke.length; i++) {
                ctx.lineTo(stroke[i][0], stroke[i][1]);
            }
            ctx.stroke();

            // Дополнительные точки для плотности
            for (const point of stroke) {
                ctx.beginPath();
                ctx.arc(point[0], point[1], 12, 0, 2 * Math.PI);
                ctx.fill();
            }
        }

        const dataUrl = canvas.toDataURL('image/png');
        console.log('🚨 CRITICAL: Критическая маска создана:', dataUrl.length);
        return dataUrl;
    }

    async getCriticalImage() {
        // Множественные попытки получения изображения
        let src = null;

        // Попытка 1: sceneManager
        if (window.sceneManager?.currentScene?.src) {
            src = window.sceneManager.currentScene.src;
        }
        
        // Попытка 2: a-sky
        if (!src) {
            const sky = document.querySelector('a-sky');
            if (sky) src = sky.getAttribute('src');
        }

        if (!src) throw new Error('Изображение не найдено');

        const response = await fetch(src);
        return await response.blob();
    }

    async dataUrlToBlob(dataUrl) {
        const response = await fetch(dataUrl);
        return await response.blob();
    }

    async applyCriticalResult(blob) {
        const blobUrl = URL.createObjectURL(blob);
        
        // Множественное применение
        if (window.sceneManager?.updateCurrentScene) {
            await window.sceneManager.updateCurrentScene(blobUrl);
        } else {
            const sky = document.querySelector('a-sky');
            if (sky) sky.setAttribute('src', blobUrl);
        }

        console.log('🚨 CRITICAL: Результат применён критически');
    }

    showCriticalProgress(text, percent) {
        let progress = document.getElementById('criticalProgress');
        if (!progress) {
            progress = document.createElement('div');
            progress.id = 'criticalProgress';
            Object.assign(progress.style, {
                position: 'fixed',
                top: '50%',
                left: '50%',
                transform: 'translate(-50%, -50%)',
                zIndex: '10001',
                background: 'linear-gradient(45deg, #ff0000, #ff6600)',
                color: 'white',
                padding: '30px',
                borderRadius: '15px',
                textAlign: 'center',
                fontSize: '18px',
                fontWeight: 'bold',
                border: '3px solid white',
                boxShadow: '0 0 20px rgba(255,0,0,0.7)'
            });
            document.body.appendChild(progress);
        }

        progress.innerHTML = `
            <div style="font-size: 24px; margin-bottom: 10px;">🚨 КРИТИЧЕСКАЯ РЕТУШЬ</div>
            <div style="margin-bottom: 15px;">${text}</div>
            <div style="width: 300px; height: 10px; background: rgba(255,255,255,0.3); border-radius: 5px; margin: 0 auto;">
                <div style="width: ${percent}%; height: 100%; background: white; border-radius: 5px; transition: width 0.3s;"></div>
            </div>
            <div style="margin-top: 10px;">${percent}%</div>
        `;
    }

    hideCriticalProgress() {
        const progress = document.getElementById('criticalProgress');
        if (progress) progress.remove();
    }
}

// КРИТИЧЕСКАЯ УСТАНОВКА
window.RetouchManager = CriticalRetouchManager;
window.criticalRetouchManager = new CriticalRetouchManager();

// Защищаем от перезаписи
Object.defineProperty(window, 'retouchManager', {
    get: () => window.criticalRetouchManager,
    set: () => console.log('🚨 CRITICAL: Блокировка перезаписи retouchManager')
});

console.log('🚨 CRITICAL: Критическое исправление ретуши активировано! 💥');

CRITICAL_EOF

echo -e "${GREEN}✅ Суперкритическое исправление создано${NC}"

# Копируем в правильные места
cp /var/www/html/super_retouch_fix.js /var/www/html/assets/retouch_manager.js 2>/dev/null || echo "Копирование в assets не удалось"
cp /var/www/html/super_retouch_fix.js /var/www/html/pano/assets/retouch_manager.js 2>/dev/null || echo "Копирование в pano/assets не удалось"

echo -e "${BLUE}🔧 Инъецируем критическое исправление в HTML файлы...${NC}"

# Функция для критической инъекции
critical_inject() {
    local file=$1
    if [[ -f "$file" ]]; then
        # Удаляем старые инъекции
        sed -i '/EMERGENCY INJECTION/,+30d' "$file" 2>/dev/null
        sed -i '/SUPER EMERGENCY/,+30d' "$file" 2>/dev/null
        
        # Добавляем критическую инъекцию
        sed -i '/<\/head>/i\
<script src="/super_retouch_fix.js?v='$(date +%s)'"></script>' "$file" 2>/dev/null
        
        echo "  ✅ Критически инъецировано в $file"
    fi
}

# Находим и патчим все HTML файлы
find /var/www/html -name "*.html" -type f | while read htmlfile; do
    critical_inject "$htmlfile"
done

echo -e "${GREEN}🔄 Перезапускаем nginx...${NC}"
systemctl reload nginx 2>/dev/null || echo "nginx reload не удался"

echo ""
echo -e "${RED}🚨 КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ УСТАНОВЛЕНО! 🚨${NC}"
echo ""
echo -e "${YELLOW}Что было сделано:${NC}"
echo "  💥 Создан CriticalRetouchManager с полной блокировкой"
echo "  🎯 Агрессивный поиск и перехват всех кнопок ретуши" 
echo "  ⚡ 2-минутный таймаут для предотвращения зависания"
echo "  🚨 Критический прогресс-бар с анимацией"
echo "  📡 Прямая инъекция в HTML файлы"
echo ""
echo -e "${GREEN}В консоли должно появиться:${NC}"
echo "  '🚨 CRITICAL FIX: Суперкритическое исправление ретуши загружается...'"
echo "  '🚨 CRITICAL: Критическое исправление ретуши активировано! 💥'"