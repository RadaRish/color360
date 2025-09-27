/**
 * Оптимизированная система управления камерой при переключении сцен
 * Версия 2.0 - Устранение "залипания" и рандомного отображения
 */

// Система плавного управления камерой
export class SmoothCameraController {
    constructor(viewerManager) {
        this.viewerManager = viewerManager;
        this.isTransitioning = false;
        this.transitionTimeout = null;
        this.lockTimeout = null;
    }

    /**
     * Быстрое и плавное переключение камеры на дефолтную позицию
     */
    async setCameraPositionSmooth(cameraPosition, sceneName) {
        if (this.isTransitioning) {
            console.log('🎯 SmoothCamera: переключение уже в процессе, отменяем предыдущее');
            this.cancelTransition();
        }

        this.isTransitioning = true;
        console.log('🎯 SmoothCamera: начинаем плавное переключение для сцены', sceneName);

        try {
            const camera = this.viewerManager.aframeCamera;
            if (!camera) {
                console.warn('🎯 SmoothCamera: камера не найдена');
                return false;
            }

            const lookControls = camera.components && camera.components['look-controls'];
            
            // ШАГ 1: Сразу устанавливаем целевую позицию без отключения управления
            console.log('🎯 SmoothCamera: устанавливаем позицию без блокировки управления');
            const success = this.viewerManager.setCameraPosition(cameraPosition);
            
            if (!success) {
                console.warn('🎯 SmoothCamera: не удалось установить позицию');
                this.isTransitioning = false;
                return false;
            }

            // ШАГ 2: Временно ограничиваем чувствительность look-controls (вместо полного отключения)
            if (lookControls) {
                this.reduceLookControlsSensitivity(lookControls);
            }

            // ШАГ 3: Через короткое время восстанавливаем нормальную чувствительность
            this.transitionTimeout = setTimeout(() => {
                if (lookControls) {
                    this.restoreLookControlsSensitivity(lookControls);
                }
                this.isTransitioning = false;
                console.log('🎯 SmoothCamera: переключение завершено, управление восстановлено');
            }, 500); // Сокращено с 2000мс до 500мс

            console.log('🎯 SmoothCamera: позиция установлена:', cameraPosition);
            return true;

        } catch (error) {
            console.error('🎯 SmoothCamera: ошибка переключения:', error);
            this.isTransitioning = false;
            return false;
        }
    }

    /**
     * Уменьшение чувствительности look-controls без полного отключения
     */
    reduceLookControlsSensitivity(lookControls) {
        if (!lookControls.data) return;

        // Сохраняем оригинальные значения
        lookControls._originalSensitivity = {
            mouseSensitivity: lookControls.data.mouseSensitivity || 1,
            touchSensitivity: lookControls.data.touchSensitivity || 1
        };

        // Значительно уменьшаем чувствительность
        lookControls.data.mouseSensitivity = 0.1;
        lookControls.data.touchSensitivity = 0.1;

        console.log('🎯 SmoothCamera: чувствительность управления снижена');
    }

    /**
     * Восстановление нормальной чувствительности look-controls
     */
    restoreLookControlsSensitivity(lookControls) {
        if (!lookControls._originalSensitivity) return;

        // Восстанавливаем оригинальные значения
        lookControls.data.mouseSensitivity = lookControls._originalSensitivity.mouseSensitivity;
        lookControls.data.touchSensitivity = lookControls._originalSensitivity.touchSensitivity;

        delete lookControls._originalSensitivity;
        console.log('🎯 SmoothCamera: чувствительность управления восстановлена');
    }

    /**
     * Отмена текущего переключения
     */
    cancelTransition() {
        if (this.transitionTimeout) {
            clearTimeout(this.transitionTimeout);
            this.transitionTimeout = null;
        }

        if (this.lockTimeout) {
            clearTimeout(this.lockTimeout);
            this.lockTimeout = null;
        }

        // Восстанавливаем управление если было изменено
        const camera = this.viewerManager.aframeCamera;
        const lookControls = camera && camera.components && camera.components['look-controls'];
        
        if (lookControls && lookControls._originalSensitivity) {
            this.restoreLookControlsSensitivity(lookControls);
        }

        this.isTransitioning = false;
        console.log('🎯 SmoothCamera: переключение отменено');
    }

    /**
     * Немедленная установка позиции без анимации (для экстренных случаев)
     */
    setCameraPositionImmediate(cameraPosition, sceneName) {
        console.log('🎯 SmoothCamera: немедленная установка позиции для', sceneName);
        
        this.cancelTransition(); // Отменяем все активные переходы
        
        const success = this.viewerManager.setCameraPosition(cameraPosition);
        if (success) {
            console.log('🎯 SmoothCamera: позиция установлена немедленно:', cameraPosition);
        }
        
        return success;
    }

    /**
     * Проверка состояния переключения
     */
    isTransitionActive() {
        return this.isTransitioning;
    }

    /**
     * Принудительная остановка всех переходов
     */
    forceStop() {
        this.cancelTransition();
        console.log('🎯 SmoothCamera: принудительная остановка всех переходов');
    }
}

// Альтернативная стратегия: предварительная загрузка позиции
export class PredictiveCameraController {
    constructor(viewerManager) {
        this.viewerManager = viewerManager;
        this.preloadedPositions = new Map();
    }

    /**
     * Предварительное сохранение позиции для сцены
     */
    preloadScenePosition(sceneId, cameraPosition) {
        this.preloadedPositions.set(sceneId, cameraPosition);
        console.log('🎯 PredictiveCamera: позиция предзагружена для сцены', sceneId);
    }

    /**
     * Мгновенное применение предзагруженной позиции
     */
    applyPreloadedPosition(sceneId) {
        const position = this.preloadedPositions.get(sceneId);
        if (!position) {
            console.log('🎯 PredictiveCamera: позиция для сцены', sceneId, 'не предзагружена');
            return false;
        }

        console.log('🎯 PredictiveCamera: применяем предзагруженную позицию для', sceneId);
        
        // Устанавливаем позицию мгновенно, до того как пользователь заметит
        const success = this.viewerManager.setCameraPosition(position);
        
        if (success) {
            console.log('🎯 PredictiveCamera: предзагруженная позиция применена');
        }
        
        return success;
    }

    /**
     * Очистка кэша позиций
     */
    clearCache() {
        this.preloadedPositions.clear();
        console.log('🎯 PredictiveCamera: кэш позиций очищен');
    }
}

// Интеграция в ViewerManager
export function integrateSmoothCameraControl(viewerManager) {
    // Создаем контроллеры
    viewerManager._smoothCameraController = new SmoothCameraController(viewerManager);
    viewerManager._predictiveCameraController = new PredictiveCameraController(viewerManager);
    
    // Добавляем методы в ViewerManager
    viewerManager.setCameraPositionSmooth = function(cameraPosition, sceneName) {
        return this._smoothCameraController.setCameraPositionSmooth(cameraPosition, sceneName);
    };
    
    viewerManager.setCameraPositionImmediate = function(cameraPosition, sceneName) {
        return this._smoothCameraController.setCameraPositionImmediate(cameraPosition, sceneName);
    };
    
    viewerManager.preloadScenePosition = function(sceneId, cameraPosition) {
        return this._predictiveCameraController.preloadScenePosition(sceneId, cameraPosition);
    };
    
    viewerManager.applyPreloadedPosition = function(sceneId) {
        return this._predictiveCameraController.applyPreloadedPosition(sceneId);
    };
    
    viewerManager.isCameraTransitioning = function() {
        return this._smoothCameraController.isTransitionActive();
    };
    
    viewerManager.stopCameraTransitions = function() {
        this._smoothCameraController.forceStop();
    };
    
    console.log('🎯 SmoothCameraControl: интегрирован в ViewerManager');
}