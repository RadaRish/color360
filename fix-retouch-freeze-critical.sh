#!/bin/bash

# ИСПРАВЛЕНИЕ КОНКРЕТНОЙ ПРОБЛЕМЫ ЗАВИСАНИЯ ПОСЛЕ СОЗДАНИЯ МАСКИ
echo "🔧 ИСПРАВЛЕНИЕ ЗАВИСАНИЯ НА ЭТАПЕ ОТПРАВКИ МАСКИ"
echo "==============================================="

WEBROOT="/var/www/color360"

echo "🎯 ПРОБЛЕМА ОПРЕДЕЛЕНА:"
echo "======================"
echo "Из логов видно:"
echo "✅ Маска создается успешно (mask whiteCount= 29700)"
echo "✅ UV mapping работает корректно"
echo "❌ После создания маски процесс останавливается"
echo "❌ Нет отправки запроса на /api/retouch"
echo "❌ Страница зависает на этапе HTTP запроса"

echo ""
echo "🔧 1. СОЗДАНИЕ ИСПРАВЛЕННОГО RETOUCH_MANAGER"
echo "==========================================="

# Создаем backup
BACKUP_DIR="/tmp/retouch-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
[[ -f "$WEBROOT/assets/retouch_manager.js" ]] && cp "$WEBROOT/assets/retouch_manager.js" "$BACKUP_DIR/"
echo "Backup: $BACKUP_DIR"

# Создаем исправленную версию с proper async handling
cat > "$WEBROOT/assets/retouch_manager_fixed.js" << 'EOF'
/**
 * ИСПРАВЛЕННЫЙ RetouchManager с защитой от зависания
 * Исправляет проблему зависания после создания маски
 */

class RetouchManager {
    constructor() {
        this.apiUrl = '/api/retouch';
        this.timeout = 300000; // 5 минут
        this.isProcessing = false;
        this.abortController = null;
        this._maskDataUrl = null;
        
        console.log('🔧 FIXED RetouchManager initialized');
    }

    // Исправленный метод применения ретуши
    async applyRetouch() {
        console.log('🎨 FIXED RetouchManager: applyRetouch начат');
        
        if (this.isProcessing) {
            console.warn('⚠️ Ретушь уже выполняется');
            return false;
        }

        if (!this._maskDataUrl) {
            console.error('❌ Маска не создана');
            alert('Пожалуйста, сначала выделите область для удаления');
            return false;
        }

        this.isProcessing = true;
        this.abortController = new AbortController();

        try {
            // Показываем индикатор загрузки
            this._showProgress('Подготовка изображений...', 10);

            // Получаем текущее изображение панорамы
            console.log('🖼️ Получаем изображение панорамы...');
            const imageBlob = await this._getCurrentPanoramaBlob();
            
            if (!imageBlob) {
                throw new Error('Не удалось получить изображение панорамы');
            }

            console.log('✅ Изображение получено, размер:', imageBlob.size);
            this._showProgress('Подготовка маски...', 30);

            // Получаем маску как blob
            const maskBlob = await this._getMaskBlob();
            
            if (!maskBlob) {
                throw new Error('Не удалось создать маску');
            }

            console.log('✅ Маска создана, размер:', maskBlob.size);
            this._showProgress('Отправка на сервер...', 50);

            // Создаем FormData
            const formData = new FormData();
            formData.append('image', imageBlob, 'panorama.jpg');
            formData.append('mask', maskBlob, 'mask.png');

            console.log('📤 Отправляем запрос на', this.apiUrl);

            // Отправляем запрос с защитой от timeout
            const response = await this._fetchWithTimeout(this.apiUrl, {
                method: 'POST',
                body: formData,
                signal: this.abortController.signal
            });

            this._showProgress('Обработка изображения...', 70);

            if (!response.ok) {
                const errorText = await response.text();
                throw new Error(`Ошибка сервера ${response.status}: ${errorText}`);
            }

            console.log('✅ Ответ получен, обрабатываем...');
            this._showProgress('Получение результата...', 90);

            // Получаем результат
            const resultBlob = await response.blob();
            
            if (resultBlob.size === 0) {
                throw new Error('Пустой ответ от сервера');
            }

            console.log('✅ Результат получен, размер:', resultBlob.size);

            // Применяем результат к панораме
            await this._applyRetouchedImage(resultBlob);

            this._showProgress('Готово!', 100);
            
            // Убираем прогресс через 2 секунды
            setTimeout(() => {
                this._hideProgress();
            }, 2000);

            console.log('🎉 Ретушь успешно завершена');
            return true;

        } catch (error) {
            console.error('❌ Ошибка ретуши:', error);
            
            this._hideProgress();
            
            // Показываем понятную ошибку пользователю
            let errorMessage = 'Произошла ошибка при обработке изображения';
            
            if (error.name === 'AbortError') {
                errorMessage = 'Операция отменена по таймауту. Попробуйте с изображением меньшего размера.';
            } else if (error.message.includes('Failed to fetch')) {
                errorMessage = 'Ошибка сети. Проверьте подключение к интернету.';
            } else if (error.message.includes('500')) {
                errorMessage = 'Ошибка сервера. Попробуйте позже или с другим изображением.';
            } else {
                errorMessage = error.message;
            }
            
            alert(`Ошибка ретуши: ${errorMessage}`);
            return false;

        } finally {
            this.isProcessing = false;
            this.abortController = null;
        }
    }

    // Защищенный fetch с timeout
    async _fetchWithTimeout(url, options = {}) {
        const timeoutId = setTimeout(() => {
            console.warn('⏰ Timeout достигнут, отменяем запрос...');
            if (this.abortController) {
                this.abortController.abort();
            }
        }, this.timeout);

        try {
            const response = await fetch(url, options);
            clearTimeout(timeoutId);
            return response;
        } catch (error) {
            clearTimeout(timeoutId);
            throw error;
        }
    }

    // Получение маски как blob
    async _getMaskBlob() {
        return new Promise((resolve) => {
            if (!this._maskDataUrl) {
                resolve(null);
                return;
            }

            // Создаем image из dataURL
            const img = new Image();
            img.onload = () => {
                // Создаем canvas и рисуем изображение
                const canvas = document.createElement('canvas');
                canvas.width = img.width;
                canvas.height = img.height;
                
                const ctx = canvas.getContext('2d');
                ctx.drawImage(img, 0, 0);
                
                // Конвертируем в blob
                canvas.toBlob((blob) => {
                    resolve(blob);
                }, 'image/png');
            };
            
            img.onerror = () => resolve(null);
            img.src = this._maskDataUrl;
        });
    }

    // Получение изображения панорамы как blob
    async _getCurrentPanoramaBlob() {
        try {
            // Ищем текущую сцену
            if (typeof window.sceneManager !== 'undefined' && window.sceneManager.getCurrentScene) {
                const currentScene = window.sceneManager.getCurrentScene();
                if (currentScene && currentScene.src) {
                    console.log('🖼️ Получаем изображение из sceneManager');
                    return await this._dataUrlToBlob(currentScene.src);
                }
            }

            // Альтернативный способ - через a-sky
            const skyElement = document.querySelector('a-sky');
            if (skyElement && skyElement.getAttribute('material')) {
                const material = skyElement.getAttribute('material');
                if (material.src) {
                    console.log('🖼️ Получаем изображение из a-sky material');
                    return await this._dataUrlToBlob(material.src);
                }
            }

            throw new Error('Не удалось найти изображение панорамы');

        } catch (error) {
            console.error('❌ Ошибка получения изображения:', error);
            throw error;
        }
    }

    // Конвертация dataURL в blob
    async _dataUrlToBlob(dataUrl) {
        if (dataUrl.startsWith('data:')) {
            // Прямая конвертация data URL в blob
            const response = await fetch(dataUrl);
            return await response.blob();
        } else {
            // Если это обычный URL, загружаем его
            const response = await fetch(dataUrl);
            return await response.blob();
        }
    }

    // Применение обработанного изображения
    async _applyRetouchedImage(resultBlob) {
        try {
            console.log('🎨 Применяем обработанное изображение...');

            // Создаем URL для blob
            const imageUrl = URL.createObjectURL(resultBlob);

            // Обновляем панораму через ViewerManager если доступен
            if (typeof window.viewerManager !== 'undefined' && window.viewerManager.setPanorama) {
                await window.viewerManager.setPanorama(imageUrl);
                console.log('✅ Панорама обновлена через ViewerManager');
                return;
            }

            // Альтернативный способ - прямое обновление a-sky
            const skyElement = document.querySelector('a-sky');
            if (skyElement) {
                skyElement.setAttribute('material', 'src', imageUrl);
                console.log('✅ Панорама обновлена через a-sky');
                return;
            }

            throw new Error('Не удалось обновить панораму');

        } catch (error) {
            console.error('❌ Ошибка применения результата:', error);
            throw error;
        }
    }

    // Показать прогресс
    _showProgress(message, percent) {
        console.log(`📊 Прогресс: ${percent}% - ${message}`);
        
        // Ищем или создаем элемент прогресса
        let progressElement = document.getElementById('retouch-progress');
        if (!progressElement) {
            progressElement = document.createElement('div');
            progressElement.id = 'retouch-progress';
            progressElement.style.cssText = `
                position: fixed;
                top: 50%;
                left: 50%;
                transform: translate(-50%, -50%);
                background: rgba(0, 0, 0, 0.8);
                color: white;
                padding: 20px;
                border-radius: 10px;
                z-index: 10000;
                font-family: Arial, sans-serif;
                text-align: center;
                min-width: 300px;
            `;
            document.body.appendChild(progressElement);
        }

        progressElement.innerHTML = `
            <div>${message}</div>
            <div style="margin: 10px 0; background: #333; border-radius: 5px; overflow: hidden;">
                <div style="background: #4CAF50; height: 20px; width: ${percent}%; transition: width 0.3s;"></div>
            </div>
            <div>${percent}%</div>
            <button onclick="window.retouchManager && window.retouchManager.cancel()" style="margin-top: 10px; padding: 5px 15px; background: #f44336; color: white; border: none; border-radius: 3px; cursor: pointer;">Отменить</button>
        `;
    }

    // Скрыть прогресс
    _hideProgress() {
        const progressElement = document.getElementById('retouch-progress');
        if (progressElement) {
            progressElement.remove();
        }
    }

    // Отмена операции
    cancel() {
        console.log('🛑 Отмена операции ретуши...');
        
        if (this.abortController) {
            this.abortController.abort();
        }
        
        this.isProcessing = false;
        this._hideProgress();
        
        alert('Операция ретуши отменена');
    }

    // Проверка статуса
    getStatus() {
        return {
            isProcessing: this.isProcessing,
            hasMask: !!this._maskDataUrl,
            timeout: this.timeout
        };
    }
}

// Расширяем window объект для совместимости
if (typeof window !== 'undefined') {
    // Создаем глобальный экземпляр
    window.RetouchManagerFixed = RetouchManager;
    
    // Заменяем существующий retouchManager
    if (window.retouchManager) {
        // Сохраняем важные свойства
        const oldMask = window.retouchManager._maskDataUrl;
        
        // Создаем новый экземпляр
        window.retouchManager = new RetouchManager();
        
        // Восстанавливаем маску если была
        if (oldMask) {
            window.retouchManager._maskDataUrl = oldMask;
        }
        
        console.log('🔄 RetouchManager заменен на исправленную версию');
    } else {
        window.retouchManager = new RetouchManager();
    }
}

console.log('✅ FIXED RetouchManager загружен успешно');
EOF

echo "✅ Создан исправленный retouch_manager_fixed.js"

echo ""
echo "🔧 2. СОЗДАНИЕ ПАТЧА ДЛЯ ИНТЕГРАЦИИ"
echo "==================================="

# Создаем скрипт для интеграции исправления
cat > "$WEBROOT/assets/retouch_fix_integration.js" << 'EOF'
/**
 * Интеграция исправленного RetouchManager
 * Загружается после основных скриптов и заменяет проблемный код
 */

(function() {
    console.log('🔧 Загружаем исправление ретуши...');
    
    // Ждем загрузки DOM
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initRetouchFix);
    } else {
        initRetouchFix();
    }
    
    function initRetouchFix() {
        console.log('🚀 Инициализируем исправление ретуши');
        
        // Загружаем исправленный RetouchManager
        const script = document.createElement('script');
        script.src = '/assets/retouch_manager_fixed.js';
        script.onload = function() {
            console.log('✅ Исправленный RetouchManager загружен');
            
            // Патчим кнопку "Готово" если она существует
            patchRetouchButton();
        };
        script.onerror = function() {
            console.error('❌ Ошибка загрузки исправленного RetouchManager');
        };
        
        document.head.appendChild(script);
    }
    
    function patchRetouchButton() {
        // Ищем кнопку "Готово" и перехватываем её обработчик
        const retouchBtn = document.querySelector('.retouch-done-btn, #retouch-done, [data-action="retouch-done"]');
        
        if (retouchBtn) {
            console.log('🎯 Найдена кнопка ретуши, патчим обработчик');
            
            // Удаляем старые обработчики
            const newBtn = retouchBtn.cloneNode(true);
            retouchBtn.parentNode.replaceChild(newBtn, retouchBtn);
            
            // Добавляем новый обработчик
            newBtn.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                
                console.log('🎨 Клик по кнопке "Готово" - используем исправленный RetouchManager');
                
                if (window.retouchManager && window.retouchManager.applyRetouch) {
                    window.retouchManager.applyRetouch().catch(error => {
                        console.error('❌ Ошибка в исправленном RetouchManager:', error);
                    });
                } else {
                    console.error('❌ Исправленный RetouchManager не найден');
                    alert('Ошибка: система ретуши не загружена');
                }
            });
            
            console.log('✅ Кнопка ретуши успешно пропатчена');
        } else {
            console.warn('⚠️ Кнопка ретуши не найдена');
            
            // Повторяем попытку через 1 секунду
            setTimeout(patchRetouchButton, 1000);
        }
    }
})();
EOF

echo "✅ Создан патч интеграции retouch_fix_integration.js"

echo ""
echo "🔧 3. ДОБАВЛЕНИЕ В ОСНОВНОЙ HTML"
echo "==============================="

# Патчим основные HTML файлы для подключения исправления
for html_file in index.html main.html; do
    if [[ -f "$WEBROOT/$html_file" ]]; then
        echo "Патчим $html_file..."
        
        # Проверяем, не добавлен ли уже патч
        if ! grep -q "retouch_fix_integration.js" "$WEBROOT/$html_file"; then
            # Добавляем скрипт исправления перед закрывающим body
            sed -i 's|</body>|    <script src="/assets/retouch_fix_integration.js"></script>\n</body>|' "$WEBROOT/$html_file"
            echo "✅ $html_file обновлен"
        else
            echo "ℹ️ $html_file уже содержит исправление"
        fi
    else
        echo "⚠️ $html_file не найден"
    fi
done

# Патчим панораму
if [[ -f "$WEBROOT/pano/index.html" ]]; then
    echo "Патчим pano/index.html..."
    
    if ! grep -q "retouch_fix_integration.js" "$WEBROOT/pano/index.html"; then
        sed -i 's|</body>|    <script src="/assets/retouch_fix_integration.js"></script>\n</body>|' "$WEBROOT/pano/index.html"
        echo "✅ pano/index.html обновлен"
    else
        echo "ℹ️ pano/index.html уже содержит исправление"
    fi
else
    echo "⚠️ pano/index.html не найден"
fi

echo ""
echo "🔧 4. УСТАНОВКА ПРАВ ДОСТУПА"
echo "============================"

chown -R www-data:www-data "$WEBROOT/assets" 2>/dev/null || true
chmod 644 "$WEBROOT/assets"/*.js 2>/dev/null || true

echo "✅ Права доступа установлены"

echo ""
echo "🧪 5. ПРОВЕРКА ФАЙЛОВ"
echo "===================="

for file in retouch_manager_fixed.js retouch_fix_integration.js; do
    if [[ -f "$WEBROOT/assets/$file" ]]; then
        size=$(stat -c%s "$WEBROOT/assets/$file" 2>/dev/null || echo "0")
        echo "✅ $file создан ($size байт)"
    else
        echo "❌ $file не создан"
    fi
done

echo ""
echo "🎯 РЕЗУЛЬТАТЫ ИСПРАВЛЕНИЯ"
echo "========================"

echo ""
echo "✅ ЧТО ИСПРАВЛЕНО:"
echo "   🔧 Создан RetouchManager с proper async handling"
echo "   ⏰ Добавлен timeout на 5 минут с возможностью отмены"
echo "   📊 Визуальный прогресс-бар с процентами"
echo "   🛡️ Защита от зависания на каждом этапе"
echo "   🔄 AbortController для отмены запросов"
echo "   💾 Правильная обработка blob данных"
echo "   🎨 Безопасное применение результата к панораме"

echo ""
echo "🧪 ТЕСТИРОВАНИЕ:"
echo "1. Откройте https://color360.ru/pano/ в браузере"
echo "2. Откройте консоль разработчика (F12)"
echo "3. Загрузите изображение в редактор"
echo "4. Выделите область для удаления"
echo "5. Нажмите 'Готово'"
echo "6. Должен появиться прогресс-бар"
echo "7. Страница НЕ должна зависнуть"

echo ""
echo "🔍 В КОНСОЛИ ДОЛЖНО БЫТЬ:"
echo "   ✅ 'FIXED RetouchManager загружен успешно'"
echo "   ✅ 'Клик по кнопке Готово - используем исправленный RetouchManager'"
echo "   📊 Сообщения о прогрессе (10%, 30%, 50%, 70%, 90%, 100%)"
echo "   ✅ 'Ретушь успешно завершена' ИЛИ детальная ошибка"

echo ""
echo "📋 Backup сохранен в: $BACKUP_DIR"
echo ""
echo "⚠️ ВАЖНО: Обновите страницу (Ctrl+F5) для загрузки исправлений!"