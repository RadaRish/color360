import ExportManager from './core/export_manager.js';
import HotspotManager from './core/hotspot_manager.js';
import ProjectManager from './core/project_manager.js';
import SceneManager from './core/scene_manager.js';
import ViewerManager from './core/viewer_manager.js';
import HotspotEditor from './ui/hotspot-editor.js';
import SceneList from './ui/scene_list.js';

document.addEventListener('DOMContentLoaded', () => {
  const viewerContainer = document.getElementById('viewer-container');
  if (!viewerContainer) {
    console.error('viewer-container не найден в DOM!');
    return;
  }

  setTimeout(() => {
    try {
      const hotspotManager = new HotspotManager(); // Создаем сначала hotspotManager
      const viewerManager = new ViewerManager('viewer-container', hotspotManager); // Передаем его в ViewerManager
      const sceneManager = new SceneManager(viewerManager);
      const projectManager = new ProjectManager(sceneManager, hotspotManager);
      const exportManager = new ExportManager(sceneManager, hotspotManager, projectManager);
      const hotspotEditor = new HotspotEditor('hotspot-editor-modal');

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
        // Функция для показа уведомлений
        showNotification: (message, type = 'info') => {
          const notification = document.createElement('div');
          notification.style.cssText = `
                        position: fixed;
                        top: 20px;
                        right: 20px;
                        padding: 12px 20px;
                        background: ${type === 'success' ? '#4CAF50' : type === 'error' ? '#f44336' : '#2196F3'};
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

      // Глобальные функции для редактирования и удаления, вызываемые из A-Frame компонентов
      window.editMarker = async (hotspotId) => {
        const hotspot = hotspotManager.findHotspotById(hotspotId);
        if (!hotspot) return;

        const scenes = sceneManager.getAllScenes();
        const currentScene = sceneManager.getSceneById(hotspot.sceneId);

        try {
          const data = await hotspotEditor.showEditMode(hotspot);

          if (data) {
            hotspotManager.updateHotspot(hotspot.id, data);
          }
        } catch (error) {
          console.error('Ошибка при редактировании маркера:', error);
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
            toggle.textContent = isHidden ? '⮞' : '⮜';

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
            toggle.textContent = sidebar.classList.contains('hide') ? '⮞' : '⮜';
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

      // Кнопка экспорта
      const exportBtn = document.getElementById('export-btn');
      if (exportBtn) {
        exportBtn.onclick = async () => {
          try {
            await exportManager.exportProject();
          } catch (error) {
            console.error('Ошибка экспорта:', error);
            alert('Ошибка при экспорте: ' + error.message);
          }
        };
      }

      // Кнопка очистки хотспотов-сирот
      const cleanupBtn = document.getElementById('cleanup-btn');
      if (cleanupBtn) {
        cleanupBtn.onclick = () => {
          try {
            const scenes = sceneManager.getAllScenes();
            const validSceneIds = scenes.map(scene => scene.id);
            const orphanedCount = hotspotManager.cleanupOrphanedHotspots(validSceneIds);

            if (orphanedCount > 0) {
              alert(`Очистка завершена! Удалено ${orphanedCount} хотспотов-сирот.`);
              // Обновляем отображение текущей сцены
              const currentScene = sceneManager.getCurrentScene();
              if (currentScene) {
                viewerManager.restoreMarkersForScene(currentScene.id);
              }
            } else {
              alert('Хотспоты-сироты не найдены. Данные уже чистые!');
            }
          } catch (error) {
            console.error('Ошибка очистки:', error);
            alert('Ошибка при очистке: ' + error.message);
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

      // Сохранение проекта
      const saveProjectBtn = document.getElementById('save-project');
      if (saveProjectBtn) {
        saveProjectBtn.onclick = () => {
          try {
            const json = projectManager.saveProject();
            const blob = new Blob([json], { type: 'application/json' });
            const a = document.createElement('a');
            a.href = URL.createObjectURL(blob);
            a.download = 'panorama-project.json';
            a.click();
            URL.revokeObjectURL(a.href);
          } catch (error) {
            alert('Ошибка при сохранении проекта');
          }
        };
      }

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
                                    <input type="range" id="default-hotspot-size" min="0.1" max="1" step="0.1" value="0.3">
                                    Размер хотспотов: <span id="hotspot-size-value">0.3</span>
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
                                    <input type="range" id="default-infopoint-size" min="0.1" max="1" step="0.1" value="0.3">
                                    Размер инфоточек: <span id="infopoint-size-value">0.3</span>
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
