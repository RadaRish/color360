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
    try {
      // ЗАЩИТА: блокируем только автоматически созданные проблематичные сцены без src
      if (scene.name && scene.name.match(/^\d+\.(JPG|jpg)$/) && !scene.src) {
        console.warn('🚫 Блокируем добавление проблематичной автоматической сцены:', scene.name);
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

      console.log('Сцена добавлена:', scene.name);
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
    console.log('🗑️ Попытка удалить сцену:', sceneId);

    const index = this.scenes.findIndex(s => s.id === sceneId);
    if (index === -1) {
      console.error('❌ Сцена не найдена для удаления:', sceneId);
      return Promise.resolve(false);
    }

    const scene = this.scenes[index];
    console.log('🗑️ Найдена сцена для удаления:', scene.name);

    // Проверяем, можно ли удалить сцену (должна остаться хотя бы одна)
    if (this.scenes.length <= 1) {
      console.error('❌ Нельзя удалить последнюю сцену');
      alert('Нельзя удалить последнюю сцену. В туре должна остаться хотя бы одна сцена.');
      return Promise.resolve(false);
    }

    // Удаляем все хотспоты связанные с этой сценой
    if (window.hotspotManager) {
      const hotspotsToDelete = window.hotspotManager.getHotspotsForScene(sceneId);
      console.log('🗑️ Удаляем', hotspotsToDelete.length, 'хотспотов для сцены:', scene.name);
      hotspotsToDelete.forEach(hotspot => {
        window.hotspotManager.deleteHotspot(hotspot.id);
      });
    }

    // Если удаляем текущую сцену, переключаемся на другую
    if (this.currentScene && this.currentScene.id === sceneId) {
      const remainingScenes = this.scenes.filter(s => s.id !== sceneId);
      if (remainingScenes.length > 0) {
        console.log('🔄 Переключаемся на другую сцену перед удалением');
        this.switchToScene(remainingScenes[0].id);
      } else {
        this.currentScene = null;
        this.viewerManager.clearMarkers();
      }
    }

    // Удаляем сцену из массива
    this.scenes.splice(index, 1);
    console.log('✅ Сцена успешно удалена:', scene.name);
    console.log('📊 Осталось сцен:', this.scenes.length);

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
      console.log(`📝 Сцена переименована: ${sceneId} -> "${newName}"`);
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
    console.log('🔄 switchToScene вызван для сцены:', sceneId);
    console.trace('📍 Стек вызовов switchToScene');

    // ЗАЩИТА от повторных вызовов в течение короткого времени
    const now = Date.now();
    if (this._lastSwitchTime && this._lastSwitchTarget === sceneId && (now - this._lastSwitchTime) < 200) { // Уменьшаем время защиты до 200ms
      console.log('🛡️ Дублированный вызов switchToScene заблокирован - последний вызов', (now - this._lastSwitchTime), 'ms назад');
      return true;
    }
    this._lastSwitchTime = now;
    this._lastSwitchTarget = sceneId;

    const scene = this.getSceneById(sceneId);
    if (!scene) {
      console.error('Сцена не найдена:', sceneId);
      return false;
    }

    if (scene === this.currentScene) {
      console.log('ℹ️ Уже на этой сцене:', sceneId);
      return true; // Уже на этой сцене
    }

    try {
      // Очищаем маркеры текущей сцены
      this.viewerManager.clearMarkers();

      // Загружаем новую панораму
      const success = await this.viewerManager.setPanorama(scene.src);
      if (!success) {
        console.error('Не удалось загрузить панораму для сцены:', scene.name);
        return false;
      }

      this.currentScene = scene;

      // ВАЖНО: сбрасываем флаги защиты от повторных переходов после успешного переключения
      setTimeout(() => {
        this._lastSwitchTime = null;
        this._lastSwitchTarget = null;
        console.log('🔓 Защита от повторных переходов сброшена');
      }, 1000); // Сбрасываем через 1 секунду

      // Восстанавливаем маркеры новой сцены
      if (this.hotspotManager) {
        const sceneHotspots = this.hotspotManager.getHotspotsForScene(sceneId);
        console.log('🔄 Восстанавливаем маркеры для сцены:', sceneId, 'найдено маркеров:', sceneHotspots.length);
        console.log('🔍 Маркеры для восстановления:', sceneHotspots.map(h => ({ id: h.id, title: h.title, sceneId: h.sceneId, color: h.color, type: h.type, icon: h.icon })));

        sceneHotspots.forEach(hotspot => {
          console.log('🎯 Восстанавливаем маркер:', hotspot.id, 'для сцены:', hotspot.sceneId, 'с цветом:', hotspot.color, 'тип:', hotspot.type, 'иконка:', hotspot.icon);

          // ВАЖНО: перед созданием маркера восстанавливаем все его данные
          this.hotspotManager.restoreHotspotData(hotspot);

          // Дополнительно пытаемся получить полные данные (videoUrl из реестра и т.п.)
          if (window.hotspotManager && typeof window.hotspotManager.getHotspotWithFullData === 'function') {
            const full = window.hotspotManager.getHotspotWithFullData(hotspot.id);
            if (full) Object.assign(hotspot, full);
          }

          // ИСПРАВЛЕНИЕ: Для видео-областей проверяем и пересоздаем видео-элементы
          if (hotspot.type === 'video-area' && hotspot.videoUrl) {
            console.log('🎬 Обнаружена видео-область, проверяем видео-элемент:', hotspot.id);

            const videoId = `video-${hotspot.id}`;
            let videoEl = document.getElementById(videoId);

            if (!videoEl) {
              console.log('🔧 Видео-элемент отсутствует, создаем заново для:', hotspot.id);
              this.viewerManager.createMissingVideoElement(hotspot);
            } else if (videoEl.src !== hotspot.videoUrl) {
              console.log('🔄 Обновляем src видео-элемента для:', hotspot.id, 'новый URL:', hotspot.videoUrl);
              videoEl.src = hotspot.videoUrl;
              videoEl.load();
            } else {
              console.log('✅ Видео-элемент корректен для:', hotspot.id);
            }
          }

          this.viewerManager.createVisualMarker(hotspot);
        });

        console.log('✅ Восстановлено', sceneHotspots.length, 'маркеров для сцены:', sceneId);
        // После восстановления маркеров пробуем еще раз подтянуть большие видео из IndexedDB
        try {
          if (window.hotspotManager && typeof window.hotspotManager._restoreVideosFromIndexedDB === 'function') {
            const needRestore = sceneHotspots.some(h => h.type === 'video-area' && h.hasVideo && !h.videoUrl);
            if (needRestore) {
              console.log('🔄 post-switchToScene: обнаружены видео без URL — запускаем восстановление из IndexedDB');
              setTimeout(() => {
                try { window.hotspotManager._restoreVideosFromIndexedDB(); } catch (e) { console.warn('⚠️ Ошибка post-switch восстановления видео:', e); }
              }, 120);
            }
          }
        } catch (e) {
          console.warn('⚠️ post-switch восстановление видео не удалось инициировать:', e);
        }
      } else {
        console.warn('⚠️ hotspotManager не инициализирован - маркеры не восстановлены');
      }

      // Устанавливаем вид камеры для сцены, если он сохранен
      if (scene.cameraPosition) {
        console.log('📹 Восстанавливаем позицию камеры для сцены:', sceneId, scene.cameraPosition);
        const applyCam = () => this.viewerManager.setCameraPosition(scene.cameraPosition);
        // Первичная попытка
        applyCam();
        // Повторяем после кадра рендера
        requestAnimationFrame(() => {
          applyCam();
          // И ещё одна попытка после короткой задержки для полной инициализации
          setTimeout(() => {
            applyCam();
            const got = this.viewerManager.getCameraPosition();
            if (got) {
              const near = (a, b) => Math.abs((a || 0) - (b || 0)) < 0.01;
              if (!near(got.position.x, scene.cameraPosition.position.x) || !near(got.position.y, scene.cameraPosition.position.y) || !near(got.position.z, scene.cameraPosition.position.z)) {
                console.warn('⚠️ Позиция камеры после применения отличается от сохраненной', { want: scene.cameraPosition, got });
              }
            }
          }, 50);
        });
      }

      console.log('Переключились на сцену:', scene.name);
      return true;
    } catch (error) {
      console.error('Ошибка при переключении сцены:', error);
      // Сбрасываем защиту и при ошибке
      this._lastSwitchTime = null;
      this._lastSwitchTarget = null;
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
      console.log(`🔀 Порядок сцен изменен: ${fromIndex} -> ${toIndex}`);
      return true;
    }
    console.warn('⚠️ Не удалось изменить порядок сцен', { fromIndex, toIndex });
    return false;
  }

  /**
   * Очищает сохраненную позицию камеры для указанной сцены
   */
  clearCameraForScene(sceneId) {
    console.log('🗑️ clearCameraForScene вызван для сцены:', sceneId);

    const scene = this.getSceneById(sceneId);
    if (!scene) {
      console.error('❌ Сцена не найдена для очистки камеры:', sceneId);
      return false;
    }

    if (scene.cameraPosition) {
      delete scene.cameraPosition;
      console.log('✅ Позиция камеры очищена для сцены:', sceneId, scene.name);
      return true;
    } else {
      console.log('ℹ️ У сцены', sceneId, 'не было сохраненной позиции камеры');
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