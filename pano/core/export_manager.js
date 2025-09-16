/**
 * Менеджер экспорта панорамных туров
 * Экспортирует готовое A-Frame приложение для размещения на сервере
 * Использует нашу разработанную систему с поддержкой кириллицы и кастомных иконок
 */
class ExportManager {
    constructor(sceneManager, hotspotManager, projectManager) {
        this.exportData = null;
        this.sceneManager = sceneManager;
        this.hotspotManager = hotspotManager;
        this.projectManager = projectManager;
    }

    /**
     * Создает тестовые данные для отладки экспорта
     */
    createTestProjectData() {
        return {
            projectTitle: 'Тестовый панорамный тур',
            scenes: [
                {
                    id: 'test-scene-1',
                    name: 'Тестовая сцена 1',
                    panoramaFile: 'test-scene-1.jpg',
                    panoramaData: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjU2IiBoZWlnaHQ9IjEyOCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48ZGVmcz48bGluZWFyR3JhZGllbnQgaWQ9ImdyYWQiIHgxPSIwJSIgeTE9IjAlIiB4Mj0iMTAwJSIgeTI9IjEwMCUiPjxzdG9wIG9mZnNldD0iMCUiIHN0b3AtY29sb3I9IiMxZTI5M2IiLz48c3RvcCBvZmZzZXQ9IjEwMCUiIHN0b3AtY29sb3I9IiMyZDNhNGYiLz48L2xpbmVhckdyYWRpZW50PjwvZGVmcz48cmVjdCB3aWR0aD0iMjU2IiBoZWlnaHQ9IjEyOCIgZmlsbD0idXJsKCNncmFkKSIvPjx0ZXh0IHg9IjUwJSIgeT0iNTAlIiBkb21pbmFudC1iYXNlbGluZT0iY2VudGVyIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LWZhbWlseT0iQXJpYWwiIGZvbnQtc2l6ZT0iMTQiIGZpbGw9IiNmZmYiPtCi0LXRgdGC0L7QstCw0Y8g0YHRhtC10L3QsCA8L3RleHQ+PC9zdmc+', // SVG заглушка
                    hotspots: [
                        {
                            id: 'test-hotspot-1',
                            position: { x: 1, y: 0, z: -3 },
                            title: 'Тестовый хотспот',
                            description: 'Описание тестового хотспота',
                            type: 'info-point',
                            color: '#ff0000',
                            size: 0.3
                        },
                        {
                            id: 'test-hotspot-2',
                            position: { x: -2, y: 1, z: -4 },
                            title: 'Навигационный хотспот',
                            type: 'hotspot',
                            targetSceneId: 'test-scene-2',
                            color: '#00ff00',
                            size: 0.4
                        }
                    ],
                    initialView: { yaw: 0, pitch: 0, fov: Math.PI / 3 }
                },
                {
                    id: 'test-scene-2',
                    name: 'Тестовая сцена 2',
                    panoramaFile: 'test-scene-2.jpg',
                    panoramaData: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjU2IiBoZWlnaHQ9IjEyOCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48ZGVmcz48bGluZWFyR3JhZGllbnQgaWQ9ImdyYWQyIiB4MT0iMCUiIHkxPSIwJSIgeDI9IjEwMCUiIHkyPSIxMDAlIj48c3RvcCBvZmZzZXQ9IjAlIiBzdG9wLWNvbG9yPSIjMmQxYjY5Ii8+PHN0b3Agb2Zmc2V0PSIxMDAlIiBzdG9wLWNvbG9yPSIjMWUzYTRmIi8+PC9saW5lYXJHcmFkaWVudD48L2RlZnM+PHJlY3Qgd2lkdGg9IjI1NiIgaGVpZ2h0PSIxMjgiIGZpbGw9InVybCgjZ3JhZDIpIi8+PHRleHQgeD0iNTAlIiB5PSI1MCUiIGRvbWluYW50LWJhc2VsaW5lPSJjZW50ZXIiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtZmFtaWx5PSJBcmlhbCIgZm9udC1zaXplPSIxNCIgZmlsbD0iI2ZmZiI+0KLQtdGB0YLQvtCy0LDRjyDRgdGG0LXQvdCwIDI8L3RleHQ+PC9zdmc+',
                    hotspots: [
                        {
                            id: 'test-hotspot-3',
                            position: { x: 0, y: -1, z: -5 },
                            title: 'Возврат',
                            type: 'hotspot',
                            targetSceneId: 'test-scene-1',
                            color: '#0000ff',
                            size: 0.3
                        }
                    ],
                    initialView: { yaw: 0, pitch: 0, fov: Math.PI / 3 }
                }
            ],
            settings: {
                autorotate: false,
                showSceneList: true,
                fullscreenButton: true
            }
        };
    }

    /**
     * Экспорт тестового проекта для отладки
     */
    async exportTestProject() {
        try {

            const testData = this.createTestProjectData();

            // Создаем структуру файлов для экспорта
            const exportPackage = await this.createExportPackage(testData);

            // Генерируем и скачиваем ZIP архив
            await this.downloadExportPackage(exportPackage);

        } catch (error) {
            console.error('❌ [TEST EXPORT] Ошибка при тестовом экспорте:', error);
        }
    }
    removeFileExtension(filename) {
        if (!filename || typeof filename !== 'string') {
            return filename;
        }

        // Список распространенных расширений видео и изображений
        const videoExtensions = ['.mp4', '.avi', '.mov', '.webm', '.mkv', '.flv', '.wmv', '.m4v', '.3gp', '.ogv'];
        const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.svg', '.webp', '.tiff', '.ico'];
        const allExtensions = [...videoExtensions, ...imageExtensions];

        const lowerFilename = filename.toLowerCase();

        for (const ext of allExtensions) {
            if (lowerFilename.endsWith(ext)) {
                return filename.slice(0, -ext.length);
            }
        }

        return filename;
    }

    /**
     * Экспорт проекта в готовое приложение
     */
    async exportProject() {
        // start export

        try {
            // Получаем все данные проекта
            const projectData = await this.collectProjectData();

            // Создаем структуру файлов для экспорта
            const exportPackage = await this.createExportPackage(projectData);

            // Генерируем и скачиваем ZIP архив
            await this.downloadExportPackage(exportPackage);

            // export done

        } catch (error) {
            console.error('❌ Ошибка при экспорте:', error);
            alert('Ошибка при экспорте проекта: ' + error.message);
        }
    }

    /**
     * Собирает все данные проекта
     */
    async collectProjectData() {
        // collecting project data

        const scenes = this.sceneManager.getAllScenes();
        const projectInfo = this.projectManager.getProjectInfo();

        // scenes count: %d
        // eslint-disable-next-line no-unused-expressions
        scenes.length;
        scenes.forEach((scene, i) => {
            // scene info
        });

        // Очищаем хотспоты, которые принадлежат несуществующим сценам
        const validSceneIds = scenes.map(scene => scene.id);
        const orphanedCount = this.hotspotManager.cleanupOrphanedHotspots(validSceneIds);
        if (orphanedCount > 0) {
            // cleaned orphaned hotspots
        }

        // Получаем ВСЕ хотспоты для диагностики (текущее состояние в памяти ДО выборки по сценам)
        const allHotspotsInitial = this.hotspotManager.getHotspots();

        if (allHotspotsInitial.length) {

        }

        // Карта распределения хотспотов по сценам (предварительная)
        const distributionInitial = {};
        allHotspotsInitial.forEach(h => { distributionInitial[h.sceneId] = (distributionInitial[h.sceneId] || 0) + 1; });

        // Подготовим карту соответствия editorId -> exportId (первый проход)
        const idMap = {};
        scenes.forEach((scene, index) => {
            const exportId = this.generateSceneId(scene.name, index);
            idMap[scene.id] = exportId;
        });

        // Собираем информацию о каждой сцене (второй проход)
        const exportScenes = [];
        for (let index = 0; index < scenes.length; index++) {
            const scene = scenes[index];

            // Основной способ – получить хотспоты через менеджер (форсирует загрузку из localStorage)
            let hotspots = this.hotspotManager.getHotspotsForScene(scene.id) || [];

            // Fallback 1: если пусто, но в объекте сцены есть хотспоты
            if (hotspots.length === 0 && scene.hotspots && scene.hotspots.length) {

                hotspots = scene.hotspots;
            }
            // Fallback 2: если всё ещё пусто, попробуем взять из общего массива (по sceneId)
            if (hotspots.length === 0) {
                const allAfterLoad = this.hotspotManager.getHotspots(); // после потенциальной loadFromStorage внутри getHotspotsForScene
                const matching = allAfterLoad.filter(h => h.sceneId === scene.id);
                if (matching.length) {

                    hotspots = matching;
                }
            }
            if (hotspots.length === 0) {

            } else {

            }
            // ВАЖНО: перед конвертацией попытаемся заполнить отсутствующие videoUrl (реестр/IndexedDB/legacy)
            await this.fillMissingVideoUrls(hotspots);

            const convertedHotspots = hotspots.map(hotspot => this.convertHotspot(hotspot, idMap));
            // Проверяем корректность конвертации позиций
            convertedHotspots.forEach(ch => {
                if (!ch.position || typeof ch.position.x !== 'number') {

                }
            });

            // Получаем текущие настройки камеры для сцены
            let initialView = {
                yaw: 0,
                pitch: 0,
                fov: 80 // 80 градусов как в редакторе (стандартный FOV)
            };

            // 0) Если у сцены уже сохранена позиция камеры — используем её в приоритете
            let hasSceneSavedCamera = false;
            if (scene.cameraPosition && scene.cameraPosition.rotation) {
                try {
                    if (typeof scene.cameraPosition.rotation.x === 'number') {
                        initialView.pitch = scene.cameraPosition.rotation.x;
                        hasSceneSavedCamera = true;
                    }
                    if (typeof scene.cameraPosition.rotation.y === 'number') {
                        initialView.yaw = scene.cameraPosition.rotation.y;
                        hasSceneSavedCamera = true;
                    }
                    // Если есть FOV - берём его
                    if (typeof scene.cameraPosition.fov === 'number' && !isNaN(scene.cameraPosition.fov)) {
                        initialView.fov = Math.max(10, Math.min(130, scene.cameraPosition.fov));
                    }
                } catch (_) {}
            }

            // 1) Пытаемся получить реальные настройки камеры из viewer manager (ТОЛЬКО если у сцены нет своей сохранённой позиции)
            if (!hasSceneSavedCamera && this.viewerManager && typeof this.viewerManager.getCameraPosition === 'function') {
                try {
                    const cameraData = this.viewerManager.getCameraPosition();
                    if (cameraData && cameraData.rotation) {
                        // rotation.x = pitch, rotation.y = yaw, rotation.z = roll
                        initialView.pitch = (cameraData.rotation.x ?? initialView.pitch) || 0;
                        initialView.yaw = (cameraData.rotation.y ?? initialView.yaw) || 0;

                        // Пытаемся получить текущий FOV
                        const camera = this.viewerManager.aframeCamera;
                        if (camera) {
                            // Для A-Frame камера задается через компонент 'camera'
                            const camComp = camera.getAttribute('camera') || {};
                            const currentFov = parseFloat(camComp.fov) || 80;
                            initialView.fov = currentFov;
                        }

                        console.log('✅ [EXPORT] Получены настройки камеры от viewerManager для сцены', scene.name, ':', {
                            pitch: initialView.pitch,
                            yaw: initialView.yaw,
                            fov: initialView.fov
                        });
                    }
                } catch (error) {

                }
            }

            // Альтернативно - пытаемся получить из самой сцены если есть сохраненные настройки
            if (scene.initialView) {
                initialView = {
                    yaw: (scene.initialView.yaw ?? initialView.yaw),
                    pitch: (scene.initialView.pitch ?? initialView.pitch),
                    fov: (scene.initialView.fov ?? initialView.fov)
                };

            }

            exportScenes.push({
                id: idMap[scene.id],
                name: scene.name,
                panoramaFile: scene.name || `scene_${index}.jpg`,
                panoramaData: scene.src, // URL или Data URL изображения
                hotspots: convertedHotspots,
                initialView: initialView
            });
        }

        // Итоговая проверка распределения уже в exportScenes
        const exportDistribution = {};
        exportScenes.forEach(s => { exportDistribution[s.id] = s.hotspots.length; });

        // Сохраняем debug-данные глобально для ручного анализа из консоли
        window.__EXPORT_DEBUG__ = {
            timestamp: Date.now(),
            scenes: exportScenes.map(s => ({ id: s.id, name: s.name, hotspots: s.hotspots.length })),
            totalHotspotsInitial: allHotspotsInitial.length,
            exportDistribution,
            orphanedCount,
            distributionInitial
        };

        return {
            projectTitle: projectInfo.title || 'Панорамный тур',
            scenes: exportScenes,
            settings: {
                autorotate: projectInfo.autorotate || false,
                showSceneList: projectInfo.showSceneList !== false,
                fullscreenButton: projectInfo.fullscreenButton !== false
            }
        };
    }

    /**
     * Дополняет хотспоты отсутствующими videoUrl из доступных источников:
     * - реестр видео (localStorage)
     * - IndexedDB ('color_tour_videos')
     * - legacy поля _originalData.videoUrl / videoData
     */
    async fillMissingVideoUrls(hotspots) {
        try {
            if (!Array.isArray(hotspots) || hotspots.length === 0) return;
            const hm = this.hotspotManager;
            let db = null;
            for (const h of hotspots) {
                if (!h) continue;
                const isVideoType = (h.type === 'video-area' || h.type === 'animated-object');
                if (!isVideoType) continue;
                if (h.videoUrl && String(h.videoUrl).trim() !== '') continue;

                // 1) Реестр
                try {
                    if (hm && typeof hm.getVideoUrlFromRegistry === 'function') {
                        const reg = hm.getVideoUrlFromRegistry(h.id);
                        if (reg) { h.videoUrl = reg; h.hasVideo = true; continue; }
                    }
                } catch { }

                // 2) IndexedDB
                try {
                    if (hm && typeof hm._openVideoDB === 'function') {
                        if (!db) { try { db = await hm._openVideoDB(); } catch { db = null; } }
                        if (db) {
                            const v = await new Promise(res => {
                                const tx = db.transaction('videos', 'readonly');
                                const rq = tx.objectStore('videos').get(h.id);
                                rq.onsuccess = () => res(rq.result && rq.result.data);
                                rq.onerror = () => res(null);
                            });
                            if (v) { h.videoUrl = v; h.hasVideo = true; continue; }
                        }
                    }
                } catch { }

                // 3) Legacy _originalData
                try {
                    const od = h._originalData || {};
                    const raw = od.videoUrl || od.videoData;
                    if (typeof raw === 'string' && raw.trim()) {
                        let dataUrl = raw;
                        if (!raw.startsWith('data:video')) {
                            const cleaned = raw.replace(/^base64,/i, '');
                            dataUrl = `data:video/mp4;base64,${cleaned}`;
                        }
                        h.videoUrl = dataUrl; h.hasVideo = true; continue;
                    }
                } catch { }
            }
        } catch (e) {

        }
    }

    /**
     * Генерирует безопасный ID для сцены
     */
    generateSceneId(sceneName, index) {
        // Убираем небезопасные символы и создаем уникальный ID
        const cleanName = sceneName
            .replace(/[^a-zA-Zа-яА-Я0-9]/g, '-')
            .replace(/-+/g, '-')
            .replace(/^-|-$/g, '');

        return `scene-${index}-${cleanName}`;
    }

    /**
     * Применяет начальный вид камеры для сцены
     */
    applyInitialView(scene) {
        const camera = document.querySelector('#tour-camera');
        if (!camera || !scene.initialView) {

            return;
        }

        // Устанавливаем FOV
        if (scene.initialView.fov) {
            camera.setAttribute('fov', scene.initialView.fov);
        }

        // Устанавливаем поворот камеры
        if (scene.initialView.rotation) {
            // Используем готовую строку rotation
            camera.setAttribute('rotation', scene.initialView.rotation);

        } else if (scene.initialView.yaw !== undefined || scene.initialView.pitch !== undefined) {
            // Вычисляем rotation из yaw/pitch
            const yaw = scene.initialView.yaw || 0;
            const pitch = scene.initialView.pitch || 0;
            const roll = 0; // обычно roll = 0 для панорам
            
            const rotationString = pitch + ' ' + yaw + ' ' + roll;
            camera.setAttribute('rotation', rotationString);

        }
    }

    /**
     * Генерирует безопасный ID для элемента панорамы в экспорте
     */
    generatePanoramaElementId(sceneName, index) {
        // Убираем небезопасные символы и создаем ID для элемента панорамы
        const cleanName = sceneName
            .replace(/[^a-zA-Zа-яА-Я0-9]/g, '-')
            .replace(/-+/g, '-')
            .replace(/^-|-$/g, '');

        return `scene-${index}-${cleanName}-panorama`;
    }

    /**
     * Создает современный SVG маркер со стрелкой (синхронизировано с редактором)
     */
    createModernArrowSVG(color, size, options = {}) {
        const noFill = !!options.noFill;
        const highResolution = 512;
        const center = highResolution / 2;
        const iconSize = center * 0.4;

        return `<svg width="${highResolution}" height="${highResolution}" viewBox="0 0 ${highResolution} ${highResolution}" xmlns="http://www.w3.org/2000/svg">
            <defs>
                <radialGradient id="gradient-hotspot" cx="40%" cy="30%" r="60%">
                    <stop offset="0%" stop-color="#64B5F6" stop-opacity="1"/>
                    <stop offset="60%" stop-color="#2196F3" stop-opacity="0.9"/>
                    <stop offset="100%" stop-color="#42A5F5" stop-opacity="0.8"/>
                </radialGradient>
                <filter id="glow-hotspot" x="-100%" y="-100%" width="300%" height="300%">
                    <feGaussianBlur stdDeviation="8" result="coloredBlur"/>
                    <feMerge>
                        <feMergeNode in="coloredBlur"/>
                        <feMergeNode in="SourceGraphic"/>
                    </feMerge>
                </filter>
            </defs>
            <g class="marker-content">
                <!-- Основной фон маркера -->
                <polygon points="${center},${center * 0.3} ${center * 1.4},${center * 0.8} ${center * 1.15},${center * 0.8} ${center * 1.15},${center * 1.4} ${center * 0.85},${center * 1.4} ${center * 0.85},${center * 0.8} ${center * 0.6},${center * 0.8}" 
                         fill="${noFill ? 'none' : 'url(#gradient-hotspot)'}" 
                         filter="url(#glow-hotspot)" 
                         stroke="rgba(255, 255, 255, 0.4)" 
                         stroke-width="3"/>
                <!-- Стрелка (увеличенная в 2 раза) -->
                <g fill="${noFill ? 'none' : '#ffffff'}" opacity="0.95">
                    <circle cx="${center}" cy="${center}" r="${iconSize}" fill="none" stroke="#ffffff" stroke-width="8"/>
                    <polygon points="${center},${center - iconSize * 1.6} ${center - iconSize * 0.6},${center + iconSize * 0.6} ${center},${center} ${center + iconSize * 0.6},${center + iconSize * 0.6}" ${noFill ? 'fill="none" stroke="#ffffff" stroke-width="6"' : 'fill="#ffffff"'}/>
                </g>
            </g>
        </svg>`;
    }

    /**
     * Создает современный SVG маркер с иконкой "i" (синхронизировано с редактором)
     */
    createModernInfoSVG(color, size, options = {}) {
        const noFill = !!options.noFill;
        const highResolution = 512;
        const center = highResolution / 2;
        const iconSize = center * 0.4;

        return `<svg width="${highResolution}" height="${highResolution}" viewBox="0 0 ${highResolution} ${highResolution}" xmlns="http://www.w3.org/2000/svg">
            <defs>
                <radialGradient id="gradient-info" cx="40%" cy="30%" r="60%">
                    <stop offset="0%" stop-color="#81C784" stop-opacity="1"/>
                    <stop offset="60%" stop-color="#4CAF50" stop-opacity="0.9"/>
                    <stop offset="100%" stop-color="#66BB6A" stop-opacity="0.8"/>
                </radialGradient>
                <filter id="glow-info" x="-100%" y="-100%" width="300%" height="300%">
                    <feGaussianBlur stdDeviation="8" result="coloredBlur"/>
                    <feMerge>
                        <feMergeNode in="coloredBlur"/>
                        <feMergeNode in="SourceGraphic"/>
                    </feMerge>
                </filter>
            </defs>
            <g class="marker-content">
                <!-- Основной фон маркера -->
                <circle cx="${center}" cy="${center}" r="${center * 0.7}" 
                        fill="${noFill ? 'none' : 'url(#gradient-info)'}" 
                        filter="url(#glow-info)" 
                        stroke="rgba(255, 255, 255, 0.4)" 
                        stroke-width="3"/>
                <!-- Иконка "i" в круге -->
                <g>
                    <circle cx="${center}" cy="${center}" r="${iconSize * 0.9}" ${noFill ? 'fill="none" stroke="#ffffff" stroke-width="4"' : 'fill="#ffffff" stroke="#ffffff" stroke-width="4"'}/>
                    <circle cx="${center}" cy="${center - iconSize * 0.3}" r="${iconSize * 0.12}" ${noFill ? 'fill="none" stroke="#4CAF50" stroke-width="4"' : 'fill="#4CAF50"'}/>
                    <rect x="${center - iconSize * 0.08}" y="${center - iconSize * 0.05}" width="${iconSize * 0.16}" height="${iconSize * 0.6}" ${noFill ? 'fill="none" stroke="#4CAF50" stroke-width="6"' : 'fill="#4CAF50"'} rx="${iconSize * 0.04}"/>
                </g>
            </g>
        </svg>`;
    }

    /**
     * Конвертирует хотспот в формат для экспорта
     */
    convertHotspot(hotspot, idMap) {
        // convert hotspot

        const converted = {
            id: hotspot.id,
            position: {
                x: hotspot.position?.x || 0,
                y: hotspot.position?.y || 0,
                z: hotspot.position?.z || 0
            },
            title: hotspot.title ? this.removeFileExtension(hotspot.title) : 'Без названия',
            description: (hotspot.description ?? hotspot._originalData?.description ?? ''),
            type: hotspot.type || 'hotspot',
            targetSceneId: hotspot.targetSceneId || null, // временно, перепишем ниже через idMap
            icon: hotspot.icon || (hotspot.type === 'hotspot' ? 'arrow' :
                hotspot.type === 'info-point' ? 'sphere' :
                    hotspot.type === 'video-area' ? 'cube' :
                        hotspot.type === 'animated-object' ? 'cube' : 'sphere'),
            size: hotspot.size || 0.3,
            color: hotspot.color || (hotspot.type === 'info-point' ? '#ffcc00' :
                hotspot.type === 'video-area' ? '#ff6600' :
                    hotspot.type === 'animated-object' ? '#ffffff' : '#00ff00'),
            textColor: hotspot.textColor || '#ffffff',
            textSize: hotspot.textSize || 1.0,
            noFill: !!hotspot.noFill,
            videoUrl: hotspot.videoUrl || hotspot._originalData?.videoUrl || null,
            poster: hotspot.poster || hotspot._originalData?.poster || (this.hotspotManager?.getPoster?.(hotspot.id) || null),
            videoWidth: hotspot.videoWidth || hotspot._originalData?.videoWidth || null,
            videoHeight: hotspot.videoHeight || hotspot._originalData?.videoHeight || null,
            chromaEnabled: !!hotspot.chromaEnabled,
            chromaColor: hotspot.chromaColor || '#00ff00',
            chromaSimilarity: hotspot.chromaSimilarity ?? 0.4,
            chromaSmoothness: hotspot.chromaSmoothness ?? 0.1,
            chromaThreshold: hotspot.chromaThreshold ?? 0.0,
            customIconData: hotspot.customIconData || null // для пользовательских иконок
        };

        // Переписываем targetSceneId (editor id -> export id), чтобы переходы работали в сборке
        if (converted.targetSceneId && idMap && idMap[converted.targetSceneId]) {
            converted.targetSceneId = idMap[converted.targetSceneId];
        }

        // converted hotspot position

        return converted;
    }

    /**
     * Генерирует HTML файл для просмотра тура
     */
    generateViewerHTML(projectData) {
        // generate viewer html
        return `<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="Content-Security-Policy" content="default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob: https://aframe.io https://fonts.googleapis.com https://fonts.gstatic.com; connect-src 'self' data: blob: https://aframe.io https://fonts.googleapis.com https://fonts.gstatic.com;">
    <title>${projectData.projectTitle}</title>
    <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🌐</text></svg>">
    <script src="https://aframe.io/releases/1.4.0/aframe.min.js"></script>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@300;400;500&subset=cyrillic&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div id="tour-container">
        <!-- Левая панель со сценами -->
        <div id="scene-panel" class="open">
            <div class="scene-panel-header">
                <span class="title">${projectData.projectTitle}</span>
                <button id="scene-panel-toggle" title="Скрыть/показать список сцен">⟨</button>
            </div>
            <div id="scene-list"></div>
        </div>

        <!-- A-Frame сцена -->
        <a-scene 
            id="tour-scene"
            embedded
            style="height: 100vh; width: 100%;"
            background="color: #000000"
            vr-mode-ui="enabled: false"
            cursor="rayOrigin: mouse"
            raycaster="objects: [data-raycastable]; far: 100; interval: 100"
            renderer="antialias: true; colorManagement: true; sortObjects: true"
            loading-screen="enabled: false">
            
            <!-- Активы -->
            <a-assets>
                ${projectData.scenes.map((scene, index) =>
            `<img id="${this.generatePanoramaElementId(scene.name, index)}" src="panoramas/${scene.id}.jpg">`
        ).join('\n                ')}
            </a-assets>

            <!-- Небесная сфера для панорамы -->
            <a-sky id="panorama-sky" src="#${projectData.scenes[0] ? this.generatePanoramaElementId(projectData.scenes[0].name, 0) : 'scene-0'}" rotation="0 0 0"></a-sky>

            <!-- Камера с орбитальным управлением -->
            <a-camera 
                id="tour-camera"
                look-controls="pointerLockEnabled: false"
                wasd-controls="enabled: false"
                position="0 0 0"
                fov="75">
            </a-camera>

            <!-- Контейнер для хотспотов -->
            <a-entity id="hotspots-container"></a-entity>
        </a-scene>

        <!-- Элементы управления -->
    <div id="tour-controls">
            <button id="fullscreen-btn">⛶</button>
            <button id="zoom-in-btn">+</button>
            <button id="zoom-out-btn">−</button>
            <button id="reset-view-btn">⌂</button>
            <button id="gyro-btn" title="Гироскоп">📱</button>
        </div>
        <!-- Индикатор загрузки -->
            <div id="tour-loading" role="status" aria-live="polite" aria-label="Загрузка" style="display:none">
                <div class="color-logo">
                    <span class="logo-letter letter-c" data-letter="C">C</span>
                    <span class="logo-letter letter-o" data-letter="o">o</span>
                    <span class="logo-letter letter-l" data-letter="l">l</span>
                    <span class="logo-letter letter-o2" data-letter="o">o</span>
                    <span class="logo-letter letter-r" data-letter="R">R</span>
                </div>
                <div class="loading-text">Загрузка...</div>
            </div>
    </div>

    <!-- Данные тура и логика -->
    <script src="tour-data.js"></script>
</body>
</html>`;
    }

    /**
     * Создает пакет файлов для экспорта
     */
    async createExportPackage(projectData) {
        // create export package

        const packageFiles = {};

        // 1. Создаем базовое A-Frame приложение для просмотра
        packageFiles['index.html'] = this.generateViewerHTML(projectData);

        // 2. Создаем JavaScript файл с данными и логикой
        packageFiles['tour-data.js'] = this.generateTourDataJS(projectData);

        // 2.1. Runtime больше не требуется отдельным файлом (перенесен в tour-data.js)

        // 3. Создаем CSS стили 
        packageFiles['style.css'] = this.generateViewerCSS();

        // 4. Добавляем изображения панорам
        await this.processPanoramaImages(projectData, packageFiles);

        // 5. Добавляем кастомные иконки хотспотов
        await this.processCustomIcons(projectData, packageFiles);

        // 6. Создаем README с инструкциями
        packageFiles['README.md'] = this.generateReadme(projectData);

        return packageFiles;
    }

    /**
     * Генерирует A-Frame компоненты
     */
    generateAFrameComponents() {
        return `
        // Компонент billboard для поворота к камере
        AFRAME.registerComponent('billboard', {
            tick: function () {
                const camera = document.querySelector('[camera]');
                if (camera) {
                    this.el.object3D.lookAt(camera.object3D.position);
                }
            }
        });

        // Компонент face-camera для правильной ориентации видео-областей
        AFRAME.registerComponent('face-camera', {
            init: function () {
                this.cameraEl = null;
                this.tick = this.tick.bind(this);
                this.findCamera();
            },

            findCamera: function () {
                this.cameraEl = document.querySelector('[camera]') ||
                              document.querySelector('a-camera') ||
                              document.querySelector('#defaultCamera');

                if (!this.cameraEl) {
                    const scene = document.querySelector('a-scene');
                    if (scene && scene.camera && scene.camera.el) {
                        this.cameraEl = scene.camera.el;
                    }
                }
            },

            tick: function () {
                if (!this.cameraEl) {
                    this.findCamera();
                    return;
                }

                const cameraWorldPosition = new THREE.Vector3();
                const elementWorldPosition = new THREE.Vector3();

                this.cameraEl.object3D.getWorldPosition(cameraWorldPosition);
                this.el.object3D.getWorldPosition(elementWorldPosition);

                const direction = new THREE.Vector3();
                direction.subVectors(cameraWorldPosition, elementWorldPosition);
                direction.y = 0;
                direction.normalize();

                if (direction.length() > 0) {
                    const angle = Math.atan2(direction.x, direction.z);
                    this.el.object3D.rotation.set(0, angle, 0);
                }
            }
        });

        // Компонент для кириллического текста (с поддержкой family/bold/underline)
        AFRAME.registerComponent('cyrillic-text', {
            schema: {
                value: { type: 'string', default: '' },
                color: { type: 'color', default: '#ffffff' },
                align: { type: 'string', default: 'center' },
                family: { type: 'string', default: 'Arial, sans-serif' },
                bold: { type: 'boolean', default: false },
                underline: { type: 'boolean', default: false }
            },
            init: function () { this.createTextTexture(); },
            update: function () { this.createTextTexture(); },
            createTextTexture: function () {
                const canvas = document.createElement('canvas');
                const ctx = canvas.getContext('2d');
                const data = this.data;
                const value = data.value;
                const color = data.color;
                const align = data.align;
                const family = data.family;
                const bold = data.bold;
                const underline = data.underline;
                canvas.width = 1024; canvas.height = 256;
                ctx.clearRect(0,0,canvas.width,canvas.height);
                const fontSize = 48; // базовый, масштаб задается через entity.setAttribute('scale')
                ctx.font = (bold ? 'bold ' : '') + fontSize + 'px ' + family;
                ctx.fillStyle = color;
                ctx.textAlign = align;
                ctx.textBaseline = 'middle';
                const x = align === 'center' ? canvas.width/2 : (align === 'right' ? canvas.width-20 : 20);
                ctx.fillText(value || '', x, canvas.height/2);
                if (underline) {
                    const metrics = ctx.measureText(value || '');
                    const textWidth = metrics.width;
                    const startX = x - (align === 'center' ? textWidth/2 : (align === 'right' ? textWidth : 0));
                    ctx.fillRect(startX, canvas.height/2 + fontSize*0.45, textWidth, 4);
                }
                const texture = new THREE.CanvasTexture(canvas); texture.needsUpdate = true;
                const material = new THREE.MeshBasicMaterial({ map: texture, transparent: true, alphaTest: 0.1 });
                const geometry = new THREE.PlaneGeometry(2, 0.5);
                const mesh = new THREE.Mesh(geometry, material);
                this.el.setObject3D('mesh', mesh);
            }
        });

        // Шейдер chroma-key для удаления фона по ключевому цвету
        if (!AFRAME.shaders || !AFRAME.shaders['chroma-key']) {
            AFRAME.registerShader('chroma-key', {
                schema: {
                    src: { type: 'map' },
                    color: { type: 'color', default: '#00ff00' },
                    similarity: { type: 'number', default: 0.4 },
                    smoothness: { type: 'number', default: 0.1 },
                    threshold: { type: 'number', default: 0.0 }
                },
                init: function (data) {
                    this.material = new THREE.ShaderMaterial({
                        uniforms: {
                            map: { value: null },
                            keyColor: { value: new THREE.Color(data.color) },
                            similarity: { value: data.similarity },
                            smoothness: { value: data.smoothness },
                            threshold: { value: data.threshold }
                        },
                        transparent: true,
                        depthWrite: false,
                        side: THREE.DoubleSide,
                        vertexShader: 'varying vec2 vUV; void main(){ vUV = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
                        fragmentShader: 'uniform sampler2D map; uniform vec3 keyColor; uniform float similarity; uniform float smoothness; uniform float threshold; varying vec2 vUV; void main(){ vec4 color = texture2D(map, vUV); float kr = 0.299, kg = 0.587, kb = 0.114; float r = color.r, g = color.g, b = color.b; float y = kr * r + kg * g + kb * b; float cr = (r - y) * 0.713 + 0.5; float cb = (b - y) * 0.564 + 0.5; float rK = keyColor.r, gK = keyColor.g, bK = keyColor.b; float yK = kr * rK + kg * gK + kb * bK; float crK = (rK - yK) * 0.713 + 0.5; float cbK = (bK - yK) * 0.564 + 0.5; float d = distance(vec2(cb, cr), vec2(cbK, crK)); float a = smoothstep(similarity, similarity + smoothness, d); a = clamp((a - threshold) / (1.0 - threshold + 1e-6), 0.0, 1.0); gl_FragColor = vec4(color.rgb, a * color.a); }'
                    });
                },
                update: function (data) {
                    if (data.src && data.src.image) { this.material.uniforms.map.value = data.src.image; this.material.needsUpdate = true; }
                    if (data.color) this.material.uniforms.keyColor.value.set(data.color);
                    if (typeof data.similarity === 'number') this.material.uniforms.similarity.value = data.similarity;
                    if (typeof data.smoothness === 'number') this.material.uniforms.smoothness.value = data.smoothness;
                    if (typeof data.threshold === 'number') this.material.uniforms.threshold.value = data.threshold;
                }
            });
        }

        // Компонент обработки хотспотов
        AFRAME.registerComponent('hotspot-handler', {
            schema: {
                hotspotId: { type: 'string' },
                type: { type: 'string', default: 'info' },
                linkTo: { type: 'string' },
                title: { type: 'string' },
                description: { type: 'string' },
                videoUrl: { type: 'string' }
            },
            init: function() {
                this.el.addEventListener('click', this.onClick.bind(this));
                this.el.addEventListener('mouseenter', this.onMouseEnter.bind(this));
                this.el.addEventListener('mouseleave', this.onMouseLeave.bind(this));
                this._modalOpen = false;
                
                // Добавляем data-raycastable для корректной работы raycaster
                this.el.setAttribute('data-raycastable', '');
            },
            onClick: function() {
                // hotspot click
                // Info-point: всегда показываем текст, НЕ навигируем
                if (this.data.type === 'info-point' || this.data.type === 'infopoint') {
                    // Скрываем возможный тултип и запрещаем появление новых на время модала
                    if (this._tooltipEl) {
                        try { window.removeEventListener('mousemove', this._tooltipMove); } catch {}
                        try { document.body.removeChild(this._tooltipEl); } catch {}
                        this._tooltipEl = null; this._tooltipMove = null;
                    }
                    this._modalOpen = true;
                    this.showInfoModal();
                    return;
                }
                // Видео-область: воспроизводим ВНУТРИ плоскости
                if (this.data.type === 'video-area') {
                    const markerEl = this.el.parentElement;
                    if (!markerEl) return;
                    let videoEl = document.getElementById('video-' + this.data.hotspotId);
                    const plane = markerEl.querySelector('a-plane');
                    if (!videoEl) {
                        videoEl = document.createElement('video');
                        videoEl.id = 'video-' + this.data.hotspotId;
                        videoEl.crossOrigin = 'anonymous';
                        videoEl.loop = true;
                        videoEl.playsInline = true;
                        // Не форсируем muted: по клику пользователя звук допускается браузером
                        videoEl.style.display = 'none';
                        const assets = document.querySelector('a-assets') || (()=>{ const a=document.createElement('a-assets'); document.querySelector('a-scene').appendChild(a); return a; })();
                        assets.appendChild(videoEl);
                        if (this.data.videoUrl) {
                            videoEl.src = this.data.videoUrl;
                        }
                    }
                    if (plane) {
                        // При первом клике заменяем постер на видео-текстуру
                        const mat = plane.getAttribute('material') || {};
                        if (!mat.src || mat.src !== ('#' + videoEl.id)) {
                            plane.setAttribute('material', { shader: 'flat', src: '#' + videoEl.id, transparent: false, side: 'double' });
                        }
                    }
                    // toggle
                    if (videoEl.paused) {
                        try { videoEl.muted = false; } catch {}
                        videoEl.play().catch(()=>{});
                    } else {
                        try { videoEl.pause(); } catch {}
                    }
                    return;
                }
                // Переход к другой сцене только для навигационных хотспотов
                if (this.data.linkTo && this.data.linkTo !== '' && this.data.linkTo !== 'undefined' && this.data.linkTo !== 'null') {
                    // go to scene
                    window.tourViewer.switchToScene(this.data.linkTo);
                    return;
                }
                // По умолчанию — инфо
                this.showInfoModal();
            },
            showInfoModal: function() {
                // Функция для удаления расширений файлов
                const removeFileExtension = (filename) => {
                    if (!filename || typeof filename !== 'string') {
                        return filename;
                    }
                    const videoExtensions = ['.mp4', '.avi', '.mov', '.webm', '.mkv', '.flv', '.wmv', '.m4v', '.3gp', '.ogv'];
                    const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.svg', '.webp', '.tiff', '.ico'];
                    const allExtensions = [...videoExtensions, ...imageExtensions];
                    const lowerFilename = filename.toLowerCase();
                    for (const ext of allExtensions) {
                        if (lowerFilename.endsWith(ext)) {
                            return filename.slice(0, -ext.length);
                        }
                    }
                    return filename;
                };

                // Создаем модальное окно для информации
                const modal = document.createElement('div');
                modal.style.cssText = 
                    'position: fixed;' +
                    'top: 0;' +
                    'left: 0;' +
                    'width: 100%;' +
                    'height: 100%;' +
                    'background: rgba(0, 0, 0, 0.8);' +
                    'z-index: 10000;' +
                    'display: flex;' +
                    'align-items: center;' +
                    'justify-content: center;';
                
                const content = document.createElement('div');
                content.style.cssText = 
                    'background: #2a2a2a;' +
                    'padding: 30px;' +
                    'border-radius: 10px;' +
                    'max-width: 500px;' +
                    'color: white;' +
                    'font-family: Roboto, Arial, sans-serif;';
                
                content.innerHTML = 
                    '<h3 style="margin: 0 0 15px 0; color: #ffcc00;">' + (this.data.title ? removeFileExtension(this.data.title) : 'Информация') + '</h3>' +
                    '<p style="margin: 0 0 20px 0; line-height: 1.5;">' + (this.data.description || 'Описание отсутствует') + '</p>' +
                    '<button style="background: #ffcc00; color: black; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; font-weight: bold;">Закрыть</button>';
                
                modal.appendChild(content);
                document.body.appendChild(modal);
                
                // Закрытие модального окна
                const closeBtn = content.querySelector('button');
                const closeModal = () => {
                    try { document.body.removeChild(modal); } catch {}
                    // Разрешаем появление тултипов снова
                    this._modalOpen = false;
                };
                
                closeBtn.addEventListener('click', closeModal);
                modal.addEventListener('click', (e) => {
                    if (e.target === modal) closeModal();
                });
            },
                // Удален showVideoModal: видео теперь играет в плоскости
    onMouseEnter: function(evt) {
        if (this._modalOpen) { return; }
                const textEl = this.el.querySelector('[cyrillic-text]');
                // Показываем 3D-лейбл для всех типов (info-point, hotspot, video-area)
                if (textEl) {
                    textEl.setAttribute('visible', true);
                }
                // Запускаем hover-анимации на shape через события
                try { this.el.emit && this.el.emit('hover-on'); } catch {}
                // Ставим на паузу мягкую анимацию покачивания, если есть
                try { const comp = this.el.components && this.el.components['animation__bob']; if (comp && comp.pause) comp.pause(); } catch(e) {}
                // 2D подсказка: показываем Название + Описание для всех типов маркеров
                if (this.data && (this.data.title || this.data.description)) {
                    const tip = document.createElement('div');
                    tip.className = 'tour-tooltip';
            const title = removeFileExtension(this.data.title || 'Информация');
            const hasDesc = !!this.data.description;
            const desc = hasDesc ? '<div class="desc">' + this.data.description + '</div>' : '';
            const sep = hasDesc ? '<hr class="tour-tip-sep" />' : '';
            tip.innerHTML = '<div class="title">' + title + '</div>' + sep + desc;
                    document.body.appendChild(tip);
                    const move = (e) => { tip.style.left = (e.clientX + 12) + 'px'; tip.style.top = (e.clientY + 12) + 'px'; };
                    window.addEventListener('mousemove', move);
                    this._tooltipEl = tip; this._tooltipMove = move;
                }
            },
            onMouseLeave: function() {
                const textEl = this.el.querySelector('[cyrillic-text]');
                if (textEl) textEl.setAttribute('visible', false);
                try { this.el.emit && this.el.emit('hover-off'); } catch {}
                // Возобновляем мягкую анимацию покачивания, если есть
                try { const comp = this.el.components && this.el.components['animation__bob']; if (comp && comp.play) comp.play(); } catch(e) {}
                if (this._tooltipEl) {
                    window.removeEventListener('mousemove', this._tooltipMove);
                    document.body.removeChild(this._tooltipEl);
                    this._tooltipEl = null; this._tooltipMove = null;
                }
            }
        });
        `;
    }

    /**
     * Генерирует файл с данными тура и логикой просмотра
     */
    generateTourDataJS(projectData) {
        // generate tour-data.js (safe serialization to avoid unescaped line breaks)  
        const safeJson = JSON.stringify(projectData, (key, value) => {
            if (typeof value === 'string') {
                // Только экранируем критичные символы Unicode
                return value.replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
            }
            return value;
        }, 2);
        return `// Данные панорамного тура
const TOUR_DATA = ${safeJson};

// Делаем данные доступными глобально
window.TOUR_DATA = TOUR_DATA;

// Хелпер: удаляет известные расширения файлов из строки
function removeFileExtension(filename) {
    if (!filename || typeof filename !== 'string') return filename;
    const videoExtensions = ['.mp4', '.avi', '.mov', '.webm', '.mkv', '.flv', '.wmv', '.m4v', '.3gp', '.ogv'];
    const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.svg', '.webp', '.tiff', '.ico'];
    const allExtensions = [...videoExtensions, ...imageExtensions];
    const lower = filename.toLowerCase();
    for (const ext of allExtensions) {
        if (lower.endsWith(ext)) return filename.slice(0, -ext.length);
    }
    return filename;
}

// Основной класс просмотрщика тура
class TourViewer {
    constructor(tourData) {
        this.tourData = tourData;
        this.currentSceneId = tourData.scenes[0]?.id || null;
        this.scene = document.querySelector('#tour-scene');
        this.panoramaSky = document.querySelector('#panorama-sky');
        this.hotspotsContainer = document.querySelector('#hotspots-container');
    this.sceneList = document.querySelector('#scene-list');
    this.scenePanel = document.querySelector('#scene-panel');
    this.loadingBox = document.querySelector('#tour-loading');

    // Авторотация
    this.autorotateEnabled = !!(tourData.settings && tourData.settings.autorotate);
    this.autorotateSpeed = 0.02; // рад/сек
    this.autorotateIdleDelay = 3000; // мс
    this._autorotatePaused = false;
    this._autorotateLastTs = 0;
    this._lastUserInteraction = Date.now();
    this._autorotateRaf = null;
    // Гироскоп и pinch
    this.gyroEnabled = false;
    this._pinch = { active: false, startDist: 0, startFov: 75 };
        
        this.init();
        window.tourViewer = this; // Глобальный доступ
    }

    init() {

        // Проверяем, готовы ли элементы DOM
        if (!this.scene || !this.panoramaSky || !this.hotspotsContainer || !this.sceneList) {

            setTimeout(() => this.init(), 100);
            return;
        }

        // Ожидаем готовности A-Frame сцены
        if (this.scene.hasLoaded) {

            this.startTour();
        } else {

            this.scene.addEventListener('loaded', () => {

                this.startTour();
            });
        }
    }
    
    startTour() {

        this.setupEventListeners();
        this.loadScene(this.currentSceneId);
    }

    setupEventListeners() {
        // Построение списка сцен и переключатель панели
        this.renderSceneList();
        const toggleBtn = document.getElementById('scene-panel-toggle');
        if (toggleBtn) {
            toggleBtn.addEventListener('click', () => {
                this.scenePanel.classList.toggle('open');
                toggleBtn.textContent = this.scenePanel.classList.contains('open') ? '⟨' : '⟩';
            });
        }

        // Элементы управления
        document.getElementById('fullscreen-btn').addEventListener('click', () => {
            this.toggleFullscreen();
        });

        document.getElementById('zoom-in-btn').addEventListener('click', () => {
            this.zoomIn();
        });

        document.getElementById('zoom-out-btn').addEventListener('click', () => {
            this.zoomOut();
        });

        document.getElementById('reset-view-btn').addEventListener('click', () => {
            this.resetView();
        });

        const gyroBtn = document.getElementById('gyro-btn');
        if (gyroBtn) {
            gyroBtn.addEventListener('click', async () => {
                this.enableGyro(!this.gyroEnabled);
                gyroBtn.classList.toggle('active', this.gyroEnabled);
            });
        }

        // Горячая клавиша: R — включить/выключить авторотацию
        window.addEventListener('keydown', (e) => {
            if ((e.key || '').toLowerCase() === 'r') {
                this.enableAutorotate(!this.autorotateEnabled);
            }
        });

        this._setupAutorotateUserInteractivity();

        // Pinch-to-zoom
        const sceneEl = this.scene;
        if (sceneEl) {
            sceneEl.addEventListener('touchstart', (e) => {
                if (e.touches && e.touches.length === 2) {
                    this._pinch.active = true;
                    const dx = e.touches[0].clientX - e.touches[1].clientX;
                    const dy = e.touches[0].clientY - e.touches[1].clientY;
                    this._pinch.startDist = Math.hypot(dx, dy);
                    const cam = document.querySelector('#tour-camera');
                    this._pinch.startFov = parseFloat(cam?.getAttribute('fov')) || 75;
                }
            }, { passive: false });
            sceneEl.addEventListener('touchmove', (e) => {
                if (this._pinch.active && e.touches && e.touches.length === 2) {
                    e.preventDefault();
                    const dx = e.touches[0].clientX - e.touches[1].clientX;
                    const dy = e.touches[0].clientY - e.touches[1].clientY;
                    const dist = Math.hypot(dx, dy);
                    if (this._pinch.startDist > 0) {
                        const scale = this._pinch.startDist / dist;
                        let newFov = this._pinch.startFov * scale;
                        newFov = Math.max(30, Math.min(120, newFov));
                        const cam = document.querySelector('#tour-camera');
                        cam.setAttribute('fov', newFov);
                    }
                }
            }, { passive: false });
            const endPinch = () => { this._pinch.active = false; };
            sceneEl.addEventListener('touchend', endPinch, { passive: true });
            sceneEl.addEventListener('touchcancel', endPinch, { passive: true });
        }
    }

    switchToScene(sceneId) {
    // switch to scene
        this.currentSceneId = sceneId;
        this.loadScene(sceneId);
    this.markActiveScene(sceneId);
    }

    loadScene(sceneId) {
    // load scene
        const scene = this.tourData.scenes.find(s => s.id === sceneId);
        if (!scene) {
            console.error('❌ Сцена не найдена:', sceneId);
            return;
        }

    // scene data
        scene.hotspots.forEach(function(hotspot, i){

        });

        // Показать индикатор загрузки панорамы
        this.showLoading('Загрузка панорамы...');
        var self = this;
        var hideTimeout = setTimeout(function(){ self.hideLoading(); }, 10000);
        var onLoaded = function() {
            clearTimeout(hideTimeout);
            self.hideLoading();
            if (self.panoramaSky) {
                self.panoramaSky.removeEventListener('materialtextureloaded', onLoaded);
            }
            // После загрузки текстуры — применяем начальный вид
            try { self.applyInitialView(scene); } catch(e) { console.warn('applyInitialView after load failed', e); }
        };
        if (this.panoramaSky) {
            this.panoramaSky.addEventListener('materialtextureloaded', onLoaded);
        }

        // Найдем индекс сцены для получения правильного ID элемента панорамы
        const sceneIndex = this.tourData.scenes.findIndex(s => s.id === sceneId);
        const panoramaElementId = this.generatePanoramaElementId(scene.name, sceneIndex);
        
        // Обновляем панораму
        const panoramaElement = document.querySelector('#' + panoramaElementId);
        if (panoramaElement) {
            this.panoramaSky.setAttribute('src', '#' + panoramaElementId);

        } else {
            console.error('❌ Элемент панорамы не найден:', panoramaElementId);
        }

    // Применение начального вида перенесено в onLoaded

        // Очищаем старые хотспоты
        while (this.hotspotsContainer.firstChild) {
            this.hotspotsContainer.removeChild(this.hotspotsContainer.firstChild);
        }

        // Добавляем хотспоты

        scene.hotspots.forEach((hotspot, i) => {

            this.createHotspot(hotspot);
        });

        this.hideLoading();
}

    /**
     * Применяет начальный вид камеры для сцены с механизмом повторных попыток
     */
    applyInitialView(scene) {
        const camera = document.querySelector('#tour-camera');
        if (!camera || !scene.initialView) {

            return;
        }
        
        // Применяем вид с повторными попытками
        this.applyCameraWithRetries(scene, 0);
    }

    /**
     * Применяет камеру с повторными попытками для надежности
     */
    applyCameraWithRetries(scene, attempt) {
        const maxAttempts = 8;
        const camera = document.querySelector('#tour-camera');
        
        if (!camera || !scene.initialView) {

            return;
        }

        const lc = camera.components && camera.components['look-controls'];

        // Пауза look-controls перед применением
        try { if (lc && lc.pause) lc.pause(); } catch {}
        
        // Полный сброс состояния
        try { camera.setAttribute('rotation', '0 0 0'); } catch {}
        try { camera.object3D.rotation.set(0,0,0,'XYZ'); } catch {}
        
        setTimeout(() => {
            // FOV
            if (scene.initialView.fov) {
                let fovDegrees = scene.initialView.fov;
                if (fovDegrees < 10) fovDegrees = fovDegrees * (180 / Math.PI);
                fovDegrees = Math.max(10, Math.min(130, fovDegrees));
                try { camera.setAttribute('fov', fovDegrees); } catch {}

            }
            
            // Rotation
            if (scene.initialView.rotation) {
                try { camera.setAttribute('rotation', scene.initialView.rotation); } catch {}
                try {
                    const parts = String(scene.initialView.rotation).split(/[\s,]+/).map(parseFloat);
                    if (parts.length >= 2 && camera.object3D) {
                        // x=pitch, y=yaw, z=roll, значения в градусах
                        const deg2rad = Math.PI / 180;
                        camera.object3D.rotation.set((parts[0]||0)*deg2rad, (parts[1]||0)*deg2rad, (parts[2]||0)*deg2rad, 'XYZ');
                    }
                } catch {}

            } else if (scene.initialView.yaw !== undefined || scene.initialView.pitch !== undefined) {
                let yaw = scene.initialView.yaw || 0;
                let pitch = scene.initialView.pitch || 0;
                if (Math.abs(yaw) < 10 && Math.abs(pitch) < 10 && (yaw !== 0 || pitch !== 0)) {
                    yaw = yaw * (180 / Math.PI);
                    pitch = pitch * (180 / Math.PI);
                }
                const roll = 0;
                const rotationString = pitch + ' ' + yaw + ' ' + roll;
                try { camera.setAttribute('rotation', rotationString); } catch {}
                try {
                    if (camera.object3D) {
                        const deg2rad = Math.PI / 180;
                        camera.object3D.rotation.set(pitch*deg2rad, yaw*deg2rad, 0, 'XYZ');
                    }
                } catch {}

            }
            
            // Возобновление управления после применения
            requestAnimationFrame(() => { 
                try { if (lc && lc.play) lc.play(); } catch {} 
                
                // Проверяем результат после небольшой задержки
                setTimeout(() => {
                    const actualRotation = camera.getAttribute('rotation');

                    // Если поворот не применился правильно и есть еще попытки
                    if (attempt < maxAttempts - 1) {
                        let needRetry = false;
                        
                        if (scene.initialView.rotation) {
                            const expectedParts = String(scene.initialView.rotation).split(/[\s,]+/).map(parseFloat);
                            const actualParts = String(actualRotation || '0 0 0').split(/[\s,]+/).map(parseFloat);
                            const tolerance = 5; // градусы
                            
                            if (Math.abs((expectedParts[0] || 0) - (actualParts[0] || 0)) > tolerance ||
                                Math.abs((expectedParts[1] || 0) - (actualParts[1] || 0)) > tolerance) {
                                needRetry = true;
                            }
                        } else if (scene.initialView.yaw !== undefined || scene.initialView.pitch !== undefined) {
                            let expectedYaw = scene.initialView.yaw || 0;
                            let expectedPitch = scene.initialView.pitch || 0;
                            if (Math.abs(expectedYaw) < 10 && Math.abs(expectedPitch) < 10 && (expectedYaw !== 0 || expectedPitch !== 0)) {
                                expectedYaw = expectedYaw * (180 / Math.PI);
                                expectedPitch = expectedPitch * (180 / Math.PI);
                            }
                            
                            const actualParts = String(actualRotation || '0 0 0').split(/[\s,]+/).map(parseFloat);
                            const tolerance = 5; // градусы
                            
                            if (Math.abs(expectedPitch - (actualParts[0] || 0)) > tolerance ||
                                Math.abs(expectedYaw - (actualParts[1] || 0)) > tolerance) {
                                needRetry = true;
                            }
                        }
                        
                        if (needRetry) {

                            setTimeout(() => {
                                this.applyCameraWithRetries(scene, attempt + 1);
                            }, 300);
                        } else {

                        }
                    } else {

                    }
                }, 100);
            });
        }, 50);
    }

    /**
     * Генерирует безопасный ID для элемента панорамы в экспорте
     */
    generatePanoramaElementId(sceneName, index) {
        // Убираем небезопасные символы и создаем ID для элемента панорамы
        const cleanName = sceneName
            .replace(/[^a-zA-Zа-яА-Я0-9]/g, '-')
            .replace(/-+/g, '-')
            .replace(/^-|-$/g, '');

        return 'scene-' + index + '-' + cleanName + '-panorama';
    }

    /**
     * Вспомогательные функции для работы с цветами
     */
    _hexToRgb(hex) {
        if (!hex) return { r: 255, g: 255, b: 255 };
        let h = hex.trim();
        if (h[0] === '#') h = h.slice(1);
        if (h.length === 3) {
            const r = parseInt(h[0] + h[0], 16);
            const g = parseInt(h[1] + h[1], 16);
            const b = parseInt(h[2] + h[2], 16);
            return { r, g, b };
        }
        if (h.length === 6) {
            const r = parseInt(h.slice(0, 2), 16);
            const g = parseInt(h.slice(2, 4), 16);
            const b = parseInt(h.slice(4, 6), 16);
            return { r, g, b };
        }
        return { r: 255, g: 255, b: 255 };
    }
    _rgbToHex(r, g, b) {
        const toHex = (v) => {
            const n = Math.max(0, Math.min(255, Math.round(v)));
            return n.toString(16).padStart(2, '0');
        };
        return '#' + toHex(r) + toHex(g) + toHex(b);
    }
    _mixColor(hex, ratioToWhite = 0) {
        // ratioToWhite: 0 -> исходный цвет; 1 -> белый; отрицательные значения смешивают с чёрным
        const { r, g, b } = this._hexToRgb(hex);
        if (ratioToWhite === 0) return this._rgbToHex(r, g, b);
        if (ratioToWhite > 0) {
            const t = Math.min(1, Math.max(0, ratioToWhite));
            const R = r + (255 - r) * t;
            const G = g + (255 - g) * t;
            const B = b + (255 - b) * t;
            return this._rgbToHex(R, G, B);
        } else {
            const t = Math.min(1, Math.max(0, -ratioToWhite));
            const R = r * (1 - t);
            const G = g * (1 - t);
            const B = b * (1 - t);
            return this._rgbToHex(R, G, B);
        }
    }

    /**
     * Создает современный SVG маркер со стрелкой для хотспотов
     */
    createModernArrowSVG(color, size) {
        const HR = 512; const C = HR / 2; const s = C * 0.4;
        const gradId = 'arrow-gradient-' + Math.random().toString(36).slice(2, 11);
        const shId = 'arrow-shadow-' + Math.random().toString(36).slice(2, 11);
        const base = color || '#ffffff';
        const c0 = this._mixColor(base, 0.3);   // светлее
        const c1 = this._mixColor(base, 0.1);   // немного светлее
        const c2 = this._mixColor(base, -0.05); // чуть темнее
        // Chevron со штрихами + круговая окантовка (без заливки), как в редакторе
        return (
            '<svg width="' + HR + '" height="' + HR + '" viewBox="0 0 ' + HR + ' ' + HR + '" xmlns="http://www.w3.org/2000/svg">' +
              '<defs>' +
                '<linearGradient id="' + gradId + '" x1="0%" y1="0%" x2="100%" y2="100%">' +
                  '<stop offset="0%" stop-color="' + c0 + '" stop-opacity="0.98"/>' +
                  '<stop offset="50%" stop-color="' + c1 + '" stop-opacity="0.9"/>' +
                  '<stop offset="100%" stop-color="' + c2 + '" stop-opacity="0.82"/>' +
                '</linearGradient>' +
                '<filter id="' + shId + '" x="-50%" y="-50%" width="200%" height="200%">' +
                  '<feDropShadow dx="2" dy="3" stdDeviation="4" flood-color="rgba(0,0,0,0.3)" />' +
                '</filter>' +
              '</defs>' +
              '<g>' +
                // Круглая окантовка
                '<circle cx="' + C + '" cy="' + C + '" r="' + (s * 0.9) + '" fill="none" stroke="url(#' + gradId + ')" stroke-width="12" filter="url(#' + shId + ')" />' +
                // Левый штрих шеврона
                '<path d="M ' + (C - s * 0.3) + ' ' + (C + s * 0.15) + ' L ' + C + ' ' + (C - s * 0.3) + '" ' +
                      'fill="none" stroke="url(#' + gradId + ')" stroke-width="18" stroke-linecap="round" stroke-linejoin="round" filter="url(#' + shId + ')" />' +
                // Правый штрих шеврона
                '<path d="M ' + C + ' ' + (C - s * 0.3) + ' L ' + (C + s * 0.3) + ' ' + (C + s * 0.15) + '" ' +
                      'fill="none" stroke="url(#' + gradId + ')" stroke-width="18" stroke-linecap="round" stroke-linejoin="round" filter="url(#' + shId + ')" />' +
              '</g>' +
            '</svg>'
        );
    }

        // Вариант для hover: усиленная тень/свечение
        createModernArrowSVGHover(color, size, options = {}) {
                const HR = 512; const C = HR / 2; const s = C * 0.4;
                const gradId = 'arrow-gradientH-' + Math.random().toString(36).slice(2, 11);
                const shId = 'arrow-shadowH-' + Math.random().toString(36).slice(2, 11);
                const base = color || '#ffffff';
                const c0 = this._mixColor(base, 0.4);
                const c1 = this._mixColor(base, 0.2);
                const c2 = this._mixColor(base, 0.0);
                return (
                        '<svg width="' + HR + '" height="' + HR + '" viewBox="0 0 ' + HR + ' ' + HR + '" xmlns="http://www.w3.org/2000/svg">' +
                            '<defs>' +
                                '<linearGradient id="' + gradId + '" x1="0%" y1="0%" x2="100%" y2="100%">' +
                                    '<stop offset="0%" stop-color="' + c0 + '" stop-opacity="1"/>' +
                                    '<stop offset="50%" stop-color="' + c1 + '" stop-opacity="0.96"/>' +
                                    '<stop offset="100%" stop-color="' + c2 + '" stop-opacity="0.92"/>' +
                                '</linearGradient>' +
                                '<filter id="' + shId + '" x="-60%" y="-60%" width="220%" height="220%">' +
                                    '<feDropShadow dx="2" dy="4" stdDeviation="6" flood-color="rgba(0,0,0,0.5)" />' +
                                '</filter>' +
                            '</defs>' +
                            '<g>' +
                                '<circle cx="' + C + '" cy="' + C + '" r="' + (s * 0.9) + '" fill="none" stroke="url(#' + gradId + ')" stroke-width="12" filter="url(#' + shId + ')" />' +
                                '<path d="M ' + (C - s * 0.3) + ' ' + (C + s * 0.15) + ' L ' + C + ' ' + (C - s * 0.3) + '" ' +
                                                        'fill="none" stroke="url(#' + gradId + ')" stroke-width="18" stroke-linecap="round" stroke-linejoin="round" filter="url(#' + shId + ')" />' +
                                '<path d="M ' + C + ' ' + (C - s * 0.3) + ' L ' + (C + s * 0.3) + ' ' + (C + s * 0.15) + '" ' +
                                                        'fill="none" stroke="url(#' + gradId + ')" stroke-width="18" stroke-linecap="round" stroke-linejoin="round" filter="url(#' + shId + ')" />' +
                            '</g>' +
                        '</svg>'
                );
        }

    /**
     * Создает современный SVG маркер с иконкой "i" для инфоточек
     */
            createModernInfoSVG(color, size, options = {}) {
                    const noFill = !!options.noFill;
                const HR = 512; const C = HR / 2; const s = C * 0.4;
                const gradId = 'info-gradient-' + Math.random().toString(36).slice(2, 11);
                const base = color || '#ffffff';
                const c0 = this._mixColor(base, 0.35); // светлее
                const c1 = this._mixColor(base, 0.0);  // базовый
                const c2 = this._mixColor(base, -0.08); // темнее по краю
                // Рад. градиентный круг с бликом и буквой "i" как в редакторе
                return (
                        '<svg width="' + HR + '" height="' + HR + '" viewBox="0 0 ' + HR + ' ' + HR + '" xmlns="http://www.w3.org/2000/svg">' +
                            '<defs>' +
                                '<radialGradient id="' + gradId + '" cx="30%" cy="30%" r="70%">' +
                                    '<stop offset="0%" stop-color="' + c0 + '" stop-opacity="1"/>' +
                                    '<stop offset="70%" stop-color="' + c1 + '" stop-opacity="0.92"/>' +
                                    '<stop offset="100%" stop-color="' + c2 + '" stop-opacity="0.86"/>' +
                                '</radialGradient>' +
                            '</defs>' +
                            '<g>' +
                                // Тень круга (слегка смещённая)
                                '<circle cx="' + (C + s * 0.05) + '" cy="' + (C + s * 0.05) + '" r="' + (s * 0.9) + '" fill="rgba(0,0,0,0.3)" opacity="0.6" />' +
                                // Основной круг
                                    '<circle cx="' + C + '" cy="' + C + '" r="' + (s * 0.9) + '" ' + (noFill ? 'fill="none" stroke="rgba(255,255,255,0.85)" stroke-width="3"' : 'fill="url(#' + gradId + ')" stroke="rgba(255,255,255,0.8)" stroke-width="3"') + ' />' +
                                // Блик
                                    (noFill ? '' : '<ellipse cx="' + (C - s * 0.2) + '" cy="' + (C - s * 0.3) + '" rx="' + (s * 0.3) + '" ry="' + (s * 0.2) + '" fill="rgba(255,255,255,0.3)" opacity="0.8" />') +
                                // Точка над "i"
                                    '<circle cx="' + C + '" cy="' + (C - s * 0.3) + '" r="' + (s * 0.12) + '" ' + (noFill ? 'fill="none" stroke="#ffffff" stroke-width="2"' : 'fill="#ffffff" stroke="rgba(0,0,0,0.3)" stroke-width="1"') + ' />' +
                                // Вертикальная линия "i"
                                    '<rect x="' + (C - s * 0.08) + '" y="' + (C - s * 0.05) + '" width="' + (s * 0.16) + '" height="' + (s * 0.6) + '" rx="' + (s * 0.04) + '" ' + (noFill ? 'fill="none" stroke="#ffffff" stroke-width="3"' : 'fill="#ffffff" stroke="rgba(0,0,0,0.3)" stroke-width="1"') + ' />' +
                            '</g>' +
                        '</svg>'
                );
        }

        // Вариант для hover: усиленная тень круга
                createModernInfoSVGHover(color, size, options = {}) {
                        const noFill = !!options.noFill;
                        const HR = 512; const C = HR / 2; const s = C * 0.4;
                        const gradId = 'info-gradientH-' + Math.random().toString(36).slice(2, 11);
                        const base = color || '#ffffff';
                        const c0 = this._mixColor(base, 0.45);
                        const c1 = this._mixColor(base, 0.15);
                        const c2 = this._mixColor(base, -0.02);
                        return (
                                '<svg width="' + HR + '" height="' + HR + '" viewBox="0 0 ' + HR + ' ' + HR + '" xmlns="http://www.w3.org/2000/svg">' +
                                    '<defs>' +
                                        '<radialGradient id="' + gradId + '" cx="30%" cy="30%" r="70%">' +
                                            '<stop offset="0%" stop-color="' + c0 + '" stop-opacity="1"/>' +
                                            '<stop offset="70%" stop-color="' + c1 + '" stop-opacity="0.96"/>' +
                                            '<stop offset="100%" stop-color="' + c2 + '" stop-opacity="0.92"/>' +
                                        '</radialGradient>' +
                                    '</defs>' +
                                    '<g>' +
                                        '<circle cx="' + (C + s * 0.06) + '" cy="' + (C + s * 0.06) + '" r="' + (s * 0.95) + '" fill="rgba(0,0,0,0.45)" opacity="0.8" />' +
                                        '<circle cx="' + C + '" cy="' + C + '" r="' + (s * 0.9) + '" ' + (noFill ? 'fill="none" stroke="rgba(255,255,255,0.85)" stroke-width="3"' : 'fill="url(#' + gradId + ')" stroke="rgba(255,255,255,0.85)" stroke-width="3"') + ' />' +
                                        (noFill ? '' : '<ellipse cx="' + (C - s * 0.2) + '" cy="' + (C - s * 0.3) + '" rx="' + (s * 0.3) + '" ry="' + (s * 0.2) + '" fill="rgba(255,255,255,0.35)" opacity="0.9" />') +
                                        '<circle cx="' + C + '" cy="' + (C - s * 0.3) + '" r="' + (s * 0.12) + '" ' + (noFill ? 'fill="none" stroke="#ffffff" stroke-width="2"' : 'fill="#ffffff" stroke="rgba(0,0,0,0.35)" stroke-width="1"') + ' />' +
                                        '<rect x="' + (C - s * 0.08) + '" y="' + (C - s * 0.05) + '" width="' + (s * 0.16) + '" height="' + (s * 0.6) + '" rx="' + (s * 0.04) + '" ' + (noFill ? 'fill="none" stroke="#ffffff" stroke-width="3"' : 'fill="#ffffff" stroke="rgba(0,0,0,0.35)" stroke-width="1"') + ' />' +
                                    '</g>' +
                                '</svg>'
                        );
                }

    renderSceneList() {
        if (!this.sceneList) return;
        this.sceneList.innerHTML = '';
        this.tourData.scenes.forEach(scene => {
            const item = document.createElement('div');
            item.className = 'scene-item';
            item.dataset.sceneId = scene.id;
            item.textContent = removeFileExtension(scene.name);
            item.addEventListener('click', () => this.switchToScene(scene.id));
            this.sceneList.appendChild(item);
        });
        this.markActiveScene(this.currentSceneId);
    }

    markActiveScene(sceneId) {
        if (!this.sceneList) return;
        Array.from(this.sceneList.children).forEach(el => {
            el.classList.toggle('active', el.dataset.sceneId === sceneId);
        });
    }

    createHotspot(hotspot) {

        // Основной контейнер хотспота
        const hotspotEl = document.createElement('a-entity');
        hotspotEl.setAttribute('id', 'hotspot-' + hotspot.id);
        // Базовая позиция маркера
        const baseX = Number(hotspot.position.x) || 0;
        const baseY = Number(hotspot.position.y) || 0;
        const baseZ = Number(hotspot.position.z) || 0;
        hotspotEl.setAttribute('position', baseX + ' ' + baseY + ' ' + baseZ);
        hotspotEl.setAttribute('hotspot-handler', {
            hotspotId: hotspot.id,
            type: hotspot.type,
            linkTo: hotspot.targetSceneId,
            title: hotspot.title,
            description: hotspot.description,
            videoUrl: hotspot.videoUrl || ''
        });

        // Визуальная форма хотспота
    let shape;
    const size = parseFloat(hotspot.size) || 0.3; // В редакторе радиус = size
        
        if (hotspot.type === 'video-area') {
            // Видео-область - плоскость с правильными размерами
            shape = document.createElement('a-plane');
            const width = parseFloat(hotspot.videoWidth) || 4;
            const height = parseFloat(hotspot.videoHeight) || 3;
            shape.setAttribute('width', width);
            shape.setAttribute('height', height);
            // Нейтральный цвет и материал, чтобы не давать оттенок видео
            if (hotspot.poster) {
                // Покажем постер до старта видео
                shape.setAttribute('material', { shader: 'flat', src: hotspot.poster, transparent: false, side: 'double' });
            } else {
                shape.setAttribute('color', '#ffffff');
                shape.setAttribute('material', 'color: #ffffff; transparent: false; side: double');
            }
            
            // Добавляем face-camera компонент для правильной ориентации
            hotspotEl.setAttribute('face-camera', '');
            
            // Подготавливаем video element заранее, чтобы material мог сослаться по id
            let videoEl = document.getElementById('video-' + hotspot.id);
            if (!videoEl) {
                videoEl = document.createElement('video');
                videoEl.id = 'video-' + hotspot.id;
                videoEl.crossOrigin = 'anonymous';
                videoEl.loop = true;
                videoEl.playsInline = true;
                videoEl.style.display = 'none';
                const assets = document.querySelector('a-assets') || (()=>{ const a=document.createElement('a-assets'); document.querySelector('a-scene').appendChild(a); return a; })();
                assets.appendChild(videoEl);
                if (hotspot.videoUrl) videoEl.src = hotspot.videoUrl;
            }
        } else if (hotspot.type === 'animated-object') {
            // Анимированный объект — видео-плоскость с опциональным хромакеем
            shape = document.createElement('a-plane');
            const width = parseFloat(hotspot.videoWidth) || 2;
            const height = parseFloat(hotspot.videoHeight) || (2 * 9/16);
            shape.setAttribute('width', width);
            shape.setAttribute('height', height);
            hotspotEl.setAttribute('face-camera', '');

            // Подготовим video element
            let videoEl = document.getElementById('video-' + hotspot.id);
            if (!videoEl) {
                videoEl = document.createElement('video');
                videoEl.id = 'video-' + hotspot.id;
                videoEl.crossOrigin = 'anonymous';
                videoEl.loop = true;
                videoEl.playsInline = true;
                videoEl.muted = true;
                videoEl.style.display = 'none';
                const assets = document.querySelector('a-assets') || (()=>{ const a=document.createElement('a-assets'); document.querySelector('a-scene').appendChild(a); return a; })();
                assets.appendChild(videoEl);
                if (hotspot.videoUrl) videoEl.src = hotspot.videoUrl;
            }

            // Материал: chroma-key или flat
            if (hotspot.chromaEnabled) {
                shape.setAttribute('material', {
                    shader: 'chroma-key',
                    src: '#video-' + hotspot.id,
                    color: hotspot.chromaColor || '#00ff00',
                    similarity: hotspot.chromaSimilarity ?? 0.4,
                    smoothness: hotspot.chromaSmoothness ?? 0.1,
                    threshold: hotspot.chromaThreshold ?? 0.0,
                    side: 'double'
                });
            } else {
                shape.setAttribute('material', { shader: 'flat', src: '#video-' + hotspot.id, side: 'double' });
            }

            // Toggle по клику (с включением звука при старте по жесту)
            shape.addEventListener('click', () => {
                if (videoEl.paused) {
                    try { videoEl.muted = false; } catch {}
                    videoEl.play().catch(()=>{});
                } else {
                    try { videoEl.pause(); } catch {}
                }
            });
        } else if (hotspot.icon === 'arrow' || hotspot.type === 'hotspot') {
            // Стрелка - создаем SVG маркер для навигации
            shape = document.createElement('a-plane');
            const svgData = this.createModernArrowSVG(hotspot.color || '#ff0000', size, { noFill: !!hotspot.noFill });
            const svgHover = this.createModernArrowSVGHover(hotspot.color || '#ff0000', size, { noFill: !!hotspot.noFill });
            // Безопасно кладем SVG как <img> в a-assets и ссылаемся по id (исключаем парсинг data URL внутри A-Frame)
            const assets = document.querySelector('a-assets') || (function(){ const a=document.createElement('a-assets'); document.querySelector('a-scene').appendChild(a); return a; })();
            const imgId = 'svg-arrow-' + hotspot.id;
            let img = document.getElementById(imgId);
            if (!img) {
                img = document.createElement('img');
                img.id = imgId;
                img.crossOrigin = 'anonymous';
                img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svgData);
                assets.appendChild(img);
            }
            const imgHoverId = 'svg-arrowH-' + hotspot.id;
            let imgH = document.getElementById(imgHoverId);
            if (!imgH) {
                imgH = document.createElement('img');
                imgH.id = imgHoverId;
                imgH.crossOrigin = 'anonymous';
                imgH.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svgHover);
                assets.appendChild(imgH);
            }
            shape.setAttribute('material', { shader: 'flat', src: '#' + imgId, transparent: true, alphaTest: 0.1, side: 'double' });
            shape.setAttribute('width', size * 3);
            shape.setAttribute('height', size * 3);
            shape.setAttribute('billboard', '');
            // Анимации: плавное покачивание и масштаб при ховере
            shape.setAttribute('animation__float', 'property: position; to: 0 0.3 0; dir: alternate; loop: true; dur: 2000; easing: easeInOutSine');
            shape.setAttribute('animation__hover_on', 'property: scale; to: 1.3 1.3 1.3; startEvents: hover-on; dur: 300; easing: easeOutElastic');
            shape.setAttribute('animation__hover_off', 'property: scale; to: 1 1 1; startEvents: hover-off; dur: 200; easing: easeInOutQuad');
            // hover-подмена текстуры для усиления glow
            hotspotEl.addEventListener('mouseenter', function(){ shape.setAttribute('material', { shader: 'flat', src: '#' + imgHoverId, transparent: true, alphaTest: 0.1, side: 'double' }); shape.emit('hover-on'); });
            hotspotEl.addEventListener('mouseleave', function(){ shape.setAttribute('material', { shader: 'flat', src: '#' + imgId, transparent: true, alphaTest: 0.1, side: 'double' }); shape.emit('hover-off'); });
            // Точный коллайдер для raycaster (малый круг вместо всей плоскости)
            const collider = document.createElement('a-circle');
            collider.setAttribute('radius', Math.max(0.2, size * 0.6));
            collider.setAttribute('position', '0 0 0.02');
            collider.setAttribute('material', 'color: #ffffff; opacity: 0; transparent: true; side: double');
            collider.setAttribute('data-raycastable', '');
            hotspotEl.appendChild(collider);
            // Idle-анимация убрана для 1:1 с редактором; оставляем только hover-скейл в обработчике
        } else if (hotspot.icon === 'sphere' || hotspot.type === 'info-point' || hotspot.type === 'infopoint') {
            // Информационная точка - создаем SVG маркер с "i" иконкой
            shape = document.createElement('a-plane');
            const svgData = this.createModernInfoSVG(hotspot.color || '#0099ff', size, { noFill: !!hotspot.noFill });
            const svgHover = this.createModernInfoSVGHover(hotspot.color || '#0099ff', size, { noFill: !!hotspot.noFill });
            const assets = document.querySelector('a-assets') || (function(){ const a=document.createElement('a-assets'); document.querySelector('a-scene').appendChild(a); return a; })();
            const imgId = 'svg-info-' + hotspot.id;
            let img = document.getElementById(imgId);
            if (!img) {
                img = document.createElement('img');
                img.id = imgId;
                img.crossOrigin = 'anonymous';
                img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svgData);
                assets.appendChild(img);
            }
            const imgHoverId = 'svg-infoH-' + hotspot.id;
            let imgH = document.getElementById(imgHoverId);
            if (!imgH) {
                imgH = document.createElement('img');
                imgH.id = imgHoverId;
                imgH.crossOrigin = 'anonymous';
                imgH.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svgHover);
                assets.appendChild(imgH);
            }
            shape.setAttribute('material', { shader: 'flat', src: '#' + imgId, transparent: true, alphaTest: 0.1, side: 'double' });
            shape.setAttribute('width', size * 3);
            shape.setAttribute('height', size * 3);
            shape.setAttribute('billboard', '');
            // Анимации как в редакторе
            shape.setAttribute('animation__float', 'property: position; to: 0 0.3 0; dir: alternate; loop: true; dur: 2000; easing: easeInOutSine');
            shape.setAttribute('animation__hover_on', 'property: scale; to: 1.3 1.3 1.3; startEvents: hover-on; dur: 300; easing: easeOutElastic');
            shape.setAttribute('animation__hover_off', 'property: scale; to: 1 1 1; startEvents: hover-off; dur: 200; easing: easeInOutQuad');
            hotspotEl.addEventListener('mouseenter', function(){ shape.setAttribute('material', { shader: 'flat', src: '#' + imgHoverId, transparent: true, alphaTest: 0.1, side: 'double' }); shape.emit('hover-on'); });
            hotspotEl.addEventListener('mouseleave', function(){ shape.setAttribute('material', { shader: 'flat', src: '#' + imgId, transparent: true, alphaTest: 0.1, side: 'double' }); shape.emit('hover-off'); });
            // Точный коллайдер
            const collider2 = document.createElement('a-circle');
            collider2.setAttribute('radius', Math.max(0.2, size * 0.6));
            collider2.setAttribute('position', '0 0 0.02');
            collider2.setAttribute('material', 'color: #ffffff; opacity: 0; transparent: true; side: double');
            collider2.setAttribute('data-raycastable', '');
            hotspotEl.appendChild(collider2);
            // Idle-анимация убрана для 1:1 с редактором; оставляем только hover-скейл
        } else {
            // Плоский круглый маркер по умолчанию
            shape = document.createElement('a-circle');
            shape.setAttribute('radius', size);
            shape.setAttribute('color', hotspot.color || '#ff0000');
        }

        shape.setAttribute('opacity', '0.8');
        // Для видео-областей и аним-объектов оставляем кликабельной саму плоскость
        if (hotspot.type === 'video-area' || hotspot.type === 'animated-object') {
            shape.setAttribute('data-raycastable', '');
        }
        hotspotEl.appendChild(shape);

        // Кастомная иконка если есть
        if (hotspot.customIconData) {
            const icon = document.createElement('a-image');
            icon.setAttribute('src', 'icons/' + hotspot.id + '-icon.png');
            icon.setAttribute('width', size * 2);
            icon.setAttribute('height', size * 2);
            icon.setAttribute('position', '0 0 0.01');
            icon.setAttribute('data-raycastable', '');
            hotspotEl.appendChild(icon);
        }

    // Удалено: 3D-текст над маркером в экспорте (оставляем только 2D тултип)

    this.hotspotsContainer.appendChild(hotspotEl);
    }

toggleFullscreen() {
    if (!document.fullscreenElement) {
        document.documentElement.requestFullscreen();
    } else {
        document.exitFullscreen();
    }
}

zoomIn() {
    const camera = document.querySelector('#tour-camera');
    const currentFov = camera.getAttribute('fov');
    const newFov = Math.max(30, currentFov - 10);
    camera.setAttribute('fov', newFov);
}

zoomOut() {
    const camera = document.querySelector('#tour-camera');
    const currentFov = camera.getAttribute('fov');
    const newFov = Math.min(120, currentFov + 10);
    camera.setAttribute('fov', newFov);
}

resetView() {
    const camera = document.querySelector('#tour-camera');
    camera.setAttribute('fov', 75);
    camera.setAttribute('rotation', '0 0 0');
}
// === Гироскоп ===
async enableGyro(enabled) {
    this.gyroEnabled = !!enabled;
    const cam = document.querySelector('#tour-camera');
    if (!cam) return;
    const current = cam.getAttribute('look-controls') || {};
    if (this.gyroEnabled) {
        try { await this.requestGyroPermission(); } catch {}
        cam.setAttribute('look-controls', { ...current, magicWindowTrackingEnabled: true, pointerLockEnabled: false });
    } else {
        cam.setAttribute('look-controls', { ...current, magicWindowTrackingEnabled: false });
    }
}

async requestGyroPermission() {
    const w = window;
    if (typeof w.DeviceOrientationEvent !== 'undefined' && typeof w.DeviceOrientationEvent.requestPermission === 'function') {
        try { const res = await w.DeviceOrientationEvent.requestPermission(); return res === 'granted'; } catch { return false; }
    }
    return true;
}
// ===== Загрузка и индикатор =====
showLoading(label) {
    if (!this.loadingBox) return;
    const txt = this.loadingBox.querySelector('.loading-text');
    if (txt) txt.textContent = label || 'Загрузка...';
    this.loadingBox.style.display = 'flex';
}

hideLoading() {
    if (!this.loadingBox) return;
    this.loadingBox.style.display = 'none';
}

// ===== Авторотация =====
enableAutorotate(enabled, speed, idleDelay) {
    this.autorotateEnabled = !!enabled;
    if (typeof speed === 'number') this.autorotateSpeed = speed;
    if (typeof idleDelay === 'number') this.autorotateIdleDelay = idleDelay;
    if (this.autorotateEnabled) this._startAutorotateLoop(); else this._stopAutorotateLoop();
}

_setupAutorotateUserInteractivity() {
    var self = this;
    var onInteract = function(){ self._lastUserInteraction = Date.now(); self._autorotatePaused = true; };
    var sceneEl = document.querySelector('a-scene');
    var canvas = sceneEl ? sceneEl.querySelector('canvas') : null;
    var target = canvas || window;
    ['mousedown','wheel','touchstart','keydown'].forEach(function(evt){ target.addEventListener(evt, onInteract, { passive: true }); });
}

_startAutorotateLoop() {
    if (this._autorotateRaf) return;
    this._autorotatePaused = false;
    this._autorotateLastTs = performance.now();
    var self = this;
    var loop = function(ts){
        if (!self.autorotateEnabled) { self._autorotateRaf = null; return; }
        var dt = Math.max(0, (ts - self._autorotateLastTs) / 1000);
        self._autorotateLastTs = ts;
        if (self._autorotatePaused) {
            if (Date.now() - self._lastUserInteraction >= self.autorotateIdleDelay) self._autorotatePaused = false;
        }
        var camera = document.querySelector('#tour-camera');
        if (!self._autorotatePaused && camera) {
            var rot = camera.getAttribute('rotation') || { x: 0, y: 0, z: 0 };
            var newY = rot.y + (self.autorotateSpeed * (180 / Math.PI)) * dt;
            camera.setAttribute('rotation', rot.x + ' ' + newY + ' ' + rot.z);
        }
        self._autorotateRaf = requestAnimationFrame(loop);
    };
    this._autorotateRaf = requestAnimationFrame(loop);
}

_stopAutorotateLoop() {
        if (this._autorotateRaf) {
                cancelAnimationFrame(this._autorotateRaf);
                this._autorotateRaf = null;
        }
}

}

// === Регистрация A-Frame компонентов (перенесено из viewer.js) ===
(function(){
    if (typeof AFRAME === 'undefined') { return; }
    try {
${this.generateAFrameComponents().split('\n').map(l => '    ' + l).join('\n')}
    } catch(e){ console.error('Ошибка регистрации компонентов', e); }
})();

// === Инициализация тура ===
(function initRuntime(){

    function init(){

        if (!window.TOUR_DATA) {

            setTimeout(init, 100); 
            return;
        }
        if (!Array.isArray(window.TOUR_DATA.scenes)) {
            console.error('❌ TOUR_DATA.scenes не является массивом:', window.TOUR_DATA.scenes);
            return;
        }
        if (typeof TourViewer === 'undefined') {

            setTimeout(init, 100); 
            return;
        }

        if (!window.tourViewer) {
            try { 
                window.tourViewer = new TourViewer(window.TOUR_DATA); 

            } catch(e){ 
                console.error('❌ Ошибка инициализации TourViewer:', e); 
            }
        }
    }
    if (document.readyState === 'loading') {

        document.addEventListener('DOMContentLoaded', init);
    } else {

        init();
    }
})();
`;
    }

    /**
     * Генерирует CSS стили для просмотрщика
     */
    generateViewerCSS() {
        return `/* Стили для просмотрщика панорамного тура */
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Roboto', Arial, sans-serif;
    background: #000;
    color: #fff;
    overflow: hidden;
}

#tour-container {
    width: 100vw;
    height: 100vh;
    display: block;
}

/* Левая панель со сценами */
#scene-panel {
    position: fixed;
    top: 0;
    left: 0;
    width: 280px;
    height: 100vh;
    background: rgba(26, 26, 26, 0.85);
    border-right: 1px solid #333;
    backdrop-filter: blur(4px);
    color: #fff;
    transform: translateX(0);
    transition: transform 0.2s ease-in-out;
    z-index: 1001;
}

#scene-panel:not(.open) {
    transform: translateX(-250px);
}

.scene-panel-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 10px 8px 14px;
    border-bottom: 1px solid #333;
}

.scene-panel-header .title {
    font-size: 16px;
    font-weight: 400;
}

#scene-panel-toggle {
    background: transparent;
    border: 1px solid #555;
    color: #fff;
    width: 28px;
    height: 28px;
    border-radius: 6px;
    cursor: pointer;
}

#scene-list {
    padding: 10px;
    overflow-y: auto;
    height: calc(100vh - 50px);
}

#scene-list .scene-item {
    padding: 8px 10px;
    border-radius: 6px;
    border: 1px solid transparent;
    cursor: pointer;
    margin-bottom: 6px;
}

#scene-list .scene-item.active, #scene-list .scene-item:hover {
    border-color: #646cff;
    background: rgba(100, 108, 255, 0.15);
}

#tour-controls {
    position: fixed;
    bottom: 20px;
    right: 20px;
    display: flex;
    gap: 10px;
    z-index: 1000;
}

#tour-controls button {
    width: 50px;
    height: 50px;
    background: rgba(26, 26, 26, 0.9);
    border: 1px solid #555;
    border-radius: 8px;
    color: #fff;
    font-size: 18px;
    cursor: pointer;
    transition: all 0.2s ease;
}

#tour-controls button:hover {
    background: rgba(100, 108, 255, 0.8);
    border-color: #646cff;
}

#tour-controls button:active {
    transform: scale(0.95);
}

#tour-controls #gyro-btn.active {
    background: rgba(100, 200, 120, 0.9);
    border-color: #36c26a;
}

/* Индикатор загрузки с ColoR лого */
#tour-loading { 
  position: fixed; 
  inset: 0; 
  display: flex; 
  flex-direction: column; 
  align-items: center; 
  justify-content: center; 
  gap: 25px; 
  pointer-events: none; 
  z-index: 2000; 
  font-family: 'Roboto', Arial, sans-serif; 
  animation: fadeInLoader .3s ease; 
  background: transparent;
}
#tour-loading::before {
  display: none;
}
#tour-loading::after {
  display: none;
}
@keyframes floatingOrbs {
  0%, 100% {
    transform: translate(-50%, -50%) scale(1) rotate(0deg);
    opacity: 0.8;
  }
  25% {
    transform: translate(-50%, -50%) scale(1.2) rotate(90deg);
    opacity: 0.6;
  }
  50% {
    transform: translate(-50%, -50%) scale(0.8) rotate(180deg);
    opacity: 1;
  }
  75% {
    transform: translate(-50%, -50%) scale(1.1) rotate(270deg);
    opacity: 0.7;
  }
}
@keyframes rotatingAura {
  from {
    transform: translate(-50%, -50%) rotate(0deg);
  }
  to {
    transform: translate(-50%, -50%) rotate(360deg);
  }
}
@keyframes fadeInLoader { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: translateY(0); } }
.color-logo {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  perspective: 2000px;
  position: relative;
  z-index: 1;
}
.color-logo::before {
  display: none;
}
.color-logo::after {
  display: none;
}
@keyframes floatingParticles {
  0% {
    transform: translate(-50%, -50%) translateX(0px) translateY(0px);
  }
  25% {
    transform: translate(-50%, -50%) translateX(10px) translateY(-5px);
  }
  50% {
    transform: translate(-50%, -50%) translateX(-5px) translateY(8px);
  }
  75% {
    transform: translate(-50%, -50%) translateX(8px) translateY(3px);
  }
  100% {
    transform: translate(-50%, -50%) translateX(0px) translateY(0px);
  }
}
@keyframes shimmerWave {
  0% {
    transform: translate(-50%, -50%) rotate(0deg) scale(0.8);
    opacity: 0;
  }
  50% {
    opacity: 1;
    transform: translate(-50%, -50%) rotate(180deg) scale(1.2);
  }
  100% {
    transform: translate(-50%, -50%) rotate(360deg) scale(0.8);
    opacity: 0;
  }
}
.logo-letter {
  font-size: 84px;
  font-weight: 700;
  font-family: Arial, 'Helvetica', sans-serif;
  text-shadow: 2px 2px 0px rgba(0,0,0,0.8);
  transform-style: preserve-3d;
  animation: cleanLogoFloat 4s ease-in-out infinite;
  transition: all 0.4s cubic-bezier(0.68, -0.55, 0.265, 1.55);
  position: relative;
  overflow: visible;
}
.logo-letter::before {
  content: '';
  position: absolute;
  top: -2px;
  left: -5px;
  right: -5px;
  bottom: -2px;
  background: rgba(26, 26, 26, 0.7);
  border-radius: 8px;
  z-index: -1;
  backdrop-filter: blur(10px);
}
.logo-letter::after {
  display: none;
}
@keyframes letterGlow {
  0% {
    opacity: 0.4;
    transform: scale(0.9);
  }
  100% {
    opacity: 0.8;
    transform: scale(1.1);
  }
}
@keyframes letterHalo {
  from {
    transform: translate(-50%, -50%) rotate(0deg);
  }
  to {
    transform: translate(-50%, -50%) rotate(360deg);
  }
}
.letter-c {
  color: #ff6b6b;
  animation-delay: 0s;
  background: linear-gradient(135deg, #ff6b6b 0%, #ff8e53 50%, #ffaa1a 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}
.letter-o {
  color: #4ecdc4;
  animation-delay: 0.3s;
  background: linear-gradient(135deg, #4ecdc4 0%, #44a08d 50%, #2ecc71 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}
.letter-l {
  color: #45b7d1;
  animation-delay: 0.6s;
  background: linear-gradient(135deg, #45b7d1 0%, #667eea 50%, #764ba2 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}
.letter-o2 {
  color: #f093fb;
  animation-delay: 0.9s;
  background: linear-gradient(135deg, #f093fb 0%, #f5576c 50%, #e74c3c 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}
.letter-r {
  color: #feca57;
  animation-delay: 1.2s;
  background: linear-gradient(135deg, #feca57 0%, #ff9ff3 50%, #f39c12 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}
@keyframes cleanLogoFloat {
  0%, 100% {
    transform: translateY(0px) scale(1);
  }
  25% {
    transform: translateY(-15px) scale(1.02);
  }
  50% {
    transform: translateY(-25px) scale(1.05);
  }
  75% {
    transform: translateY(-10px) scale(1.02);
  }
}
.loading-text {
  color: rgba(255, 255, 255, 0.98);
  font-size: 16px;
  letter-spacing: 0.3em;
  text-transform: uppercase;
  background: linear-gradient(
    45deg,
    #ff6b6b 0%,
    #4ecdc4 20%,
    #45b7d1 40%,
    #f093fb 60%,
    #feca57 80%,
    #ff6b6b 100%
  );
  background-size: 300% 100%;
  -webkit-background-clip: text;
  color: transparent;
  animation: cleanTextFlow 3s ease-in-out infinite;
  font-weight: 600;
  text-shadow: 
    0 1px 2px rgba(0, 0, 0, 0.8),
    0 2px 4px rgba(0, 0, 0, 0.6);
  margin-top: 30px;
  position: relative;
  overflow: visible;
  z-index: 10;
  backdrop-filter: none;
  filter: none;
}
.loading-text::before {
  content: '';
  position: absolute;
  top: -2px;
  left: -5px;
  right: -5px;
  bottom: -2px;
  background: rgba(26, 26, 26, 0.7);
  border-radius: 8px;
  z-index: -1;
  backdrop-filter: blur(10px);
}
.loading-text::after {
  display: none;
}
@keyframes cleanTextFlow {
  0%, 100% {
    background-position: 0% 50%;
    transform: scale(1);
  }
  50% {
    background-position: 100% 50%;
    transform: scale(1.02);
  }
}

/* Подсказка (2D) */
.tour-tooltip {
    position: fixed;
    padding: 6px 10px;
    background: rgba(26, 26, 26, 0.95);
    border: 1px solid #333;
    color: #fff;
    border-radius: 6px;
    font-size: 12px;
    pointer-events: none;
    z-index: 1002;
}

.tour-tooltip .title { font-weight: 600; margin-bottom: 4px; }
.tour-tooltip .tour-tip-sep { border: none; border-top: 1px solid rgba(255,255,255,.12); margin: 4px 0; }
.tour-tooltip .desc { background: rgba(255,255,255,.06); border: 1px solid rgba(255,255,255,.08); padding: 6px 8px; border-radius: 4px; color: #eee; line-height: 1.35; }

/* Стили для A-Frame сцены */
a-scene {
    border: none !important;
}

/* Адаптивность */
@media (max-width: 768px) {
    #scene-panel {
        width: 75vw;
    }
    #tour-controls {
        bottom: 10px;
        right: 10px;
        gap: 5px;
    }
    
    #tour-controls button {
        width: 40px;
        height: 40px;
        font-size: 16px;
    }
}

/* Стили для полноэкранного режима */
#tour-container:-webkit-full-screen {
    width: 100vw;
    height: 100vh;
}

#tour-container:-moz-full-screen {
    width: 100vw;
    height: 100vh;
}

#tour-container:fullscreen {
    width: 100vw;
    height: 100vh;
}`;
    }

    /**
     * Обрабатывает изображения панорам для экспорта
     */
    async processPanoramaImages(projectData, packageFiles) {

        for (const scene of projectData.scenes) {
            if (scene.panoramaData) {
                try {
                    let blob;
                    
                    // Если это Data URL, конвертируем в Blob без fetch
                    if (scene.panoramaData.startsWith('data:')) {
                        const base64Data = scene.panoramaData.split(',')[1];
                        const mimeType = scene.panoramaData.split(';')[0].split(':')[1];
                        const binaryString = atob(base64Data);
                        const bytes = new Uint8Array(binaryString.length);
                        
                        for (let i = 0; i < binaryString.length; i++) {
                            bytes[i] = binaryString.charCodeAt(i);
                        }
                        
                        blob = new Blob([bytes], { type: mimeType });
                    } else {
                        // Если это обычный URL, используем fetch
                        const response = await fetch(scene.panoramaData);
                        blob = await response.blob();
                    }

                    // Сохраняем с именем сцены
                    const imagePath = `panoramas/${scene.id}.jpg`;
                    packageFiles[imagePath] = blob;

                } catch (error) {

                }
            }
        }
    }

    /**
     * Обрабатывает кастомные иконки хотспотов
     */
    async processCustomIcons(projectData, packageFiles) {

        const processedIcons = new Set();
        for (const scene of projectData.scenes) {
            for (const hotspot of scene.hotspots) {
                // Поддержка как customIconData (оригинал), так и уже присвоенного пути customIcon
                const dataUrl = hotspot.customIconData || hotspot.customIcon;
                if (dataUrl && dataUrl.startsWith('data:') && !processedIcons.has(hotspot.id)) {
                    try {
                        let blob;
                        
                        // Конвертируем Data URL в Blob без fetch
                        const base64Data = dataUrl.split(',')[1];
                        const mimeType = dataUrl.split(';')[0].split(':')[1];
                        const binaryString = atob(base64Data);
                        const bytes = new Uint8Array(binaryString.length);
                        
                        for (let i = 0; i < binaryString.length; i++) {
                            bytes[i] = binaryString.charCodeAt(i);
                        }
                        
                        blob = new Blob([bytes], { type: mimeType });
                        
                        const iconFileName = `icons/${hotspot.id}-icon.png`;
                        packageFiles[iconFileName] = blob;
                        hotspot.customIcon = iconFileName; // нормализуем
                        hotspot.customIconData = iconFileName; // чтобы условие в createHotspot сработало
                        processedIcons.add(hotspot.id);

                    } catch (error) {

                        hotspot.customIcon = null;
                    }
                }
            }
        }
    }

    /**
     * Генерирует README файл с инструкциями
     */
    generateReadme(projectData) {
        return `# ${projectData.projectTitle}

Панорамный тур, созданный в ColoR Tour Editor.

## Установка

1. Разархивируйте файлы на ваш веб-сервер
2. Откройте index.html в браузере

## Структура файлов

- \`index.html\` - главная страница тура
- \`tour-data.js\` - данные тура и логика просмотра
- \`style.css\` - стили интерфейса
- \`panoramas/\` - изображения панорам
- \`icons/\` - кастомные иконки хотспотов

## Возможности

- 🖱️ Навигация мышью по панораме
- 📱 Поддержка мобильных устройств
- 🎯 Интерактивные хотспоты с кириллическими названиями
- 🔗 Переходы между сценами
- 🖼️ Кастомные иконки маркеров
- ⛶ Полноэкранный режим
- 🔍 Зумирование

## Управление

- **Мышь**: поворот камеры
- **Клик по хотспоту**: взаимодействие
- **Кнопки управления**: зум, сброс вида, полный экран
- **Селектор сцен**: быстрый переход между локациями

## Технические требования

- Современный браузер с поддержкой WebGL
- Веб-сервер (не работает при открытии file://)

---

Создано в ColoR Tour Editor v1.0
Дата экспорта: ${new Date().toLocaleDateString('ru-RU')}
Количество сцен: ${projectData.scenes.length}
`;
    }

    /**
     * Создает и скачивает ZIP архив
     */
    async downloadExportPackage(packageFiles) {

        if (typeof JSZip === 'undefined') {
            throw new Error('JSZip не загружен. Убедитесь что библиотека подключена.');
        }

        const zip = new JSZip();

        // Добавляем все файлы в архив
        for (const [filePath, content] of Object.entries(packageFiles)) {
            if (content instanceof Blob) {
                // Для бинарных файлов (изображения)
                zip.file(filePath, content);
            } else {
                // Для текстовых файлов
                zip.file(filePath, content);
            }
        }

        // Генерируем архив
        const zipBlob = await zip.generateAsync({
            type: 'blob',
            compression: 'DEFLATE',
            compressionOptions: { level: 6 }
        });

        // Создаем ссылку для скачивания
        const url = URL.createObjectURL(zipBlob);
        const link = document.createElement('a');
        link.href = url;
        link.download = 'panorama-tour.zip';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);

    }
}

// Глобальные функции для отладки экспорта из консоли браузера
window.testExport = function () {
    if (window.exportManager) {
        window.exportManager.exportTestProject();
    } else {
        console.error('exportManager не найден');
    }
};

window.debugExport = function () {
    if (window.exportManager) {
        const projectData = window.exportManager.collectProjectData();

        projectData.scenes.forEach((scene, index) => {

        });
        window.__LAST_EXPORT_DATA__ = projectData;
        return projectData;
    } else {
        console.error('exportManager не найден');
    }
};

window.testFullExport = async function () {
    if (window.exportManager) {

        try {
            const result = await window.exportManager.exportProject();

            return result;
        } catch (error) {
            console.error('❌ Ошибка при экспорте:', error);
        }
    } else {
        console.error('exportManager не найден');
    }
};

export default ExportManager;
