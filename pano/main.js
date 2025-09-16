import ExportManager from './core/export_manager.js';
import HotspotManager from './core/hotspot_manager.js';
import ProjectManager from './core/project_manager.js';
import SceneManager from './core/scene_manager.js';
import ViewerManager from './core/viewer_manager.js';
import HotspotEditor from './ui/hotspot-editor.js';
import SceneList from './ui/scene_list.js';
import RetouchManager from './ui/retouch_manager.js';

document.addEventListener('DOMContentLoaded', () => {
  const viewerContainer = document.getElementById('viewer-container');
  if (!viewerContainer) {
    console.error('viewer-container не найден в DOM!');
    return;
  }

  // Initialize floating user menu
  initializeFloatingUserMenu();

  setTimeout(() => {
    try {
      const hotspotManager = new HotspotManager(); // Создаем сначала hotspotManager
      const viewerManager = new ViewerManager('viewer-container', hotspotManager); // Передаем его в ViewerManager
      const sceneManager = new SceneManager(viewerManager);
      const projectManager = new ProjectManager(sceneManager, hotspotManager);
      const exportManager = new ExportManager(sceneManager, hotspotManager, projectManager);
      const hotspotEditor = new HotspotEditor('hotspot-editor-modal');

  // Экспорт-менеджеру нужен доступ к viewerManager, чтобы корректно сохранять yaw/pitch/FOV
  exportManager.viewerManager = viewerManager;

      // Загружаем и применяем сохраненные настройки
      const settings = viewerManager.getDefaultSettings();
      viewerManager.updateCameraSettings(settings);

      // Связываем менеджеры друг с другом
      hotspotManager.setViewerManager(viewerManager);
      sceneManager.setHotspotManager(hotspotManager);
      hotspotManager.setSceneManager(sceneManager);

      window.sceneManager = sceneManager;
      window.hotspotManager = hotspotManager;
      window.viewerManager = viewerManager;
      window.hotspotEditor = hotspotEditor;
      window.exportManager = exportManager;

      // Создаем глобальный объект app для удобного доступа
      window.app = {
        sceneManager,
        hotspotManager,
        viewerManager,
        hotspotEditor,
        exportManager,
        projectManager,
        // будет установлен позже
        retouchManager: null,
        // Функция для показа уведомлений
        showNotification: (message, type = 'info') => {
          const notification = document.createElement('div');
          notification.style.cssText = `
                        position: fixed;
                        top: 20px;
                        right: 80px; /* смещаем левее, чтобы не перекрывать аватар */
                        padding: 12px 20px;
                        background: ${type === 'success' ? '#4CAF50' : type === 'error' ? '#f44336' : type === 'warning' ? '#ff9800' : '#2196F3'};
                        color: white;
                        border-radius: 4px;
                        z-index: 10000;
                        font-family: system-ui, sans-serif;
                        font-size: 14px;
                        box-shadow: 0 2px 8px rgba(0,0,0,0.3);
                        max-width: 300px;
                    `;
          notification.textContent = message;
          document.body.appendChild(notification);

          setTimeout(() => {
            notification.remove();
          }, 3000);
        }
      };

  const sceneList = new SceneList(sceneManager, document.getElementById('scene-list'));
      sceneList.render();

  // Инициализация ретуши (маска на канвасе + undo)
  const retouchManager = new RetouchManager(viewerManager, sceneManager);
  window.app.retouchManager = retouchManager;

      // Глобальные функции для редактирования и удаления, вызываемые из A-Frame компонентов
      window.editMarker = async (hotspotId) => {
        const hotspot = hotspotManager.findHotspotById(hotspotId);
        if (!hotspot) return;

        const scenes = sceneManager.getAllScenes();
        const currentScene = sceneManager.getSceneById(hotspot.sceneId);

        try {
          // Скрываем маркер чтобы он не следовал за курсором
          try { window.viewerManager && window.viewerManager.hideMarker(hotspotId); } catch (_) {}

          const data = await hotspotEditor.showEditMode(hotspot);

          if (data) {
            hotspotManager.updateHotspot(hotspot.id, data);
          }
        } catch (error) {
          console.error('Ошибка при редактировании маркера:', error);
        } finally {
          // Восстанавливаем видимость маркера
          try { window.viewerManager && window.viewerManager.showMarker(hotspotId); } catch (_) {}
        }
      };

      window.deleteMarker = (hotspotId) => {
        if (confirm('Вы уверены, что хотите удалить эту точку?')) {
          hotspotManager.removeHotspotById(hotspotId);
        }
      };

      // Обработчик для создания хотспота из контекстного меню
      viewerManager.getViewer().container.addEventListener('context-menu-add-hotspot', async (e) => {
        const { type, position } = e.detail;
        const scenes = sceneManager.getAllScenes();
        const currentScene = sceneManager.getCurrentScene();

        if (!currentScene) {
          alert("Сначала добавьте или выберите сцену.");
          return;
        }

        const data = await hotspotEditor.show({
          type,
          scenes: scenes.filter(s => s.id !== currentScene.id)
        });

        if (data) {
          hotspotManager.addHotspot(currentScene, {
            ...data,
            type,
            position,
          });
        }
      });

      // --- Обработчики событий UI ---

      // Боковая панель с мобильной адаптацией
      const sidebar = document.getElementById('sidebar');
      const toggle = document.getElementById('sidebar-toggle');
      if (sidebar && toggle) {
        toggle.onclick = function () {
          if (window.innerWidth <= 768) {
            // Мобильное меню
            sidebar.classList.toggle('show');
            toggle.textContent = sidebar.classList.contains('show') ? '✕' : '☰';
          } else {
            // Десктопное меню
            sidebar.classList.toggle('hide');
            const isHidden = sidebar.classList.contains('hide');
            toggle.textContent = isHidden ? '⮜' : '⮜';

            // Прямое управление позицией кнопки
            if (isHidden) {
              toggle.style.left = '0px';
              toggle.style.background = 'rgba(100, 108, 255, 0.9)';
              toggle.style.borderColor = 'rgba(100, 108, 255, 0.5)';
            } else {
              toggle.style.left = '300px';
              toggle.style.background = 'rgba(26, 26, 26, 0.95)';
              toggle.style.borderColor = 'rgba(255, 255, 255, 0.2)';
            }
          }

          // Уведомляем A-Frame о изменении размера окна для корректного обновления
          setTimeout(() => {
            window.dispatchEvent(new Event('resize'));

            // Дополнительно обновляем A-Frame canvas если доступен
            if (viewerManager && viewerManager.aframeScene) {
              const canvas = viewerManager.aframeScene.canvas;
              if (canvas && canvas.renderer) {
                canvas.renderer.setSize(
                  canvas.parentElement.clientWidth,
                  canvas.parentElement.clientHeight
                );
              }
            }
          }, 300); // Задержка соответствует CSS transition
        };

        // Инициализация для мобильных устройств
        if (window.innerWidth <= 768) {
          sidebar.classList.remove('show');
          toggle.textContent = '☰';
        }

        // Обработка изменения размера экрана
        window.addEventListener('resize', () => {
          if (window.innerWidth > 768) {
            sidebar.classList.remove('show');
            toggle.textContent = sidebar.classList.contains('hide') ? '⮜' : '⮜';
          } else {
            sidebar.classList.remove('hide');
            toggle.textContent = sidebar.classList.contains('show') ? '✕' : '☰';
            toggle.style.left = '10px';
          }
        });

        // Закрытие мобильного меню при клике вне его
        document.addEventListener('click', (e) => {
          if (window.innerWidth <= 768 &&
            sidebar.classList.contains('show') &&
            !sidebar.contains(e.target) &&
            !toggle.contains(e.target)) {
            sidebar.classList.remove('show');
            toggle.textContent = '☰';
          }
        });
      }

      // Полноэкранный режим
      const fullscreenBtn = document.getElementById('fullscreen-btn');
      if (fullscreenBtn) {
        fullscreenBtn.onclick = () => {
          if (!document.fullscreenElement) {
            viewerContainer.requestFullscreen().catch(err => {
              alert(`Error attempting to enable full-screen mode: ${err.message} (${err.name})`);
            });
          } else {
            document.exitFullscreen();
          }
        };
      }

      // Кнопка настроек
      const settingsBtn = document.getElementById('settings-btn');
      if (settingsBtn) {
        settingsBtn.onclick = () => {
          showAppSettings();
        };
      }

  // Кнопка экспорта удалена из основной панели - экспорт доступен через плавающее меню пользователя

      // Кнопка ретуши (Удалить объект)
      const retouchBtn = document.getElementById('retouch-btn');
      const retouchUndoBtn = document.getElementById('retouch-undo-btn');
      if (retouchBtn) {
        retouchBtn.onclick = async () => {
          const currentScene = sceneManager.getCurrentScene();
          if (!currentScene) {
            alert('Нет активной сцены для ретуши');
            return;
          }
          try {
            await retouchManager.startMaskDraw(currentScene);
            // После завершения маски отправляем на /api/retouch
            const result = await retouchManager.applyRetouch(currentScene);
            if (result?.applied) {
              window.app?.showNotification?.('Ретушь применена', 'success');
              if (retouchUndoBtn) retouchUndoBtn.disabled = !retouchManager.canUndo(currentScene.id);
            } else {
              window.app?.showNotification?.('Ретушь отменена', 'info');
            }
          } catch (e) {
            console.error('Ошибка ретуши:', e);
            window.app?.showNotification?.('Ошибка ретуши: ' + (e?.message || e), 'error');
          }
        };
      }
      if (retouchUndoBtn) {
        retouchUndoBtn.onclick = async () => {
          const currentScene = sceneManager.getCurrentScene();
          if (!currentScene) return;
          try {
            const ok = await retouchManager.undo(currentScene);
            if (ok) {
              window.app?.showNotification?.('Отменено', 'info');
            }
          } finally {
            retouchUndoBtn.disabled = !retouchManager.canUndo(currentScene?.id);
          }
        };
      }

      // Кнопка установки вида камеры
      const setCameraViewBtn = document.getElementById('set-camera-view-btn');
      if (setCameraViewBtn) {
        setCameraViewBtn.onclick = () => {
          try {
            const currentScene = sceneManager.getCurrentScene();
            if (!currentScene) {
              alert('Нет активной сцены для сохранения вида камеры');
              return;
            }

            const success = viewerManager.saveCameraPositionForScene(currentScene.id);
            if (success) {
              const cleanName = (currentScene.name || '').replace(/\.[^.]+$/, '');
              window.app?.showNotification?.(`Вид камеры сохранен для сцены "${cleanName}"`, 'success');
            } else {
              window.app?.showNotification?.('Ошибка при сохранении вида камеры', 'error');
            }
          } catch (error) {
            console.error('Ошибка сохранения вида камеры:', error);
            alert('Ошибка при сохранении вида камеры: ' + error.message);
          }
        };
      }

      // Кнопка очистки вида камеры
      const clearCameraViewBtn = document.getElementById('clear-camera-view-btn');
      if (clearCameraViewBtn) {
        clearCameraViewBtn.onclick = () => {
          try {
            const currentScene = sceneManager.getCurrentScene();
            if (!currentScene) {
              alert('Нет активной сцены для очистки вида камеры');
              return;
            }

            const success = sceneManager.clearCameraForScene(currentScene.id);
            if (success) {
              const cleanName2 = (currentScene.name || '').replace(/\.[^.]+$/, '');
              window.app?.showNotification?.(`Вид камеры очищен для сцены "${cleanName2}"`, 'info');
            } else {
              window.app?.showNotification?.('У этой сцены не было сохраненного вида камеры', 'warning');
            }
          } catch (error) {
            console.error('Ошибка очистки вида камеры:', error);
            alert('Ошибка при очистке вида камеры: ' + error.message);
          }
        };
      }

      // Кнопки управления зумом
      const zoomInBtn = document.getElementById('zoom-in-btn');
      const zoomOutBtn = document.getElementById('zoom-out-btn');
      const zoomResetBtn = document.getElementById('zoom-reset-btn');

      if (zoomInBtn) {
        zoomInBtn.onclick = () => {
          if (viewerManager && viewerManager.zoomIn) viewerManager.zoomIn();
        };
      }
      if (zoomOutBtn) {
        zoomOutBtn.onclick = () => {
          if (viewerManager && viewerManager.zoomOut) viewerManager.zoomOut();
        };
      }
      if (zoomResetBtn) {
        zoomResetBtn.onclick = () => {
          if (viewerManager && viewerManager.resetZoom) viewerManager.resetZoom();
        };
      }

      // Кнопка сохранения проекта в основной панели
      const saveProjectBtn = document.getElementById('save-project');
      if (saveProjectBtn) {
        saveProjectBtn.onclick = () => {
          saveLocalProject();
        };
      }

      // Кнопка экспорта в основной панели
      const exportBtn = document.getElementById('export-btn');
      if (exportBtn) {
        exportBtn.onclick = () => {
          exportTour();
        };
      }

      // Модальное окно загрузки
      const openUploadBtn = document.getElementById('open-upload');
      const dropZone = document.getElementById('drop-zone');
      const dropArea = document.getElementById('drop-area');
      const fileInput = document.getElementById('file-input');

      if (dropZone) {
        // Показываем окно загрузки при первой загрузке
        dropZone.style.cssText = `
          display: flex !important;
          position: fixed !important;
          top: 0 !important;
          left: 0 !important;
          width: 100% !important;
          height: 100% !important;
          background: rgba(0, 0, 0, 0.75) !important;
          z-index: 99999 !important;
          align-items: center !important;
          justify-content: center !important;
          opacity: 1 !important;
          pointer-events: auto !important;
          backdrop-filter: blur(8px) !important;
        `;
        dropZone.classList.add('show');
      }

      if (openUploadBtn && dropZone) {
        openUploadBtn.onclick = () => {
          // Принудительно устанавливаем все стили
          dropZone.style.cssText = `
            display: flex !important;
            position: fixed !important;
            top: 0 !important;
            left: 0 !important;
            width: 100% !important;
            height: 100% !important;
            background: rgba(0, 0, 0, 0.75) !important;
            z-index: 99999 !important;
            align-items: center !important;
            justify-content: center !important;
            opacity: 1 !important;
            pointer-events: auto !important;
            backdrop-filter: blur(8px) !important;
          `;

          dropZone.classList.add('show');
        };
        dropZone.addEventListener('click', (e) => {
          if (e.target.id === 'drop-zone') {
            dropZone.classList.remove('show');
            dropZone.style.cssText = 'display: none !important;';
          }
        });
      }

      // Обработка drag & drop
      if (dropArea) {
        ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
          dropArea.addEventListener(eventName, (e) => {
            e.preventDefault();
            e.stopPropagation();
          });
        });

        ['dragenter', 'dragover'].forEach(eventName => {
          dropArea.addEventListener(eventName, () => {
            dropArea.classList.add('drag-over');
          });
        });

        ['dragleave', 'drop'].forEach(eventName => {
          dropArea.addEventListener(eventName, () => {
            dropArea.classList.remove('drag-over');
          });
        });

        dropArea.addEventListener('drop', async (e) => {
          const files = [...e.dataTransfer.files];
          if (files.length === 0) return;

          // Мгновенно скрываем окно загрузки
          if (dropZone) {
            dropZone.classList.remove('show');
            dropZone.style.cssText = 'display: none !important;';
          }

          // Показываем индикатор загрузки
          if (viewerManager) {
            viewerManager.showGlobalLoading(`Перенос ${files.length} панорам...`);
          }

          try {
            let loadedCount = 0;

            for (const file of files) {
              if (!file.type.startsWith('image/')) continue;

              loadedCount++;
              if (viewerManager) {
                viewerManager.showGlobalLoading(`Обработка панорамы ${loadedCount}/${files.length}: ${file.name}`);
              }

              const src = await new Promise(resolve => {
                const reader = new FileReader();
                reader.onload = ev => resolve(ev.target.result);
                reader.readAsDataURL(file);
              });
              await sceneManager.addScene({ name: file.name, src });
            }

            if (viewerManager) {
              viewerManager.hideGlobalLoading();
            }

            sceneList.render();
          } catch (error) {
            console.error('Ошибка при загрузке панорам:', error);
            if (viewerManager) {
              viewerManager.hideGlobalLoading();
            }
            alert('Ошибка при загрузке одной или нескольких панорам');
          }
        });
      }

  // Сохранение проекта: кнопка сохранения удалена из левой панели. Используйте плавающее меню пользователя.

      // Загрузка проекта
      const loadProjectBtn = document.getElementById('load-project-btn');
      const loadFileInput = document.getElementById('load-file');

      if (loadProjectBtn && loadFileInput) {
        loadProjectBtn.onclick = () => loadFileInput.click();

        loadFileInput.addEventListener('change', async (e) => {
          const file = e.target.files[0];
          if (file) {
            // ИСПРАВЛЕНИЕ: Мгновенно скрываем окно загрузки
            if (dropZone) {
              dropZone.classList.remove('show');
              dropZone.style.cssText = 'display: none !important;';
            }

            // Показываем индикатор загрузки
            if (viewerManager) {
              viewerManager.showGlobalLoading('Загрузка проекта...');
            }

            try {
              const content = await file.text();
              const success = await projectManager.loadProject(content);

              if (viewerManager) {
                viewerManager.hideGlobalLoading();
              }

              if (success) {
                sceneList.render();
                // project loaded
              } else {
                alert('Не удалось загрузить проект. Проверьте консоль для деталей.');
              }
            } catch (error) {
              console.error('Ошибка при загрузке проекта:', error);
              if (viewerManager) {
                viewerManager.hideGlobalLoading();
              }
              alert('Ошибка при чтении файла проекта');
            }
            e.target.value = '';
          }
        });
      }

      // Загрузка панорамных изображений
      if (fileInput) {
        fileInput.addEventListener('change', async (e) => {
          const files = [...e.target.files];
          if (files.length === 0) return;

          // ИСПРАВЛЕНИЕ: Мгновенно скрываем окно загрузки и показываем прогресс
          if (dropZone) {
            dropZone.classList.remove('show');
            dropZone.style.cssText = 'display: none !important;';
          }

          // Показываем индикатор загрузки сразу
          if (viewerManager) {
            viewerManager.showGlobalLoading(`Загрузка ${files.length} панорам...`);
          }

          try {
            let loadedCount = 0;

            for (const file of files) {
              if (!file.type.startsWith('image/')) continue;

              // Обновляем прогресс для каждого файла
              loadedCount++;
              if (viewerManager) {
                viewerManager.showGlobalLoading(`Обработка панорамы ${loadedCount}/${files.length}: ${file.name}`);
              }

              const src = await new Promise(resolve => {
                const reader = new FileReader();
                reader.onload = ev => resolve(ev.target.result);
                reader.readAsDataURL(file);
              });
              await sceneManager.addScene({ name: file.name, src });
            }

            // Завершаем индикацию загрузки
            if (viewerManager) {
              viewerManager.hideGlobalLoading();
            }

            sceneList.render();
          } catch (error) {
            if (viewerManager) {
              viewerManager.hideGlobalLoading();
            }
            alert('Ошибка при загрузке одной или нескольких панорам');
          }

          e.target.value = '';
        });
      }

      // app initialized

      // Функция настроек приложения
      window.showAppSettings = () => {
        const settingsModal = document.createElement('div');
        settingsModal.className = 'modal';
        settingsModal.style.display = 'flex';

        settingsModal.innerHTML = `
                    <div class="modal-content">
                        <span class="close-btn settings-close">&times;</span>
                        
                        <div class="settings-container">
                            <div class="settings-group">
                                <h4>Управление камерой</h4>
                                <label>
                                    <input type="range" id="mouse-sensitivity" min="0.1" max="2" step="0.1" value="1">
                                    Чувствительность мыши: <span id="sensitivity-value">1</span>
                                </label>
                                <label>
                                    <input type="range" id="zoom-speed" min="1" max="10" step="1" value="5">
                                    Скорость зума (кнопки +/- и колесико мыши): <span id="zoom-speed-value">5</span>
                                </label>
                  <label style="display:flex;align-items:center;gap:8px;margin-top:6px;">
                    <input type="checkbox" id="gyro-enabled">
                    Включить гироскоп (на мобильных устройствах)
                  </label>
                            </div>
                            
                            <div class="settings-divider"></div>
                            
                            <div class="settings-group">
                                <h4>Хотспоты по умолчанию</h4>
                                <label>
                                    <input type="color" id="default-hotspot-color" value="#00ff00">
                                    Цвет хотспотов
                                </label>
                                <label>
                                    <input type="range" id="default-hotspot-size" min="0.1" max="1" step="0.1" value="0.6">
                                    Размер хотспотов: <span id="hotspot-size-value">0.6</span>
                                </label>
                            </div>
                            
                            <div class="settings-divider"></div>
                            
                            <div class="settings-group">
                                <h4>Инфоточки по умолчанию</h4>
                                <label>
                                    <input type="color" id="default-infopoint-color" value="#ffcc00">
                                    Цвет инфоточек
                                </label>
                                <label>
                                    <input type="range" id="default-infopoint-size" min="0.1" max="1" step="0.1" value="0.5">
                                    Размер инфоточек: <span id="infopoint-size-value">0.5</span>
                                </label>
                            </div>
                        </div>
                        
                        <button onclick="applySettings()" class="btn-primary">Применить настройки</button>
                    </div>
                `;

        document.body.appendChild(settingsModal);

        // Обработчики для слайдеров
        const sensitivitySlider = settingsModal.querySelector('#mouse-sensitivity');
        const sensitivityValue = settingsModal.querySelector('#sensitivity-value');
        sensitivitySlider.addEventListener('input', (e) => {
          sensitivityValue.textContent = e.target.value;
        });

        const zoomSpeedSlider = settingsModal.querySelector('#zoom-speed');
        const zoomSpeedValue = settingsModal.querySelector('#zoom-speed-value');
        zoomSpeedSlider.addEventListener('input', (e) => {
          zoomSpeedValue.textContent = e.target.value;
        });

        const hotspotSizeSlider = settingsModal.querySelector('#default-hotspot-size');
        const hotspotSizeValue = settingsModal.querySelector('#hotspot-size-value');
        hotspotSizeSlider.addEventListener('input', (e) => {
          hotspotSizeValue.textContent = e.target.value;
        });

        const infopointSizeSlider = settingsModal.querySelector('#default-infopoint-size');
        const infopointSizeValue = settingsModal.querySelector('#infopoint-size-value');
        infopointSizeSlider.addEventListener('input', (e) => {
          infopointSizeValue.textContent = e.target.value;
        });

        // Проставляем сохранённые значения, если есть
        try {
          const saved = JSON.parse(localStorage.getItem('panorama-editor-settings') || '{}');
          if (saved.mouseSensitivity) { sensitivitySlider.value = saved.mouseSensitivity; sensitivityValue.textContent = saved.mouseSensitivity; }
          if (saved.zoomSpeed) { zoomSpeedSlider.value = saved.zoomSpeed; zoomSpeedValue.textContent = saved.zoomSpeed; }
          if (saved.hotspotColor) document.getElementById('default-hotspot-color').value = saved.hotspotColor;
          if (saved.hotspotSize) { hotspotSizeSlider.value = saved.hotspotSize; hotspotSizeValue.textContent = saved.hotspotSize; }
          if (saved.infopointColor) document.getElementById('default-infopoint-color').value = saved.infopointColor;
          if (saved.infopointSize) { infopointSizeSlider.value = saved.infopointSize; infopointSizeValue.textContent = saved.infopointSize; }
          if (typeof saved.gyroEnabled === 'boolean') document.getElementById('gyro-enabled').checked = saved.gyroEnabled;
        } catch { }

        // Закрытие модального окна
        const closeBtn = settingsModal.querySelector('.settings-close');
        closeBtn.addEventListener('click', () => {
          settingsModal.remove();
        });

        settingsModal.addEventListener('click', (e) => {
          if (e.target === settingsModal) {
            settingsModal.remove();
          }
        });
      };

      // Функция применения настроек
      window.applySettings = () => {
        const mouseSensitivity = document.getElementById('mouse-sensitivity').value;
        const zoomSpeed = document.getElementById('zoom-speed').value;
        const gyroEnabled = !!document.getElementById('gyro-enabled').checked;
        const hotspotColor = document.getElementById('default-hotspot-color').value;
        const hotspotSize = document.getElementById('default-hotspot-size').value;
        const infopointColor = document.getElementById('default-infopoint-color').value;
        const infopointSize = document.getElementById('default-infopoint-size').value;

        // Сохраняем настройки в localStorage
        const settings = {
          mouseSensitivity: parseFloat(mouseSensitivity),
          zoomSpeed: parseFloat(zoomSpeed),
          gyroEnabled,
          hotspotColor,
          hotspotSize: parseFloat(hotspotSize),
          infopointColor,
          infopointSize: parseFloat(infopointSize)
        };

        localStorage.setItem('panorama-editor-settings', JSON.stringify(settings));

        // Применяем настройки к камере
        viewerManager.updateCameraSettings(settings);

        // Применяем настройки к существующим маркерам
        hotspotManager.updateAllMarkersWithSettings(settings);

        alert('Настройки применены!');
        document.querySelector('.modal').remove();
      };

      // Загружаем сохраненные настройки при старте
      const savedSettings = localStorage.getItem('panorama-editor-settings');
      if (savedSettings) {
        const settings = JSON.parse(savedSettings);
        viewerManager.updateCameraSettings(settings);
      }

      // Добавляем обработчик для кнопки очистки данных
      const clearDataBtn = document.getElementById('clear-data-btn');
      if (clearDataBtn) {
        clearDataBtn.addEventListener('click', () => {
          if (confirm('Вы уверены, что хотите очистить все данные приложения? Это действие нельзя отменить.')) {
            localStorage.clear();
            sessionStorage.clear();
            location.reload();
          }
        });
      }

      // Предупреждение о потере данных при обновлении страницы или закрытии браузера
      let hasUnsavedChanges = false;

      // Отслеживаем добавление панорам
      const originalAddScene = sceneManager.addScene;
      sceneManager.addScene = function (...args) {
        hasUnsavedChanges = true;
        return originalAddScene.apply(this, args);
      };

      // Отслеживаем добавление хотспотов
      const originalAddHotspot = hotspotManager.addHotspot;
      hotspotManager.addHotspot = function (...args) {
        hasUnsavedChanges = true;
        return originalAddHotspot.apply(this, args);
      };

      // Отслеживаем загрузку изображений
      const originalLoadPanorama = viewerManager.loadPanorama;
      viewerManager.loadPanorama = function (...args) {
        hasUnsavedChanges = true;
        return originalLoadPanorama.apply(this, args);
      };

      // Предупреждение при попытке обновить страницу
      window.addEventListener('beforeunload', (e) => {
        if (hasUnsavedChanges) {
          const message = 'У вас есть несохраненные изменения в туре. Если вы обновите страницу или закроете браузер, все данные будут потеряны безвозвратно. Вы уверены, что хотите продолжить?';
          e.preventDefault();
          e.returnValue = message;
          return message;
        }
      });

      // Функция для сброса флага (можно вызвать после экспорта)
      window.markAsSaved = () => {
        hasUnsavedChanges = false;
      };

      // Функция для принудительной установки флага
      window.markAsUnsaved = () => {
        hasUnsavedChanges = true;
      };

      // Добавляем тестовую кнопку для проверки редактирования маркеров
      // Удалены диагностические утилиты и тестовые хендлеры для продакшна

    } catch (error) {
      alert('Ошибка инициализации приложения. Перезагрузите страницу.');
    }
  }, 100);
});

// Initialize floating user menu
function initializeFloatingUserMenu() {
  const floatingUserButton = document.getElementById('floating-user-button');
  const floatingUserDropdown = document.getElementById('floating-user-dropdown');
  const avatarInput = document.getElementById('avatar-input');
  
  if (!floatingUserButton || !floatingUserDropdown) return;

  // If avatar exists in localStorage, show it in the button
  const existingAvatar = localStorage.getItem('color360_avatar');
  if (existingAvatar) {
    const img = document.createElement('img');
    img.className = 'user-avatar';
    img.src = existingAvatar;
    // replace button content (SVG) with avatar image
    floatingUserButton.innerHTML = '';
    floatingUserButton.appendChild(img);
  }
  
  // make button focusable for keyboard users
  floatingUserButton.setAttribute('tabindex', '0');

  // Toggle dropdown on button click
  floatingUserButton.addEventListener('click', (e) => {
    e.stopPropagation();
    floatingUserDropdown.classList.toggle('open');
  });

  // Close on Escape (works when dropdown is open)
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' || e.key === 'Esc') {
      if (floatingUserDropdown.classList.contains('open')) {
        floatingUserDropdown.classList.remove('open');
      }
    }
  });

  // Close dropdown when clicking outside
  document.addEventListener('click', (e) => {
    if (floatingUserDropdown.classList.contains('open') &&
        !floatingUserButton.contains(e.target) &&
        !floatingUserDropdown.contains(e.target)) {
      floatingUserDropdown.classList.remove('open');
    }
  });
  
  // Update menu based on user authentication status
  updateFloatingUserMenu();

  // If token exists, fetch profile to update avatar from server
  const token = localStorage.getItem('color360_token');
  if (token) {
    fetch('/api/user/profile', { headers: { 'Authorization': `Bearer ${token}` } })
      .then(r => r.ok ? r.json() : null)
      .then(profile => {
        if (profile && profile.avatar) {
          localStorage.setItem('color360_avatar', profile.avatar);
          // update button image
          const btn = document.getElementById('floating-user-button');
          if (btn) {
            const existing = btn.querySelector('img.user-avatar');
            if (existing) existing.src = profile.avatar; else {
              const img = document.createElement('img'); img.className = 'user-avatar'; img.src = profile.avatar; btn.innerHTML = ''; btn.appendChild(img);
            }
          }
          updateFloatingUserMenu();
        }
      }).catch(()=>{});
  }

  // Listen for avatar updates from profile page
  window.addEventListener('message', (ev) => {
    try {
      const data = ev.data || {};
      if (data && data.type === 'avatar-updated' && data.url) {
        localStorage.setItem('color360_avatar', data.url);
        updateFloatingUserMenu();
      }
    } catch(e){}
  });
}

// Listen for avatar updates from profile popup via postMessage
window.addEventListener('message', (e) => {
  try {
    const data = e.data || {};
    if (data && data.type === 'avatar-updated' && data.url) {
      localStorage.setItem('color360_avatar', data.url);
      const btnImg = document.querySelector('#floating-user-button img.user-avatar');
      if (btnImg) btnImg.src = data.url;
      const menuImg = document.querySelector('#floating-user-dropdown .user-avatar');
      if (menuImg) menuImg.src = data.url;
    }
  } catch (err) { }
});

// Also listen to storage events in case another tab updated avatar
window.addEventListener('storage', (e) => {
  if (e.key === 'color360_avatar' && e.newValue) {
    const url = e.newValue;
    const btnImg = document.querySelector('#floating-user-button img.user-avatar');
    if (btnImg) btnImg.src = url;
    const menuImg = document.querySelector('#floating-user-dropdown .user-avatar');
    if (menuImg) menuImg.src = url;
  }
});

// Update floating user menu based on authentication status
function updateFloatingUserMenu() {
  const floatingUserDropdown = document.getElementById('floating-user-dropdown');
  if (!floatingUserDropdown) return;
  
  const userToken = localStorage.getItem('color360_token');
  
  if (userToken) {
    // User is logged in
    const userJson = localStorage.getItem('color360_user');
    let user = null;
    try {
      user = userJson ? JSON.parse(userJson) : null;
    } catch (e) {
      console.error('Error parsing user data:', e);
    }
    
    const isAdmin = user && user.isAdmin;
    const userName = user ? user.name : 'Пользователь';
    
    floatingUserDropdown.innerHTML = `
      <div class="user-info">
        <div style="display:flex;gap:8px;align-items:center;">
          <div style="width:28px;height:28px;overflow:hidden;border-radius:50%;background:#222;display:flex;align-items:center;justify-content:center;">
            <img class="user-avatar" src="${localStorage.getItem('color360_avatar') || ''}" alt="avatar" onerror="this.style.display='none'" />
          </div>
          <div>Здравствуйте, ${userName}</div>
        </div>
  <button id="new-project-btn">Создать новый проект</button>
        <button id="save-server-project-btn">Сохранить проект</button>
        <button id="save-local-project-logged-btn">Сохранить проект локально</button>
        <button id="load-local-project-logged-btn">Загрузить проект локально</button>
  <button id="load-server-project-btn">Загрузить проект</button>
        <div class="divider"></div>
  <a href="${isAdmin ? '/admin' : '/profile.html'}" target="_blank">${isAdmin ? 'Админ панель' : 'Личный кабинет'}</a>
        <button id="logout-btn">Выйти</button>
      </div>
    `;
    
    // Add event listeners for menu items
  document.getElementById('new-project-btn')?.addEventListener('click', createNewProject);
  document.getElementById('save-server-project-btn')?.addEventListener('click', async () => { await createNewServerProject(); floatingUserDropdown.classList.remove('open'); });
  document.getElementById('save-local-project-logged-btn')?.addEventListener('click', () => { saveLocalProject(); floatingUserDropdown.classList.remove('open'); });
  document.getElementById('load-local-project-logged-btn')?.addEventListener('click', () => { loadLocalProject(); floatingUserDropdown.classList.remove('open'); });
  document.getElementById('load-server-project-btn')?.addEventListener('click', loadServerProjects);
  document.getElementById('logout-btn')?.addEventListener('click', logoutUser);
  } else {
    // User is not logged in
    floatingUserDropdown.innerHTML = `
      <button id="login-btn">Вход</button>
      <button id="register-btn">Регистрация</button>
      <div class="divider"></div>
      <button id="save-local-project-btn">Сохранить проект локально</button>
      <button id="load-local-project-btn">Загрузить проект из локального хранилища</button>
      <button id="export-tour-btn">Экспортировать панорамный тур</button>
    `;
    
    // Add event listeners for menu items
    document.getElementById('login-btn')?.addEventListener('click', showLoginModal);
    document.getElementById('register-btn')?.addEventListener('click', showRegisterModal);
    document.getElementById('save-local-project-btn')?.addEventListener('click', () => { saveLocalProject(); floatingUserDropdown.classList.remove('open'); });
    document.getElementById('load-local-project-btn')?.addEventListener('click', () => { loadLocalProject(); floatingUserDropdown.classList.remove('open'); });
    document.getElementById('export-tour-btn')?.addEventListener('click', () => { exportTour(); floatingUserDropdown.classList.remove('open'); });
  }

  // Avatar input handler (attach only if input exists)
  // ВРЕМЕННО ОТКЛЮЧЕНО: возможность загрузки пользовательской иконки на аватар
  /*
  const avatarInputEl = document.getElementById('avatar-input');
  if (avatarInputEl) {
    avatarInputEl.addEventListener('change', async (e) => {
      const file = e.target.files && e.target.files[0];
      if (!file) return;
      try {
        const dataUrl = await new Promise((res) => {
          const r = new FileReader();
          r.onload = () => res(r.result);
          r.readAsDataURL(file);
        });
        localStorage.setItem('color360_avatar', dataUrl);
        // Update current avatar image in menu and button
        const img = document.querySelector('#floating-user-dropdown .user-avatar');
        if (img) img.src = dataUrl;
        const btnImg = document.querySelector('#floating-user-button img.user-avatar');
        if (btnImg) btnImg.src = dataUrl; else {
          const newImg = document.createElement('img');
          newImg.className = 'user-avatar';
          newImg.src = dataUrl;
          // clear existing svg
          const btn = document.getElementById('floating-user-button');
          btn.innerHTML = '';
          btn.appendChild(newImg);
        }
        floatingUserDropdown.classList.remove('open');
        window.app?.showNotification?.('Аватар обновлен', 'success');
      } catch (err) {
        console.error('Ошибка при загрузке аватара', err);
        window.app?.showNotification?.('Ошибка при загрузке аватара', 'error');
      }
    });
  }
  */
}

// Function to create a new project
function createNewProject() {
  if (confirm('Вы уверены, что хотите создать новый проект? Все несохраненные изменения будут потеряны.')) {
    // Clear current project
    if (window.app && window.app.sceneManager && window.app.hotspotManager) {
      window.app.sceneManager.clearScenes();
      window.app.hotspotManager.loadHotspots([]);
      window.app.sceneManager.renderSceneList();
      window.app.showNotification('Новый проект создан', 'success');
    }
  document.getElementById('floating-user-dropdown').style.display = 'none';
  }
}

// Function to save project locally
function saveLocalProject() {
  try {
    if (window.app && window.app.projectManager) {
      const json = window.app.projectManager.saveProject();
      const blob = new Blob([json], { type: 'application/json' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = 'panorama-project.json';
      a.click();
      URL.revokeObjectURL(a.href);
      window.app.showNotification('Проект сохранен локально', 'success');
    }
  } catch (error) {
    console.error('Ошибка при сохранении проекта:', error);
    window.app?.showNotification?.('Ошибка при сохранении проекта', 'error');
  }
}

// Function to load project from local storage
function loadLocalProject() {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = '.json';
  
  input.onchange = async (e) => {
    const file = e.target.files[0];
    if (file) {
      try {
        const content = await file.text();
        if (window.app && window.app.projectManager) {
          const success = await window.app.projectManager.loadProject(content);
          if (success) {
            window.app.sceneManager.renderSceneList();
            window.app.showNotification('Проект загружен', 'success');
          } else {
            window.app.showNotification('Ошибка при загрузке проекта', 'error');
          }
        }
      } catch (error) {
        console.error('Ошибка при загрузке проекта:', error);
        window.app?.showNotification?.('Ошибка при загрузке проекта', 'error');
      }
    }
  };
  
  input.click();
}

// Function to export tour
function exportTour() {
  try {
    if (window.app && window.app.exportManager) {
      window.app.exportManager.exportProject();
    }
  } catch (error) {
    console.error('Ошибка при экспорте:', error);
    window.app?.showNotification?.('Ошибка при экспорте проекта', 'error');
  }
}

// Function to load projects from server
async function loadServerProjects() {
  try {
    const userToken = localStorage.getItem('color360_token');
    if (!userToken) {
      window.app?.showNotification?.('Пользователь не авторизован', 'error');
      return;
    }
    
  const response = await fetch('/api/projects', {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${userToken}`
      }
    });
    
    if (response.ok) {
      const sessions = await response.json();
      showServerProjectsModal(sessions);
    } else {
      window.app?.showNotification?.('Ошибка при загрузке проектов', 'error');
    }
  } catch (error) {
    console.error('Ошибка при загрузке проектов:', error);
    window.app?.showNotification?.('Ошибка при загрузке проектов', 'error');
  }
}

// Function to show server projects modal
function showServerProjectsModal(sessions) {
  // Create modal for selecting server projects
  const modal = document.createElement('div');
  modal.style.cssText = `
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: rgba(0, 0, 0, 0.75);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 100000;
    backdrop-filter: blur(8px);
  `;
  
  const modalContent = document.createElement('div');
  modalContent.style.cssText = `
    background: rgba(26, 26, 26, 0.95);
    border-radius: 12px;
    padding: 24px;
    min-width: 400px;
    max-width: 600px;
    max-height: 80vh;
    overflow-y: auto;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
    border: 1px solid rgba(255, 255, 255, 0.1);
    backdrop-filter: blur(20px);
  `;
  
  modalContent.innerHTML = `
    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px;">
      <h3 style="margin: 0; color: white;">Сохраненные проекты</h3>
      <button id="close-modal-btn" style="background: none; border: none; color: white; font-size: 24px; cursor: pointer;">&times;</button>
    </div>
    <div id="sessions-list" style="margin-bottom: 20px;">
      ${sessions.length > 0 ? 
        sessions.map(session => `
          <div style="display: flex; justify-content: space-between; align-items: center; padding: 12px; background: rgba(255, 255, 255, 0.05); border-radius: 8px; margin-bottom: 8px;">
            <div>
              <div style="color: white; font-weight: 500;">${session.name}</div>
              <div style="color: rgba(255, 255, 255, 0.7); font-size: 12px;">Создан: ${new Date(session.created).toLocaleDateString('ru-RU')}</div>
            </div>
            <div>
              <button class="load-session-btn" data-id="${session.id}" style="background: #646cff; color: white; border: none; padding: 6px 12px; border-radius: 4px; cursor: pointer; margin-right: 8px;">Загрузить</button>
              <button class="delete-session-btn" data-id="${session.id}" style="background: #dc3545; color: white; border: none; padding: 6px 12px; border-radius: 4px; cursor: pointer;">Удалить</button>
            </div>
          </div>
        `).join('') : 
        '<div style="color: rgba(255, 255, 255, 0.7); text-align: center; padding: 20px;">Нет сохраненных проектов</div>'
      }
    </div>
    <button id="create-new-session-btn" style="background: #28a745; color: white; border: none; padding: 12px 20px; border-radius: 8px; cursor: pointer; width: 100%;">Создать новый проект</button>
  `;
  
  modal.appendChild(modalContent);
  document.body.appendChild(modal);
  
  // Add event listeners
  document.getElementById('close-modal-btn').addEventListener('click', () => {
    document.body.removeChild(modal);
  });
  
  modal.addEventListener('click', (e) => {
    if (e.target === modal) {
      document.body.removeChild(modal);
    }
  });
  
  document.querySelectorAll('.load-session-btn').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      const sessionId = e.target.getAttribute('data-id');
      await loadServerProject(sessionId);
      document.body.removeChild(modal);
    });
  });
  
  document.querySelectorAll('.delete-session-btn').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      const sessionId = e.target.getAttribute('data-id');
      await deleteServerProject(sessionId);
      // Refresh the modal
      document.body.removeChild(modal);
      loadServerProjects();
    });
  });
  
  document.getElementById('create-new-session-btn').addEventListener('click', async () => {
    await createNewServerProject();
    document.body.removeChild(modal);
  });
}

// Function to load a project from server
async function loadServerProject(sessionId) {
  try {
    const userToken = localStorage.getItem('color360_token');
    if (!userToken) {
      window.app?.showNotification?.('Пользователь не авторизован', 'error');
      return;
    }
    
  const response = await fetch(`/api/projects/${sessionId}`, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${userToken}`
      }
    });
    
    if (response.ok) {
      const session = await response.json();
      if (window.app && window.app.projectManager) {
        const success = await window.app.projectManager.loadProject(JSON.stringify(session.data));
        if (success) {
          window.app.sceneManager.renderSceneList();
          window.app.showNotification('Проект загружен с сервера', 'success');
        } else {
          window.app.showNotification('Ошибка при загрузке проекта', 'error');
        }
      }
    } else {
      window.app?.showNotification?.('Ошибка при загрузке проекта', 'error');
    }
  } catch (error) {
    console.error('Ошибка при загрузке проекта:', error);
    window.app?.showNotification?.('Ошибка при загрузке проекта', 'error');
  }
}

// Function to delete a project from server
async function deleteServerProject(sessionId) {
  try {
    const userToken = localStorage.getItem('color360_token');
    if (!userToken) {
      window.app?.showNotification?.('Пользователь не авторизован', 'error');
      return;
    }
    
  const response = await fetch(`/api/projects/${sessionId}`, {
      method: 'DELETE',
      headers: {
        'Authorization': `Bearer ${userToken}`
      }
    });
    
    if (response.ok) {
      window.app?.showNotification?.('Проект удален', 'success');
    } else {
      window.app?.showNotification?.('Ошибка при удалении проекта', 'error');
    }
  } catch (error) {
    console.error('Ошибка при удалении проекта:', error);
    window.app?.showNotification?.('Ошибка при удалении проекта', 'error');
  }
}

// Function to create a new project on server
async function createNewServerProject() {
  try {
    const userToken = localStorage.getItem('color360_token');
    if (!userToken) {
      window.app?.showNotification?.('Пользователь не авторизован', 'error');
      return;
    }
    
    const projectName = prompt('Введите название нового проекта:');
    if (!projectName) return;
    
    // Get current project data
    let projectData = {};
    if (window.app && window.app.projectManager) {
      try {
        projectData = JSON.parse(window.app.projectManager.saveProject());
      } catch (e) {
        console.error('Error getting project data:', e);
      }
    }
    
    // Проверим количество уже сохранённых проектов на сервере и применим лимит 3
    try {
  const listResp = await fetch('/api/projects', {
        method: 'GET',
        headers: { 'Authorization': `Bearer ${userToken}` }
      });
      if (listResp.ok) {
        const sessions = await listResp.json();
        if (Array.isArray(sessions) && sessions.length >= 3) {
          window.app?.showNotification?.('Достигнуто максимальное количество сохранённых проектов (3). Удалите ненужный проект на сервере или обновите тариф.', 'error');
          return;
        }
      }
    } catch (e) {

      // Продолжим попытку создания — сервер может сам отклонить запрос
    }

  const response = await fetch('/api/projects', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${userToken}`
      },
      body: JSON.stringify({
        name: projectName,
        data: projectData
      })
    });
    
    if (response.ok) {
      window.app?.showNotification?.('Проект создан на сервере', 'success');
    } else {
      const result = await response.json();
      window.app?.showNotification?.(result.message || 'Ошибка при создании проекта', 'error');
    }
  } catch (error) {
    console.error('Ошибка при создании проекта:', error);
    window.app?.showNotification?.('Ошибка при создании проекта', 'error');
  }
}

// Function to show login modal
function showLoginModal() {
  // This would typically redirect to the main site login page
  if (confirm('Перейти на страницу входа?')) {
    window.open('/', '_blank');
  }
  document.getElementById('floating-user-dropdown').style.display = 'none';
}

// Function to show register modal
function showRegisterModal() {
  // This would typically redirect to the main site registration page
  if (confirm('Перейти на страницу регистрации?')) {
    window.open('/', '_blank');
  }
  document.getElementById('floating-user-dropdown').style.display = 'none';
}

// Function to logout user
function logoutUser() {
  localStorage.removeItem('color360_token');
  localStorage.removeItem('color360_user');
  updateFloatingUserMenu();
  window.app?.showNotification?.('Вы вышли из аккаунта', 'info');
  document.getElementById('floating-user-dropdown').style.display = 'none';
}
