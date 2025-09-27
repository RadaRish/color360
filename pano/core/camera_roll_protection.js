/**
 * Система агрессивного предотвращения camera roll (наклона) для A-Frame
 * Версия 3.0 - Максимально эффективная защита от перекоса при вертикальном движении
 */

// Глобальный флаг для отслеживания системы
window.CAMERA_ROLL_PROTECTION_ACTIVE = true;

// Универсальная функция исправления roll для любого объекта
function forceCorrectRotation(obj3d, debugPrefix = '') {
    if (!obj3d || !obj3d.rotation) return false;
    
    let corrected = false;
    
    // Исправляем Z-rotation (roll) - должно быть 0
    if (Math.abs(obj3d.rotation.z) > 0.0001) {
        if (debugPrefix) console.log(`${debugPrefix}: исправляем roll ${obj3d.rotation.z} → 0`);
        obj3d.rotation.z = 0;
        corrected = true;
    }
    
    // Ограничиваем pitch (X-rotation) в разумных пределах
    const maxPitch = Math.PI / 2.1; // ~85 градусов
    if (obj3d.rotation.x > maxPitch) {
        if (debugPrefix) console.log(`${debugPrefix}: ограничиваем pitch ${obj3d.rotation.x} → ${maxPitch}`);
        obj3d.rotation.x = maxPitch;
        corrected = true;
    } else if (obj3d.rotation.x < -maxPitch) {
        if (debugPrefix) console.log(`${debugPrefix}: ограничиваем pitch ${obj3d.rotation.x} → ${-maxPitch}`);
        obj3d.rotation.x = -maxPitch;
        corrected = true;
    }
    
    if (corrected) {
        obj3d.updateMatrixWorld(true);
    }
    
    return corrected;
}

// Исправление quaternion
function forceCorrectQuaternion(obj3d, debugPrefix = '') {
    if (!obj3d || !obj3d.quaternion) return false;
    
    // Конвертируем quaternion в Euler углы
    const euler = new THREE.Euler();
    euler.setFromQuaternion(obj3d.quaternion, 'YXZ');
    
    let corrected = false;
    
    // Исправляем roll (Z)
    if (Math.abs(euler.z) > 0.0001) {
        if (debugPrefix) console.log(`${debugPrefix}: исправляем quaternion roll ${euler.z} → 0`);
        euler.z = 0;
        corrected = true;
    }
    
    // Ограничиваем pitch (X)
    const maxPitch = Math.PI / 2.1;
    if (euler.x > maxPitch) {
        euler.x = maxPitch;
        corrected = true;
    } else if (euler.x < -maxPitch) {
        euler.x = -maxPitch;
        corrected = true;
    }
    
    if (corrected) {
        obj3d.quaternion.setFromEuler(euler);
        obj3d.updateMatrixWorld(true);
    }
    
    return corrected;
}

// Агрессивная защита A-Frame камеры от roll
function protectCameraFromRoll(camera) {
    if (!camera) return;
    
    // 1. Исправляем основной object3D
    forceCorrectRotation(camera.object3D, '🎯 Camera.object3D');
    forceCorrectQuaternion(camera.object3D, '🎯 Camera.quaternion');
    
    // 2. Исправляем A-Frame атрибуты
    const rotation = camera.getAttribute('rotation');
    if (rotation && (Math.abs(rotation.z) > 0.0001 || Math.abs(rotation.x) > 85)) {
        const maxPitch = 85;
        const newX = Math.max(-maxPitch, Math.min(maxPitch, rotation.x || 0));
        const newRotation = `${newX} ${rotation.y || 0} 0`;
        camera.setAttribute('rotation', newRotation);
    }
    
    // 3. Исправляем look-controls компонент
    const lookControls = camera.components && camera.components['look-controls'];
    if (lookControls) {
        // Исправляем pitchObject
        if (lookControls.pitchObject) {
            forceCorrectRotation(lookControls.pitchObject, '🎯 PitchObject');
            // Убираем Y и Z повороты с pitch объекта - только X!
            if (lookControls.pitchObject.rotation.y !== 0) {
                lookControls.pitchObject.rotation.y = 0;
            }
            if (lookControls.pitchObject.rotation.z !== 0) {
                lookControls.pitchObject.rotation.z = 0;
            }
        }
        
        // Исправляем yawObject  
        if (lookControls.yawObject) {
            forceCorrectRotation(lookControls.yawObject, '🎯 YawObject');
            // Убираем X и Z повороты с yaw объекта - только Y!
            if (lookControls.yawObject.rotation.x !== 0) {
                lookControls.yawObject.rotation.x = 0;
            }
            if (lookControls.yawObject.rotation.z !== 0) {
                lookControls.yawObject.rotation.z = 0;
            }
        }
    }
    
    // 4. Исправляем все дочерние объекты камеры
    if (camera.object3D && camera.object3D.children) {
        camera.object3D.children.forEach((child, index) => {
            forceCorrectRotation(child, `🎯 Camera.child[${index}]`);
            forceCorrectQuaternion(child, `🎯 Camera.child[${index}].quat`);
        });
    }
}

// Создание системы защиты от roll
export function createCameraRollProtection(viewerManager) {
    if (!viewerManager || !viewerManager.aframeCamera) {
        console.warn('🎯 CameraRollProtection: нет камеры для защиты');
        return null;
    }
    
    const camera = viewerManager.aframeCamera;
    const protectionSystem = {
        active: true,
        intervals: [],
        
        // Агрессивный интервал защиты - каждые 16мс (60fps)
        startAggressiveProtection() {
            // Очищаем старые интервалы
            this.intervals.forEach(clearInterval);
            this.intervals = [];
            
            // Супер-частая проверка (60fps)
            const highFreqInterval = setInterval(() => {
                if (!this.active) return;
                protectCameraFromRoll(camera);
            }, 16);
            
            // Дополнительная проверка (30fps)
            const mediumFreqInterval = setInterval(() => {
                if (!this.active) return;
                protectCameraFromRoll(camera);
            }, 33);
            
            // Резервная проверка (10fps)
            const lowFreqInterval = setInterval(() => {
                if (!this.active) return;
                protectCameraFromRoll(camera);
            }, 100);
            
            this.intervals.push(highFreqInterval, mediumFreqInterval, lowFreqInterval);
            console.log('🎯 Агрессивная защита от roll запущена (60fps + 30fps + 10fps)');
        },
        
        // Перехват всех событий камеры
        interceptCameraEvents() {
            // Перехват componentchanged
            camera.addEventListener('componentchanged', (event) => {
                if (event.detail.name === 'rotation' && this.active) {
                    setTimeout(() => protectCameraFromRoll(camera), 0);
                }
            });
            
            // Перехват loaded события
            camera.addEventListener('loaded', () => {
                this.hackLookControls();
            });
            
            // Если уже загружено, сразу хакаем
            if (camera.hasLoaded) {
                this.hackLookControls();
            }
        },
        
        // Хакинг look-controls компонента
        hackLookControls() {
            const lookControls = camera.components && camera.components['look-controls'];
            if (!lookControls) {
                setTimeout(() => this.hackLookControls(), 100);
                return;
            }
            
            console.log('🎯 Хакаем look-controls для защиты от roll');
            
            // Перехват update метода
            if (lookControls.update && !lookControls.update._rollProtectionHacked) {
                const originalUpdate = lookControls.update;
                lookControls.update = function(dt) {
                    const result = originalUpdate.call(this, dt);
                    if (protectionSystem.active) {
                        protectCameraFromRoll(camera);
                    }
                    return result;
                };
                lookControls.update._rollProtectionHacked = true;
            }
            
            // Перехват onMouseMove
            if (lookControls.onMouseMove && !lookControls.onMouseMove._rollProtectionHacked) {
                const originalMouseMove = lookControls.onMouseMove;
                lookControls.onMouseMove = function(event) {
                    const result = originalMouseMove.call(this, event);
                    if (protectionSystem.active) {
                        // Немедленная коррекция после движения мыши
                        protectCameraFromRoll(camera);
                        // И еще раз через микрозадачу
                        Promise.resolve().then(() => {
                            if (protectionSystem.active) {
                                protectCameraFromRoll(camera);
                            }
                        });
                    }
                    return result;
                };
                lookControls.onMouseMove._rollProtectionHacked = true;
            }
            
            // Перехват onTouchMove
            if (lookControls.onTouchMove && !lookControls.onTouchMove._rollProtectionHacked) {
                const originalTouchMove = lookControls.onTouchMove;
                lookControls.onTouchMove = function(event) {
                    const result = originalTouchMove.call(this, event);
                    if (protectionSystem.active) {
                        protectCameraFromRoll(camera);
                        Promise.resolve().then(() => {
                            if (protectionSystem.active) {
                                protectCameraFromRoll(camera);
                            }
                        });
                    }
                    return result;
                };
                lookControls.onTouchMove._rollProtectionHacked = true;
            }
        },
        
        // Запуск полной защиты
        start() {
            this.active = true;
            this.startAggressiveProtection();
            this.interceptCameraEvents();
            
            // Немедленная коррекция
            protectCameraFromRoll(camera);
            
            console.log('🎯 Система защиты от camera roll запущена');
        },
        
        // Остановка защиты
        stop() {
            this.active = false;
            this.intervals.forEach(clearInterval);
            this.intervals = [];
            console.log('🎯 Система защиты от camera roll остановлена');
        }
    };
    
    return protectionSystem;
}

// Интеграция в ViewerManager
export function integrateCameraRollProtection(viewerManager) {
    // Ждем инициализации камеры
    const waitForCamera = () => {
        if (!viewerManager.aframeCamera) {
            setTimeout(waitForCamera, 50);
            return;
        }
        
        // Создаем и запускаем систему защиты
        viewerManager._rollProtection = createCameraRollProtection(viewerManager);
        if (viewerManager._rollProtection) {
            viewerManager._rollProtection.start();
        }
    };
    
    waitForCamera();
}