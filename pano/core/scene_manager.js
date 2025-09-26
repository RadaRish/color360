// Управление сценами с поддержкой A-Frame
export default class SceneManager {
  constructor(viewerManager) {
    this.viewerManager = viewerManager;
    this.scenes = [];
    this.currentScene = null;
    this.hotspotManager = null; // Будет установлено позже
  }

  setHotspotManager(hotspotManager) {
    this.hotspotManager = hotspotManager;
  }

  async addScene(scene) {
    console.log('🎬 SceneManager.addScene() вызвана:', scene.name, scene.src ? 'с src' : 'без src');
    
    try {
      // ЗАЩИТА: блокируем только автоматически созданные проблематичные сцены без src
      if (scene.name && scene.name.match(/^\d+\.(JPG|jpg)$/) && !scene.src) {
        console.log('🚫 Блокируем проблематичную сцену без src');
        return false;
      }

      // Проверяем, что у сцены есть все необходимые поля  
      if (!scene.id) {
        scene.id = 'scene_' + Date.now() + '_' + Math.floor(Math.random() * 1000);
      }
      if (!scene.hotspots) {
        scene.hotspots = [];
      }

      this.scenes.push(scene);

      // Если это первая сцена, устанавливаем её как текущую
      if (!this.currentScene) {
        await this.switchToScene(scene.id);
      }

      return true;
    } catch (error) {
      console.error('Ошибка при добавлении сцены:', error);
      // Удаляем сцену из массива если загрузка не удалась
      const index = this.scenes.indexOf(scene);
      if (index !== -1) {
        this.scenes.splice(index, 1);
      }
      return false;
    }
  }

  removeScene(sceneId) {

    const index = this.scenes.findIndex(s => s.id === sceneId);
    if (index === -1) {
      console.error('❌ Сцена не найдена для удаления:', sceneId);
      return Promise.resolve(false);
    }

    const scene = this.scenes[index];

    // Проверяем, можно ли удалить сцену (должна остаться хотя бы одна)
    if (this.scenes.length <= 1) {
      console.error('❌ Нельзя удалить последнюю сцену');
      alert('Нельзя удалить последнюю сцену. В туре должна остаться хотя бы одна сцена.');
      return Promise.resolve(false);
    }

    // Удаляем все хотспоты связанные с этой сценой
    if (window.hotspotManager) {
      const hotspotsToDelete = window.hotspotManager.getHotspotsForScene(sceneId);

      hotspotsToDelete.forEach(hotspot => {
        window.hotspotManager.deleteHotspot(hotspot.id);
      });
    }

    // Если удаляем текущую сцену, переключаемся на другую
    if (this.currentScene && this.currentScene.id === sceneId) {
      const remainingScenes = this.scenes.filter(s => s.id !== sceneId);
      if (remainingScenes.length > 0) {

        this.switchToScene(remainingScenes[0].id);
      } else {
        this.currentScene = null;
        this.viewerManager.clearMarkers();
      }
    }

    // Удаляем сцену из массива
    this.scenes.splice(index, 1);

    return Promise.resolve(true);
  }

  getSceneById(sceneId) {
    return this.scenes.find(s => s.id === sceneId);
  }

  getAllScenes() {
    return [...this.scenes];
  }

  /**
   * Переименовывает сцену
   */
  renameScene(sceneId, newName) {
    const scene = this.getSceneById(sceneId);
    if (scene) {
      scene.name = newName;

      return true;
    }
    console.error(`❌ Сцена с ID ${sceneId} не найдена для переименования`);
    return false;
  }

  getCurrentScene() {
    return this.currentScene;
  }

  clearScenes() {
    this.scenes = [];
    this.currentScene = null;
    this.viewerManager.clearMarkers();
  }

  async switchToScene(sceneId) {
    // ЗАЩИТА от повторных вызовов в течение короткого времени
    const now = Date.now();
    if (this._lastSwitchTime && this._lastSwitchTarget === sceneId && (now - this._lastSwitchTime) < 200) { // Уменьшаем время защиты до 200ms

      // ИСПРАВЛЕНИЕ: Убедимся, что фон черный даже при блокировке
      if (this.viewerManager && this.viewerManager.aframeSky) {
        this.viewerManager.aframeSky.setAttribute('color', '#000000');
        this.viewerManager.aframeSky.setAttribute('opacity', '1');
      }
      return true;
    }
    this._lastSwitchTime = now;
    this._lastSwitchTarget = sceneId;

    const scene = this.getSceneById(sceneId);
    if (!scene) {
      console.error('Сцена не найдена:', sceneId);
      // ИСПРАВЛЕНИЕ: Устанавливаем черный фон при ошибке
      if (this.viewerManager && this.viewerManager.aframeSky) {
        this.viewerManager.aframeSky.setAttribute('color', '#000000');
        this.viewerManager.aframeSky.setAttribute('opacity', '1');
      }
      return false;
    }

    if (scene === this.currentScene) {

      return true; // Уже на этой сцене
    }

    try {
      // Очищаем маркеры текущей сцены
      this.viewerManager.clearMarkers();

      // Загружаем новую панораму
      console.log('🎬 SceneManager: загружаем панораму для сцены', scene.name, 'src:', scene.src ? scene.src.slice(0, 100) + '...' : 'null');
      const success = await this.viewerManager.setPanorama(scene.src);
      if (!success) {
        console.error('Не удалось загрузить панораму для сцены:', scene.name);
        // ИСПРАВЛЕНИЕ: Устанавливаем черный фон при ошибке загрузки
        if (this.viewerManager.aframeSky) {
          this.viewerManager.aframeSky.setAttribute('color', '#000000');
          this.viewerManager.aframeSky.setAttribute('opacity', '1');
        }
        return false;
      }

      this.currentScene = scene;

      // ВАЖНО: сбрасываем флаги защиты от повторных переходов после успешного переключения
      setTimeout(() => {
        this._lastSwitchTime = null;
        this._lastSwitchTarget = null;

      }, 1000); // Сбрасываем через 1 секунду

      // Восстанавливаем маркеры новой сцены
      if (this.hotspotManager) {
        const sceneHotspots = this.hotspotManager.getHotspotsForScene(sceneId);

        sceneHotspots.forEach(hotspot => {

          // ВАЖНО: перед созданием маркера восстанавливаем все его данные
          this.hotspotManager.restoreHotspotData(hotspot);

          // Дополнительно пытаемся получить полные данные (videoUrl из реестра и т.п.)
          if (window.hotspotManager && typeof window.hotspotManager.getHotspotWithFullData === 'function') {
            const full = window.hotspotManager.getHotspotWithFullData(hotspot.id);
            if (full) Object.assign(hotspot, full);
          }

          // ИСПРАВЛЕНИЕ: Для видео-областей проверяем и пересоздаем видео-элементы
          if (hotspot.type === 'video-area' && hotspot.videoUrl) {

            const videoId = `video-${hotspot.id}`;
            let videoEl = document.getElementById(videoId);

            if (!videoEl) {

              this.viewerManager.createMissingVideoElement(hotspot);
            } else if (videoEl.src !== hotspot.videoUrl) {

              videoEl.src = hotspot.videoUrl;
              videoEl.load();
            } else {

            }
          }

          this.viewerManager.createVisualMarker(hotspot);
        });

        // После восстановления маркеров пробуем еще раз подтянуть большие видео из IndexedDB
        try {
          if (window.hotspotManager && typeof window.hotspotManager._restoreVideosFromIndexedDB === 'function') {
            const needRestore = sceneHotspots.some(h => h.type === 'video-area' && h.hasVideo && !h.videoUrl);
            if (needRestore) {

              setTimeout(() => {
                try { window.hotspotManager._restoreVideosFromIndexedDB(); } catch (e) { console.warn('⚠️ Ошибка post-switch восстановления видео:', e); }
              }, 120);
            }
          }
        } catch (e) {

        }
      } else {

      }

      // Устанавливаем вид камеры для сцены, если он сохранен
      if (scene.cameraPosition) {

        // 🎯 ИСПРАВЛЕНИЕ: Стабильное управление камерой без резких скачков
        const applyCameraPosition = async () => {
          try {
            const camera = this.viewerManager.aframeCamera;
            if (!camera) return;
            
            const lookControls = camera.components && camera.components['look-controls'];
            console.log('🎯 SceneManager: устанавливаем дефолтный вид камеры для сцены', scene.name);
            
            // 🔧 КРИТИЧЕСКИ ВАЖНО: отключаем look-controls на ДОЛЬШЕ для предотвращения конфликтов
            if (lookControls && lookControls.pause) {
              lookControls.pause();
              console.log('🎯 SceneManager: look-controls отключены для установки дефолтного вида');
            }
            
            // Устанавливаем позицию за один раз без повторных попыток
            const applied = this.viewerManager.setCameraPosition(scene.cameraPosition);
            
            if (applied) {
              console.log('🎯 SceneManager: дефолтная позиция камеры установлена:', scene.cameraPosition);
              
              // 🔧 УВЕЛИЧИВАЕМ задержку до 2 секунд для полной стабилизации
              setTimeout(() => {
                if (lookControls && lookControls.play) {
                  lookControls.play();
                  console.log('🎯 SceneManager: look-controls включены после 2сек стабилизации');
                }
              }, 2000); // Увеличили до 2 секунд для предотвращения возврата к предыдущей позиции
            }
          } catch (error) {
            console.error('🎯 SceneManager: ошибка установки позиции камеры:', error);
          }
        };

        // Применяем позицию камеры сразу после загрузки панорамы
        setTimeout(() => {
          applyCameraPosition();
        }, 300); // Ждем полной загрузки панорамы
      }

      return true;
    } catch (error) {
      console.error('Ошибка при переключении сцены:', error);
      // Сбрасываем защиту и при ошибке
      this._lastSwitchTime = null;
      this._lastSwitchTarget = null;
      
      // ИСПРАВЛЕНИЕ: Устанавливаем черный фон при ошибке
      if (this.viewerManager && this.viewerManager.aframeSky) {
        this.viewerManager.aframeSky.setAttribute('color', '#000000');
        this.viewerManager.aframeSky.setAttribute('opacity', '1');
      }
      
      return false;
    }
  }

  // Методы для совместимости с UI
  switchScene(sceneId) {
    return this.switchToScene(sceneId);
  }

  updateScene(sceneId, updates) {
    const scene = this.getSceneById(sceneId);
    if (scene) {
      Object.assign(scene, updates);
      return true;
    }
    return false;
  }

  // Вспомогательные методы
  getSceneIndex(sceneId) {
    return this.scenes.findIndex(s => s.id === sceneId);
  }

  moveScene(fromIndex, toIndex) {
    if (fromIndex >= 0 && fromIndex < this.scenes.length &&
      toIndex >= 0 && toIndex < this.scenes.length) {
      const [movedScene] = this.scenes.splice(fromIndex, 1);
      this.scenes.splice(toIndex, 0, movedScene);
      return true;
    }
    return false;
  }

  /**
   * Переупорядочивает сцены по индексам (для DnD из UI)
   */
  reorderScenes(fromIndex, toIndex) {
    const ok = this.moveScene(fromIndex, toIndex);
    if (ok) {

      return true;
    }

    return false;
  }

  /**
   * Очищает сохраненную позицию камеры для указанной сцены
   */
  clearCameraForScene(sceneId) {

    const scene = this.getSceneById(sceneId);
    if (!scene) {
      console.error('❌ Сцена не найдена для очистки камеры:', sceneId);
      return false;
    }

    if (scene.cameraPosition) {
      delete scene.cameraPosition;

      return true;
    } else {

      return false;
    }
  }

  // Экспорт данных для сохранения
  exportScenes() {
    return this.scenes.map(scene => ({
      id: scene.id,
      name: scene.name,
      src: scene.src
    }));
  }

  // Импорт данных при загрузке проекта
  async importScenes(scenesData) {
    this.clearScenes();

    for (const sceneData of scenesData) {
      await this.addScene({
        id: sceneData.id,
        name: sceneData.name,
        src: sceneData.src,
        hotspots: []
      });
    }

    // Переключаемся на первую сцену если есть
    if (this.scenes.length > 0) {
      await this.switchToScene(this.scenes[0].id);
    }
  }
}