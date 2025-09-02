export default class HotspotManager {
  constructor() {
    this.viewerManager = null; // Будет установлено позже
    this.hotspots = [];
    this.sceneManager = null; // Будет установлено позже
    // Реестр видео-URL для надежного восстановления между сценами/перезагрузками
    this._videoRegistryKey = 'color_tour_video_registry';
    this.videoRegistry = this.loadVideoRegistry();

    // Реестр постеров (обложек) для видео-областей
    this._posterRegistryKey = 'color_tour_video_posters';
    this.posterRegistry = this.loadPosterRegistry();
  }

  setViewerManager(viewerManager) {
    this.viewerManager = viewerManager;
    // После привязки viewerManager пробуем восстановить отсутствующие большие видео
    try {
      if (this.hotspots && this.hotspots.some(h => h.hasVideo && !h.videoUrl)) {
        console.log('🔄 setViewerManager: обнаружены видео для восстановления, пытаемся через IndexedDB...');
        if (this._restoreVideosFromIndexedDB) {
          // Небольшая задержка чтобы DOM сцены инициализировался
          setTimeout(() => {
            try { this._restoreVideosFromIndexedDB(); } catch (e) { console.warn('⚠️ Ошибка восстановления видео (setViewerManager):', e); }
          }, 60);
        }
      } else if (this.hotspots && this.viewerManager && typeof this.viewerManager.createMissingVideoElement === 'function') {
        // Возможен сценарий когда videoUrl уже подгружены (например из реестра) до установки viewerManager
        this.hotspots.filter(h => h.hasVideo && h.videoUrl).forEach(h => {
          try { this.viewerManager.createMissingVideoElement(h); } catch { }
        });
      }
    } catch (e) {
      console.warn('⚠️ setViewerManager post-restore логика дала сбой:', e);
    }
  }

  setSceneManager(sceneManager) {
    this.sceneManager = sceneManager;
  }

  addHotspot(scene, hotspotData) {
    const id = `hotspot_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    console.log('🎯 Создаем хотспот с данными:', hotspotData);
    console.log('🎯 Позиция в hotspotData:', hotspotData.position);

    // Нормализуем позицию перед созданием хотспота
    let normalizedPosition;
    if (typeof hotspotData.position === 'string') {
      const coords = hotspotData.position.split(' ').map(c => parseFloat(c) || 0);
      normalizedPosition = { x: coords[0] || 0, y: coords[1] || 0, z: coords[2] || 0 };
    } else if (hotspotData.position && typeof hotspotData.position === 'object') {
      normalizedPosition = hotspotData.position;
    } else {
      normalizedPosition = { x: 0, y: 0, z: -5 };
    }

    const normalizeTitle = (t) => {
      try {
        if (!t || typeof t !== 'string') return t;
        // Удаляем расширение файла (видео/изображение)
        const lower = t.toLowerCase();
        const exts = ['.mp4', '.avi', '.mov', '.webm', '.mkv', '.flv', '.wmv', '.m4v', '.3gp', '.ogv', '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.svg', '.webp', '.tiff', '.ico'];
        for (const ext of exts) { if (lower.endsWith(ext)) return t.slice(0, -ext.length).slice(0, 100); }
        return t.slice(0, 100);
      } catch { return t; }
    };

    const newHotspot = {
      id,
      sceneId: scene.id,
      ...hotspotData,
      title: hotspotData && hotspotData.title ? normalizeTitle(hotspotData.title) : hotspotData.title,
      position: normalizedPosition
    };
    console.log('🎯 Финальный хотспот:', newHotspot);
    console.log('🎯 Позиция в newHotspot:', newHotspot.position);

    this.hotspots.push(newHotspot);
    scene.hotspots.push(newHotspot); // Также сохраняем в сцене для совместимости

    this.viewerManager.createVisualMarker(newHotspot);

    // Регистрируем videoUrl в реестре, если он уже задан
    if (newHotspot.videoUrl && typeof newHotspot.videoUrl === 'string' && newHotspot.videoUrl.trim() !== '') {
      this.registerVideoUrl(newHotspot.id, newHotspot.videoUrl);
    }

    // Автоматически сохраняем в localStorage
    this.saveToStorage();

    console.log('Хотспот добавлен:', newHotspot);
  }

  updateHotspot(hotspotId, data) {
    const hotspot = this.findHotspotById(hotspotId);
    if (!hotspot) return false;

    const normalized = { ...data };
    if (data && typeof data.title === 'string') {
      try {
        const t = data.title;
        const lower = t.toLowerCase();
        const exts = ['.mp4', '.avi', '.mov', '.webm', '.mkv', '.flv', '.wmv', '.m4v', '.3gp', '.ogv', '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.svg', '.webp', '.tiff', '.ico'];
        for (const ext of exts) { if (lower.endsWith(ext)) { normalized.title = t.slice(0, -ext.length).slice(0, 100); break; } }
        if (!normalized.title) normalized.title = t.slice(0, 100);
      } catch { /* ignore */ }
    }
    Object.assign(hotspot, normalized);
    this.viewerManager.updateVisualMarker(hotspot);

    // Если обновился videoUrl — фиксируем его в реестре для будущего восстановления
    if (data && typeof data.videoUrl === 'string' && data.videoUrl.trim() !== '') {
      this.registerVideoUrl(hotspotId, data.videoUrl);
    }

    // Автоматически сохраняем в localStorage
    this.saveToStorage();

    console.log('Хотспот обновлен:', hotspot);
    return true;
  }

  updateHotspotPosition(hotspotId, position) {
    const hotspot = this.findHotspotById(hotspotId);
    if (!hotspot) {
      console.warn('Хотспот не найден для обновления позиции:', hotspotId);
      return;
    }

    // Преобразуем позицию в правильный формат объекта для сохранения
    let normalizedPosition;
    if (position && typeof position === 'object') {
      if (position.x !== undefined && position.y !== undefined && position.z !== undefined) {
        // A-Frame позиция объект - извлекаем координаты
        normalizedPosition = {
          x: parseFloat(position.x) || 0,
          y: parseFloat(position.y) || 0,
          z: parseFloat(position.z) || 0
        };
      } else {
        // Уже нормализованный объект
        normalizedPosition = position;
      }
    } else if (typeof position === 'string') {
      // Строковая позиция "x y z"
      const coords = position.split(' ').map(c => parseFloat(c) || 0);
      normalizedPosition = { x: coords[0] || 0, y: coords[1] || 0, z: coords[2] || 0 };
    } else {
      console.warn('💾 Неизвестный формат позиции:', position);
      normalizedPosition = { x: 0, y: 0, z: -5 };
    }

    hotspot.position = normalizedPosition;
    console.log('💾 Позиция хотспота обновлена:', hotspotId, normalizedPosition);
    console.log('💾 Тип позиции:', typeof normalizedPosition, 'Конструктор:', normalizedPosition?.constructor?.name);
    console.log('💾 Содержимое позиции:', JSON.stringify(normalizedPosition));

    // Также обновляем в связанной сцене
    if (this.sceneManager) {
      const scene = this.sceneManager.getSceneById(hotspot.sceneId);
      if (scene) {
        const sceneHotspot = scene.hotspots.find(h => h.id === hotspotId);
        if (sceneHotspot) {
          sceneHotspot.position = normalizedPosition;
        }
      }
    }

    // Автоматически сохраняем в localStorage
    this.saveToStorage();
  }

  removeHotspotById(hotspotId) {
    const index = this.hotspots.findIndex(h => h.id === hotspotId);
    if (index === -1) return;

    const hotspot = this.hotspots[index];

    // Удаляем из массива хотспотов
    this.hotspots.splice(index, 1);

    // Также удаляем из связанной сцены
    if (this.sceneManager) {
      const scene = this.sceneManager.getSceneById(hotspot.sceneId);
      if (scene && scene.hotspots) {
        const sceneIndex = scene.hotspots.findIndex(h => h.id === hotspotId);
        if (sceneIndex !== -1) {
          scene.hotspots.splice(sceneIndex, 1);
        }
      }
    }

    // Удаляем визуальный маркер
    if (this.viewerManager) {
      this.viewerManager.removeVisualMarker(hotspotId);
    }

    // Сохраняем изменения
    this.saveToStorage();

    console.log('Хотспот удален:', hotspotId);
  }

  editHotspot(hotspotId) {
    const hotspot = this.findHotspotById(hotspotId);
    if (!hotspot) {
      console.warn('Хотспот не найден для редактирования:', hotspotId);
      return;
    }

    // Вызываем глобальную функцию редактирования маркера
    if (window.editMarker) {
      window.editMarker(hotspotId);
    } else {
      console.warn('Функция editMarker не найдена');
    }
  }

  removeHotspotByMarkerId(markerId) {
    // Извлекаем ID хотспота из ID маркера
    const hotspotId = markerId.replace('marker-', '');
    this.removeHotspotById(hotspotId);
  }

  findHotspotById(id) {
    const hotspot = this.hotspots.find(h => h.id === id);
    if (hotspot && hotspot._needsVideoRestore && !hotspot.videoUrl) {
      // Логируем о необходимости восстановления video URL
      console.log(`🔄 Хотспот ${id} требует восстановления videoUrl`);
      if (typeof hotspot._needsVideoRestore === 'string') {
        console.log(`📁 Ожидаемый файл: ${hotspot._needsVideoRestore}`);
      }
    }
    return hotspot;
  }

  findHotspotByMarkerId(markerId) {
    const hotspotId = markerId.replace('marker-', '');
    return this.findHotspotById(hotspotId);
  }

  getHotspotsForScene(sceneId) {
    console.log('🔍 getHotspotsForScene вызван для сцены:', sceneId);
    console.log('🔍 Все доступные маркеры:', this.hotspots);

    // Загружаем из localStorage при каждом запросе для актуализации данных
    this.loadFromStorage();

    // ВАЖНО: фильтруем хотспоты строго по sceneId
    const sceneHotspots = this.hotspots.filter(h => h.sceneId === sceneId);
    console.log('🔍 Найдено маркеров для сцены', sceneId, ':', sceneHotspots.length);

    if (sceneHotspots.length === 0) {
      console.log('📋 Маркеры других сцен:', this.hotspots.filter(h => h.sceneId !== sceneId));
    }

    return sceneHotspots;
  }

  /**
   * Очищает хотспоты, принадлежащие несуществующим сценам
   */
  cleanupOrphanedHotspots(validSceneIds) {
    console.log('🧹 Очищаем хотспоты-сироты...');
    console.log('✅ Валидные ID сцен:', validSceneIds);

    const before = this.hotspots.length;
    const orphanedHotspots = this.hotspots.filter(h => !validSceneIds.includes(h.sceneId));

    if (orphanedHotspots.length > 0) {
      console.log('🗑️ Найдены хотспоты-сироты для удаления:', orphanedHotspots.length);
      orphanedHotspots.forEach(hotspot => {
        console.log(`  🗑️ Удаляем хотспот "${hotspot.title}" (sceneId: ${hotspot.sceneId})`);
      });

      this.hotspots = this.hotspots.filter(h => validSceneIds.includes(h.sceneId));
      this.saveToStorage();

      console.log(`✅ Очистка завершена: было ${before}, стало ${this.hotspots.length}`);
      return orphanedHotspots.length;
    }

    console.log('✅ Хотспоты-сироты не найдены');
    return 0;
  }

  getHotspots() {
    // Возвращаем все хотспоты
    return this.hotspots || [];
  }

  loadHotspots(hotspotsData) {
    this.hotspots = hotspotsData || [];
    console.log('Загружено хотспотов:', this.hotspots.length);

    // Пост-обработка: сразу нормализуем и пытаемся восстановить видео-URL из возможных полей (file/src/videoData)
    try {
      let needIndexedRestore = false;
      (this.hotspots || []).forEach((h) => {
        // Нормализуем базовые поля, цвета, размеры и т.п.
        try { this.restoreHotspotData(h); } catch (e) { console.warn('⚠️ Ошибка restoreHotspotData в loadHotspots:', e); }

        // Если после нормализации видео всё ещё нет — помечаем для IndexedDB
        if (h && h.hasVideo && !h.videoUrl) {
          needIndexedRestore = true;
        }
      });

      // Если есть маркеры, требующие восстановления из IndexedDB — запускаем
      if (needIndexedRestore && this._restoreVideosFromIndexedDB) {
        setTimeout(() => {
          try { this._restoreVideosFromIndexedDB(); } catch (e) { console.warn('⚠️ Ошибка восстановления видео из IndexedDB (loadHotspots):', e); }
        }, 80);
      }
    } catch (e) {
      console.warn('⚠️ Пост-обработка загруженных хотспотов завершилась с ошибкой:', e);
    }
  }

  getAllHotspots() {
    return this.hotspots;
  }

  updateAllMarkersWithSettings(settings) {
    this.hotspots.forEach(hotspot => {
      if (!hotspot.size) {
        hotspot.size = hotspot.type === 'hotspot' ? settings.hotspotSize : settings.infopointSize;
      }
      if (!hotspot.color) { // Если у хотспота нет индивидуального цвета
        hotspot.color = hotspot.type === 'hotspot' ? settings.hotspotColor : settings.infopointColor;
        if (this.viewerManager) {
          this.viewerManager.updateVisualMarker(hotspot);
        }
      }
    });
  }

  /**
   * Сохраняет текущие хотспоты в localStorage
   */
  saveToStorage() {
    try {
      console.log('💾 Сохраняем хотспоты:', this.hotspots.length);

      // РАДИКАЛЬНАЯ ОПТИМИЗАЦИЯ: сохраняем только критически важные данные
      const hotspotsToSave = this.hotspots.map(hotspot => {
        // Сохраняем только минимально необходимые поля
        const minimizedHotspot = {
          id: hotspot.id,
          sceneId: hotspot.sceneId,
          type: hotspot.type,
          position: hotspot.position
        };

        // КРИТИЧЕСКИ ВАЖНО: Сохраняем цвет хотспота
        if (hotspot.color && hotspot.color !== 'undefined') {
          minimizedHotspot.color = hotspot.color;
        }

        // КРИТИЧЕСКИ ВАЖНО: Сохраняем иконку хотспота
        if (hotspot.icon && hotspot.icon !== 'undefined') {
          minimizedHotspot.icon = hotspot.icon;
        }

        // КРИТИЧЕСКИ ВАЖНО: Сохраняем данные пользовательской иконки для кастомных иконок
        if (hotspot.icon === 'custom' && hotspot.customIconData) {
          minimizedHotspot.customIconData = hotspot.customIconData;
        }

        // Сохраняем другие важные визуальные настройки
        if (hotspot.size && hotspot.size !== 0.3) {
          minimizedHotspot.size = hotspot.size;
        }
        if (hotspot.targetSceneId) {
          minimizedHotspot.targetSceneId = hotspot.targetSceneId;
        }

        // Добавляем размеры только если они не дефолтные
        if (hotspot.width && hotspot.width !== 2) {
          minimizedHotspot.width = hotspot.width;
        }
        if (hotspot.height && hotspot.height !== 1.5) {
          minimizedHotspot.height = hotspot.height;
        }

        // Видео размеры (для video-area и animated-object)
        if (hotspot.videoWidth) minimizedHotspot.videoWidth = hotspot.videoWidth;
        if (hotspot.videoHeight) minimizedHotspot.videoHeight = hotspot.videoHeight;

        // Для iframe-3d сохраняем iframeUrl (он небольшой) и размеры
        if (hotspot.type === 'iframe-3d') {
          if (hotspot.iframeUrl) minimizedHotspot.iframeUrl = hotspot.iframeUrl;
        }

        // Хромакей параметры для animated-object
        if (hotspot.type === 'animated-object') {
          if (hotspot.chromaEnabled) minimizedHotspot.chromaEnabled = !!hotspot.chromaEnabled;
          if (hotspot.chromaColor) minimizedHotspot.chromaColor = hotspot.chromaColor;
          if (hotspot.chromaSimilarity !== undefined) minimizedHotspot.chromaSimilarity = hotspot.chromaSimilarity;
          if (hotspot.chromaSmoothness !== undefined) minimizedHotspot.chromaSmoothness = hotspot.chromaSmoothness;
          if (hotspot.chromaThreshold !== undefined) minimizedHotspot.chromaThreshold = hotspot.chromaThreshold;
        }

        // Добавляем rotation только если он не нулевой
        if (hotspot.rotation && (hotspot.rotation !== "0 0 0" && hotspot.rotation !== 0)) {
          minimizedHotspot.rotation = hotspot.rotation;
        }

        // Добавляем title только если он есть и не пустой
        if (hotspot.title && hotspot.title.trim()) {
          minimizedHotspot.title = hotspot.title.substring(0, 50); // Ограничиваем длину
        }

        // ИСПРАВЛЕНИЕ: Сохраняем _originalData с исключенными большими полями
        const excludedFields = ['videoUrl', 'videoData', 'thumbnail', 'poster', 'src', 'href', 'data', 'content', 'blob', 'customIconData'];
        const originalData = {};
        let hasOriginalData = false;

        excludedFields.forEach(field => {
          if (hotspot.hasOwnProperty(field) && hotspot[field]) {
            // Специальная оптимизация для videoUrl с огромными base64 (data:video/)
            if (field === 'videoUrl') {
              const val = String(hotspot[field]);
              const isDataUrl = val.startsWith('data:video');
              // Если это большой dataURL (> 50KB), НЕ кладем его в _originalData (полагаться на реестр)
              if (isDataUrl && val.length > 50 * 1024) {
                // Регистрируем имя файла/хэш вместо полного содержимого
                if (!minimizedHotspot.videoFileName) {
                  try {
                    const parts = val.substring(0, 120).split('/');
                    minimizedHotspot.videoFileName = parts[parts.length - 1].slice(0, 40) + '...';
                  } catch { }
                }
                minimizedHotspot.hasVideo = true;
                console.log('⚡ Пропускаем сохранение большого base64 videoUrl в _originalData (используем реестр + IndexedDB)');
                // Асинхронно сохраняем в IndexedDB
                this._saveLargeVideoToIndexedDB && this._saveLargeVideoToIndexedDB(hotspot.id, val);
                return; // skip
              }
            }
            // Аналогичная оптимизация для videoData (когда хранится чистое base64 без префикса или с ним)
            if (field === 'videoData') {
              const val = String(hotspot[field]);
              const isLarge = val.length > 50 * 1024; // ~50KB
              if (isLarge) {
                // Формируем dataURL если нужно и сохраняем в IndexedDB вместо localStorage
                let dataUrl = val.startsWith('data:video') ? val : `data:video/mp4;base64,${val}`;
                minimizedHotspot.hasVideo = true;
                if (!minimizedHotspot.videoFileName) {
                  try { minimizedHotspot.videoFileName = (dataUrl.substring(0, 60) + '...'); } catch { }
                }
                console.log('⚡ Пропускаем сохранение большого videoData в _originalData (перенос в IndexedDB)');
                this._saveLargeVideoToIndexedDB && this._saveLargeVideoToIndexedDB(hotspot.id, dataUrl);
                return; // skip storing huge raw videoData
              }
            }
            originalData[field] = hotspot[field];
            hasOriginalData = true;
            console.log(`💾 Сохраняем в _originalData: ${field} (размер: ${JSON.stringify(hotspot[field]).length} символов)`);
          }
        });

        // Если есть большие данные для сохранения, сохраняем их в _originalData
        if (hasOriginalData) {
          minimizedHotspot._originalData = originalData;
        }

        // ВАЖНО: Сохраняем информацию о наличии videoUrl для восстановления
        if (hotspot.videoUrl && hotspot.videoUrl.trim() !== '') {
          // Сохраняем только имя файла или последние символы URL для идентификации
          const urlParts = hotspot.videoUrl.split('/');
          const fileName = urlParts[urlParts.length - 1];
          if (fileName.length < 100) { // Сохраняем короткие имена файлов
            minimizedHotspot.videoFileName = fileName;
          }
          minimizedHotspot.hasVideo = true;
        }

        // Логирование для отладки размера данных
        const originalSize = JSON.stringify(hotspot).length;
        const optimizedSize = JSON.stringify(minimizedHotspot).length;
        const reduction = ((originalSize - optimizedSize) / originalSize * 100).toFixed(1);

        console.log(`💾 Минимизированный хотспот: ${hotspot.id}`);
        console.log(`   Размер до: ${originalSize} символов`);
        console.log(`   Размер после минимизации: ${optimizedSize} символов`);
        console.log(`   Общее сжатие: ${reduction}%`);

        return minimizedHotspot;
      });

      const dataToSave = JSON.stringify(hotspotsToSave);

      // Проверяем размер данных
      const sizeKB = (dataToSave.length / 1024).toFixed(2);
      console.log(`💾 Размер оптимизированных данных: ${sizeKB} KB (было: 5653+ KB)`);

      // Проверяем, что размер приемлемый (менее 2MB)
      if (dataToSave.length > 2 * 1024 * 1024) {
        console.warn('⚠️ Данные все еще слишком большие, дополнительная оптимизация...');
        // Сохраняем только последние 30 хотспотов
        const recentHotspots = hotspotsToSave.slice(-30);
        const reducedData = JSON.stringify(recentHotspots);
        console.log(`💾 Сохраняем только последние 30 хотспотов: ${(reducedData.length / 1024).toFixed(2)} KB`);
        localStorage.setItem('color_tour_hotspots', reducedData);
      } else {
        localStorage.setItem('color_tour_hotspots', dataToSave);
      }

      console.log('💾 Хотспоты сохранены в localStorage (оптимизированная версия)');
    } catch (error) {
      if (error.name === 'QuotaExceededError') {
        console.error('❌ localStorage переполнен! Пытаемся экстренную оптимизацию...');
        this.handleQuotaExceeded();
      } else {
        console.error('❌ Ошибка сохранения хотспотов:', error);
      }
    }
  }

  /**
   * Загружает реестр видео-URL из localStorage
   */
  loadVideoRegistry() {
    try {
      const raw = localStorage.getItem(this._videoRegistryKey);
      const parsed = raw ? JSON.parse(raw) : {};
      return parsed && typeof parsed === 'object' ? parsed : {};
    } catch (e) {
      console.warn('⚠️ Не удалось загрузить реестр видео-URL, создаем новый:', e);
      return {};
    }
  }

  /**
   * Загружает реестр постеров из localStorage
   */
  loadPosterRegistry() {
    try {
      const raw = localStorage.getItem(this._posterRegistryKey);
      const parsed = raw ? JSON.parse(raw) : {};
      return parsed && typeof parsed === 'object' ? parsed : {};
    } catch (e) {
      console.warn('⚠️ Не удалось загрузить реестр постеров, создаем новый:', e);
      return {};
    }
  }

  /**
   * Сохраняет реестр видео-URL в localStorage
   */
  saveVideoRegistry() {
    try {
      // Пытаемся сохранить как есть
      localStorage.setItem(this._videoRegistryKey, JSON.stringify(this.videoRegistry || {}));
    } catch (e) {
      console.warn('⚠️ Не удалось сохранить реестр видео-URL:', e);
      // Fallback: создаем урезанную копию без огромных data:URL
      try {
        const slim = {};
        const src = this.videoRegistry || {};
        for (const id in src) {
          const entry = src[id] || {};
          const url = String(entry.url || '');
          const isHugeData = url.startsWith('data:video') && url.length > 50 * 1024;
          if (isHugeData) {
            slim[id] = { url: null, fileName: entry.fileName, storedIn: 'indexeddb', ts: Date.now() };
          } else {
            // Ограничиваем длину URL для безопасности
            slim[id] = { ...entry };
            if (slim[id].url && String(slim[id].url).length > 5000) {
              slim[id].url = null;
              slim[id].storedIn = 'indexeddb';
            }
          }
        }
        localStorage.setItem(this._videoRegistryKey, JSON.stringify(slim));
        this.videoRegistry = slim;
        console.log('✅ Реестр видео сохранен в урезанном виде');
      } catch (e2) {
        console.warn('⚠️ Не удалось сохранить даже урезанный реестр видео:', e2);
      }
    }
  }

  /**
   * Сохраняет реестр постеров в localStorage
   */
  savePosterRegistry() {
    try {
      localStorage.setItem(this._posterRegistryKey, JSON.stringify(this.posterRegistry || {}));
    } catch (e) {
      console.warn('⚠️ Не удалось сохранить реестр постеров:', e);
    }
  }

  /**
   * Регистрирует videoUrl для хотспота и синхронизирует базовые флаги
   */
  registerVideoUrl(hotspotId, videoUrl) {
    if (!hotspotId || !videoUrl) return;

    const fileName = (() => {
      try {
        const parts = String(videoUrl).split('/');
        return parts[parts.length - 1] || String(videoUrl);
      } catch {
        return String(videoUrl);
      }
    })();

    // Не сохраняем огромные data:URL в localStorage — только пометка, что хранится в IndexedDB
    const isHugeData = String(videoUrl).startsWith('data:video') && String(videoUrl).length > 50 * 1024;
    if (isHugeData) {
      this.videoRegistry[hotspotId] = { url: null, fileName, storedIn: 'indexeddb', ts: Date.now() };
    } else {
      this.videoRegistry[hotspotId] = { url: videoUrl, fileName, ts: Date.now() };
    }
    this.saveVideoRegistry();

    // Синхронизируем в памяти хотспот
    const hotspot = this.findHotspotById(hotspotId);
    if (hotspot) {
      hotspot.videoUrl = videoUrl;
      hotspot.hasVideo = true;
      hotspot.videoFileName = fileName;
      if (hotspot._needsVideoRestore) delete hotspot._needsVideoRestore;
    }
  }

  /**
   * Регистрирует обложку (poster) как data URL или внешний URL
   */
  registerPoster(hotspotId, posterUrl) {
    if (!hotspotId || !posterUrl) return;
    this.posterRegistry[hotspotId] = { url: posterUrl, ts: Date.now() };
    this.savePosterRegistry();

    const hotspot = this.findHotspotById(hotspotId);
    if (hotspot) {
      hotspot.poster = posterUrl;
    }
  }

  /**
   * Возвращает обложку (poster) из реестра
   */
  getPoster(hotspotId) {
    const entry = this.posterRegistry ? this.posterRegistry[hotspotId] : null;
    return entry && entry.url ? entry.url : null;
  }

  /**
   * Возвращает videoUrl из реестра для указанного хотспота
   */
  getVideoUrlFromRegistry(hotspotId) {
    const entry = this.videoRegistry ? this.videoRegistry[hotspotId] : null;
    if (!entry) return null;
    if (entry.storedIn === 'indexeddb' || !entry.url) return null; // восстановление через IndexedDB
    return entry.url;
  }

  /**
   * Обрабатывает переполнение localStorage
   */
  handleQuotaExceeded() {
    try {
      const now = Date.now();
      if (this._lastQuotaRecoveryTime && (now - this._lastQuotaRecoveryTime) < 5000) {
        console.warn('⏱️ handleQuotaExceeded: пропуск повторной оптимизации (частые вызовы)');
        return;
      }
      this._lastQuotaRecoveryTime = now;

      console.log('⚠️ localStorage переполнен, выполняем автоматическую оптимизацию...');

      // Сохраняем существующие реестры перед очисткой
      let videoRegistryBackup = null;
      let posterRegistryBackup = null;
      try { videoRegistryBackup = JSON.stringify(this.videoRegistry || {}); } catch { }
      try { posterRegistryBackup = JSON.stringify(this.posterRegistry || {}); } catch { }

      // Очищаем только ключи, влияющие на размер, а не весь localStorage (мягкая очистка)
      try { localStorage.removeItem('color_tour_hotspots'); } catch { }

      // Если всё ещё превышает лимит (некоторые браузеры могут бросить сразу) — fallback тотальная очистка
      try { localStorage.setItem('__quota_test__', '1'); localStorage.removeItem('__quota_test__'); }
      catch {
        console.log('⚠️ Мягкая очистка не помогла — выполняем полную очистку');
        localStorage.clear();
      }

      // Сохраняем только последние 20 хотспотов с расширенными визуальными полями
      const recentHotspots = this.hotspots.slice(-20).map(h => ({
        id: h.id,
        sceneId: h.sceneId,
        type: h.type || 'video-area',
        position: h.position,
        width: h.width || 2,
        height: h.height || 1.5,
        color: h.color,
        size: h.size,
        icon: h.icon,
        title: h.title,
        targetSceneId: h.targetSceneId,
        textColor: h.textColor,
        textSize: h.textSize,
        videoFileName: h.videoFileName,
        hasVideo: !!h.hasVideo
      }));

      const emergencyData = JSON.stringify(recentHotspots);
      console.log(`🆘 Автоматическое сохранение ${recentHotspots.length} последних хотспотов (расширенный формат): ${(emergencyData.length / 1024).toFixed(2)} KB`);
      localStorage.setItem('color_tour_hotspots', emergencyData);

      // Восстанавливаем реестры (если они не слишком большие)
      try { if (videoRegistryBackup && videoRegistryBackup.length < 200 * 1024) localStorage.setItem(this._videoRegistryKey, videoRegistryBackup); } catch { }
      try { if (posterRegistryBackup && posterRegistryBackup.length < 200 * 1024) localStorage.setItem(this._posterRegistryKey, posterRegistryBackup); } catch { }

      console.log('💾 Автоматическое сохранение выполнено успешно (расширенный формат)');
    } catch (retryError) {
      console.error('❌ Ошибка при автоматическом сохранении:', retryError);
    }
  }

  /**
   * Загружает хотспоты из localStorage
   */
  loadFromStorage() {
    try {
      const stored = localStorage.getItem('color_tour_hotspots');
      if (stored) {
        this.hotspots = JSON.parse(stored);
        console.log('📥 Хотспоты загружены из localStorage:', this.hotspots.length);

        // Восстанавливаем недостающие поля из полных данных хотспотов
        this.hotspots.forEach((hotspot, index) => {
          console.log(`📥 Загруженный хотспот ${index + 1}: ${hotspot.id}`);
          console.log(`   Позиция: ${JSON.stringify(hotspot.position)}`);

          // Восстанавливаем недостающие поля из полных данных в памяти
          this.restoreHotspotData(hotspot);
        });

        // Асинхронно восстанавливаем большие видео из IndexedDB (если они были вынесены)
        try {
          if (this.hotspots.some(h => h.hasVideo && !h.videoUrl)) {
            console.log('🔄 Обнаружены хотспоты с отсутствующим videoUrl — планируем восстановление из IndexedDB...');
            if (this._restoreVideosFromIndexedDB) {
              setTimeout(() => {
                try { this._restoreVideosFromIndexedDB(); } catch (e) { console.warn('⚠️ Ошибка восстановления видео из IndexedDB:', e); }
              }, 80);
            }
          }
        } catch (e) {
          console.warn('⚠️ Планирование восстановления из IndexedDB не удалось:', e);
        }

        return true;
      }
      return false;
    } catch (error) {
      console.error('❌ Ошибка загрузки хотспотов:', error);
      return false;
    }
  }

  /**
   * Восстанавливает исключенные при сохранении поля хотспота
   */
  restoreHotspotData(hotspot) {
    // Устанавливаем дефолтные значения для основных полей
    if (!hotspot.width) hotspot.width = 2;
    if (!hotspot.height) hotspot.height = 1.5;
    if (!hotspot.rotation) hotspot.rotation = "0 0 0";
    if (!hotspot.type) hotspot.type = "video-area";

    // Восстанавливаем размеры видео если отсутствуют
    if (hotspot.type === 'video-area') {
      if (!hotspot.videoWidth) hotspot.videoWidth = 4;
      if (!hotspot.videoHeight) hotspot.videoHeight = 3;
    } else if (hotspot.type === 'animated-object') {
      if (!hotspot.videoWidth) hotspot.videoWidth = 2;
      if (!hotspot.videoHeight) hotspot.videoHeight = (2 * 9 / 16);
      // Значения по умолчанию для хромакея
      if (hotspot.chromaEnabled === undefined) hotspot.chromaEnabled = false;
      if (!hotspot.chromaColor) hotspot.chromaColor = '#00ff00';
      if (hotspot.chromaSimilarity === undefined) hotspot.chromaSimilarity = 0.4;
      if (hotspot.chromaSmoothness === undefined) hotspot.chromaSmoothness = 0.1;
      if (hotspot.chromaThreshold === undefined) hotspot.chromaThreshold = 0.0;
    }

    // КРИТИЧЕСКИ ВАЖНО: сохраняем оригинальный цвет перед восстановлением
    const originalColor = hotspot.color;
    console.log('🔍 Восстановление данных хотспота:', hotspot.id, 'оригинальный цвет:', originalColor);

    // ИСПРАВЛЯЕМ: восстанавливаем цвета только если их действительно нет
    const defaultSettings = this.getDefaultSettings();

    // Проверяем, есть ли валидный цвет (включая стандартные цвета)
    const hasValidColor = originalColor &&
      originalColor !== 'undefined' &&
      originalColor !== '' &&
      originalColor !== null;

    if (!hasValidColor) {
      if (hotspot.type === 'hotspot') {
        hotspot.color = defaultSettings?.hotspotColor || '#ff0000';
      } else if (hotspot.type === 'info-point') {
        hotspot.color = defaultSettings?.infopointColor || '#0066cc';
      } else {
        hotspot.color = '#ffcc00'; // Цвет по умолчанию для других типов
      }
      console.log('🎨 Восстановлен цвет по умолчанию для хотспота:', hotspot.id, hotspot.type, '->', hotspot.color);
    } else {
      // ВАЖНО: сохраняем оригинальный цвет
      hotspot.color = originalColor;
      console.log('✅ Сохранен оригинальный цвет хотспота:', hotspot.id, hotspot.type, '->', hotspot.color);
    }

    // Восстанавливаем другие визуальные свойства
    if (!hotspot.textColor) hotspot.textColor = '#ffffff';
    if (!hotspot.textSize) hotspot.textSize = '1';
    if (!hotspot.textFamily) hotspot.textFamily = 'Arial, sans-serif';
    if (hotspot.textBold === undefined) hotspot.textBold = false;
    if (hotspot.textUnderline === undefined) hotspot.textUnderline = false;

    // ИСПРАВЛЕНИЕ: Восстанавливаем иконку если она была установлена
    if (hotspot.icon === undefined || hotspot.icon === null) {
      // Устанавливаем иконку по умолчанию в зависимости от типа
      if (hotspot.type === 'hotspot') {
        hotspot.icon = 'arrow';
      } else if (hotspot.type === 'info-point') {
        hotspot.icon = 'sphere';
      } else if (hotspot.type === 'video-area' || hotspot.type === 'animated-object') {
        hotspot.icon = 'cube';
      } else {
        hotspot.icon = 'sphere'; // По умолчанию
      }
      console.log('🖼️ Восстановлена иконка по умолчанию для хотспота:', hotspot.id, hotspot.type, '->', hotspot.icon);
    } else {
      console.log('✅ Сохранена оригинальная иконка хотспота:', hotspot.id, hotspot.icon);
    }

    // Восстанавливаем данные пользовательской иконки, если это кастомная иконка
    if (hotspot.icon === 'custom' && hotspot.customIconData) {
      console.log('✅ Сохранены данные пользовательской иконки для хотспота:', hotspot.id);
    }

    // Восстанавливаем videoUrl из альтернативных полей (file/src/videoData), если он отсутствует
    try {
      if (!hotspot.videoUrl) {
        let candidate = null;

        const normalizeDataVideo = (str) => {
          if (!str || typeof str !== 'string') return null;
          const v = str.trim();
          if (v.startsWith('data:video/')) return v;
          // Преобразуем формы: "mp4;base64,...." или "webm;base64,..."
          const m = v.match(/^(mp4|webm|ogg);base64,(.+)$/i);
          if (m) return `data:video/${m[1].toLowerCase()};base64,${m[2]}`;
          // Преобразуем "base64,...." в mp4 по умолчанию
          const m2 = v.match(/^base64,(.+)$/i);
          if (m2) return `data:video/mp4;base64,${m2[1]}`;
          return null;
        };

        // 1) Поле file (часто попадает при импорте проекта) — может быть: "data:video/...", "mp4;base64,...", "webm;base64,...", либо просто "base64,..."
        if (!candidate && typeof hotspot.file === 'string' && hotspot.file.trim().length > 0) {
          candidate = normalizeDataVideo(hotspot.file);
        }

        // 2) Поле src — если вдруг там лежит dataURL видео
        if (!candidate && typeof hotspot.src === 'string') {
          const v = normalizeDataVideo(hotspot.src);
          if (v) candidate = v;
        }

        // 3) Поле videoData (чистое base64) — оборачиваем в dataURL
        if (!candidate && typeof hotspot.videoData === 'string' && hotspot.videoData.trim().length > 0) {
          candidate = normalizeDataVideo(hotspot.videoData);
        }

        if (candidate && candidate.startsWith('data:video')) {
          hotspot.videoUrl = candidate;
          hotspot.hasVideo = true;
          try { this.registerVideoUrl(hotspot.id, candidate); } catch { }
          // Сохраняем большой dataURL в IndexedDB для надёжности между сессиями
          try { this._saveLargeVideoToIndexedDB && this._saveLargeVideoToIndexedDB(hotspot.id, candidate); } catch { }
          // Очищаем флаг восстановления, если был
          if (hotspot._needsVideoRestore) delete hotspot._needsVideoRestore;
          // Немедленно обновляем визуальный элемент, если viewerManager уже привязан
          try {
            if (this.viewerManager && typeof this.viewerManager.createMissingVideoElement === 'function') {
              this.viewerManager.createMissingVideoElement(hotspot);
            }
          } catch { /* ignore */ }
        }
      }
    } catch (e) {
      console.warn('⚠️ Ошибка при восстановлении videoUrl из альтернативных полей:', e);
    }

    // Проверяем, нужно ли восстановить videoUrl (после попытки из альтернативных полей)
    if (hotspot.hasVideo && !hotspot.videoUrl) {
      if (hotspot.videoFileName) {
        // Помечаем для восстановления с информацией о файле
        hotspot._needsVideoRestore = hotspot.videoFileName;
        console.log(`⚠️ videoUrl отсутствует для хотспота ${hotspot.id} - файл: ${hotspot.videoFileName}`);
      } else {
        hotspot._needsVideoRestore = true;
        console.log(`⚠️ videoUrl отсутствует для хотспота ${hotspot.id} - потребуется переустановка`);
      }
    }

    // ЕДИНООБРАЗИЕ НАЗВАНИЙ: удаляем расширение файлов из title
    try {
      if (hotspot.title && typeof hotspot.title === 'string') {
        const t = hotspot.title;
        const lower = t.toLowerCase();
        const exts = ['.mp4', '.avi', '.mov', '.webm', '.mkv', '.flv', '.wmv', '.m4v', '.3gp', '.ogv', '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.svg', '.webp', '.tiff', '.ico'];
        for (const ext of exts) {
          if (lower.endsWith(ext)) {
            hotspot.title = t.slice(0, -ext.length).slice(0, 100);
            break;
          }
        }
        if (hotspot.title === t) {
          hotspot.title = t.slice(0, 100);
        }
      }
    } catch { /* ignore */ }
  }

  /**
   * Получает настройки по умолчанию (fallback если основная функция недоступна)
   */
  getDefaultSettings() {
    if (window.viewerManager && typeof window.viewerManager.getDefaultSettings === 'function') {
      return window.viewerManager.getDefaultSettings();
    }

    // Fallback настройки
    return {
      hotspotColor: '#ff0000',
      infopointColor: '#0066cc',
      hotspotSize: 0.3,
      infopointSize: 0.25
    };
  }

  /**
   * Получает хотспот с восстановленными полными данными
   */
  getHotspotWithFullData(hotspotId) {
    const hotspot = this.findHotspotById(hotspotId);
    if (!hotspot) return null;

    // Создаем копию хотспота для безопасности
    const fullHotspot = { ...hotspot };

    // СНАЧАЛА пробуем восстановить из реестра
    if (!fullHotspot.videoUrl) {
      const regUrl = this.getVideoUrlFromRegistry(hotspotId);
      if (regUrl) {
        fullHotspot.videoUrl = regUrl;
        fullHotspot.hasVideo = true;
        const parts = String(regUrl).split('/');
        fullHotspot.videoFileName = parts[parts.length - 1] || undefined;
        if (fullHotspot._needsVideoRestore) delete fullHotspot._needsVideoRestore;
        console.log(`✅ videoUrl восстановлен из реестра для ${hotspotId}`);
        return fullHotspot;
      }
    }

    // ИСПРАВЛЕНИЕ: Восстанавливаем videoUrl из _originalData при наличии флага
    if (fullHotspot._needsVideoRestore && !fullHotspot.videoUrl) {
      console.log(`🔄 Восстановление videoUrl для хотспота ${hotspotId}`);

      // Пытаемся найти оригинальные данные в памяти
      const savedHotspots = JSON.parse(localStorage.getItem('color_tour_hotspots') || '[]');
      const originalHotspot = savedHotspots.find(h => h.id === hotspotId);

      if (originalHotspot && originalHotspot._originalData) {
        // Восстанавливаем videoUrl из оригинальных данных
        if (originalHotspot._originalData.videoUrl) {
          fullHotspot.videoUrl = originalHotspot._originalData.videoUrl;
          console.log(`✅ videoUrl восстановлен из _originalData для ${hotspotId}`);
          // Сохраняем в реестр на будущее
          this.registerVideoUrl(hotspotId, fullHotspot.videoUrl);
        }
        // Если нет videoUrl, но есть videoData — формируем data URL
        else if (originalHotspot._originalData.videoData) {
          const raw = originalHotspot._originalData.videoData;
          const dataUrl = raw.startsWith('data:video') ? raw : `data:video/mp4;base64,${raw}`;
          fullHotspot.videoUrl = dataUrl;
          fullHotspot.hasVideo = true;
          console.log(`✅ videoUrl реконструирован из videoData для ${hotspotId}`);
          this.registerVideoUrl(hotspotId, fullHotspot.videoUrl);
        }

        // Восстанавливаем другие исключенные поля
        if (originalHotspot._originalData.videoData && !fullHotspot.videoData) {
          fullHotspot.videoData = originalHotspot._originalData.videoData;
          console.log(`✅ videoData восстановлен из _originalData для ${hotspotId}`);
        }

        // Восстанавливаем данные пользовательской иконки
        if (originalHotspot._originalData.customIconData && !fullHotspot.customIconData) {
          fullHotspot.customIconData = originalHotspot._originalData.customIconData;
          console.log(`✅ customIconData восстановлен из _originalData для ${hotspotId}`);
        }
      } else {
        // Если нет оригинальных данных, логируем предупреждение
        console.warn(`⚠️ Не удалось найти _originalData для восстановления ${hotspotId}`);

        if (typeof fullHotspot._needsVideoRestore === 'string') {
          const fileName = fullHotspot._needsVideoRestore;
          console.log(`📁 Ожидаемый файл: ${fileName} - требуется ручное восстановление`);
        }
      }

      // Удаляем флаг восстановления
      delete fullHotspot._needsVideoRestore;
    }

    return fullHotspot;
  }

  /**
   * Автоматически восстанавливает видео без пользовательских подсказок
   */
  promptForVideoRestore(hotspot, expectedFileName) {
    console.log(`🔄 Автоматическое восстановление видео для ${hotspot.id}`);
    console.log(`📁 Ожидаемый файл: ${expectedFileName}`);

    // Автоматически открываем редактор без подтверждения пользователя
    this.editHotspot(hotspot.id);
  }

  /**
   * Очищает все хотспоты
   */
  clearAll() {
    this.hotspots = [];
    localStorage.removeItem('color_tour_hotspots');
    if (this.viewerManager) {
      this.viewerManager.clearMarkers();
    }
    console.log('Все хотспоты очищены');
  }

  // ===== IndexedDB поддержка больших видео =====
  _openVideoDB() {
    if (this._videoDBPromise) return this._videoDBPromise;
    if (!this._videoSavedOnce) this._videoSavedOnce = new Set();
    this._videoDBPromise = new Promise((resolve, reject) => {
      if (!('indexedDB' in window)) return reject(new Error('IndexedDB not supported'));
      const req = indexedDB.open('color_tour_videos', 1);
      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains('videos')) db.createObjectStore('videos', { keyPath: 'id' });
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error || new Error('open error'));
    });
    return this._videoDBPromise;
  }

  async _saveLargeVideoToIndexedDB(hotspotId, dataUrl) {
    try {
      // Защита от многократного сохранения одного и того же видео за сессию
      if (!this._videoSavedOnce) this._videoSavedOnce = new Set();
      if (this._videoSavedOnce.has(hotspotId)) return;
      this._videoSavedOnce.add(hotspotId);
      const db = await this._openVideoDB();
      const tx = db.transaction('videos', 'readwrite');
      tx.objectStore('videos').put({ id: hotspotId, data: dataUrl });
      tx.oncomplete = () => console.log('💾 Видео сохранено в IndexedDB для', hotspotId);
      tx.onerror = () => console.warn('⚠️ Ошибка сохранения видео в IndexedDB:', tx.error);
    } catch (e) {
      console.warn('⚠️ IndexedDB save fail:', e);
    }
  }

  async _restoreVideosFromIndexedDB() {
    const pending = (this.hotspots || []).filter(h => h.hasVideo && !h.videoUrl);
    if (!pending.length) return;
    let db; try { db = await this._openVideoDB(); } catch { return; }
    const tx = db.transaction('videos', 'readonly');
    const store = tx.objectStore('videos');
    await Promise.all(pending.map(h => new Promise(res => {
      const rq = store.get(h.id);
      rq.onsuccess = () => {
        const r = rq.result;
        if (r && r.data) {
          h.videoUrl = r.data;
          h.hasVideo = true;
          if (h._needsVideoRestore) delete h._needsVideoRestore;
          console.log('✅ videoUrl восстановлен из IndexedDB для', h.id);
          // Регистрируем и обновляем визуализацию
          this.registerVideoUrl && this.registerVideoUrl(h.id, h.videoUrl);
          if (this.viewerManager) {
            if (typeof this.viewerManager.createMissingVideoElement === 'function') {
              try { this.viewerManager.createMissingVideoElement(h); } catch { }
            }
          }
        } else {
          console.warn('⚠️ Нет записи в IndexedDB для', h.id);
        }
        res();
      };
      rq.onerror = () => { console.warn('⚠️ Ошибка чтения IndexedDB для', h.id); res(); };
    })));
  }

  /**
   * Диагностика размера localStorage (вызывать в консоли браузера)
   */
  static checkStorageSize() {
    let total = 0;
    const results = {};

    for (let key in localStorage) {
      if (localStorage.hasOwnProperty(key)) {
        const size = localStorage[key].length;
        total += size;
        results[key] = `${(size / 1024).toFixed(2)} KB`;
      }
    }

    console.log('📊 Анализ localStorage:');
    console.log(`📏 Общий размер: ${(total / 1024).toFixed(2)} KB`);
    console.log('📋 По ключам:', results);

    // Примерная оценка лимита (обычно 5-10 MB)
    const estimatedLimit = 5 * 1024 * 1024; // 5 MB в байтах
    const usage = (total / estimatedLimit * 100).toFixed(2);
    console.log(`⚡ Использовано примерно: ${usage}% от лимита`);

    return { total, results, usage };
  }
}

// Добавляем глобальную функцию для быстрой диагностики
window.checkStorageSize = HotspotManager.checkStorageSize;
