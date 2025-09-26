import CoordinateManager from './coordinate_manager.js';
import ModernMarkerGenerator from './modern_marker_generator.js';

export default class ViewerManager {
  constructor(containerId, hotspotManager) {
    this.container = document.getElementById(containerId);
    this.aframeScene = null;
    this.aframeCamera = null;
    this.aframeSky = null;
    this.currentPanorama = null;
    this._currentPanoramaBlobUrl = null;
    this.zoomSpeed = 1.0; // Скорость зума по умолчанию
    this.hotspotManager = hotspotManager; // Ссылка на менеджер хотспотов
    this.coordinateManager = new CoordinateManager(this); // Передаем ссылку на ViewerManager
    this.modernMarkerGenerator = new ModernMarkerGenerator(); // Генератор современных маркеров

    // Флаги состояния
    this._isResizing = false;
    this._resizeSaveTimeout = null;
    this._currentResizeHandle = null; // Хранит информацию о текущем угле изменения размера

    // Авторотация (автоповорот) панорамы
    this.autorotateEnabled = false;
    this.autorotateSpeed = 0.02; // радиан/сек
    this.autorotateIdleDelay = 3000; // мс до возобновления после взаимодействия
    this._autorotatePaused = false;
    this._autorotateLastTs = 0;
    this._lastUserInteraction = Date.now();
    this._autorotateRaf = null;

    // Гироскоп и жесты
    this.gyroEnabled = false;
    this._pinch = { active: false, startDist: 0, startFov: 80 };

    this.initializeViewer();
  }

  // Обновление debug overlay (элемент в index.html)
  updateDebugOverlay(info) {
    try {
      const pre = document.getElementById('debug-overlay-pre');
      if (!pre) return;
      const lines = [];
      if (info) {
        for (const k of Object.keys(info)) {
          let v = info[k];
          if (typeof v === 'object') {
            try { v = JSON.stringify(v, null, 0); } catch(e) { v = String(v); }
          }
          lines.push(`${k}: ${v}`);
        }
      }
      pre.textContent = lines.join('\n');
    } catch (e) { console.warn('Не удалось обновить debug overlay:', e); }
  }

  _hashString(str) {
    // Простая хеш-функция для генерации идентификатора из строки
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const chr = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + chr;
      hash |= 0; // Приводим к 32bit
    }
    return hash;
  }

  initializeViewer() {
    // Инициализируем A-Frame сцену
    this.initializeAFrame();

    // Регистрируем компонент billboard для правильной ориентации текста
    if (!AFRAME.components['billboard']) {
      AFRAME.registerComponent('billboard', {
        tick: function () {
          const camera = this.el.sceneEl.camera;
          if (camera) {
            this.el.object3D.lookAt(camera.getWorldPosition(new THREE.Vector3()));
          }
        }
      });
    }

    // Регистрируем компонент для отображения кириллицы
    if (!AFRAME.components['cyrillic-text']) {
      AFRAME.registerComponent('cyrillic-text', {
        schema: {
          value: { type: 'string' },
          color: { type: 'color', default: '#ffffff' },
          align: { type: 'string', default: 'center' },
          family: { type: 'string', default: 'Arial, sans-serif' },
          bold: { type: 'boolean', default: false },
          underline: { type: 'boolean', default: false }
        },
        init: function () {
          this.updateText();
        },
        update: function () {
          this.updateText();
        },
        updateText: function () {
          // Создаем canvas для отрисовки кириллицы
          const canvas = document.createElement('canvas');
          const ctx = canvas.getContext('2d');
          canvas.width = 512;
          canvas.height = 128;

          // Настройки шрифта
          const fontPx = 48;
          const weight = this.data.bold ? 'bold ' : '';
          const family = this.data.family || 'Arial, sans-serif';
          const text = this.data.value || '';

          ctx.font = `${weight}${fontPx}px ${family}`;
          ctx.fillStyle = this.data.color;
          ctx.textAlign = this.data.align;
          ctx.textBaseline = 'middle';

          // Фон можно добавить при необходимости
          // Отрисовываем текст
          ctx.clearRect(0, 0, canvas.width, canvas.height);
          ctx.fillText(text, canvas.width / 2, canvas.height / 2);

          // Подчёркивание
          if (this.data.underline && text) {
            const metrics = ctx.measureText(text);
            const underlineY = canvas.height / 2 + fontPx * 0.45;
            const underlineWidth = metrics.width;
            const startX = canvas.width / 2 - underlineWidth / 2;
            const endX = canvas.width / 2 + underlineWidth / 2;
            ctx.strokeStyle = this.data.color;
            ctx.lineWidth = 3;
            ctx.beginPath();
            ctx.moveTo(startX, underlineY);
            ctx.lineTo(endX, underlineY);
            ctx.stroke();
          }

          // Создаем текстуру и материал
          const texture = new THREE.CanvasTexture(canvas);
          const material = new THREE.MeshBasicMaterial({
            map: texture,
            transparent: true,
            alphaTest: 0.5
          });

          // Создаем plane геометрию
          const geometry = new THREE.PlaneGeometry(2, 0.5);
          const mesh = new THREE.Mesh(geometry, material);

          // Очищаем предыдущий mesh
          while (this.el.object3D.children.length > 0) {
            this.el.object3D.remove(this.el.object3D.children[0]);
          }

          this.el.object3D.add(mesh);
        }
      });
    }

    // Шейдер для хромакея (удаление фона по цвету)
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
          const uniforms = {
            map: { value: null },
            keyColor: { value: new THREE.Color(data.color) },
            similarity: { value: data.similarity },
            smoothness: { value: data.smoothness },
            threshold: { value: data.threshold }
          };
          this.material = new THREE.ShaderMaterial({
            uniforms,
            transparent: true,
            depthWrite: false,
            side: THREE.DoubleSide,
            vertexShader: `
              varying vec2 vUV;
              void main(){
                vUV = uv;
                gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0);
              }
            `,
            fragmentShader: `
              uniform sampler2D map;
              uniform vec3 keyColor;
              uniform float similarity;
              uniform float smoothness;
              uniform float threshold;
              varying vec2 vUV;
              void main(){
                vec4 color = texture2D(map, vUV);
                // RGB -> YCbCr приблизительно
                float r = color.r; float g = color.g; float b = color.b;
                float kr = 0.299; float kg = 0.587; float kb = 0.114;
                float y = kr*r + kg*g + kb*b;
                float cr = (r - y) * 0.713 + 0.5;
                float cb = (b - y) * 0.564 + 0.5;
                float rK = keyColor.r; float gK = keyColor.g; float bK = keyColor.b;
                float yK = kr*rK + kg*gK + kb*bK;
                float crK = (rK - yK) * 0.713 + 0.5;
                float cbK = (bK - yK) * 0.564 + 0.5;
                float blend = distance(vec2(cb,cr), vec2(cbK,crK));
                float alpha = smoothstep(similarity, similarity + smoothness, blend);
                alpha = clamp((alpha - threshold)/(1.0-threshold+1e-6), 0.0, 1.0);
                gl_FragColor = vec4(color.rgb, alpha * color.a);
              }
            `
          });
        },
        update: function (data) {
          if (data.src && data.src.image) {
            this.material.uniforms.map.value = data.src.image;
            this.material.needsUpdate = true;
          }
          if (data.color) this.material.uniforms.keyColor.value.set(data.color);
          if (typeof data.similarity === 'number') this.material.uniforms.similarity.value = data.similarity;
          if (typeof data.smoothness === 'number') this.material.uniforms.smoothness.value = data.smoothness;
          if (typeof data.threshold === 'number') this.material.uniforms.threshold.value = data.threshold;
        }
      });
    }

    // Регистрируем компонент hotspot-handler для обработки взаимодействий
    if (typeof AFRAME !== 'undefined') {
      AFRAME.registerComponent('hotspot-handler', {
        schema: {
          hotspotId: { type: 'string' },
          hotspotType: { type: 'string' }
        },
        init: function () {
          const el = this.el;
          const data = this.data;
          // init hotspot-handler

          // Добавляем CSS pointer-events для обеспечения получения событий мыши
          el.setAttribute('style', 'pointer-events: auto;');

          // Переменные для отслеживания кликов
          let clickCount = 0;
          let clickTimer = null;
          let lastClickTime = 0;
          let rightClickHandled = false;
          let doubleClickHandled = false;

          // ОТЛАДКА: добавляем обработчики для событий мыши с защитой от дублирования
          const mousedownHandler = () => { };
          const mouseupHandler = () => { };
          const clickHandler = () => { };

          // Добавляем обработчики только один раз
          if (!el._debugHandlersAdded) {
            el.addEventListener('mousedown', mousedownHandler, true);
            el.addEventListener('mouseup', mouseupHandler, true);
            el.addEventListener('click', clickHandler, true);
            el._debugHandlersAdded = true;
          }

          // Обработчики событий от raycaster с дебаунсингом
          let intersectedTimeout = null;
          let clearedTimeout = null;

          el.addEventListener('raycaster-intersected', (e) => {
            if (intersectedTimeout) clearTimeout(intersectedTimeout);
            intersectedTimeout = setTimeout(() => {
              el.emit('mouseenter');
            }, 50); // Дебаунсинг 50ms
          });

          el.addEventListener('raycaster-intersected-cleared', (e) => {
            if (clearedTimeout) clearTimeout(clearedTimeout);
            clearedTimeout = setTimeout(() => {
              el.emit('mouseleave');
            }, 50); // Дебаунсинг 50ms
          });

          // Обработчики событий
          // Удалено: показ/скрытие 3D-текста (cyrillic-text) на наведение — используем только 2D tooltip
          el.addEventListener('mouseenter', () => { });
          el.addEventListener('mouseleave', () => { });

          // КАСТОМНАЯ система обработки событий мыши с отслеживанием состояния
          let mouseDownTime = 0;
          let isRightMouseDown = false;
          let clickStartTime = 0;

          el.addEventListener('mousedown', (e) => {
            const currentTime = Date.now();
            mouseDownTime = currentTime;

            // НЕ ПЫТАЕМСЯ определить правую кнопку через A-Frame
            // Полагаемся на canvas обработчики для правого клика
            // rely on canvas handlers for right click

            // Левая кнопка мыши - начинаем отслеживание для двойного клика
            if (e.which === 1 || e.button === 0) {
              clickStartTime = currentTime;
            }
          });

          el.addEventListener('mouseup', (e) => {
            // Просто логируем
            // no special handling on mouseup
          });

          // ДВОЙНОЙ КЛИК ОТКЛЮЧЕН ПО ПРОСЬБЕ ПОЛЬЗОВАТЕЛЯ
          // Отслеживание быстрых двойных кликов через собственную логику
          /*
          el.addEventListener('click', (e) => {
            const currentTime = Date.now();
            const timeSinceMouseDown = currentTime - clickStartTime;
    
            // Если клик произошел очень быстро после другого клика - это может быть двойной клик
            if (timeSinceMouseDown < 50 && (currentTime - lastClickTime) < 300) {

              doubleClickHandled = true;
              el.parentElement._doubleClickHandled = true;
    
              e.preventDefault();
              e.stopPropagation();
    
              const hotspotId = data.hotspotId;
              if (window.hotspotManager) {

                window.hotspotManager.editHotspot(hotspotId);
              }
    
              setTimeout(() => {
                doubleClickHandled = false;
                delete el.parentElement._doubleClickHandled;
              }, 300);
    
              return false;
            }
    
            lastClickTime = currentTime;
          });
          */

          // НЕ добавляем дополнительные обработчики contextmenu и dblclick
          // Полагаемся на canvas обработчики для этих событий
          // rely on canvas handlers for contextmenu and dblclick

          el.addEventListener('click', (e) => {
            // a-frame click

            // 🔥 КРИТИЧЕСКАЯ ПРОВЕРКА: блокируем клик после правого клика
            const currentTime = Date.now();
            const lastRightClickTime = window.viewerManager ? window.viewerManager._lastRightClickTime : 0;
            const timeSinceRightClick = currentTime - (lastRightClickTime || 0);

            if (timeSinceRightClick < 300) {
              return;
            }

            // Дополнительная проверка глобальной блокировки
            // ИСКЛЮЧЕНИЕ: видео-области НЕ блокируются глобальной системой для ЛКМ кликов
            if (window._dragSystemBlocked && data.hotspotType !== 'video-area') {
              return;
            }

            // СПЕЦИАЛЬНАЯ ОБРАБОТКА для видео-областей: используем упрощенную логику воспроизведения
            if (data.hotspotType === 'video-area') {
              // video-area simplified click handler

              // Получаем ссылку на video элемент
              const markerEl = el.parentElement;
              const videoEl = markerEl.querySelector('video');

              if (videoEl) {
                // Упрощенная логика toggle для видео
                if (videoEl.paused) {
                  videoEl.play().catch(error => {
                    console.error('❌ Ошибка запуска видео:', error);
                  });
                } else {
                  videoEl.pause();
                }

                // Добавляем обработчик клика на сам видео-элемент (для надёжного toggle)
                if (!videoEl._clickHandlerAdded) {
                  videoEl.addEventListener('click', (ev) => {
                    ev.stopPropagation(); // Предотвращаем всплытие события
                    if (videoEl.paused) {
                      videoEl.play().catch(error => {
                        console.error('❌ Ошибка запуска видео:', error);
                      });
                    } else {
                      videoEl.pause();
                    }
                  });
                  videoEl._clickHandlerAdded = true;
                }

                // Название теперь отображается единообразно через 3D‑лейбл (cyrillic-text) и не дублируется 2D подложкой
              }
              return; // Завершаем обработку для видео-областей
            }

            // Специальная обработка: Ctrl+Click для редактирования
            if (e.ctrlKey) {
              // ctrl+click edit

              doubleClickHandled = true;
              el.parentElement._doubleClickHandled = true;

              e.preventDefault();
              e.stopPropagation();

              const hotspotId = data.hotspotId;
              if (window.hotspotManager) {
                window.hotspotManager.editHotspot(hotspotId);
              }

              setTimeout(() => {
                doubleClickHandled = false;
                delete el.parentElement._doubleClickHandled;
              }, 300);

              return false;
            }

            // Проверяем флаги блокировки
            if (rightClickHandled || doubleClickHandled) {
              return;
            }

            // Ищем родительский элемент маркера для проверки флагов блокировки
            const markerParent = el.parentElement;

            if (markerParent) {
              // Проверяем флаги блокировки от приоритетных обработчиков
              if (markerParent._rightClickHandled) {
                return;
              }

              if (markerParent._doubleClickHandled) {
                return;
              }

              if (markerParent._wasDragged) {
                return;
              }
            }

            // Также проверяем сам элемент
            if (el._wasDragged) {
              return;
            }

            // proceed primary action

            // Находим данные хотспота и вызываем соответствующую функцию
            const hotspotId = data.hotspotId;
            const hotspot = window.hotspotManager ? window.hotspotManager.getHotspotWithFullData(hotspotId) : null;

            if (hotspot) {
              if (hotspot.type === 'hotspot' && hotspot.targetSceneId) {

                // НЕ ВЫЗЫВАЕМ switchToScene здесь - это делает DOM обработчик с защитой!
                // window.sceneManager.switchToScene(hotspot.targetSceneId);
              } else if (hotspot.type === 'info-point') {

                window.viewerManager.showInfoPointModal(hotspot);
              } else if (hotspot.type === 'video-area') {
                // Обработка уже выполнена в блоке выше для data.hotspotType === 'video-area'

              }
            }
          });
        }
      });
    }
  }

  /**
   * Упрощенная функция воспроизведения видео с надежной логикой toggle
   */
  playVideoElement(videoEl, hotspot) {
    try {

      console.log('🔍 Текущее состояние:', {
        paused: videoEl.paused,
        readyState: videoEl.readyState
      });

      // Простая логика toggle
      if (videoEl.paused) {

        videoEl.play().catch(err => {
          console.error('❌ Ошибка запуска:', err);
          if (err.name === 'NotAllowedError') {
            videoEl.muted = true;
            videoEl.play().catch(e => console.error('❌ Не удалось запустить без звука:', e));
          }
        });
      } else {

        videoEl.pause();
      }
    } catch (err) {
      console.error('❌ Ошибка в playVideoElement:', err);
    }
  }

  /**
   * Проверяет наличие активных хотспотов в сцене
   */
  hasActiveHotspots() {
    return this.hotspots && this.hotspots.length > 0;
  }

  /**
   * Создает недостающий видео элемент для хотспота
   */
  createMissingVideoElement(hotspot) {

    console.log('🔍 Параметры hotspot:', {
      id: hotspot.id,
      title: hotspot.title,
      videoUrl: hotspot.videoUrl,
      hasVideoUrl: !!hotspot.videoUrl
    });

    const videoId = `video-${hotspot.id}`;

    // Находим соответствующую видео-плоскость заранее (нужно и для существующего, и для нового видео)
    const marker = document.getElementById(`marker-${hotspot.id}`);
    const videoPlane = marker ? marker.querySelector('a-plane') : null;

    // Вспомогательная функция для безопасного снятия текста
    const safeRemoveText = (plane) => {
      try {
        if (!plane) return;
        if (plane.hasAttribute && plane.hasAttribute('text')) {
          const comp = plane.components && plane.components.text ? plane.components.text : null;
          if (comp && typeof comp.remove === 'function') {
            try { comp.remove(); } catch (_) { }
          }
          try { plane.removeAttribute('text'); } catch (_) { }
        }
      } catch (err) {

      }
    };

    // Гарантированно применяет видео‑материал к плоскости, если он еще не установлен
    const ensureVideoMaterialApplied = (plane, vEl) => {
      if (!plane || !vEl) return;
      const mat = plane.getAttribute ? plane.getAttribute('material') : null;
      const hasSrc = mat && (mat.src || (typeof mat.map === 'object'));
      if (!hasSrc && vEl.readyState >= 2 && vEl.videoWidth > 0 && vEl.videoHeight > 0) {
        safeRemoveText(plane);
        plane.setAttribute('material', {
          src: `#${videoId}`,
          transparent: false,
          side: 'double'
        });
      }
    };

    // Если видео уже существует — обновляем и настраиваем привязку материала
    const existingVideo = document.getElementById(videoId);
    if (existingVideo) {

      const attachOneTimeListeners = () => {
        const onLoadedMeta = () => {

          ensureVideoMaterialApplied(videoPlane, existingVideo);
        };
        const onLoadedData = () => {

          ensureVideoMaterialApplied(videoPlane, existingVideo);
          cleanup();
        };
        const onCanPlay = () => {

          ensureVideoMaterialApplied(videoPlane, existingVideo);
          cleanup();
        };
        const cleanup = () => {
          existingVideo.removeEventListener('loadedmetadata', onLoadedMeta);
          existingVideo.removeEventListener('loadeddata', onLoadedData);
          existingVideo.removeEventListener('canplay', onCanPlay);
        };
        existingVideo.addEventListener('loadedmetadata', onLoadedMeta);
        existingVideo.addEventListener('loadeddata', onLoadedData);
        existingVideo.addEventListener('canplay', onCanPlay);
      };

      // Проверяем и обновляем src если нужно
      if (hotspot.videoUrl && hotspot.videoUrl !== existingVideo.src) {

        attachOneTimeListeners();
        if (existingVideo.readyState !== undefined) {
          existingVideo.src = hotspot.videoUrl;
          existingVideo.load();

        } else {
          setTimeout(() => {
            existingVideo.src = hotspot.videoUrl;
            existingVideo.load();

          }, 100);
        }
      } else {
        // Даже если src не менялся — пробуем применить материал, если видео уже готово
        ensureVideoMaterialApplied(videoPlane, existingVideo);
      }
      return;
    }

    // Создаем видео элемент
    const videoEl = document.createElement('video');
    videoEl.id = videoId;
    videoEl.crossOrigin = 'anonymous';
    videoEl.loop = true;
    videoEl.muted = true;
    videoEl.autoplay = false; // ОТКЛЮЧАЕМ autoplay - видео должно запускаться по клику
    videoEl.controls = false;
    videoEl.style.display = 'none';
    videoEl.preload = 'metadata';

    // НЕ устанавливаем poster - он может блокировать отображение
    // videoEl.poster = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

    // Добавляем в assets
    let assets = this.aframeScene.querySelector('a-assets');
    if (!assets) {

      assets = document.createElement('a-assets');
      this.aframeScene.appendChild(assets);
    }
    assets.appendChild(videoEl);

    // Обработчики загрузки
    videoEl.addEventListener('loadeddata', () => {

      // ИСПРАВЛЯЕМ: ждем полной готовности видео перед созданием текстуры
      if (videoEl.readyState >= 2 && videoEl.videoWidth > 0 && videoEl.videoHeight > 0) {
        if (videoPlane) {
          // Убираем текст-заглушку безопасно
          safeRemoveText(videoPlane);
          // Настраиваем материал с видео текстурой
          videoPlane.setAttribute('material', {
            src: `#${videoId}`,
            transparent: false,
            side: 'double'
          });
          // Дублируем попытку через тик и через 100мс, чтобы покрыть гонки
          setTimeout(() => ensureVideoMaterialApplied(videoPlane, videoEl), 0);
          setTimeout(() => ensureVideoMaterialApplied(videoPlane, videoEl), 100);
        }
      } else {
        // Если видео еще не готово, ждем события canplay

      }
    });

    videoEl.addEventListener('canplay', () => {

      // ИСПРАВЛЯЕМ: настраиваем материал в canplay если не было настроено в loadeddata
      const currentMaterial = videoPlane ? videoPlane.getAttribute('material') : null;
      if (videoPlane && (!currentMaterial || !currentMaterial.src)) {
        // Убираем текст безопасно
        safeRemoveText(videoPlane);
        // Настраиваем материал
        videoPlane.setAttribute('material', {
          src: `#${videoId}`,
          transparent: false,
          side: 'double'
        });
      }
      // Повторные попытки на случай гонок
      setTimeout(() => ensureVideoMaterialApplied(videoPlane, videoEl), 0);
      setTimeout(() => ensureVideoMaterialApplied(videoPlane, videoEl), 100);

      // НЕ запускаем автоматически - видео должно запускаться только по клику пользователя

    });

    videoEl.addEventListener('error', (e) => {
      console.error('❌ Ошибка загрузки недостающего видео:', {
        hotspot: hotspot.title || hotspot.id,
        videoUrl: hotspot.videoUrl,
        error: e.target.error
      });

      if (videoPlane) {
        // Показываем заглушку при ошибке
        videoPlane.setAttribute('material', {
          color: '#cc3333',
          transparent: false
        });
        videoPlane.setAttribute('text', {
          value: `❌ Ошибка загрузки видео\n${hotspot.title || 'Без названия'}`,
          align: 'center',
          color: '#ffffff'
        });
      }
    });

    // Устанавливаем источник видео если есть
    if (hotspot.videoUrl && hotspot.videoUrl.trim() !== '') {
      try {
        videoEl.src = hotspot.videoUrl;

        // Принудительная загрузка
        videoEl.load();

        // Если данные уже готовы/прилетят сразу — попробуем применить материал
        const plane = videoPlane;
        setTimeout(() => {
          try { ensureVideoMaterialApplied(plane); } catch (_) { }
        }, 0);
        setTimeout(() => {
          try { ensureVideoMaterialApplied(plane); } catch (_) { }
        }, 100);
      } catch (error) {
        console.error('❌ Ошибка установки src для недостающего видео:', error);
      }
    } else {

    }

  }

  initializeAFrame() {
    // Создаем A-Frame сцену
    this.aframeScene = document.createElement('a-scene');
    this.aframeScene.setAttribute('embedded', 'true');
    this.aframeScene.setAttribute('style', 'width: 100%; height: 100%; cursor: grab; background: #000000 !important;'); // ИСПРАВЛЕНИЕ: Устанавливаем черный фон
    this.aframeScene.setAttribute('cursor', 'rayOrigin: mouse');
    this.aframeScene.setAttribute('raycaster', 'objects: .interactive');
    this.aframeScene.setAttribute('vr-mode-ui', 'enabled: false');
    this.aframeScene.setAttribute('background', 'color: #000000'); // ИСПРАВЛЕНИЕ: Устанавливаем черный фон

    // Создаем assets для шрифтов
    const assets = document.createElement('a-assets');

    // Удаляем проблематичную загрузку Roboto
    // const robotoFont = document.createElement('a-asset-item');
    // ...

    this.aframeScene.appendChild(assets);

    // Создаем камеру
    this.aframeCamera = document.createElement('a-entity');
    this.aframeCamera.setAttribute('camera', 'fov: 80; zoom: 1');
    this.aframeCamera.setAttribute('look-controls', {
      enabled: true,
      reverseMouseDrag: false,
      touchEnabled: true,
      mouseEnabled: true,
      pointerLockEnabled: false,
      magicWindowTrackingEnabled: false
    });
    this.aframeCamera.setAttribute('wasd-controls', 'enabled: false');
    this.aframeCamera.id = 'camera';
    this.aframeScene.appendChild(this.aframeCamera);

    // НЕ создаем курсор - убираем центральный кружок
    // const cursor = document.createElement('a-cursor');
    // ...

    // Создаем элемент неба для панорамы
    this.aframeSky = document.createElement('a-sky');
    this.aframeSky.setAttribute('color', '#000000'); // Черный по умолчанию
    this.aframeSky.setAttribute('opacity', '1'); // Всегда показываем небо
    this.aframeScene.appendChild(this.aframeSky);

    // Добавляем сцену в контейнер
    this.container.appendChild(this.aframeScene);

    // Убираем фон A-Frame после загрузки
    this.aframeScene.addEventListener('renderstart', () => {
      this.removeLAFrame();
      // Добавляем глобальные обработчики для отладки событий мыши
      this.setupGlobalMouseHandlers();
    });

    // Инициализируем координатный менеджер после создания сцены
    this.initializeCoordinateManager();

    // Инициализируем обработчики событий после создания сцены с небольшой задержкой
    setTimeout(() => {
      this.setupEventHandlers();
      this.setupZoomControls(); // Добавляем поддержку зума колесиком мыши
      this.updateZoomIndicator(80); // Инициализируем индикатор зума

      // Настраиваем обработчики пользовательского взаимодействия для паузы авторотации
      this._setupAutorotateUserInteractivity();
    }, 100);

    // Подключаем кнопку debug-overlay, если она есть
    setTimeout(() => {
      try {
        const dbgBtn = document.getElementById('debug-toggle-btn');
        const dbgBox = document.getElementById('debug-overlay');
        if (dbgBtn && dbgBox) {
          dbgBtn.addEventListener('click', () => {
            dbgBox.style.display = dbgBox.style.display === 'block' ? 'none' : 'block';
            try {
              const mesh = this.aframeSky && this.aframeSky.getObject3D && this.aframeSky.getObject3D('mesh');
              const canvas = this.aframeScene && this.aframeScene.querySelector && this.aframeScene.querySelector('canvas');
              this.updateDebugOverlay({ stage: 'idle', src: this.aframeSky && this.aframeSky.getAttribute && this.aframeSky.getAttribute('src'), meshHasMap: !!(mesh && mesh.material && mesh.material.map), canvasRect: canvas ? canvas.getBoundingClientRect() : null });
            } catch (e) { /* ignore */ }
          });
        }
      } catch (e) { console.warn('Не удалось зарегистрировать debug toggle:', e); }
    }, 500);

  }

  removeLAFrame() {
    // Удаляем все элементы загрузчика A-Frame
    const loader = document.querySelector('.a-loader');
    if (loader) {
      loader.style.display = 'none';
      loader.remove();
    }

    const loaderTitle = document.querySelector('.a-loader-title');
    if (loaderTitle) {
      loaderTitle.style.display = 'none';
      loaderTitle.remove();
    }

    // Удаляем кнопку VR
    const vrButton = document.querySelector('.a-enter-vr-button');
    if (vrButton) {
      vrButton.style.display = 'none';
      vrButton.remove();
    }

    // Убираем фон с canvas
    const canvases = document.querySelectorAll('canvas');
    canvases.forEach(canvas => {
      canvas.style.background = '#000000'; // ИСПРАВЛЕНИЕ: Устанавливаем черный фон вместо transparent
      canvas.style.backgroundColor = '#000000'; // ИСПРАВЛЕНИЕ: Устанавливаем черный фон
    });

    // Убираем фон сцены Three.js и устанавливаем черный
    if (this.aframeScene && this.aframeScene.object3D && this.aframeScene.object3D.background) {
      this.aframeScene.object3D.background = new THREE.Color(0x000000); // ИСПРАВЛЕНИЕ: Устанавливаем черный фон
    }

    // Устанавливаем черный непрозрачный фон для renderer Three.js
    setTimeout(() => {
      if (this.aframeScene && this.aframeScene.renderer) {
        this.aframeScene.renderer.setClearColor(0x000000, 1); // Черный непрозрачный фон
        this.aframeScene.renderer.alpha = false;
      }
    }, 100);

  }

  // === Глобальный индикатор загрузки ===
  showGlobalLoading(label = 'Загрузка панорам...') {
    const box = document.getElementById('futuristic-progress');
    if (!box) return;
    const labelEl = box.querySelector('.label');
    if (labelEl) labelEl.textContent = label;
    box.style.display = 'flex';
  }

  hideGlobalLoading() {
    const box = document.getElementById('futuristic-progress');
    if (!box) return;
    box.style.display = 'none';
  }

  setupGlobalMouseHandlers() {
    // Добавляем глобальные обработчики для отладки и резервной обработки событий
    const canvas = this.aframeScene.querySelector('canvas');
    if (canvas) {

      canvas.addEventListener('contextmenu', (e) => {

        // Всегда предотвращаем стандартное контекстное меню
        e.preventDefault();

        // ВАЖНО: проверяем, не обработал ли уже событие маркер
        if (this._contextMenuHandled) {

          return;
        }

        // ИСПРАВЛЯЕМ: НЕ проверяем глобальную блокировку для contextmenu
        // Контекстное меню должно работать независимо от системы перетаскивания

        // ИСПРАВЛЯЕМ: используем координатный менеджер для определения позиции

        const intersection = this.getIntersectionPoint(e);

        if (intersection) {

          // Проверяем, есть ли маркер рядом с позицией клика
          const nearestMarker = this.findNearestMarker(intersection);

          if (nearestMarker) {

            // Устанавливаем флаг обработки ПЕРЕД вызовом функции
            this._contextMenuHandled = true;

            this.handleMarkerRightClick(e, nearestMarker.element, nearestMarker.hotspot);

            // Сбрасываем флаг после завершения обработки
            setTimeout(() => {
              this._contextMenuHandled = false;

            }, 300);

            // КРИТИЧЕСКИ ВАЖНО: НЕМЕДЛЕННО ПРЕРЫВАЕМ ВЫПОЛНЕНИЕ

            return;
          }

          // Маркер НЕ найден - показываем меню создания

          this.handleCanvasRightClick(e);
          return;
        }

        // Intersection НЕ получен - показываем меню создания

        this.handleCanvasRightClick(e);
        return;

      });

      // ДВОЙНОЙ КЛИК ОТКЛЮЧЕН ПО ПРОСЬБЕ ПОЛЬЗОВАТЕЛЯ
      /*
      canvas.addEventListener('dblclick', (e) => {

          // Проверяем глобальную блокировку dblclick
          if (this._dblClickHandled) {

              e.preventDefault();
              return;
          }
          
          // Проверяем, попали ли мы на маркер
          this.handleCanvasDoubleClick(e);
      });
      */      // КРИТИЧЕСКИ ВАЖНЫЙ обработчик mousedown в CAPTURE фазе для МГНОВЕННОЙ блокировки
      canvas.addEventListener('mousedown', (e) => {
        // МГНОВЕННАЯ ГЛОБАЛЬНАЯ БЛОКИРОВКА при правом клике
        const isRightClick = (e.button === 2) || (e.which === 3) || (e.buttons === 2);

        if (isRightClick) {
          // НЕМЕДЛЕННАЯ глобальная блокировка ТОЛЬКО системы перетаскивания
          // НЕ блокируем контекстное меню!
          window._dragSystemBlocked = true;

          setTimeout(() => {
            window._dragSystemBlocked = false;

          }, 200);
        }

        // Флаг для отслеживания навигации по сцене
        this._isNavigating = false;

        // Проверяем, кликнули ли по углу изменения размера
        if (!isRightClick) {
          const resizeHandle = this.getResizeHandleAt(e);
          if (resizeHandle && !this._isResizing) {

            // Сохраняем информацию о текущем изменении размера
            this._currentResizeHandle = resizeHandle;

            // Запускаем изменение размера
            this.startResize(
              resizeHandle.marker,
              resizeHandle.videoPlane,
              resizeHandle.hotspot,
              resizeHandle.corner,
              e
            );

            e.stopPropagation();
            e.preventDefault();
            return;
          }

          // Проверяем, кликнули ли по кнопке вращения
          const rotationHandle = this.getRotationHandleAt(e);
          if (rotationHandle) {

            this.rotateVideoArea(
              rotationHandle.marker,
              rotationHandle.videoPlane,
              rotationHandle.hotspot,
              rotationHandle.action
            );

            e.stopPropagation();
            e.preventDefault();
            return;
          }

          // ТОЛЬКО ПОСЛЕ ВСЕХ ПРОВЕРОК проверяем зону перемещения
          const moveZone = this.getMoveZoneAt(e);
          if (moveZone && this.coordinateManager) {

            // Запускаем перетаскивание видео-области
            this.coordinateManager.startVideoAreaDragging(
              moveZone.marker,
              moveZone.videoPlane,
              moveZone.hotspot,
              e
            );

            e.stopPropagation();
            e.preventDefault();
            return;
          }

          // Если не попали ни в какую специальную зону - это навигация по сцене
          if (!isRightClick) {

            this._isNavigating = true;

            // Устанавливаем курсор для навигации
            canvas.style.cursor = 'move';
            document.body.style.cursor = 'move';

          }
        }

        if (isRightClick) {

          // АГРЕССИВНАЯ блокировка систем перетаскивания для правого клика
          this._blockDraggingForRightClick = true;
          this._rightClickInProgress = true;
          this._lastRightClickTime = Date.now(); // Важно для CoordinateManager

          // Уведомляем CoordinateManager о правом клике
          if (this.coordinateManager) {
            this.coordinateManager._rightClickDetected = true;
            setTimeout(() => {
              this.coordinateManager._rightClickDetected = false;
            }, 500);
          }

          // Блокировка на достаточное время
          setTimeout(() => {
            this._blockDraggingForRightClick = false;
            this._rightClickInProgress = false;
          }, 800);

          // Сохраняем информацию о правом клике для последующего contextmenu
          this._rightClickDetected = true;
          setTimeout(() => {
            this._rightClickDetected = false;
          }, 1500);
        }
      }, true); // CAPTURE фаза - КРИТИЧЕСКИ ВАЖНО для перехвата ПЕРЕД A-Frame!

      // Добавляем обработчик mousemove для изменения курсора
      canvas.addEventListener('mousemove', (e) => {
        // ИСПРАВЛЯЕМ: сохраняем глобальную позицию мыши для функции isMouseOverMarker
        window._lastMousePosition = { x: e.clientX, y: e.clientY };

        if (this._isResizing || (this.coordinateManager && this.coordinateManager.isDragging)) {
          return; // Не меняем курсор во время операций
        }

        // Если идет навигация - оставляем курсор move
        if (this._isNavigating) {
          return; // Не меняем курсор во время навигации
        }

        let newCursor = 'default';

        // ВАЖНО: проверяем элементы по приоритету - от самых специфических к общим

        // 1. Углы изменения размера (самый высокий приоритет)
        const resizeHandle = this.getResizeHandleAt(e);
        if (resizeHandle) {
          const corner = resizeHandle.corner;

          switch (corner) {
            case 'top-left':
              newCursor = 'nw-resize';

              break;
            case 'top-right':
              newCursor = 'ne-resize';

              break;
            case 'bottom-left':
              newCursor = 'ne-resize';

              break;
            case 'bottom-right':
              newCursor = 'nw-resize';

              break;
          }
        } else {
          // 2. Кнопки вращения
          const rotationHandle = this.getRotationHandleAt(e);
          if (rotationHandle) {

            // Используем курсоры с круглыми стрелками для поворотов
            if (rotationHandle.action === 'rotate-left') {
              newCursor = 'url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns=\'http://www.w3.org/2000/svg\' width=\'24\' height=\'24\' viewBox=\'0 0 24 24\'%3E%3Cpath d=\'M12,5V1L7,6L12,11V7A6,6 0 0,1 18,13A6,6 0 0,1 12,19A6,6 0 0,1 6,13H4A8,8 0 0,0 12,21A8,8 0 0,0 20,13A8,8 0 0,0 12,5Z\' fill=\'%23ffffff\'/%3E%3C/svg%3E") 12 12, auto';

            } else if (rotationHandle.action === 'rotate-right') {
              newCursor = 'url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns=\'http://www.w3.org/2000/svg\' width=\'24\' height=\'24\' viewBox=\'0 0 24 24\'%3E%3Cpath d=\'M12,5V1L17,6L12,11V7A6,6 0 0,0 6,13A6,6 0 0,0 12,19A6,6 0 0,0 18,13H20A8,8 0 0,1 12,21A8,8 0 0,1 4,13A8,8 0 0,1 12,5Z\' fill=\'%23ffffff\'/%3E%3C/svg%3E") 12 12, auto';

            } else {
              newCursor = 'ew-resize'; // fallback
            }
          } else {
            // 3. Зона перемещения (самый низкий приоритет)
            const moveZone = this.getMoveZoneAt(e);
            if (moveZone) {

              newCursor = 'move';
            }
          }
        }

        // Обновляем курсор только если он изменился
        if (canvas.style.cursor !== newCursor) {
          canvas.style.cursor = newCursor;
          document.body.style.cursor = newCursor; // Дублируем для надежности

        }
      });

      // Добавляем обработчик mouseup для сброса навигации
      canvas.addEventListener('mouseup', (e) => {
        if (this._isNavigating) {

          this._isNavigating = false;

          // Возвращаем курсор по умолчанию
          canvas.style.cursor = 'default';
          document.body.style.cursor = 'default';

        }
      });

      // Добавляем обработчик mouseleave для сброса навигации при уходе мыши с canvas
      canvas.addEventListener('mouseleave', (e) => {
        if (this._isNavigating) {

          this._isNavigating = false;

          // Возвращаем курсор по умолчанию
          canvas.style.cursor = 'default';
          document.body.style.cursor = 'default';

        }
      });
    }

    // Добавляем глобальный обработчик клавиатуры для альтернативного редактирования и закрытия меню
    document.addEventListener('keydown', (e) => {
      // Escape - закрытие всех контекстных меню
      if (e.key === 'Escape') {

        this.hideAllContextMenus();
        this.cleanupAutoCloseHandlers();
        e.preventDefault();
        return;
      }

      // E + маркер под курсором = редактирование
      if (e.key === 'e' || e.key === 'E' || e.key === 'у' || e.key === 'У') {

        // Находим маркер под курсором мыши
        this.editMarkerUnderCursor();
      }
    });
  }

  handleMarkerRightClick(event, markerElement, hotspot) {

    // ИСПРАВЛЕНИЕ БАГА: убираем все drag-tooltips при ПКМ
    this.removeAllDragTooltips();

    // Показываем контекстное меню маркера (редактирования)

    this.showMarkerContextMenu(event.clientX, event.clientY, hotspot);

    // КРИТИЧЕСКИ ВАЖНО: предотвращаем дальнейшее распространение события
    event.stopPropagation();
    event.preventDefault();
  }

  // Новый метод для удаления всех drag-tooltips
  removeAllDragTooltips() {

    // Ищем все элементы с tooltip
    const allMarkers = document.querySelectorAll('a-plane[data-hotspot-id], a-entity[data-hotspot-id]');
    allMarkers.forEach(markerEl => {
      if (markerEl._domTooltip) {

        window.removeEventListener('mousemove', markerEl._domTooltipMove);
        try { 
          document.body.removeChild(markerEl._domTooltip); 
        } catch (_) { 

        }
        markerEl._domTooltip = null; 
        markerEl._domTooltipMove = null;
      }
    });
  }

  handleCanvasRightClick(event) {
    // НОВАЯ ЛОГИКА: более агрессивная обработка правых кликов

    // КРИТИЧЕСКИ ВАЖНО: проверяем, не было ли уже обработано контекстное меню
    if (this._contextMenuHandled) {

      return;
    }

    // Проверяем, не происходит ли перетаскивание
    if (this.coordinateManager && this.coordinateManager.isDragging) {

      return;
    }

    // Сохраняем информацию о последнем маркере для стабильности
    if (!this._lastHoveredMarker) {
      this._lastHoveredMarker = null;
    }

    // Если мы дошли до сюда, то это клик на пустом месте - показываем обычное контекстное меню

    this.showContextMenu(event.clientX, event.clientY);

  }

  handleCanvasDoubleClick(event) {
    // НОВАЯ ЛОГИКА: более агрессивная обработка двойных кликов

    // Проверяем, не происходит ли перетаскивание
    if (this.coordinateManager && this.coordinateManager.isDragging) {

      return;
    }

    // Проверяем, был ли клик непосредственно на маркере (через event.target)
    const target = event.target;
    if (target && target.closest && target.closest('.interactive')) {

      return;
    }

    // Проверяем все маркеры с видимыми tooltip'ами (они под курсором)
    const markers = this.aframeScene.querySelectorAll('[data-hotspot-id]');
    let targetMarker = null;

    markers.forEach(markerEl => {
      if (markerEl._tooltipVisible) {
        const hotspotId = markerEl.getAttribute('data-hotspot-id');
        const hotspot = this.hotspotManager ? this.hotspotManager.findHotspotById(hotspotId) : null;
        if (hotspot) {
          targetMarker = { element: markerEl, hotspot: hotspot };
        }
      }
    });

    if (targetMarker) {

      event.preventDefault();

      if (this.hotspotManager) {

        this.hotspotManager.editHotspot(targetMarker.hotspot.id);
      }
      return;
    }

    // Fallback: пробуем найти через intersection point
    const intersection = this.getIntersectionPoint(event);
    if (intersection) {
      // Находим ближайший маркер к точке клика
      const marker = this.findNearestMarker(intersection);
      if (marker && marker.hotspot) {

        event.preventDefault();

        if (this.hotspotManager) {

          this.hotspotManager.editHotspot(marker.hotspot.id);
        }
        return;
      }
    }

    // Если мы здесь, то double click был не на маркере
  }

  findNearestMarker(position) {
    // Находим маркер ближайший к указанной позиции

    const markers = this.aframeScene.querySelectorAll('[data-hotspot-id]');
    let nearestMarker = null;
    let nearestDistance = Infinity;

    markers.forEach((markerEl, index) => {
      const markerPosition = markerEl.getAttribute('position');
      if (markerPosition) {
        const distance = this.calculateDistance(position, markerPosition);
        console.log(`🎯 Маркер ${index}:`, markerEl.getAttribute('data-hotspot-id'),
          'позиция:', markerPosition, 'расстояние:', distance.toFixed(3));

        if (distance < nearestDistance && distance < 1.5) { // УВЕЛИЧИЛИ с 0.8 до 1.5 для лучшего обнаружения маркеров
          nearestDistance = distance;
          const hotspotId = markerEl.getAttribute('data-hotspot-id');
          const hotspot = this.hotspotManager ? this.hotspotManager.findHotspotById(hotspotId) : null;
          if (hotspot) {
            nearestMarker = {
              element: markerEl,
              hotspot: hotspot,
              distance: distance
            };

          }
        }
      }
    });

    if (nearestMarker) {

      return nearestMarker;
    } else {

      return null;
    }
  }

  editMarkerUnderCursor() {
    // Получаем все маркеры с видимыми tooltip'ами (они под курсором)
    const markers = this.aframeScene.querySelectorAll('[data-hotspot-id]');
    let targetMarker = null;

    markers.forEach(markerEl => {
      if (markerEl._tooltipVisible) {
        const hotspotId = markerEl.getAttribute('data-hotspot-id');
        const hotspot = this.hotspotManager ? this.hotspotManager.findHotspotById(hotspotId) : null;
        if (hotspot) {
          targetMarker = { element: markerEl, hotspot: hotspot };
        }
      }
    });

    if (targetMarker) {

      if (this.hotspotManager) {
        this.hotspotManager.editHotspot(targetMarker.hotspot.id);
      }
    } else {

    }
  }

  calculateDistance(pos1, pos2) {
    const dx = pos1.x - pos2.x;
    const dy = pos1.y - pos2.y;
    const dz = pos1.z - pos2.z;
    return Math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  async setPanorama(imageSrc) {
    console.log('🖼️ setPanorama() вызвана с imageSrc:', imageSrc ? imageSrc.slice(0, 100) + '...' : 'null');
    
    if (!this.aframeSky) {
      console.error('A-Frame sky элемент не найден');
      // ИСПРАВЛЕНИЕ: Устанавливаем черный фон при ошибке
      if (this.aframeScene) {
        this.aframeScene.setAttribute('background', 'color: #000000');
      }
      return false;
    }

    try {

      // Освобождаем предыдущий blob URL, если он был, при загрузке НЕ из data URL
      if (!imageSrc.startsWith('data:') && this._currentPanoramaBlobUrl) {
        try {
          URL.revokeObjectURL(this._currentPanoramaBlobUrl);
        } catch (revokeError) {
          console.warn('⚠️ Не удалось освободить предыдущий blob URL панорамы:', revokeError);
        }
        this._currentPanoramaBlobUrl = null;
      }

  try { this.updateDebugOverlay({ stage: 'start', src: imageSrc }); } catch (e) {}

      // ИСПРАВЛЕНИЕ: Устанавливаем черный фон до загрузки изображения
      this.aframeSky.setAttribute('color', '#000000');
      this.aframeSky.setAttribute('opacity', '1');
      this.aframeSky.setAttribute('visible', 'true');

      // Показываем индикатор загрузки панорамы
      this.showGlobalLoading('Загрузка панорамы...');

      // Спрятать индикатор после загрузки текстуры/ошибки/тайм-аута
      let hideTimer = setTimeout(() => {

        this.hideGlobalLoading();
  try { this.showToast('Тайм-аут загрузки панорамы — показ возможен позже. Проверьте сеть или формат файла.', 'warn', 8000); } catch (e) {}
        // ИСПРАВЛЕНИЕ: Устанавливаем черный фон при тайм-ауте
        this.aframeSky.setAttribute('color', '#000000');
        this.aframeSky.setAttribute('opacity', '1');
        this.aframeSky.setAttribute('visible', 'true');
      }, 15000); // Увеличиваем тайм-аут до 15 секунд

      // Более надежный способ отслеживания загрузки текстуры
      const textureLoadPromise = new Promise((resolve, reject) => {
        const onTextureLoadedOnce = () => {
          clearTimeout(hideTimer);
          this.hideGlobalLoading();
          this.aframeSky.removeEventListener('materialtextureloaded', onTextureLoadedOnce);
          // ИСПРАВЛЕНИЕ: Убедимся, что небо видимо после загрузки
          this.aframeSky.setAttribute('opacity', '1');
          this.aframeSky.setAttribute('visible', 'true');

          resolve();
        };
        
        const onErrorOnce = (error) => {
          clearTimeout(hideTimer);
          this.hideGlobalLoading();
          this.aframeSky.removeEventListener('materialerror', onErrorOnce);
          console.error('❌ Ошибка загрузки текстуры:', error);
          try { this.showToast('Ошибка загрузки панорамы. Смотрите консоль для деталей.', 'error', 9000); } catch (e) {}
          // ИСПРАВЛЕНИЕ: Устанавливаем черный фон при ошибке
          this.aframeSky.setAttribute('color', '#000000');
          this.aframeSky.setAttribute('opacity', '1');
          this.aframeSky.setAttribute('visible', 'true');
          reject(error);
        };
        
        // Добавляем обработчики событий
        this.aframeSky.addEventListener('materialtextureloaded', onTextureLoadedOnce);
        this.aframeSky.addEventListener('materialerror', onErrorOnce);
        
        // Добавляем тайм-аут для обработки случаев, когда события не срабатывают
        setTimeout(() => {
          // Проверяем, была ли уже загрузка
          if (!this.aframeSky._textureLoaded) {
            clearTimeout(hideTimer);
            this.hideGlobalLoading();
            this.aframeSky.removeEventListener('materialtextureloaded', onTextureLoadedOnce);
            this.aframeSky.removeEventListener('materialerror', onErrorOnce);
            // Убедимся, что небо видимо
            this.aframeSky.setAttribute('opacity', '1');
            this.aframeSky.setAttribute('visible', 'true');

            resolve();
          }
        }, 5000);
      });

      // Проверяем, является ли это Data URL (загруженный файл)
      if (imageSrc.startsWith('data:')) {

        // ИСПРАВЛЕНИЕ: Конвертируем Data URL в Blob без использования fetch
        try {
          // Функция для конвертации Data URL в Blob
          function dataURLtoBlob(dataurl) {
            var arr = dataurl.split(',');
            var mime = arr[0].match(/:(.*?);/)[1];
            var bstr = atob(arr[1]);
            var n = bstr.length;
            var u8arr = new Uint8Array(n);
            while (n--) {
              u8arr[n] = bstr.charCodeAt(n);
            }
            return new Blob([u8arr], { type: mime });
          }

          // Конвертируем Data URL в Blob
          if (this._currentPanoramaBlobUrl) {
            try {
              URL.revokeObjectURL(this._currentPanoramaBlobUrl);
            } catch (revokeError) {
              console.warn('⚠️ Не удалось освободить предыдущий blob URL панорамы:', revokeError);
            }
            this._currentPanoramaBlobUrl = null;
          }
          const blob = dataURLtoBlob(imageSrc);
          const blobUrl = URL.createObjectURL(blob);
          this._currentPanoramaBlobUrl = blobUrl;

          // Убираем цвет перед установкой изображения и принудительно сбрасываем src
          this.aframeSky.removeAttribute('color');
          try { this.aframeSky.setAttribute('src', ''); } catch(e) {}
          
          // Принудительно очищаем кэш материала A-Frame для data: URL
          try {
            const mesh = this.aframeSky.getObject3D && this.aframeSky.getObject3D('mesh');
            if (mesh && mesh.material && mesh.material.map) {
              mesh.material.map.dispose(); // Освобождаем старую текстуру
              mesh.material.map = null;
              mesh.material.needsUpdate = true;
            }
          } catch (e) {}
          
          // Принудительно очищаем системный кэш материалов A-Frame
          try {
            if (this.aframeScene && this.aframeScene.systems && this.aframeScene.systems.material) {
              this.aframeScene.systems.material.uncacheTexture(imageSrc);
              this.aframeScene.systems.material.uncacheTexture(blobUrl);
            }
          } catch (e) {}
          
          // Небольшая пауза, чтобы A-Frame успел обработать очистку
          await new Promise(r => setTimeout(r, 40));
          this.aframeSky.setAttribute('src', blobUrl);
          this.aframeSky.setAttribute('opacity', '1');
          this.aframeSky.setAttribute('visible', 'true');
          this.currentPanorama = imageSrc;

          // Ждем загрузку текстуры или тайм-аут
          await Promise.race([
            textureLoadPromise,
            new Promise((_, reject) => 
              setTimeout(() => reject(new Error('Тайм-аут загрузки текстуры')), 15000)
            )
          ]);

          // FALLBACK: проверяем, создал ли A-Frame материал с текстурой
          try {
            const mesh = this.aframeSky.getObject3D && this.aframeSky.getObject3D('mesh');
            console.log('🔧 Проверяем mesh после загрузки:', mesh ? 'найден' : 'отсутствует');
            if (mesh && mesh.material) {
              console.log('🎨 Material после загрузки:', mesh.material.type, 'map:', mesh.material.map ? 'есть' : 'нет');
              if (!mesh.material.map && typeof THREE !== 'undefined') {
                console.log('🛠️ Принудительно создаем текстуру из blob URL');
                const loader = new THREE.TextureLoader();
                loader.load(blobUrl, (tex) => {
                  mesh.material.map = tex;
                  mesh.material.needsUpdate = true;
                  console.log('✅ Текстура успешно загружена через TextureLoader');
                }, undefined, (err) => {
                  console.error('❌ Ошибка загрузки текстуры через TextureLoader:', err);
                });
              }
            } else {
              console.warn('⚠️ Mesh или material не найдены после загрузки');
            }
          } catch (e) {
            console.error('❌ Ошибка в FALLBACK обработке:', e);
          }

          // Финальная проверка состояния
          const finalMesh = this.aframeSky.getObject3D && this.aframeSky.getObject3D('mesh');
          const hasMap = !!(finalMesh && finalMesh.material && finalMesh.material.map);
          console.log('🏁 Завершение загрузки data URL:', { 
            meshFound: !!finalMesh, 
            materialFound: !!(finalMesh && finalMesh.material),
            mapFound: hasMap,
            skyVisible: this.aframeSky.getAttribute('visible'),
            skySrc: this.aframeSky.getAttribute('src')
          });
          
          // Скрываем уведомление об успешной загрузке — не показываем toast
          try { this.updateDebugOverlay({ stage: 'loaded', src: blobUrl, meshHasMap: hasMap }); } catch (e) {}
          return true;
        } catch (blobError) {
          console.error('❌ Ошибка конвертации в blob URL:', blobError);
          clearTimeout(hideTimer);
          this.hideGlobalLoading();
          // ИСПРАВЛЕНИЕ: Устанавливаем черный фон при ошибке
          this.aframeSky.setAttribute('color', '#000000');
          this.aframeSky.setAttribute('opacity', '1');
          this.aframeSky.setAttribute('visible', 'true');
          return false;
        }
      }

      // Если это URL файла — создаём/используем img в a-assets и привязываем a-sky к id

      // Генерируем безопасный ID для asset
      const safeId = 'panorama-asset-' + Math.abs(this._hashString(imageSrc)).toString();

      // Создаем a-assets если нужно
      let assets = this.aframeScene.querySelector('a-assets');
      if (!assets) {
        assets = document.createElement('a-assets');
        this.aframeScene.appendChild(assets);
      }

      // Проверяем, есть ли уже img с таким id
      let img = document.getElementById(safeId);
      if (!img) {
        img = document.createElement('img');
        img.id = safeId;
        img.crossOrigin = 'anonymous';
        img.style.display = 'none';
        assets.appendChild(img);
      }

      // Устанавливаем src и слушаем события загрузки/ошибки
      const loadPromise = new Promise((resolve, reject) => {
        const onLoad = () => {
          img.removeEventListener('load', onLoad);
          img.removeEventListener('error', onError);
          resolve();
        };
        const onError = (e) => {
          img.removeEventListener('load', onLoad);
          img.removeEventListener('error', onError);
          reject(new Error('Ошибка загрузки изображения как asset'));
        };
        img.addEventListener('load', onLoad);
        img.addEventListener('error', onError);
      });

      // Устанавливаем src с принудительным обходом кэша для temp-file URLs
      if (imageSrc.includes('/api/temp-file/')) {
        img.src = imageSrc + '?t=' + Date.now() + '&nocache=' + Math.random();
      } else {
        img.src = imageSrc;
      }
      
      // Отладка загрузки изображения
      console.log('🖼️ Загружаем панораму:', imageSrc);
      console.log('📝 Asset ID:', safeId);
      console.log('🔗 Final img.src:', img.src);

      // Дождёмся декодирования изображения до привязки к a-sky, чтобы избежать "image is incomplete"
      let decoded = false;
      try {
        if (typeof img.decode === 'function') {
          await Promise.race([
            img.decode(),
            new Promise((_, rej) => setTimeout(() => rej(new Error('decode timeout')), 15000))
          ]);
          decoded = true;
        }
      } catch (e) {
        // Если decode() недоступен/упал — ждём хотя бы load
        try {
          await Promise.race([
            loadPromise,
            new Promise((_, rej) => setTimeout(() => rej(new Error('load timeout')), 15000))
          ]);
        } catch (e2) {
          // Ничего — дадим шанс A-Frame загрузить самостоятельно ниже
        }
      }

      // Убираем цвет перед установкой изображения и принудительно сбрасываем src у a-sky
      this.aframeSky.removeAttribute('color');
      try { this.aframeSky.setAttribute('src', ''); } catch(e) {}
      
      // Принудительно очищаем кэш материала A-Frame
      try {
        const mesh = this.aframeSky.getObject3D && this.aframeSky.getObject3D('mesh');
        if (mesh && mesh.material && mesh.material.map) {
          mesh.material.map.dispose(); // Освобождаем старую текстуру
          mesh.material.map = null;
          mesh.material.needsUpdate = true;
        }
      } catch (e) {}
      
      // Принудительно очищаем системный кэш материалов A-Frame
      try {
        if (this.aframeScene && this.aframeScene.systems && this.aframeScene.systems.material) {
          const url = imageSrc.includes('/api/temp-file/') ? imageSrc.split('?')[0] : imageSrc;
          this.aframeScene.systems.material.uncacheTexture(url);
          this.aframeScene.systems.material.uncacheTexture(imageSrc);
        }
      } catch (e) {}
      
      await new Promise(r => setTimeout(r, 40));
      this.aframeSky.setAttribute('src', `#${safeId}`);
      this.aframeSky.setAttribute('opacity', '1'); // Показываем небо после загрузки
      this.aframeSky.setAttribute('visible', 'true');
      this.currentPanorama = imageSrc;
      
      // Отладка A-Frame sky
      console.log('🌌 A-Sky src установлен:', `#${safeId}`);
      console.log('👁️ A-Sky visible:', this.aframeSky.getAttribute('visible'));
      console.log('🔍 A-Sky opacity:', this.aframeSky.getAttribute('opacity'));

      // Ждём либо загрузки asset (на всякий случай), либо texture события, либо тайм-аута
      await Promise.race([
        loadPromise,
        textureLoadPromise,
        new Promise((_, reject) => setTimeout(() => reject(new Error('Тайм-аут загрузки текстуры')), 15000))
      ]);

      // FALLBACK: если A-Frame не создал material.map — попробуем создать текстуру из <img> или через TextureLoader
      try {
        const mesh = this.aframeSky.getObject3D && this.aframeSky.getObject3D('mesh');
        
        // Отладка mesh и material
        console.log('🔧 A-Frame mesh:', mesh ? 'найден' : 'не найден');
        if (mesh && mesh.material) {
          console.log('🎨 Material:', mesh.material);
          console.log('🗺️ Material map:', mesh.material.map ? 'есть' : 'нет');
          if (mesh.material.map && mesh.material.map.image) {
            console.log('📸 Texture image размер:', mesh.material.map.image.width + 'x' + mesh.material.map.image.height);
          }
        }
        
        // Если a-sky потерял src (null), выставим его заново — иногда атрибут удаляется A-Frame
        const currentSrc = this.aframeSky.getAttribute('src');
        if (!currentSrc) {
          try {
            if (typeof blobUrl !== 'undefined' && blobUrl) {
              this.aframeSky.setAttribute('src', blobUrl);
            } else if (typeof safeId !== 'undefined' && safeId) {
              this.aframeSky.setAttribute('src', `#${safeId}`);
            } else {
              // последняя надежда — пробуем установить исходный URL
              this.aframeSky.setAttribute('src', imageSrc);
            }

          } catch (e) {

          }
        }
        // Дадим A-Frame короткую паузу после (возможной) повторной установки src
        await new Promise(r => setTimeout(r, 180));

        // Принудительно обновляем материал если нет текстуры
        if (mesh && mesh.material && !mesh.material.map) {
          console.log('🛠️ Принудительно создаем текстуру из img element');
          const imgElement = document.getElementById(safeId);
          if (imgElement && imgElement.complete && imgElement.naturalWidth > 0) {
            try {
              // Используем глобальный THREE из A-Frame
              const texture = new window.THREE.Texture(imgElement);
              texture.needsUpdate = true;
              texture.flipY = false; // Важно для правильной ориентации
              // Исправлено: используем RGBAFormat или RGB если недоступен
              texture.format = window.THREE.RGBAFormat || window.THREE.RGBFormat;
              mesh.material.map = texture;
              mesh.material.needsUpdate = true;
              console.log('✅ Текстура принудительно создана');
            } catch (e) {
              console.error('❌ Ошибка создания текстуры:', e);
            }
          } else {
            console.log('❌ Img element не готов или не найден');
          }
        }

        // Защита от сброса материала - проверяем каждые 500мс
        const protectMaterial = () => {
          try {
            const currentMesh = this.aframeSky.getObject3D && this.aframeSky.getObject3D('mesh');
            if (currentMesh && currentMesh.material && !currentMesh.material.map) {
              const imgElement = document.getElementById(safeId);
              if (imgElement && imgElement.complete && imgElement.naturalWidth > 0) {
                console.log('🔧 Восстанавливаем потерянную текстуру');
                const texture = new window.THREE.Texture(imgElement);
                texture.needsUpdate = true;
                texture.flipY = false;
                // Исправлено: используем RGBAFormat или RGB если недоступен
                texture.format = window.THREE.RGBAFormat || window.THREE.RGBFormat;
                currentMesh.material.map = texture;
                currentMesh.material.needsUpdate = true;
              }
            }
          } catch (e) {
            console.error('❌ Ошибка защиты материала:', e);
          }
        };

        // Запускаем защиту на 5 секунд
        const protectionInterval = setInterval(protectMaterial, 500);
        setTimeout(() => clearInterval(protectionInterval), 5000);

        if (mesh && (!mesh.material || !mesh.material.map)) {
          // Попробуем взять изображение из a-assets
          const assetImg = document.getElementById(safeId);
          if (assetImg && typeof THREE !== 'undefined') {
            try {
              const tex = new THREE.Texture(assetImg);
              tex.needsUpdate = true;
              if (mesh.material) {
                mesh.material.map = tex;
                mesh.material.needsUpdate = true;
              } else {
                mesh.material = new THREE.MeshBasicMaterial({ map: tex });
              }

            } catch (e) {

            }
          } else if (typeof THREE !== 'undefined') {
            // Последняя попытка — использовать TextureLoader по оригинальному URL
            await new Promise((res) => {
              try {
                const loader = new THREE.TextureLoader();
                loader.load(imageSrc, (tex) => {
                  try {
                    if (mesh.material) {
                      mesh.material.map = tex;
                      mesh.material.needsUpdate = true;
                    } else {
                      mesh.material = new THREE.MeshBasicMaterial({ map: tex });
                    }

                  } catch (e) { console.warn('⚠️ Ошибка при применении текстуры (fallback imageSrc):', e); }
                  res();
                }, undefined, (err) => { console.warn('⚠️ TextureLoader не смог загрузить imageSrc:', err); res(); });
              } catch (e) { console.warn('⚠️ TextureLoader final fallback failed:', e); res(); }
            });
          }
        }
      } catch (e) {

      }

  // Принудительное обновление текстуры/рендера после asset load
  try {
    const mesh2 = this.aframeSky.getObject3D && this.aframeSky.getObject3D('mesh');
    if (mesh2 && mesh2.material) {
      if (mesh2.material.map) mesh2.material.map.needsUpdate = true;
      mesh2.material.needsUpdate = true;
    }
    if (this.aframeScene && this.aframeScene.renderer && this.aframeScene.camera) {
      try { this.aframeScene.renderer.render(this.aframeScene.object3D, this.aframeScene.camera); } catch (e) {}
    }
  } catch (e) { console.warn('⚠️ Принудительное обновление текстуры не удалось:', e); }

  try { this.updateDebugOverlay({ stage: 'loaded', src: imageSrc, meshHasMap: !!(this.aframeSky.getObject3D && this.aframeSky.getObject3D('mesh') && this.aframeSky.getObject3D('mesh').material && this.aframeSky.getObject3D('mesh').material.map) }); } catch (e) {}
  // Скрываем уведомление об успешной загрузке — не показываем toast
      return true;

    } catch (error) {
      console.error('❌ Ошибка при загрузке панорамы:', error.message);
      console.error('📁 Путь к файлу:', imageSrc);
  try { this.showToast('Не удалось загрузить панораму — проверьте путь/формат/права доступа.', 'error', 9000); } catch (e) {}
      try { this.updateDebugOverlay({ stage: 'error', src: imageSrc, error: error.message }); } catch (e) {}
      
      // ИСПРАВЛЕНИЕ: Устанавливаем черный фон при ошибке загрузки
      this.aframeSky.setAttribute('color', '#000000');
      this.aframeSky.setAttribute('opacity', '1');
      this.aframeSky.setAttribute('visible', 'true');
      this.hideGlobalLoading();
      return false;
    }
  }

  // === Авторотация камеры ===
  enableAutorotate(enabled, speed = null, idleDelay = null) {
    this.autorotateEnabled = !!enabled;
    if (speed !== null && !isNaN(speed)) this.autorotateSpeed = speed;
    if (idleDelay !== null && !isNaN(idleDelay)) this.autorotateIdleDelay = idleDelay;

    if (this.autorotateEnabled) {
      this._startAutorotateLoop();
    } else {
      this._stopAutorotateLoop();
    }
  }

  _setupAutorotateUserInteractivity() {
    const onInteract = () => {
      this._lastUserInteraction = Date.now();
      this._autorotatePaused = true;
    };
    const sceneEl = this.aframeScene;
    if (!sceneEl) return;
    const canvas = sceneEl.querySelector('canvas');
    const target = canvas || sceneEl;
    ['mousedown', 'wheel', 'touchstart', 'keydown'].forEach(evt => {
      target.addEventListener(evt, onInteract, { passive: true });
    });
  }

  _startAutorotateLoop() {
    if (this._autorotateRaf) return;
    this._autorotatePaused = false;
    this._autorotateLastTs = performance.now();
    const loop = (ts) => {
      if (!this.autorotateEnabled) { this._autorotateRaf = null; return; }
      const dt = Math.max(0, (ts - this._autorotateLastTs) / 1000);
      this._autorotateLastTs = ts;

      // Возобновляем после паузы по истечении idleDelay
      if (this._autorotatePaused) {
        if (Date.now() - this._lastUserInteraction >= this.autorotateIdleDelay) {
          this._autorotatePaused = false;
        }
      }

      if (!this._autorotatePaused && this.aframeCamera) {
        const rot = this.aframeCamera.getAttribute('rotation') || { x: 0, y: 0, z: 0 };
        const newY = rot.y + (this.autorotateSpeed * (180 / Math.PI)) * dt; // конвертируем рад/сек в град/сек
        this.aframeCamera.setAttribute('rotation', `${rot.x} ${newY} ${rot.z}`);
      }

      this._autorotateRaf = requestAnimationFrame(loop);
    };
    this._autorotateRaf = requestAnimationFrame(loop);
  }

  _stopAutorotateLoop() {
    if (this._autorotateRaf) {
      cancelAnimationFrame(this._autorotateRaf);
      this._autorotateRaf = null;
    }
  }

  /**
   * Инициализация координатного менеджера
   */
  initializeCoordinateManager() {
    this.coordinateManager.initialize(this.aframeScene);

  }

  setupEventHandlers() {
    // Обработка правого клика для контекстного меню
    this.container.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      this.showContextMenu(e.clientX, e.clientY, e);
    });

    // Закрытие контекстного меню при обычном клике
    this.container.addEventListener('click', (e) => {
      // ПОЛНОСТЬЮ ОТКЛЮЧАЕМ автоматическое закрытие в глобальном обработчике
      // Теперь меню закрывается только через специальные auto-close обработчики

      // НЕ вызываем this.hideContextMenu() - пусть меню остается видимым
      // Закрытие происходит только через auto-close обработчики в showMarkerContextMenu
    });
  }

  showContextMenu(x, y, event) {

    // СЕЛЕКТИВНОЕ удаление: удаляем только обычные контекстные меню, НЕ трогаем меню маркеров
    const existingGeneralMenus = document.querySelectorAll('.custom-context-menu');
    existingGeneralMenus.forEach(menu => {

      menu.remove();
    });

    const menu = document.createElement('div');
    menu.className = 'custom-context-menu';
    menu.style.left = x + 'px';
    menu.style.top = y + 'px';

    menu.innerHTML = `
            <button data-type="hotspot">🔗 Хотспот</button>
            <button data-type="info-point">ℹ️ Инфоточка</button>
            <button data-type="video-area">🎬 Видео-область</button>
  <button data-type="animated-object">🧩 Анимированный объект</button>
  <button data-type="iframe-3d">🪟 3D-iframe</button>
        `;

    document.body.appendChild(menu);

    // Обработчики для кнопок меню
    menu.querySelectorAll('button').forEach(btn => {
      btn.addEventListener('click', () => {
        const type = btn.dataset.type;

        // Получаем 3D координаты клика
        const intersection = this.getIntersectionPoint(event);
        if (!intersection) {

          return;
        }

        // Вызываем событие для main.js
        const customEvent = new CustomEvent('context-menu-add-hotspot', {
          detail: { type, position: `${intersection.x} ${intersection.y} ${intersection.z}` }
        });
        this.container.dispatchEvent(customEvent);

        menu.remove();
      });
    });

    // Закрытие меню при клике вне его
    setTimeout(() => {
      const closeHandler = (e) => {
        if (!menu.contains(e.target)) {
          menu.remove();
          document.removeEventListener('click', closeHandler);
        }
      };
      document.addEventListener('click', closeHandler);
    }, 0);
  }

  hideContextMenu() {
    // СЕЛЕКТИВНОЕ закрытие: закрываем только обычные контекстные меню
    const generalMenus = document.querySelectorAll('.custom-context-menu');
    generalMenus.forEach(menu => {

      menu.remove();
    });
  }

  // Небольшой toast для уведомлений в UI (временный, лёгкий)
  showToast(message, level = 'info', timeout = 6000) {
    try {
      const id = `viewer-toast-${Date.now()}`;
      const el = document.createElement('div');
      el.id = id;
      el.className = 'viewer-toast';
      const bg = level === 'error' ? 'rgba(204,51,51,0.95)' : (level === 'warn' ? 'rgba(238,165,60,0.95)' : 'rgba(50,50,50,0.9)');
  el.style.cssText = `position:fixed; right:80px; bottom:16px; z-index:2147483647; background:${bg}; color:#fff; padding:10px 14px; border-radius:6px; box-shadow:0 6px 18px rgba(0,0,0,0.4); font-family:Arial, sans-serif; font-size:13px; max-width:320px;`;
      el.textContent = message;
      document.body.appendChild(el);
      setTimeout(() => {
        try { el.style.transition = 'opacity 240ms ease'; el.style.opacity = '0'; } catch (e) {}
      }, Math.max(1200, timeout - 300));
      setTimeout(() => { try { document.body.removeChild(el); } catch (e) {} }, timeout);
    } catch (err) {

    }
  }

  /**
   * Определяет, кликнули ли по углу изменения размера видео-области
   */
  getResizeHandleAt(event) {
    const camera = this.aframeCamera;
    const scene = this.aframeScene;

    if (!camera || !scene || typeof THREE === 'undefined') {
      return null;
    }

    const rect = scene.canvas.getBoundingClientRect();
    const x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    const y = -((event.clientY - rect.top) / rect.height) * 2 + 1;

    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2(x, y);
    raycaster.setFromCamera(mouse, camera.getObject3D('camera'));

    // Находим все углы изменения размера
    const resizeHandles = this.aframeScene.querySelectorAll('.resize-handle');
    const intersectableObjects = [];

    resizeHandles.forEach(handle => {
      if (handle.object3D && handle.getAttribute('visible') !== 'false') {
        intersectableObjects.push(handle.object3D);
        // Запоминаем связь между object3D и элементом
        handle.object3D.userData.element = handle;
      }
    });

    if (intersectableObjects.length === 0) {
      return null;
    }

    const intersects = raycaster.intersectObjects(intersectableObjects, true);

    if (intersects.length > 0) {
      // ИСПРАВЛЯЕМ: берем САМОЕ БЛИЗКОЕ пересечение и проверяем, что это действительно resize handle
      const closest = intersects[0];
  const handleElement = (closest.object.userData && closest.object.userData.element) ? closest.object.userData.element : (closest.object.parent && closest.object.parent.userData && closest.object.parent.userData.element ? closest.object.parent.userData.element : undefined);

      if (handleElement && handleElement.classList.contains('resize-handle')) {
        const corner = handleElement.getAttribute('data-corner');
        const markerEl = handleElement.parentElement;

        if (corner && markerEl) {

          // Находим видео-область в этом маркере
          const videoPlane = markerEl.querySelector('[data-video-plane]');

          if (videoPlane) {
            // Находим hotspot по ID маркера
            const markerId = markerEl.getAttribute('data-marker-id');
            let hotspot = null;

            if (markerId && this.hotspotManager) {
              hotspot = this.hotspotManager.findHotspotById(markerId);
            }

            return {
              corner,
              handle: handleElement,
              marker: markerEl,
              videoPlane,
              hotspot,
              distance: closest.distance
            };
          }
        }
      }
    }

    return null;
  }

  /**
   * Выполняет raycast из позиции мыши и возвращает все пересечения
   */
  raycastFromMouse(event) {
    const camera = this.aframeCamera;
    const scene = this.aframeScene;

    if (!camera || !scene || typeof THREE === 'undefined') {
      return [];
    }

    const rect = scene.canvas.getBoundingClientRect();
    const x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    const y = -((event.clientY - rect.top) / rect.height) * 2 + 1;

    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2(x, y);
    raycaster.setFromCamera(mouse, camera.getObject3D('camera'));

    // Собираем все объекты сцены для пересечения
    const intersectableObjects = [];

    scene.querySelectorAll('a-entity').forEach(entity => {
      if (entity.object3D && entity.getAttribute('visible') !== 'false') {
        intersectableObjects.push(entity.object3D);
        entity.object3D.userData.element = entity;
      }
    });

    const intersects = raycaster.intersectObjects(intersectableObjects, true);
    return intersects;
  }

  /**
   * Определяет, кликнули ли по кнопке вращения видео-области
   */
  getRotationHandleAt(event) {
    const camera = this.aframeCamera;
    const scene = this.aframeScene;

    if (!camera || !scene || typeof THREE === 'undefined') {
      return null;
    }

    const rect = scene.canvas.getBoundingClientRect();
    const x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    const y = -((event.clientY - rect.top) / rect.height) * 2 + 1;

    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2(x, y);
    raycaster.setFromCamera(mouse, camera.getObject3D('camera'));

    // Находим все кнопки вращения
    const rotationHandles = this.aframeScene.querySelectorAll('.rotation-handle');
    const intersectableObjects = [];

    rotationHandles.forEach(handle => {
      if (handle.object3D && handle.getAttribute('visible') !== 'false') {
        intersectableObjects.push(handle.object3D);
        // Запоминаем связь между object3D и элементом
        handle.object3D.userData.element = handle;
      }
    });

    if (intersectableObjects.length === 0) {
      return null;
    }

    const intersects = raycaster.intersectObjects(intersectableObjects, true);

    if (intersects.length > 0) {
      const closest = intersects[0];
  const handleElement = (closest.object.userData && closest.object.userData.element) ? closest.object.userData.element : (closest.object.parent && closest.object.parent.userData && closest.object.parent.userData.element ? closest.object.parent.userData.element : undefined);

      if (handleElement) {
        const action = handleElement.getAttribute('data-rotation-action');
        const markerEl = handleElement.parentElement;

        if (action && markerEl) {

          // Находим видео-область в этом маркере
          const videoPlane = markerEl.querySelector('[data-video-plane]');

          if (videoPlane) {
            // Находим hotspot по ID маркера
            const markerId = markerEl.getAttribute('data-marker-id');
            let hotspot = null;

            if (markerId && this.hotspotManager) {
              hotspot = this.hotspotManager.findHotspotById(markerId);
            }

            return {
              action,
              handle: handleElement,
              marker: markerEl,
              videoPlane,
              hotspot,
              distance: closest.distance
            };
          }
        }
      }
    }

    return null;
  }

  /**
   * Определяет, кликнули ли по зоне перемещения видео-области
   */
  getMoveZoneAt(event) {
    const camera = this.aframeCamera;
    const scene = this.aframeScene;

    if (!camera || !scene || typeof THREE === 'undefined') {
      return null;
    }

    const rect = scene.canvas.getBoundingClientRect();
    const x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    const y = -((event.clientY - rect.top) / rect.height) * 2 + 1;

    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2(x, y);
    raycaster.setFromCamera(mouse, camera.getObject3D('camera'));

    // Находим все зоны перемещения
    const moveZones = this.aframeScene.querySelectorAll('.move-zone');
    const intersectableObjects = [];

    moveZones.forEach(zone => {
      if (zone.object3D && zone.getAttribute('visible') !== 'false') {
        intersectableObjects.push(zone.object3D);
        // Запоминаем связь между object3D и элементом
        zone.object3D.userData.element = zone;
      }
    });

    if (intersectableObjects.length === 0) {
      return null;
    }

    const intersects = raycaster.intersectObjects(intersectableObjects, true);

    if (intersects.length > 0) {
      const closest = intersects[0];
  const zoneElement = (closest.object.userData && closest.object.userData.element) ? closest.object.userData.element : (closest.object.parent && closest.object.parent.userData && closest.object.parent.userData.element ? closest.object.parent.userData.element : undefined);

      if (zoneElement) {
        const markerEl = zoneElement.parentElement;

        if (markerEl) {

          // Находим видео-область в этом маркере
          const videoPlane = markerEl.querySelector('[data-video-plane]');

          if (videoPlane) {
            // Находим hotspot по ID маркера
            const markerId = markerEl.getAttribute('data-marker-id');
            let hotspot = null;

            if (markerId && this.hotspotManager) {
              hotspot = this.hotspotManager.findHotspotById(markerId);
            }

            return {
              zone: zoneElement,
              marker: markerEl,
              videoPlane,
              hotspot,
              distance: closest.distance
            };
          }
        }
      }
    }

    return null;
  }

  getIntersectionPoint(event) {
    if (!this.aframeScene || !this.aframeCamera) {
      return null;
    }

    // Используем CoordinateManager если он доступен для максимальной точности
    if (this.coordinateManager && typeof this.coordinateManager.getMousePositionOnSphere === 'function') {

      const position = this.coordinateManager.getMousePositionOnSphere(event);
      if (position) {

        return position;
      }
    }

    // Fallback: используем собственный ray-casting
    const camera = this.aframeCamera;
    const scene = this.aframeScene;

    if (!camera || !scene || !scene.canvas) {

      return null;
    }

    // Получаем координаты мыши относительно canvas
    const rect = scene.canvas.getBoundingClientRect();
    const x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    const y = -((event.clientY - rect.top) / rect.height) * 2 + 1;

    // Создаем луч от камеры через THREE.js
    if (typeof THREE !== 'undefined') {
      const raycaster = new THREE.Raycaster();
      const mouse = new THREE.Vector2(x, y);

      raycaster.setFromCamera(mouse, camera.getObject3D('camera'));

      // Пересечение с невидимой сферой радиуса 10
      const sphereRadius = 10;
      const sphere = new THREE.Sphere(new THREE.Vector3(0, 0, 0), sphereRadius);
      const intersectionPoint = new THREE.Vector3();

      if (raycaster.ray.intersectSphere(sphere, intersectionPoint)) {

        return {
          x: intersectionPoint.x,
          y: intersectionPoint.y,
          z: intersectionPoint.z
        };
      }
    }

    // Последний fallback к старому методу

    const phi = (x * Math.PI);
    const theta = ((y + 1) * Math.PI / 2);

    const radius = 10;
    const position = {
      x: radius * Math.sin(theta) * Math.cos(phi),
      y: radius * Math.cos(theta),
      z: radius * Math.sin(theta) * Math.sin(phi)
    };

    return position;
  }

  createVisualMarker(hotspot) {
    if (!this.aframeScene) return;

    // ВАЖНО: Проверяем, не существует ли уже маркер с таким ID
    const existingMarker = document.getElementById(`marker-${hotspot.id}`);
    if (existingMarker) {

      return existingMarker;
    }

    const markerEl = document.createElement('a-entity');
    // Устанавливаем уникальный ID для DOM-элемента, связанный с ID хотспота
    markerEl.id = `marker-${hotspot.id}`;
    markerEl.setAttribute('data-hotspot-id', hotspot.id);
    markerEl.setAttribute('data-marker-id', hotspot.id); // Для поиска в getResizeHandleAt

  // Трекинг ассетов (img в a-assets) и blob URL, чтобы корректно чистить при пересоздании
  markerEl._assetIds = [];
  markerEl._assetUrls = [];

    // Позиционируем маркер
    if (hotspot.position && hotspot.position.x !== undefined && hotspot.position.y !== undefined && hotspot.position.z !== undefined) {
      const posStr = `${hotspot.position.x} ${hotspot.position.y} ${hotspot.position.z}`;

      markerEl.setAttribute('position', posStr);
    } else {

      markerEl.setAttribute('position', '0 0 -5'); // Позиция по умолчанию
    }

    // Делаем маркер интерактивным и перетаскиваемым
    markerEl.className = 'interactive draggable';

    // Добавляем время создания для защиты от случайных кликов
    markerEl._creationTime = Date.now();

    // ВАЖНО: добавляем приоритетные обработчики событий ТОЛЬКО на shape элемент
    // так как A-Frame обрабатывает события именно на них

    // Важно: добавляем класс interactive и к shape для raycaster
    // Добавляем состояние для перетаскивания
    markerEl._isDragging = false;
    markerEl._tooltipVisible = false;

    // Получаем настройки для маркера
    const defaultSettings = this.getDefaultSettings();
    const radius = hotspot.size || (hotspot.type === 'hotspot' ? defaultSettings.hotspotSize : defaultSettings.infopointSize);

    // ВАЖНО: Всегда используем сохраненный цвет если он есть, иначе - цвет по умолчанию для типа
    let color;
    if (hotspot.color && hotspot.color !== 'undefined' && hotspot.color !== '') {
      color = hotspot.color;

    } else {
      color = (hotspot.type === 'hotspot' ? defaultSettings.hotspotColor : defaultSettings.infopointColor);

    }

  let icon = hotspot.icon || (hotspot.type === 'hotspot' ? 'arrow' : 'sphere');
  // Убираем дублирование: 'scene-transition' ведём как 'arrow'
  if (icon === 'scene-transition') icon = 'arrow';

    // Для видео-области создаем плоскость вместо маркера
    if (hotspot.type === 'video-area') {
      return this.createVideoArea(hotspot, markerEl);
    }

    // Новый тип: 3D-iframe (DOM overlay поверх canvas, привязанный к плоскости)
    if (hotspot.type === 'iframe-3d') {
      return this.createIframeOverlay(hotspot, markerEl);
    }

    // Для анимированного объекта используем видео-плоскость с опциональным хромакеем
    if (hotspot.type === 'animated-object') {
      return this.createAnimatedObject(hotspot, markerEl);
    }

    // Создаем геометрию
    let shape;

    // Проверяем, есть ли пользовательская иконка
    if (icon === 'custom' && hotspot.customIconData) {

      // Создаем плоскость для изображения
      shape = document.createElement('a-plane');

      // Создаем уникальный ID для текстуры
      const textureId = `custom-texture-${hotspot.id}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2,6)}`;

      // Создаем элемент img для текстуры
      const img = document.createElement('img');
      img.id = textureId;
      img.src = hotspot.customIconData;
      img.crossOrigin = 'anonymous';
      img.style.display = 'none';

      // Добавляем изображение в assets
      let assets = this.aframeScene.querySelector('a-assets');
      if (!assets) {
        assets = document.createElement('a-assets');
        this.aframeScene.appendChild(assets);
      }
      assets.appendChild(img);

      // Запоминаем ID ассета для последующей очистки
      markerEl._assetIds.push(textureId);

      // Настраиваем материал с текстурой
      shape.setAttribute('material', {
        src: `#${textureId}`,
        transparent: true,
        alphaTest: 0.5
      });

      // Устанавливаем размер (для плоскости используем width и height)
      shape.setAttribute('width', radius * 2);
      shape.setAttribute('height', radius * 2);

      // Добавляем billboard атрибут для предотвращения наклона при перемещении
      shape.setAttribute('billboard', '');

  } else if (icon === 'profile' || (icon === 'custom' && !hotspot.customIconData)) {
      // Если иконка должна быть профиля пользователя или пользовательская иконка не задана,
      // используем иконку профиля с главной страницы (портретная фигура человечка)

      // Создаем плоскость для изображения профиля
      shape = document.createElement('a-plane');

      // Создаем SVG иконку профиля (портретная фигура человечка)
      const profileSvg = `
        <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path>
          <circle cx="12" cy="7" r="4"></circle>
        </svg>
      `;

      // Создаем уникальный ID для текстуры
  const textureId = `profile-marker-${hotspot.id}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2,6)}`;

      // Конвертируем SVG в data URL
      const svgBlob = new Blob([profileSvg], { type: 'image/svg+xml;charset=utf-8' });
      const url = URL.createObjectURL(svgBlob);

      // Создаем элемент img для текстуры
      const img = document.createElement('img');
      img.id = textureId;
      img.src = url;
      img.crossOrigin = 'anonymous';
      img.style.display = 'none';

      // Добавляем изображение в assets
      let assets = this.aframeScene.querySelector('a-assets');
      if (!assets) {
        assets = document.createElement('a-assets');
        this.aframeScene.appendChild(assets);
      }
      assets.appendChild(img);

      // Ждем загрузки изображения
      img.onload = () => {
        // Настраиваем материал с текстурой
        shape.setAttribute('material', {
          src: `#${textureId}`,
          transparent: true,
          alphaTest: 0.1,
          side: 'double'
        });
      };

  // Запоминаем ID ассета и blob URL для очистки при удалении
  markerEl._assetIds.push(textureId);
  markerEl._assetUrls.push(url);

  // Устанавливаем размер (уменьшили множитель для более естественного масштаба)
  const markerSize = radius * 2.0;
      shape.setAttribute('width', markerSize);
      shape.setAttribute('height', markerSize);

  } else if (icon === 'cube' || icon === 'cylinder' || icon === 'octahedron') {
      // Примитивные иконки A-Frame

      switch (icon) {
        case 'cube':
          shape = document.createElement('a-box');
          shape.setAttribute('width', radius);
          shape.setAttribute('height', radius);
          shape.setAttribute('depth', radius);
          break;
        case 'cylinder':
          shape = document.createElement('a-cylinder');
          shape.setAttribute('radius', radius);
          shape.setAttribute('height', radius * 2);
          break;
        case 'octahedron':
          shape = document.createElement('a-octahedron');
          shape.setAttribute('radius', radius);
          break;
        default:
          shape = document.createElement('a-sphere');
          shape.setAttribute('radius', radius);
      }

      // Материал/цвет
      const material = { color: color, metalness: 0, roughness: 1 };
  // Режим "без контура" (ранее: без заливки) для примитивов: делаем полупрозрачным или каркасом
      if (hotspot.noFill) {
        // wireframe может выглядеть "сеткой", поэтому применим прозрачность
        material.transparent = true;
        material.opacity = 0.15;
      }
      shape.setAttribute('material', material);

      // Немного сглаживания граней куба
      if (icon === 'cube') {
        try { shape.setAttribute('radius', Math.max(0.01, radius * 0.05)); } catch (_) {}
      }

    } else {
      // Создаем современный SVG маркер высокого разрешения
      // Особый случай: иконка "Круг" (sphere) должна быть стилизованным кругом как в PNG — рисуем специальный круглый маркер
      const modernMarkerSvg = (icon === 'sphere')
        ? this.modernMarkerGenerator.createCircleOnlyMarker(1024, { color, noFill: !!hotspot.noFill })
        : this.modernMarkerGenerator.createModernMarker(hotspot.type, 1024, { color, hotspot, noFill: !!hotspot.noFill });

      // Создаем плоскость для SVG маркера
      shape = document.createElement('a-plane');

      // Создаем уникальный ID для текстуры
      const textureId = `modern-marker-${hotspot.type}-${hotspot.id}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2,6)}`;

      // Конвертируем SVG в data URL
      const svgData = new XMLSerializer().serializeToString(modernMarkerSvg);
      const svgBlob = new Blob([svgData], { type: 'image/svg+xml;charset=utf-8' });
      const url = URL.createObjectURL(svgBlob);

      // Создаем элемент img для текстуры
      const img = document.createElement('img');
      img.id = textureId;
      img.src = url;
      img.crossOrigin = 'anonymous';
      img.style.display = 'none';

      // Добавляем изображение в assets
      let assets = this.aframeScene.querySelector('a-assets');
      if (!assets) {
        assets = document.createElement('a-assets');
        this.aframeScene.appendChild(assets);
      }
      assets.appendChild(img);

      // Ждем загрузки изображения
      img.onload = () => {
        // Настраиваем материал с текстурой
        shape.setAttribute('material', {
          src: `#${textureId}`,
          transparent: true,
          alphaTest: 0.1,
          side: 'double'
        });
      };

      // Запоминаем ID ассета и blob URL для очистки при удалении
      markerEl._assetIds.push(textureId);
      markerEl._assetUrls.push(url);

  // Устанавливаем размер (скорректированный множитель для соответствия пресетам UI)
  const markerSize = radius * 2.0;
      shape.setAttribute('width', markerSize);
      shape.setAttribute('height', markerSize);
    }

    // Добавляем класс для raycaster
    shape.className = 'interactive modern-marker';

    // Добавляем наш компонент для обработки взаимодействий
    shape.setAttribute('hotspot-handler', `hotspotId: ${hotspot.id}; hotspotType: ${hotspot.type}`);

    // Современные анимации с плавными переходами
    shape.setAttribute('animation__float', 'property: position; to: 0 0.3 0; dir: alternate; loop: true; dur: 2000; easing: easeInOutSine;');

  // Плавные анимации при наведении (используем transform вместо scale для лучшей производительности)
    shape.setAttribute('animation__hover_on', 'property: scale; to: 1.3 1.3 1.3; startEvents: mouseenter; dur: 300; easing: easeOutElastic;');
    shape.setAttribute('animation__hover_off', 'property: scale; to: 1 1 1; startEvents: mouseleave; dur: 200; easing: easeInOutQuad;');

    // Удалено: 3D-текстовые подписи над маркерами (оставляем только 2D tooltip на hover)
    const textContainer = null;

    // События для показа/скрытия текста и перетаскивания

    // Простой тест наведения
    markerEl.addEventListener('mouseenter', (e) => {

      e.stopPropagation();
      if (!markerEl._isDragging && !markerEl._tooltipVisible) {
        markerEl._tooltipVisible = true;

      }

      // 2D тултип: Название + Описание (как в экспорте), с экранированием и переносами строк
      const hasInfo = (hotspot && (hotspot.title || hotspot.description));
      if (hasInfo && !markerEl._domTooltip) {
        const tip = document.createElement('div');
        tip.className = 'tour-tooltip';
        const title = this.removeFileExtension(hotspot.title || 'Информация');
        const escapeHtml = (s) => String(s)
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;')
          .replace(/"/g, '&quot;')
          .replace(/'/g, '&#39;');
        const hasDesc = !!hotspot.description;
        const descHtml = hasDesc ? `<div class="desc">${escapeHtml(hotspot.description).replace(/\n/g, '<br>')}</div>` : '';
        const sep = hasDesc ? '<hr class="tour-tip-sep" />' : '';
        tip.innerHTML = `<div class="title">${title}</div>${sep}${descHtml}`;
        // Применяем цвет, размер, семейство шрифтов, жирность и подчёркивание из настроек хотспота
        try {
          const titleEl = tip.querySelector('.title');
          const descEl = tip.querySelector('.desc');
          const color = hotspot.textColor || '#ffffff';
          if (titleEl) titleEl.style.color = color;
          if (descEl) descEl.style.color = color;
          const fontSizePx = Math.round((hotspot.textSize || 1) * 16);
          if (titleEl && hotspot.textSize) titleEl.style.fontSize = `${fontSizePx}px`;
          if (descEl && hotspot.textSize) descEl.style.fontSize = `${fontSizePx}px`;
          const family = hotspot.textFamily || 'Arial, sans-serif';
          if (titleEl) titleEl.style.fontFamily = family;
          if (descEl) descEl.style.fontFamily = family;
          const weight = hotspot.textBold ? '700' : '400';
          if (titleEl) titleEl.style.fontWeight = weight;
          if (descEl) descEl.style.fontWeight = weight;
          const decoration = hotspot.textUnderline ? 'underline' : 'none';
          if (titleEl) titleEl.style.textDecoration = decoration;
          if (descEl) descEl.style.textDecoration = decoration;
        } catch (_) { /* noop */ }
        document.body.appendChild(tip);
        // Tooltip: use fixed positioning to avoid layout shifts and page scrollbars
        tip.style.position = 'fixed';
        tip.style.pointerEvents = 'none';
        tip.style.zIndex = '2147483647';
        // small padding
        const padding = 12;
        const move = (ev) => {
          // clamp tooltip inside viewport
          const vw = Math.max(document.documentElement.clientWidth || 0, window.innerWidth || 0);
          const vh = Math.max(document.documentElement.clientHeight || 0, window.innerHeight || 0);
          const rect = tip.getBoundingClientRect();
          let left = ev.clientX + padding;
          let top = ev.clientY + padding;
          if (left + rect.width + 8 > vw) left = Math.max(8, vw - rect.width - 8);
          if (top + rect.height + 8 > vh) top = Math.max(8, vh - rect.height - 8);
          tip.style.left = left + 'px';
          tip.style.top = top + 'px';
        };
        window.addEventListener('mousemove', move);
        markerEl._domTooltip = tip; markerEl._domTooltipMove = move;
      }

      // ЗАПОМИНАЕМ последний маркер под курсором для стабильности контекстного меню
      this._lastHoveredMarker = { element: markerEl, hotspot: hotspot, time: Date.now() };
    });

    markerEl.addEventListener('mouseleave', (e) => {

      e.stopPropagation();
      if (!markerEl._isDragging && markerEl._tooltipVisible) {
        markerEl._tooltipVisible = false;

      }

      // Скрываем 2D тултип
      if (markerEl._domTooltip) {
        window.removeEventListener('mousemove', markerEl._domTooltipMove);
        try { document.body.removeChild(markerEl._domTooltip); } catch (_) { }
        markerEl._domTooltip = null; markerEl._domTooltipMove = null;
      }

      // НЕ сбрасываем _lastHoveredMarker сразу - оставляем УВЕЛИЧЕННОЕ окно для стабильности
      setTimeout(() => {
        if (this._lastHoveredMarker && this._lastHoveredMarker.element === markerEl) {
          this._lastHoveredMarker = null;
        }
      }, 500); // УВЕЛИЧИЛИ с 200ms до 500ms для лучшей стабильности
    });

    // УДАЛЯЕМ: локальный обработчик contextmenu на маркере
    // Теперь за всю обработку контекстного меню отвечает ТОЛЬКО canvas обработчик
    // который правильно определяет маркеры через findNearestMarker()

    // markerEl.addEventListener('contextmenu', (e) => {
    //   console.log('🎯 contextmenu на маркере:', hotspot.title);
    //   e.preventDefault();
    //   e.stopPropagation();
    //   // НЕ устанавливаем глобальный флаг _contextMenuHandled
    //   // Пусть canvas обработчик сам определит маркер и покажет меню
    // });

    // Клик без перетаскивания - основная функция
    markerEl.addEventListener('click', (e) => {

      // 🔥 КРИТИЧЕСКАЯ ПРОВЕРКА: блокируем клик после правого клика (как в A-Frame компоненте)
      const currentTime = Date.now();
      const lastRightClickTime = window.viewerManager ? window.viewerManager._lastRightClickTime : 0;
      const timeSinceRightClick = currentTime - (lastRightClickTime || 0);

      if (timeSinceRightClick < 300) {

        return;
      }

      // Дополнительная проверка глобальной блокировки
      if (window._dragSystemBlocked) {

        return;
      }

      // Проверяем флаги блокировки от приоритетных обработчиков
      if (markerEl._rightClickHandled) {

        return;
      }

      if (markerEl._doubleClickHandled) {

        return;
      }

      e.stopPropagation();
      e.preventDefault();

      // Проверяем флаг перетаскивания
      if (!markerEl._wasDragged) {
        if (hotspot.type === 'hotspot' && hotspot.targetSceneId) {

          // ЗАЩИТА: проверяем, что целевая сцена существует
          const targetScene = window.sceneManager && typeof window.sceneManager.getSceneById === 'function' ? window.sceneManager.getSceneById(hotspot.targetSceneId) : undefined;
          if (!targetScene) {

            return;
          }

          // ЗАЩИТА: проверяем, что мы не на целевой сцене уже
          const currentScene = window.sceneManager && typeof window.sceneManager.getCurrentScene === 'function' ? window.sceneManager.getCurrentScene() : undefined;
          if (currentScene && currentScene.id === hotspot.targetSceneId) {

            return;
          }

          // ЗАЩИТА: добавляем небольшую задержку для предотвращения случайных кликов при загрузке
          const markerAge = Date.now() - (markerEl._creationTime || 0);
          if (markerAge < 500) { // Уменьшаем время защиты

            return;
          }

          // Дополнительная проверка: не переходим если предыдущий переход был недавно
          const timeSinceLastTransition = Date.now() - (window._lastTransitionTime || 0);
          if (timeSinceLastTransition < 1000) {

            return;
          }

          window._lastTransitionTime = Date.now();
          window.sceneManager.switchToScene(hotspot.targetSceneId);
        } else if (hotspot.type === 'info-point') {

          this.showInfoPointModal(hotspot);
        } else if (hotspot.type === 'video-area') {
          // Клик по видео-области обрабатывается строго внутри createVisualMarker() на самой плоскости.
          // Здесь не дублируем, чтобы избежать двойного play/pause и AbortError.

        }
      } else {

      }

      // Сбрасываем флаг с задержкой чтобы не мешать проверке выше
      setTimeout(() => {
        markerEl._wasDragged = false;
      }, 10);
    });

    // Добавляем billboard только для плоских маркеров (a-plane)
    if (shape && shape.tagName && shape.tagName.toLowerCase() === 'a-plane') {
      shape.setAttribute('billboard', '');
    }
    
    // Сохраняем текущие параметры для отслеживания изменений
    markerEl._lastColor = color;
    markerEl._lastNoFill = !!hotspot.noFill;
    markerEl._lastIcon = icon;
    markerEl._lastSize = radius;
    
    markerEl.appendChild(shape);

    // СНАЧАЛА добавляем маркер в сцену
    this.aframeScene.appendChild(markerEl);

    // ПОТОМ настраиваем перетаскивание через координатный менеджер (чтобы его обработчики добавились ПОСЛЕ приоритетных)
    if (this.coordinateManager) {
      this.coordinateManager.setupMarkerDragging(markerEl, hotspot.id, (newPosition) => {
        // Обновляем позицию в менеджере хотспотов
        this.hotspotManager.updateHotspotPosition(hotspot.id, newPosition);
        markerEl._wasDragged = true;

      });
    }

    console.log('Маркер добавлен в сцену:', {
      id: markerEl.id,
      className: markerEl.className,
      position: markerEl.getAttribute('position'),
      hasShape: !!shape,
      hasTextContainer: !!textContainer,
      sceneChildren: this.aframeScene.children.length
    });

    // Проверяем через небольшую задержку, что элемент действительно в DOM
    setTimeout(() => {
      const checkEl = document.getElementById(`marker-${hotspot.id}`);

    }, 100);
  }

  /**
   * Создает плоскость-заглушку и DOM iframe-оверлей, синхронизируемый с 3D-позицией (эмуляция «встраивания» YouTube и др.).
   * hotspot fields: { iframeUrl, videoWidth, videoHeight }
   */
  createIframeOverlay(hotspot, markerEl) {
    // Помечаем тип маркера
    markerEl.setAttribute('data-marker-type', 'iframe-3d');

    // Параметры размера (динамические через hotspot)
    let width = parseFloat(hotspot.videoWidth) || 4;
    let height = parseFloat(hotspot.videoHeight) || 3;

    // Плоскость-носитель в 3D (видимая тонкая рамка/фон по желанию)
    const plane = document.createElement('a-plane');
    plane.setAttribute('width', width);
    plane.setAttribute('height', height);
    plane.className = 'interactive';
    plane.setAttribute('material', 'color: #111; opacity: 0.6; side: double; shader: flat');
    plane.setAttribute('billboard', '');
    plane.setAttribute('hotspot-handler', `hotspotId: ${hotspot.id}; hotspotType: iframe-3d`);

    markerEl.appendChild(plane);
    this.aframeScene.appendChild(markerEl);

    // Создаем DOM iframe поверх canvas
    // Контейнер для позиционирования
    const overlay = document.createElement('div');
    overlay.style.cssText = `
      position: fixed;
      left: -9999px; top: -9999px;
      width: 0; height: 0;
      z-index: 9999;
      pointer-events: auto;
      border-radius: 8px;
      overflow: hidden;
      box-shadow: 0 4px 16px rgba(0,0,0,0.35);
      background: #000;
    `;

    const iframe = document.createElement('iframe');
    iframe.src = hotspot.iframeUrl || '';
    iframe.allow = 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture';
    iframe.allowFullscreen = true;
    iframe.style.cssText = 'display:block;border:0;width:100%;height:100%;background:#000;';
    overlay.appendChild(iframe);
    document.body.appendChild(overlay);

    // Сохраняем ссылки для последующей очистки/обновления
    markerEl._iframeOverlay = overlay;
    markerEl._iframePlane = plane;
    markerEl._iframeHotspot = hotspot;

    // Обновление позиции iframe каждый кадр рендера (через requestAnimationFrame)
    const updateOverlayPosition = () => {
      try {
        if (!this.aframeScene || !this.aframeCamera || !markerEl.parentNode) return;

        // Читаем актуальные размеры из хотспота, если они обновились
        if (markerEl._iframeHotspot) {
          const hw = parseFloat(markerEl._iframeHotspot.videoWidth);
          const hh = parseFloat(markerEl._iframeHotspot.videoHeight);
          const wNew = !isNaN(hw) && hw > 0 ? hw : width;
          const hNew = !isNaN(hh) && hh > 0 ? hh : height;
          if (wNew !== width || hNew !== height) {
            width = wNew; height = hNew;
            try { plane.setAttribute('width', width); plane.setAttribute('height', height); } catch { }
          }
        }

        // Получаем 4 угла плоскости в мировых координатах и проектируем в экранные
        const corners = this._getPlaneScreenCorners(markerEl, width, height);
        if (!corners) return;

        // Вычисляем bbox в экранных координатах
        const minX = Math.min(corners.topLeft.x, corners.topRight.x, corners.bottomLeft.x, corners.bottomRight.x);
        const maxX = Math.max(corners.topLeft.x, corners.topRight.x, corners.bottomLeft.x, corners.bottomRight.x);
        const minY = Math.min(corners.topLeft.y, corners.topRight.y, corners.bottomLeft.y, corners.bottomRight.y);
        const maxY = Math.max(corners.topLeft.y, corners.topRight.y, corners.bottomLeft.y, corners.bottomRight.y);

        const w = Math.max(0, Math.round(maxX - minX));
        const h = Math.max(0, Math.round(maxY - minY));

        // Порог минимального размера, чтобы не мигало при разворотах
        if (w < 8 || h < 8) {
          overlay.style.left = '-9999px';
          overlay.style.top = '-9999px';
          overlay.style.width = '0px';
          overlay.style.height = '0px';
          return;
        }

        overlay.style.left = `${Math.round(minX)}px`;
        overlay.style.top = `${Math.round(minY)}px`;
        overlay.style.width = `${w}px`;
        overlay.style.height = `${h}px`;
      } finally {
        overlay._raf = requestAnimationFrame(updateOverlayPosition);
      }
    };
    overlay._raf = requestAnimationFrame(updateOverlayPosition);

    // Наведение по плоскости показываем 2D tooltip стандартно
    markerEl.addEventListener('mouseenter', () => {
      markerEl._tooltipVisible = true;
    });
    markerEl.addEventListener('mouseleave', () => {
      markerEl._tooltipVisible = false;
    });

    // Клик по плоскости – просто пробрасываем клик (ничего особого не делаем)
    plane.addEventListener('click', (e) => {
      e.stopPropagation();
    });

    // Пересчет при ресайзе окна
    const onResize = () => {
      // Форс-обновление одной итерацией
      cancelAnimationFrame(overlay._raf);
      overlay._raf = requestAnimationFrame(() => updateOverlayPosition());
    };
    window.addEventListener('resize', onResize);
    markerEl._iframeOnResize = onResize;

    return markerEl;
  }

  /**
   * Возвращает экранные координаты 4-х углов плоскости (a-plane) маркера.
   */
  _getPlaneScreenCorners(markerEl, width, height) {
    try {
      const scene = this.aframeScene;
      const cameraEl = this.aframeCamera;
      if (!scene || !cameraEl) return null;
      const camera = cameraEl.getObject3D('camera');
      if (!camera) return null;

      const obj = markerEl.object3D;
      if (!obj) return null;

      // Локальные координаты углов плоскости, ориентированной на камеру
      const hw = width / 2;
      const hh = height / 2;
      const localCorners = [
        new THREE.Vector3(-hw, hh, 0), // topLeft
        new THREE.Vector3(hw, hh, 0),  // topRight
        new THREE.Vector3(-hw, -hh, 0),// bottomLeft
        new THREE.Vector3(hw, -hh, 0)  // bottomRight
      ];

      const worldCorner = new THREE.Vector3();
      const projected = new THREE.Vector3();
      const rect = scene.canvas.getBoundingClientRect();

      const toScreen = (v3) => {
        worldCorner.copy(v3).applyMatrix4(obj.matrixWorld);
        projected.copy(worldCorner).project(camera);
        const x = (projected.x + 1) / 2 * rect.width + rect.left;
        const y = (-projected.y + 1) / 2 * rect.height + rect.top;
        return { x, y };
      };

      const [tl, tr, bl, br] = localCorners.map(toScreen);
      return { topLeft: tl, topRight: tr, bottomLeft: bl, bottomRight: br };
    } catch (e) {
      return null;
    }
  }

  /**
   * Анимированный объект: видео-плоскость, всегда смотрит на камеру, опциональный хромакей
   */
  createAnimatedObject(hotspot, markerEl) {
    if (!markerEl) {
      markerEl = document.createElement('a-entity');
      markerEl.id = `marker-${hotspot.id}`;
      markerEl.setAttribute('data-hotspot-id', hotspot.id);
  const posStr = `${hotspot.position && hotspot.position.x ? hotspot.position.x : 0} ${hotspot.position && hotspot.position.y ? hotspot.position.y : 1.5} ${hotspot.position && hotspot.position.z ? hotspot.position.z : -3}`;
      markerEl.setAttribute('position', posStr);
    }

    markerEl.classList.add('interactive');
    markerEl.setAttribute('face-camera', '');

    const plane = document.createElement('a-plane');
    const width = parseFloat(hotspot.videoWidth) || 2;
    const height = parseFloat(hotspot.videoHeight) || 2 * 9 / 16;
    plane.setAttribute('width', width);
    plane.setAttribute('height', height);
    plane.className = 'animated-object-plane';

    // Создаём/подвязываем видео
    const videoId = `video-${hotspot.id}`;
    let videoEl = document.getElementById(videoId);
    if (!videoEl) {
      videoEl = document.createElement('video');
      videoEl.id = videoId;
      videoEl.crossOrigin = 'anonymous';
      videoEl.loop = true;
      videoEl.playsInline = true;
      videoEl.muted = true;
      videoEl.style.display = 'none';
      let assets = this.aframeScene.querySelector('a-assets');
      if (!assets) { assets = document.createElement('a-assets'); this.aframeScene.appendChild(assets); }
      assets.appendChild(videoEl);
    }

    if (hotspot.videoUrl) {
      videoEl.src = hotspot.videoUrl;
      try { videoEl.load(); } catch { }
    }

    // Материал: обычный или chroma-key
    const chromaEnabled = !!hotspot.chromaEnabled;
    if (chromaEnabled) {
      // Используем шейдер chroma-key
      plane.setAttribute('material', `shader: chroma-key; src: #${videoId}; color: ${hotspot.chromaColor || '#00ff00'}; similarity: ${hotspot.chromaSimilarity ?? 0.4}; smoothness: ${hotspot.chromaSmoothness ?? 0.1}; threshold: ${hotspot.chromaThreshold ?? 0.0}; side: double`);
    } else {
      plane.setAttribute('material', `shader: flat; src: #${videoId}; side: double`);
    }

    // Удалено: 3D-лейбл над видео/анимацией (оставляем только 2D tooltip)

    // Обработчик клика: toggle play/pause (с анти-дребезгом, чтобы избежать AbortError)
    if (!plane._playToggleLock) plane._playToggleLock = false;
    plane.addEventListener('click', (e) => {
      e.stopPropagation();
      if (plane._playToggleLock) return;
      plane._playToggleLock = true;
      if (videoEl.paused) {
        videoEl.play().catch((err) => {
          // Игнорируем AbortError как безопасный
          if (!(err && err.name === 'AbortError')) {

          }
        }).finally(() => { setTimeout(() => { plane._playToggleLock = false; }, 50); });
      } else {
        try { videoEl.pause(); } catch (_) { }
        setTimeout(() => { plane._playToggleLock = false; }, 50);
      }
    });

    markerEl.appendChild(plane);
    this.aframeScene.appendChild(markerEl);
    return markerEl;
  }

  showInfoPointModal(hotspot) {
    // Принудительно удаляем все tooltip'ы чтобы они не "прилипли" к курсору
    this.removeAllDragTooltips();
    
    // Удаляем существующее модальное окно если оно есть
    if (this._currentInfoModal) {
      try {
        this._currentInfoModal.backdrop.remove();
        this._currentInfoModal.element.remove();
      } catch (e) {

      }
      this._currentInfoModal = null;
    }

    // Создаем backdrop
    const backdrop = document.createElement('div');
    backdrop.style.cssText = `
      position: fixed;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      background: rgba(0, 0, 0, 0.7);
      backdrop-filter: blur(4px);
      z-index: 9999;
      opacity: 0;
      transition: opacity 0.3s ease;
    `;

    // Создаем модальное окно
    const modal = document.createElement('div');
    modal.style.cssText = `
      position: fixed;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%) scale(0.9);
      background: linear-gradient(135deg, #1a1a1a 0%, #2a2a2a 100%);
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 16px;
      box-shadow: 0 20px 50px rgba(0, 0, 0, 0.5);
      z-index: 10000;
      min-width: 300px;
      max-width: 500px;
      width: 80%;
      opacity: 0;
      transition: all 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);
    `;

    // Создаем заголовок
    const header = document.createElement('div');
    header.style.cssText = `
      padding: 20px 24px 16px;
      background: linear-gradient(90deg, ${hotspot.color || '#4CAF50'} 0%, ${hotspot.color || '#4CAF50'}80 100%);
      border-radius: 16px 16px 0 0;
      border-bottom: 1px solid rgba(255, 255, 255, 0.1);
    `;

    const title = document.createElement('h2');
    title.style.cssText = `
      margin: 0;
      color: white;
      font-size: 24px;
      font-weight: 600;
      text-shadow: 0 1px 2px rgba(0, 0, 0, 0.5);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    `;
    title.textContent = hotspot.title || 'Информация';
    header.appendChild(title);

    // Создаем контент
    const content = document.createElement('div');
    content.style.cssText = `
      padding: 20px 24px;
      color: rgba(255, 255, 255, 0.9);
      font-size: 16px;
      line-height: 1.6;
      max-height: 60vh;
      overflow-y: auto;
    `;

    const description = document.createElement('p');
    description.style.cssText = `
      margin: 0;
      color: ${hotspot.textColor || 'rgba(255, 255, 255, 0.9)'};
      font-size: ${(hotspot.textSize || 1) * 16}px;
      text-shadow: 0 1px 2px rgba(0, 0, 0, 0.5);
    `;
    description.textContent = hotspot.description || 'Дополнительная информация отсутствует';
    content.appendChild(description);

    // Создаем футер
    const footer = document.createElement('div');
    footer.style.cssText = `
      padding: -1px 24px;
      border-top: 1px solid rgba(255, 255, 255, 0.1);
      background: rgba(0, 0, 0, 0.2);
      display: flex;
      justify-content: flex-end;
      gap: 12px;
    `;

    const closeButton = document.createElement('button');
    closeButton.style.cssText = `
      padding: 12px 24px;
      background: linear-gradient(135deg, ${hotspot.color || '#4CAF50'}, ${hotspot.color || '#4CAF50'}DD);
      border: none;
      border-radius: 12px;
      color: white;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s ease;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
      text-transform: uppercase;
      letter-spacing: 0.5px;
    `;
    closeButton.textContent = 'Закрыть';

    // Hover эффект для кнопки
    closeButton.addEventListener('mouseenter', () => {
      closeButton.style.transform = 'translateY(-2px)';
      closeButton.style.boxShadow = `0 6px 20px rgba(0, 0, 0, 0.4)`;
    });

    closeButton.addEventListener('mouseleave', () => {
      closeButton.style.transform = 'translateY(0)';
      closeButton.style.boxShadow = '0 4px 12px rgba(0, 0, 0, 0.3)';
    });

    footer.appendChild(closeButton);

    // Собираем модальное окно
    modal.appendChild(header);
    modal.appendChild(content);
    modal.appendChild(footer);

    // Добавляем в DOM
    document.body.appendChild(backdrop);
    document.body.appendChild(modal);

    // Сохраняем ссылку на текущий модал
    this._currentInfoModal = {
      element: modal,
      backdrop: backdrop,
      hotspotId: hotspot.id
    };

    // Анимация появления
    requestAnimationFrame(() => {
      backdrop.style.opacity = '1';
      modal.style.opacity = '1';
      modal.style.transform = 'translate(-50%, -50%) scale(1)';
    });

    // Функция закрытия с анимацией
    const closeModal = () => {
      backdrop.style.opacity = '0';
      modal.style.opacity = '0';
      modal.style.transform = 'translate(-50%, -50%) scale(0.9)';

      setTimeout(() => {
        backdrop.remove();
        modal.remove();
        // Очищаем ссылку на текущий модал
        if (this._currentInfoModal && this._currentInfoModal.hotspotId === hotspot.id) {
          this._currentInfoModal = null;
        }
      }, 300);
    };

    // Обработчики закрытия
    closeButton.addEventListener('click', (e) => {
      e.stopPropagation();
      closeModal();
    });

    backdrop.addEventListener('click', (e) => {
      e.stopPropagation();
      // Убеждаемся, что клик точно по backdrop, а не по модальному окну
      if (e.target === backdrop) {
        closeModal();
      }
    });

    // Предотвращаем распространение кликов по модальному окну
    modal.addEventListener('click', (e) => {
      e.stopPropagation();
    });

    // Закрытие по ESC
    const escHandler = (e) => {
      if (e.key === 'Escape') {
        closeModal();
        document.removeEventListener('keydown', escHandler);
      }
    };
    document.addEventListener('keydown', escHandler);
  }

  showMarkerContextMenu(x, y, hotspot) {

    // ЗАЩИТА: Блокируем автоматическое закрытие меню СРАЗУ - ДО очистки
    this._contextMenuCreationTime = Date.now();

    // ОСТОРОЖНОЕ удаление: НЕ удаляем меню если они были созданы недавно
    const existingMenus = document.querySelectorAll('.marker-context-menu, .custom-context-menu');
    const currentTime = Date.now();
    existingMenus.forEach(menu => {
      // Проверяем время создания
      const creationTime = menu._creationTime || 0;
      if (currentTime - creationTime > 100) { // Удаляем только старые меню

        menu.remove();
      } else {

      }
    });

    // УЛУЧШЕННОЕ позиционирование с проверкой границ экрана
    const menuWidth = 220;
    const menuHeight = 300; // Примерная высота меню с кнопками

    // Проверяем, помещается ли меню справа
    let finalX = x;
    if (x + menuWidth > window.innerWidth) {
      finalX = x - menuWidth; // Показываем слева от курсора
      if (finalX < 10) finalX = 10; // Минимальный отступ от края
    }

    // Проверяем, помещается ли меню снизу
    let finalY = y;
    if (y + menuHeight > window.innerHeight) {
      finalY = y - menuHeight; // Показываем сверху от курсора
      if (finalY < 10) finalY = 10; // Минимальный отступ от края
    }

    // Убеждаемся, что меню полностью видно
    finalX = Math.max(10, Math.min(finalX, window.innerWidth - menuWidth - 10));
    finalY = Math.max(10, Math.min(finalY, window.innerHeight - menuHeight - 10));

    console.log('📐 Позиционирование меню:', {
      исходные: { x, y },
      финальные: { finalX, finalY },
      размерыЭкрана: { width: window.innerWidth, height: window.innerHeight },
      размерыМеню: { menuWidth, menuHeight }
    });

    // Создаем меню с уникальным ID и без классов (избегаем CSS конфликтов)
    const menuId = 'hotspot-editor-menu-' + Date.now();
    const menu = document.createElement('div');
    menu.id = menuId;
    menu.className = 'marker-context-menu'; // Добавляем класс для удобного поиска
    menu._creationTime = Date.now(); // ВАЖНО: помечаем время создания для защиты

    // РАДИКАЛЬНЫЙ подход: встраиваем ВСЕ стили inline в cssText
    menu.style.cssText = `
      all: initial !important;
      position: fixed !important;
      left: ${finalX}px !important;
      top: ${finalY}px !important;
      z-index: 2147483647 !important;
      width: 200px !important;
      height: auto !important;
      min-height: 100px !important;
      background: linear-gradient(135deg, #2a2a2a 0%, #1a1a1a 100%) !important;
      border: 2px solid #4CAF50 !important;
      border-radius: 8px !important;
      box-shadow: 0 8px 32px rgba(0,255,0,0.3), 0 0 0 1px rgba(76,175,80,0.5) !important;
      font-family: 'Segoe UI', Arial, sans-serif !important;
      font-size: 14px !important;
      color: white !important;
      display: block !important;
      visibility: visible !important;
      opacity: 1 !important;
      pointer-events: auto !important;
      overflow: visible !important;
      margin: 0 !important;
      padding: 8px 0 !important;
      text-align: left !important;
      line-height: normal !important;
      white-space: nowrap !important;
      user-select: none !important;
      box-sizing: border-box !important;
    `;

    // Создаем ТОЛЬКО две кнопки (удаляем "Переместить")
    const buttons = [
      { action: 'edit', text: '✏️ Редактировать', color: '#4CAF50' },
      { action: 'delete', text: '🗑️ Удалить', color: '#f44336' }
    ];

    buttons.forEach((btn, index) => {
      const button = document.createElement('div');
      button.setAttribute('data-action', btn.action);
      button.textContent = btn.text;

      button.style.cssText = `
        all: initial !important;
        display: block !important;
        width: 100% !important;
        padding: 12px 16px !important;
        margin: 0 !important;
        background: transparent !important;
        border: none !important;
        border-bottom: ${index < buttons.length - 1 ? '1px solid rgba(255,255,255,0.1)' : 'none'} !important;
        color: white !important;
        font-family: 'Segoe UI', Arial, sans-serif !important;
        font-size: 14px !important;
        font-weight: normal !important;
        text-align: left !important;
        cursor: pointer !important;
        transition: all 0.2s ease !important;
        user-select: none !important;
        box-sizing: border-box !important;
        line-height: 1.4 !important;
        white-space: nowrap !important;
        overflow: hidden !important;
        text-overflow: ellipsis !important;
      `;

      // Hover эффекты через события (избегаем CSS)
      button.addEventListener('mouseenter', () => {
        button.style.backgroundColor = `${btn.color}33 !important`;
        button.style.borderLeft = `3px solid ${btn.color} !important`;
        button.style.paddingLeft = '13px !important';
      });

      button.addEventListener('mouseleave', () => {
        button.style.backgroundColor = 'transparent !important';
        button.style.borderLeft = 'none !important';
        button.style.paddingLeft = '16px !important';
      });

      menu.appendChild(button);
    });

    // Добавляем в body
    document.body.appendChild(menu);

    // КРИТИЧЕСКИ ВАЖНО: настраиваем обработчики кликов для основного меню
    this.setupMenuHandlers(menu, hotspot);

    // Проверяем видимость
    const rect = menu.getBoundingClientRect();
    console.log('🎯 Размеры нового меню:', {
      width: rect.width,
      height: rect.height,
      visible: rect.width > 0 && rect.height > 0,
      id: menuId
    });

    // Если меню все еще невидимо - создаем супер-простое аварийное меню
    if (rect.width === 0 || rect.height === 0) {

      menu.remove();

      // Создаем максимально простое меню
      const emergency = document.createElement('div');
      emergency.className = 'marker-context-menu';
      emergency.innerHTML = `
        <div style="position:fixed!important;left:${finalX}px!important;top:${finalY}px!important;z-index:9999999!important;background:#ff0000!important;color:#fff!important;padding:20px!important;border:5px solid #ffff00!important;font-size:18px!important;font-family:Arial!important;width:250px!important;height:150px!important">
          <div style="cursor:pointer;padding:15px;border:2px solid #fff;margin:5px 0;background:#000" data-action="edit">✏️ РЕДАКТИРОВАТЬ</div>
          <div style="cursor:pointer;padding:15px;border:2px solid #fff;margin:5px 0;background:#000" data-action="delete">🗑️ УДАЛИТЬ</div>
        </div>
      `;

      document.body.appendChild(emergency);
      this.setupMenuHandlers(emergency.firstElementChild, hotspot);

      return;
    }

    // ДОПОЛНИТЕЛЬНАЯ немедленная система auto-close только для ЛКМ
    const immediateCloseHandler = (e) => {
      // Только для левого клика - мгновенное закрытие
      if (e.button === 0 && e.type === 'click') {
        // Игнорируем клики по самому меню
        if (e.target.closest('.marker-context-menu') || e.target.closest(`#${menuId}`)) {
          return;
        }

        // Игнорируем клики по маркерам
        if (e.target.closest('a-text') || e.target.closest('[hotspot-marker]') || e.target.closest('.hotspot')) {
          return;
        }

        // Проверяем существование меню
        const stillExists = document.getElementById(menuId);
        if (stillExists) {

          stillExists.remove();
          this._contextMenuCreationTime = null;

          // Удаляем обработчики
          document.removeEventListener('click', immediateCloseHandler, true);
          document.removeEventListener('mousedown', immediateCloseHandler, true);
        }
      }
    };

    // Устанавливаем НЕМЕДЛЕННО для мгновенного закрытия ЛКМ
    document.addEventListener('click', immediateCloseHandler, true);
    document.addEventListener('mousedown', immediateCloseHandler, true);

    // УЛУЧШЕННАЯ система закрытия меню - мгновенная реакция на ЛКМ по свободному пространству
    setTimeout(() => {
      // Проверяем, что меню еще существует перед установкой обработчиков
      const currentMenu = document.getElementById(menuId);
      if (!currentMenu) {

        return;
      }

      const closeHandler = (e) => {
        // Игнорируем правые клики полностью
        if (e.button === 2 || e.type === 'contextmenu') {

          return;
        }

        // Игнорируем клики по самому меню и его дочерним элементам
        if (e.target.closest('.marker-context-menu') || e.target.closest(`#${menuId}`)) {

          return;
        }

        // Игнорируем клики по маркерам/хотспотам
        if (e.target.closest('a-text') || e.target.closest('[hotspot-marker]') || e.target.closest('.hotspot')) {

          return;
        }

        // МГНОВЕННОЕ ЗАКРЫТИЕ для левого клика (button 0) по свободному пространству
        const menuAge = Date.now() - (menu._creationTime || 0);
        if (e.button === 0 && e.type === 'click') {
          // Левый клик - немедленное закрытие без задержки

        } else {
          // Для других событий - защищаем меню первые 3 секунды
          if (menuAge < 3000) {

            return;
          }
        }

        // Финальная проверка существования меню
        const stillExists = document.getElementById(menuId);
        if (!stillExists) {

          // Удаляем обработчики если меню уже нет
          document.removeEventListener('click', closeHandler, true);
          document.removeEventListener('mousedown', closeHandler, true);
          return;
        }

        stillExists.remove();
        this._contextMenuCreationTime = null;

        // КРИТИЧЕСКИ ВАЖНО: удаляем обработчики после закрытия
        document.removeEventListener('click', closeHandler, true);
        document.removeEventListener('mousedown', closeHandler, true);
      };

      // Сохраняем ссылку на обработчик для возможности удаления извне
      if (!this._activeAutoCloseHandlers) {
        this._activeAutoCloseHandlers = new Set();
      }
      this._activeAutoCloseHandlers.add(closeHandler);

      // Используем CAPTURE фазу для приоритетного перехвата
      document.addEventListener('click', closeHandler, true);
      document.addEventListener('mousedown', closeHandler, true);

    }, 3000); // УВЕЛИЧИЛИ до 3000ms для максимальной стабильности

  }

  hideAllContextMenus() {
    // Простое удаление всех контекстных меню без сложной логики

    const selectors = [
      '.marker-context-menu',
      '.custom-context-menu',
      '[id*="hotspot-editor-menu"]',
      '[id*="marker-menu"]',
      '[class*="context-menu"]'
    ];

    selectors.forEach(selector => {
      document.querySelectorAll(selector).forEach(menu => {

        menu.remove();
      });
    });

    // Сбрасываем время создания
    this._contextMenuCreationTime = null;
  }

  forceHideAllContextMenus() {
    // Принудительное удаление БЕЗ защитной задержки
    const selectors = [
      '.marker-context-menu',
      '.custom-context-menu',
      '[id*="hotspot-editor-menu"]',
      '[id*="marker-menu"]',
      '[class*="context-menu"]'
    ];

    selectors.forEach(selector => {
      document.querySelectorAll(selector).forEach(menu => {

        menu.remove();
      });
    });

    // Сбрасываем время создания
    this._contextMenuCreationTime = null;
  }

  setupMenuHandlers(menu, hotspot) {
    // Простые обработчики без сложной логики
    const editBtn = menu.querySelector('[data-action="edit"]');
    const deleteBtn = menu.querySelector('[data-action="delete"]');

    if (editBtn) {
      editBtn.addEventListener('click', (e) => {

        e.stopPropagation();
        e.preventDefault();

        if (this.hotspotManager) {
          this.hotspotManager.editHotspot(hotspot.id);

        }

        // БЕЗОПАСНОЕ закрытие: удаляем только текущее меню
        menu.remove();

      });
    }

    if (deleteBtn) {
      deleteBtn.addEventListener('click', (e) => {

        e.stopPropagation();
        e.preventDefault();

        // ИСПРАВЛЯЕМ: используем правильный метод удаления
        try {
          // Используем правильное название метода
          if (this.hotspotManager && this.hotspotManager.removeHotspotById) {
            this.hotspotManager.removeHotspotById(hotspot.id);

          } else if (this.hotspotManager && this.hotspotManager.hotspots) {
            // Fallback: удаляем напрямую из массива
            const index = this.hotspotManager.hotspots.findIndex(h => h.id === hotspot.id);
            if (index !== -1) {
              this.hotspotManager.hotspots.splice(index, 1);

              // Удаляем визуальный маркер
              this.removeVisualMarker(hotspot.id);

              // Сохраняем изменения
              if (this.hotspotManager.saveHotspots) {
                this.hotspotManager.saveHotspots();
              }

            }
          }
        } catch (error) {
          console.error('❌ Ошибка при удалении маркера:', error);

          // Попытаемся удалить хотя бы визуально и из массива
          try {
            this.removeVisualMarker(hotspot.id);

            if (this.hotspotManager && this.hotspotManager.hotspots) {
              const index = this.hotspotManager.hotspots.findIndex(h => h.id === hotspot.id);
              if (index !== -1) {
                this.hotspotManager.hotspots.splice(index, 1);
                if (this.hotspotManager.saveHotspots) {
                  this.hotspotManager.saveHotspots();
                }
              }
            }

          } catch (fallbackError) {
            console.error('❌ Критическая ошибка при принудительном удалении:', fallbackError);
          }
        }

        // БЕЗОПАСНОЕ закрытие: удаляем только текущее меню
        menu.remove();

      });
    }

  } startMoveMode(hotspot) {
    const markerEl = document.getElementById(`marker-${hotspot.id}`);
    if (!markerEl) return;

    // Визуальная индикация режима перемещения
    const shapeEl = markerEl.querySelector('a-sphere, a-box, a-cylinder, a-octahedron');
    if (shapeEl) {
      shapeEl.setAttribute('color', '#ff00ff');
      shapeEl.setAttribute('opacity', '0.7');
    }

    // Показываем инструкцию
    const instruction = document.createElement('div');
    instruction.style.cssText = `
            position: fixed;
            top: 20px;
            left: 50%;
            transform: translateX(-50%);
            background: rgba(26, 26, 26, 0.9);
            border: 1px solid #ff00ff;
            border-radius: 8px;
            padding: 12px 20px;
            color: rgba(255, 255, 255, 0.87);
            z-index: 10000;
        `;
    instruction.textContent = 'Кликните в новое место для перемещения маркера';
    document.body.appendChild(instruction);

    // Обработчик клика для нового позиционирования
    const moveHandler = (e) => {
      if (e.target.tagName === 'A-SKY') {
        const newPosition = this.getIntersectionPoint(e);
        if (newPosition) {
          // Обновляем позицию хотспота
          hotspot.position = `${newPosition.x} ${newPosition.y} ${newPosition.z}`;
          window.hotspotManager.updateHotspot(hotspot.id, { position: hotspot.position });

          // Убираем обработчик и восстанавливаем вид
          this.container.removeEventListener('click', moveHandler);
          if (shapeEl) {
            const defaultSettings = this.getDefaultSettings();
            const color = hotspot.color || (hotspot.type === 'hotspot' ? defaultSettings.hotspotColor : defaultSettings.infopointColor);
            shapeEl.setAttribute('color', color);
            shapeEl.setAttribute('opacity', '0.9');
          }
          instruction.remove();
        }
      }
    };

    this.container.addEventListener('click', moveHandler);
  }

  updateVisualMarker(hotspot) {

    const markerEl = document.getElementById(`marker-${hotspot.id}`);
    if (!markerEl) return;

    // Для видео-областей обновляем по-другому
    if (hotspot.type === 'video-area') {
      const videoPlane = markerEl.querySelector('a-plane');
      if (videoPlane) {
        // Ограничиваем частоту обновлений видео материала
        const now = Date.now();
        const lastUpdate = videoPlane._lastMaterialUpdate || 0;
        const timeSinceUpdate = now - lastUpdate;

        // Обновляем размеры
        videoPlane.setAttribute('width', hotspot.videoWidth || 4);
        videoPlane.setAttribute('height', hotspot.videoHeight || 3);

        // Обновляем название видео-области
        this.updateVideoAreaTitleText(markerEl, hotspot.title);
        this.updateVideoAreaTitle(markerEl, hotspot.videoHeight || 3);

        // ЗАЩИТА: сохраняем информацию о том, что видео воспроизводится
        const videoEl = this.aframeScene.querySelector(`#video-${hotspot.id}`);
        const isVideoCurrentlyPlaying = videoEl && !videoEl.paused && !videoEl.ended && videoEl.currentTime > 0;

        if (isVideoCurrentlyPlaying) {

          // НО обновляем размеры и позицию названия
          videoPlane.setAttribute('width', hotspot.videoWidth || 4);
          videoPlane.setAttribute('height', hotspot.videoHeight || 3);
          this.updateVideoAreaTitleText(markerEl, hotspot.title);
          this.updateVideoAreaTitle(markerEl, hotspot.videoHeight || 3);
          return; // Прекращаем обновление материала если видео воспроизводится
        }

        // Обновляем видео источник если изменился или создаем новый
        if (hotspot.videoUrl && hotspot.videoUrl.trim() !== '') {

          let videoEl = this.aframeScene.querySelector(`#video-${hotspot.id}`);

          // ИСПРАВЛЯЕМ: проверяем, воспроизводится ли видео и установлен ли уже материал
          const isVideoPlaying = videoEl && !videoEl.paused && !videoEl.ended && videoEl.currentTime > 0;
          const currentMaterial = videoPlane.getAttribute('material');
          const hasVideoMaterial = currentMaterial && currentMaterial.src === `#video-${hotspot.id}`;

          console.log('🎬 Проверка состояния видео:', {
            videoExists: !!videoEl,
            isPlaying: isVideoPlaying,
            hasVideoMaterial: hasVideoMaterial,
            videoUrl: hotspot.videoUrl
          });
          if (!videoEl) {
            // Создаем новый видео элемент

            const videoId = `video-${hotspot.id}`;
            videoEl = document.createElement('video');
            videoEl.id = videoId;
            videoEl.crossOrigin = 'anonymous';
            videoEl.loop = true;
            videoEl.muted = true;
            videoEl.autoplay = false; // ОТКЛЮЧАЕМ autoplay - видео должно запускаться по клику
            videoEl.controls = false;
            videoEl.style.display = 'none';
            videoEl.preload = 'metadata';

            // НЕ устанавливаем poster - он может блокировать отображение
            // videoEl.poster = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

            // Добавляем в assets
            let assets = this.aframeScene.querySelector('a-assets');
            if (!assets) {
              assets = document.createElement('a-assets');
              this.aframeScene.appendChild(assets);
            }
            assets.appendChild(videoEl);

            // Обработчики
            videoEl.addEventListener('loadeddata', () => {

              // ИСПРАВЛЯЕМ: ждем полной готовности видео перед созданием текстуры
              if (videoEl.readyState >= 2 && videoEl.videoWidth > 0 && videoEl.videoHeight > 0) {
                videoPlane.setAttribute('material', {
                  src: `#${videoId}`,
                  transparent: false,
                  side: 'double'
                });
              } else {

              }
            });

            videoEl.addEventListener('canplay', () => {

              // ИСПРАВЛЯЕМ: настраиваем материал в canplay если не было настроено
              const currentMaterial = videoPlane.getAttribute('material');
              if (!currentMaterial || !currentMaterial.src) {
                videoPlane.setAttribute('material', {
                  src: `#${videoId}`,
                  transparent: false,
                  side: 'double'
                });
              }

              // НЕ запускаем видео автоматически - только по клику пользователя

            });

            videoEl.addEventListener('error', (e) => {
              console.error('❌ Ошибка загрузки видео при обновлении:', e);
              videoPlane.setAttribute('material', {
                color: '#cc3333',
                transparent: false
              });
            });
          }

          // Устанавливаем или обновляем источник
          if (videoEl.src !== hotspot.videoUrl) {
            videoEl.src = hotspot.videoUrl;
          }

          // ИСПРАВЛЯЕМ: устанавливаем видео материал только если необходимо и прошло достаточно времени
          const shouldUpdateMaterial = (!isVideoPlaying && !hasVideoMaterial) || timeSinceUpdate > 1000; // Обновляем не чаще раза в секунду

          if (shouldUpdateMaterial && !isVideoPlaying && !hasVideoMaterial) {

            try { videoPlane.removeAttribute('text'); } catch (_) { }
            videoPlane.setAttribute('material', {
              src: `#video-${hotspot.id}`,
              transparent: false,
              side: 'double'
            });
            videoPlane._lastMaterialUpdate = now;
          } else if (isVideoPlaying && hasVideoMaterial) {

          } else if (hasVideoMaterial) {

          } else if (timeSinceUpdate <= 1000) {

          } else {

          }
        } else {
          // Нет videoUrl - показываем заглушку

          // Нейтральный фон без текста — никакого центрального текста при обычной работе
          videoPlane.setAttribute('material', {
            color: '#333333',
            transparent: false
          });
        }

        // Обновляем углы изменения размера
        const safeWidth = parseFloat(hotspot.videoWidth) || 4;
        const safeHeight = parseFloat(hotspot.videoHeight) || 3;
        this.updateResizeHandles(markerEl, safeWidth, safeHeight);
      }

      // Обновляем позицию
      markerEl.setAttribute('position', `${hotspot.position.x} ${hotspot.position.y} ${hotspot.position.z}`);
      return;
    }

    // Для 3D-iframe обновляем размеры и URL
    if (hotspot.type === 'iframe-3d') {
      const plane = markerEl.querySelector('a-plane');
      if (plane) {
        const w = parseFloat(hotspot.videoWidth) || 4;
        const h = parseFloat(hotspot.videoHeight) || 3;
        plane.setAttribute('width', w);
        plane.setAttribute('height', h);
      }

      // Обновляем позицию
      markerEl.setAttribute('position', `${hotspot.position.x} ${hotspot.position.y} ${hotspot.position.z}`);

      // Обновляем iframe URL при необходимости
      if (markerEl._iframeOverlay && hotspot.iframeUrl) {
        const iframe = markerEl._iframeOverlay.querySelector('iframe');
        if (iframe && iframe.src !== hotspot.iframeUrl) {
          iframe.src = hotspot.iframeUrl;
        }
      }
      // Обновляем ссылку на hotspot для динамического чтения размеров
      markerEl._iframeHotspot = hotspot;
      return;
    }

    // Если иконка изменилась, пересоздаем маркер
  const currentShape = markerEl.querySelector('a-sphere, a-box, a-cylinder, a-octahedron, a-plane');
  let newIcon = hotspot.icon || (hotspot.type === 'hotspot' ? 'arrow' : 'sphere');
  if (newIcon === 'scene-transition') newIcon = 'arrow';
  // Используем кэш последней иконки, чтобы не пересоздавать a-plane маркеры без нужды
  const currentIcon = markerEl._lastIcon || this.getShapeType(currentShape);

    // Проверяем, нужно ли пересоздать маркер
  const defaultSettings = this.getDefaultSettings();
  const rawSize = hotspot.size != null ? hotspot.size : (hotspot.type === 'hotspot' ? defaultSettings.hotspotSize : defaultSettings.infopointSize);
  const currentSize = parseFloat(rawSize);
    
    console.log('🔄 Проверка пересоздания маркера:', {
      currentIcon,
      newIcon,
      lastColor: markerEl._lastColor,
      newColor: hotspot.color,
      lastNoFill: markerEl._lastNoFill,
      newNoFill: hotspot.noFill,
      lastSize: markerEl._lastSize,
      newSize: currentSize,
      isPlane: currentShape && currentShape.tagName.toLowerCase() === 'a-plane'
    });
    
    const needsRecreation = currentIcon !== newIcon || 
      // Для современных SVG маркеров (a-plane) нужно пересоздание при изменении цвета, noFill или размера
      (currentShape && currentShape.tagName.toLowerCase() === 'a-plane' && 
  (markerEl._lastColor !== hotspot.color || 
   markerEl._lastNoFill !== hotspot.noFill ||
   parseFloat(markerEl._lastSize) !== currentSize));

  if (needsRecreation) {

      // Пересоздаем маркер с новой геометрией или обновленными параметрами
      this.removeVisualMarker(hotspot.id);
      this.createVisualMarker(hotspot);
      return;
    }

    // Обновляем позицию
    markerEl.setAttribute('position', `${hotspot.position.x} ${hotspot.position.y} ${hotspot.position.z}`);

    // Обновляем текст (3D-текст отключен; оставлено на случай будущего включения)
    const textContainer = markerEl.querySelector('a-entity');
    const textEl = textContainer ? textContainer.querySelector('[cyrillic-text]') : null;
    if (textEl) {
      const textScale = parseFloat(hotspot.textSize || 1);
      textEl.setAttribute('cyrillic-text', {
        value: (hotspot.title || 'Без названия'),
        color: hotspot.textColor || '#ffffff',
        align: 'center',
        family: hotspot.textFamily || 'Arial, sans-serif',
        bold: !!hotspot.textBold,
        underline: !!hotspot.textUnderline
      });
      if (!isNaN(textScale) && textScale > 0) {
        textEl.setAttribute('scale', `${textScale} ${textScale} ${textScale}`);
      } else {
        textEl.removeAttribute('scale');
      }
    }

    // Обновляем цвет/материал и размер маркера
    if (currentShape) {
      const defaultSettings = this.getDefaultSettings();
      const size = hotspot.size || (hotspot.type === 'hotspot' ? defaultSettings.hotspotSize : defaultSettings.infopointSize);
      const color = hotspot.color || (hotspot.type === 'hotspot' ? defaultSettings.hotspotColor : defaultSettings.infopointColor);

      // Обновляем материал корректно: для примитивов обязательно через material-компонент
      if (currentShape.tagName && currentShape.tagName.toLowerCase() !== 'a-plane') {
        const existingMat = currentShape.getAttribute('material') || {};
        const transparent = !!hotspot.noFill;
        const opacity = transparent ? 0.15 : 1.0;
        currentShape.setAttribute('material', {
          ...existingMat,
          color: color,
          transparent,
          opacity,
          metalness: 0,
          roughness: 1
        });
      }

  // Устанавливаем размер в зависимости от типа геометрии
      // Для современных маркеров (a-plane с текстурой) нужно обновлять width/height
      if (currentShape.tagName && currentShape.tagName.toLowerCase() === 'a-plane') {
        // marker size is radius-like; use adjusted scale (radius * 2.0) to match UI presets
        const markerSize = (size * 2.0);
        currentShape.setAttribute('width', markerSize);
        currentShape.setAttribute('height', markerSize);
      } else {
        switch (newIcon) {
          case 'cube':
            currentShape.setAttribute('width', size);
            currentShape.setAttribute('height', size);
            currentShape.setAttribute('depth', size);
            break;
          case 'cylinder':
            currentShape.setAttribute('radius', size);
            currentShape.setAttribute('height', size * 2);
            break;
          default: // sphere, octahedron
            currentShape.setAttribute('radius', size);
            break;
        }
      }

      // После успешного обновления без пересоздания — синхронизируем кэш сравнения
      markerEl._lastColor = hotspot.color || markerEl._lastColor;
      markerEl._lastNoFill = !!hotspot.noFill;
      markerEl._lastSize = parseFloat(size);
      markerEl._lastIcon = newIcon;

      // Если tooltip уже открыт — обновим его содержимое на лету
      if (markerEl._domTooltip) {
        const tip = markerEl._domTooltip;
        const title = this.removeFileExtension(hotspot.title || 'Информация');
        const escapeHtml = (s) => String(s)
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;')
          .replace(/"/g, '&quot;')
          .replace(/'/g, '&#39;');
        const hasDesc = !!hotspot.description;
        const descHtml = hasDesc ? `<div class=\"desc\">${escapeHtml(hotspot.description).replace(/\n/g, '<br>')}</div>` : '';
        const sep = hasDesc ? '<hr class=\"tour-tip-sep\" />' : '';
        tip.innerHTML = `<div class=\"title\">${title}</div>${sep}${descHtml}`;
        // Обновляем стили текста у уже открытого тултипа (цвет, размер, шрифт, жирность, подчёркивание)
        try {
          const titleEl = tip.querySelector('.title');
          const descEl = tip.querySelector('.desc');
          const color = hotspot.textColor || '#ffffff';
          if (titleEl) titleEl.style.color = color;
          if (descEl) descEl.style.color = color;
          const fontSizePx = Math.round((hotspot.textSize || 1) * 16);
          if (titleEl && hotspot.textSize) titleEl.style.fontSize = `${fontSizePx}px`;
          if (descEl && hotspot.textSize) descEl.style.fontSize = `${fontSizePx}px`;
          const family = hotspot.textFamily || 'Arial, sans-serif';
          if (titleEl) titleEl.style.fontFamily = family;
          if (descEl) descEl.style.fontFamily = family;
          const weight = hotspot.textBold ? '700' : '400';
          if (titleEl) titleEl.style.fontWeight = weight;
          if (descEl) descEl.style.fontWeight = weight;
          const decoration = hotspot.textUnderline ? 'underline' : 'none';
          if (titleEl) titleEl.style.textDecoration = decoration;
          if (descEl) descEl.style.textDecoration = decoration;
        } catch (_) { /* noop */ }
      }
    }
  }

  getShapeType(element) {
    if (!element) return 'sphere';
    const tagName = element.tagName.toLowerCase();
    switch (tagName) {
      case 'a-box': return 'cube';
      case 'a-cylinder': return 'cylinder';
      case 'a-octahedron': return 'octahedron';
  case 'a-plane': return 'plane';
      default: return 'sphere';
    }
  }

  removeVisualMarker(hotspotId) {
    const markerEl = document.getElementById(`marker-${hotspotId}`);
    if (markerEl) {

      // ВАЖНО: Очищаем видео ресурсы для видео-областей
      const videoEl = document.getElementById(`video-${hotspotId}`);
      if (videoEl) {

        // Останавливаем видео
        if (!videoEl.paused) {
          videoEl.pause();
        }

        // Очищаем src для освобождения памяти
        videoEl.src = '';
        videoEl.removeAttribute('src');

        // Удаляем из DOM
        videoEl.remove();
      }

      // Очистка DOM-оверлея для iframe-3d
      if (markerEl._iframeOverlay) {
        try {
          const overlay = markerEl._iframeOverlay;
          if (overlay._raf) cancelAnimationFrame(overlay._raf);
          if (markerEl._iframeOnResize) window.removeEventListener('resize', markerEl._iframeOnResize);
          overlay.remove();
        } catch (e) { /* noop */ }
        markerEl._iframeOverlay = null;
        markerEl._iframeOnResize = null;
      }

      // Очищаем coordinate manager связи
      if (this.coordinateManager) {
        this.coordinateManager.cleanupMarker(hotspotId);
      }

      // Очистка ассетов (img в a-assets) и освобождение blob URL, привязанных к маркеру
      try {
        const assets = this.aframeScene && this.aframeScene.querySelector ? this.aframeScene.querySelector('a-assets') : null;
        if (assets && markerEl._assetIds && Array.isArray(markerEl._assetIds)) {
          markerEl._assetIds.forEach(id => {
            const img = document.getElementById(id);
            if (img && img.parentElement === assets) {
              try { assets.removeChild(img); } catch (e) { /* noop */ }
            } else if (img) {
              // если элемент переехал, все равно пытаемся удалить
              try { img.remove(); } catch (e) { /* noop */ }
            }
          });
        }
        if (markerEl._assetUrls && Array.isArray(markerEl._assetUrls)) {
          markerEl._assetUrls.forEach(url => {
            try { URL.revokeObjectURL(url); } catch (_) { /* noop */ }
          });
        }
      } catch (e) {

      }

      // Удаляем маркер из DOM (это автоматически удалит все дочерние элементы и их обработчики)
      markerEl.remove();

    } else {

    }
  }

  getViewer() {
    return {
      container: this.container,
      scene: this.aframeScene,
      camera: this.aframeCamera,
      sky: this.aframeSky
    };
  }

  // Скрывает визуальный маркер (для предотвращения следования за курсором при редактировании)
  hideMarker(hotspotId) {
    try {
      const markerEl = document.getElementById(`marker-${hotspotId}`);
      if (markerEl) {
        markerEl.style.display = 'none';
        markerEl._wasHiddenForEdit = true;
      }
    } catch (e) { console.warn('hideMarker error', e); }
  }

  // Показывает визуальный маркер, если он был скрыт для редактирования
  showMarker(hotspotId) {
    try {
      const markerEl = document.getElementById(`marker-${hotspotId}`);
      if (markerEl && markerEl._wasHiddenForEdit) {
        markerEl.style.display = '';
        markerEl._wasHiddenForEdit = false;
      }
    } catch (e) { console.warn('showMarker error', e); }
  }

  clearMarkers() {
    const markers = this.aframeScene.querySelectorAll('[data-hotspot-id]');

    markers.forEach(marker => {
      const hotspotId = marker.getAttribute('data-hotspot-id');
      this.removeVisualMarker(hotspotId);
    });
  } updateCameraSettings(settings) {
    if (this.aframeCamera && settings.mouseSensitivity) {
      // Обновляем чувствительность мыши для look-controls
      const lookControls = this.aframeCamera.getAttribute('look-controls');
      this.aframeCamera.setAttribute('look-controls', {
        ...lookControls,
        mouseSensitivity: settings.mouseSensitivity,
        touchSensitivity: settings.mouseSensitivity
      });
    }

    // Сохраняем настройки скорости зума
    if (settings.zoomSpeed) {
      this.zoomSpeed = settings.zoomSpeed;
    }

    // Применяем гироскоп
    if (typeof settings.gyroEnabled === 'boolean') {
      this.enableGyro(settings.gyroEnabled);
    }
  }

  setupZoomControls() {
    // Управление зумом колесиком мыши - привязываем к document для работы в любом месте
    document.addEventListener('wheel', (e) => {
      // ПРИОРИТЕТ: Если зажат Shift - это изменение размера видео-области, а НЕ зум
      if (e.shiftKey) {
        // Проверяем, что мышь находится над A-Frame сценой
        if (!e.target.closest('a-scene') && !e.target.matches('canvas')) {
          return;
        }

        // Находим видео-область под курсором мыши
        const intersectedElements = this.raycastFromMouse(e);
        let targetVideoArea = null;
        let targetMarker = null;

        for (const intersection of intersectedElements) {
          const element = intersection.object.el;
          if (element && element.getAttribute('data-video-plane')) {
            targetVideoArea = element;
            targetMarker = element.parentNode;
            break;
          }
        }

        if (!targetVideoArea || !targetMarker) {
          return; // Нет видео-области под курсором
        }

        e.preventDefault();
        e.stopPropagation();

        // Находим соответствующий хотспот
        const markerId = targetMarker.getAttribute('data-marker-id');
        const hotspot = this.hotspotManager.hotspots.find(h => h.id === markerId);

        if (!hotspot) {

          return;
        }

        // Текущие размеры с проверкой на корректность
        let currentWidth = parseFloat(hotspot.videoWidth);
        let currentHeight = parseFloat(hotspot.videoHeight);

        // Проверяем корректность значений и устанавливаем значения по умолчанию
        if (isNaN(currentWidth) || currentWidth <= 0) {
          currentWidth = 4;
          hotspot.videoWidth = currentWidth;
        }
        if (isNaN(currentHeight) || currentHeight <= 0) {
          currentHeight = 3;
          hotspot.videoHeight = currentHeight;
        }

        // Вычисляем новые размеры
        const resizeStep = 0.2; // Шаг изменения размера
        const delta = e.deltaY > 0 ? -resizeStep : resizeStep; // Обратная логика для интуитивности

        let newWidth = currentWidth + delta;
        let newHeight = currentHeight + delta * (currentHeight / currentWidth); // Сохраняем пропорции

        // Ограничиваем размеры
        newWidth = Math.max(0.5, Math.min(20, newWidth));
        newHeight = Math.max(0.5, Math.min(20, newHeight));

        // Дополнительная проверка на корректность новых размеров
        if (isNaN(newWidth) || isNaN(newHeight)) {

          newWidth = 4;
          newHeight = 3;
        }

        // Обновляем размеры в хотспоте
        hotspot.videoWidth = newWidth;
        hotspot.videoHeight = newHeight;

        // Обновляем размеры видео-области
        targetVideoArea.setAttribute('width', newWidth);
        targetVideoArea.setAttribute('height', newHeight);

        // Обновляем позиции углов изменения размера
        this.updateResizeHandles(targetMarker, newWidth, newHeight);

        // Обновляем позицию текста названия
        this.updateVideoAreaTitle(targetMarker, newHeight);

        // Сохраняем изменения
        this.hotspotManager.saveHotspots();

        return; // Выходим, чтобы НЕ обрабатывать зум
      }

      // ОБЫЧНЫЙ ЗУМ (только если НЕ зажат Shift)
      // Проверяем, что мышь находится над A-Frame сценой
      if (!e.target.closest('a-scene') && !e.target.matches('canvas')) {
        return; // Если мышь не над сценой, не обрабатываем
      }

      // Проверяем готовность сцены и камеры
      if (!this.aframeCamera || !this.aframeScene) {

        return;
      }

      e.preventDefault();
      e.stopPropagation();

      const currentFov = parseFloat(this.aframeCamera.getAttribute('fov')) || 80;

      // Более плавный зум: уменьшаем базовый шаг и делаем его зависимым от текущего FOV
      const baseZoomStep = 2.5; // Уменьшен для более плавного зума
      const fovFactor = currentFov / 80; // Нормализация относительно стандартного FOV
      const adaptiveZoomStep = baseZoomStep * fovFactor * (this.zoomSpeed || 1);

      const delta = e.deltaY > 0 ? adaptiveZoomStep : -adaptiveZoomStep;
      let newFov = currentFov + delta;

      // Ограничиваем зум (FOV от 10 до 130 градусов для большего диапазона)
      newFov = Math.max(10, Math.min(130, newFov));

      // Применяем новый FOV и принудительно обновляем камеру
      this.aframeCamera.setAttribute('fov', newFov);
      // Принудительно обновляем Three.js камеру несколькими способами
      setTimeout(() => {
        if (this.aframeCamera.getObject3D('camera')) {
          this.aframeCamera.getObject3D('camera').updateProjectionMatrix();
          this.aframeCamera.getObject3D('camera').fov = newFov;
          this.aframeCamera.getObject3D('camera').updateProjectionMatrix();
        }
        // Дополнительно принудительно обновляем A-Frame компонент
        if (this.aframeCamera.components && this.aframeCamera.components.camera) {
          this.aframeCamera.flushToDOM();
        }
      }, 0);

      // Обновляем индикатор зума
      this.updateZoomIndicator(newFov);

      // Отладочная информация с процентами
      const oldZoom = Math.round((80 / currentFov) * 100);
      const newZoom = Math.round((80 / newFov) * 100);

    }, { passive: false }); // ВАЖНО: passive: false для возможности preventDefault()

    // Управление зумом кнопками + и -
    document.addEventListener('keydown', (e) => {
      if (e.key === '+' || e.key === '=') {
        this.zoomIn();
      } else if (e.key === '-') {
        this.zoomOut();
      }
    });

    // Pinch-to-zoom на тач-устройствах
    const sceneEl = this.aframeScene;
    if (sceneEl) {
      sceneEl.addEventListener('touchstart', (e) => {
        if (e.touches && e.touches.length === 2) {
          this._pinch.active = true;
          const dx = e.touches[0].clientX - e.touches[1].clientX;
          const dy = e.touches[0].clientY - e.touches[1].clientY;
          this._pinch.startDist = Math.hypot(dx, dy);
          this._pinch.startFov = (this.aframeCamera && typeof this.aframeCamera.getAttribute === 'function' ? parseFloat(this.aframeCamera.getAttribute('fov')) : NaN) || 80;
        }
      }, { passive: false });

      sceneEl.addEventListener('touchmove', (e) => {
        if (this._pinch.active && e.touches && e.touches.length === 2) {
          e.preventDefault();
          const dx = e.touches[0].clientX - e.touches[1].clientX;
          const dy = e.touches[0].clientY - e.touches[1].clientY;
          const dist = Math.hypot(dx, dy);
          if (this._pinch.startDist > 0) {
            const scale = this._pinch.startDist / dist; // больше расстояние -> zoom in
            let newFov = this._pinch.startFov * scale;
            newFov = Math.max(10, Math.min(130, newFov));
            this.aframeCamera.setAttribute('fov', newFov);
            if (this.aframeCamera.getObject3D('camera')) {
              this.aframeCamera.getObject3D('camera').fov = newFov;
              this.aframeCamera.getObject3D('camera').updateProjectionMatrix();
            }
            this.updateZoomIndicator(newFov);
          }
        }
      }, { passive: false });

      const endPinch = () => { this._pinch.active = false; };
      sceneEl.addEventListener('touchend', endPinch, { passive: true });
      sceneEl.addEventListener('touchcancel', endPinch, { passive: true });
    }
  }

  // === Гироскоп ===
  async enableGyro(enabled) {
    this.gyroEnabled = !!enabled;
    if (!this.aframeCamera) return;
    const current = this.aframeCamera.getAttribute('look-controls') || {};
    if (this.gyroEnabled) {
      // Запросим разрешение при необходимости (iOS 13+)
      try { await this.requestGyroPermission(); } catch (e) { console.warn('Гироскоп: разрешение не выдано', e); }
      this.aframeCamera.setAttribute('look-controls', {
        ...current,
        enabled: true,
        magicWindowTrackingEnabled: true,
        pointerLockEnabled: false,
      });
    } else {
      this.aframeCamera.setAttribute('look-controls', {
        ...current,
        magicWindowTrackingEnabled: false
      });
    }
  }

  async requestGyroPermission() {
    const w = window;
    const needPerm = typeof w.DeviceOrientationEvent !== 'undefined' && typeof w.DeviceOrientationEvent.requestPermission === 'function';
    if (needPerm) {
      try {
        const res = await w.DeviceOrientationEvent.requestPermission();
        return res === 'granted';
      } catch (e) {
        return false;
      }
    }
    return true; // На Android обычно не требуется
  }

  zoomIn() {
    if (!this.aframeCamera || !this.aframeScene) {

      return;
    }

    const currentFov = parseFloat(this.aframeCamera.getAttribute('fov')) || 80;
    const zoomStep = 5 * (this.zoomSpeed || 1);
    const newFov = Math.max(10, currentFov - zoomStep);

    // Устанавливаем новый FOV и принудительно обновляем камеру
    this.aframeCamera.setAttribute('fov', newFov);
    // Принудительно обновляем Three.js камеру несколькими способами
    setTimeout(() => {
      if (this.aframeCamera.getObject3D('camera')) {
        this.aframeCamera.getObject3D('camera').updateProjectionMatrix();
        this.aframeCamera.getObject3D('camera').fov = newFov;
        this.aframeCamera.getObject3D('camera').updateProjectionMatrix();
      }
      // Дополнительно принудительно обновляем A-Frame компонент
      if (this.aframeCamera.components && this.aframeCamera.components.camera) {
        this.aframeCamera.flushToDOM();
      }
    }, 0);
    this.updateZoomIndicator(newFov);

    const oldZoom = Math.round((80 / currentFov) * 100);
    const newZoom = Math.round((80 / newFov) * 100);

  }

  zoomOut() {
    if (!this.aframeCamera || !this.aframeScene) {

      return;
    }

    const currentFov = parseFloat(this.aframeCamera.getAttribute('fov')) || 80;
    const zoomStep = 5 * (this.zoomSpeed || 1);
    const newFov = Math.min(130, currentFov + zoomStep);

    // Устанавливаем новый FOV и принудительно обновляем камеру
    this.aframeCamera.setAttribute('fov', newFov);
    // Принудительно обновляем Three.js камеру несколькими способами
    setTimeout(() => {
      if (this.aframeCamera.getObject3D('camera')) {
        this.aframeCamera.getObject3D('camera').updateProjectionMatrix();
        this.aframeCamera.getObject3D('camera').fov = newFov;
        this.aframeCamera.getObject3D('camera').updateProjectionMatrix();
      }
      // Дополнительно принудительно обновляем A-Frame компонент
      if (this.aframeCamera.components && this.aframeCamera.components.camera) {
        this.aframeCamera.flushToDOM();
      }
    }, 0);
    this.updateZoomIndicator(newFov);

    const oldZoom = Math.round((80 / currentFov) * 100);
    const newZoom = Math.round((80 / newFov) * 100);

  }

  resetZoom() {
    if (!this.aframeCamera || !this.aframeScene) {

      return;
    }

    const currentFov = parseFloat(this.aframeCamera.getAttribute('fov')) || 80;

    // Устанавливаем FOV на 80 и принудительно обновляем камеру
    this.aframeCamera.setAttribute('fov', 80);
    // Принудительно обновляем Three.js камеру несколькими способами
    setTimeout(() => {
      if (this.aframeCamera.getObject3D('camera')) {
        this.aframeCamera.getObject3D('camera').updateProjectionMatrix();
        this.aframeCamera.getObject3D('camera').fov = 80;
        this.aframeCamera.getObject3D('camera').updateProjectionMatrix();
      }
      // Дополнительно принудительно обновляем A-Frame компонент
      if (this.aframeCamera.components && this.aframeCamera.components.camera) {
        this.aframeCamera.flushToDOM();
      }
    }, 0);
    this.updateZoomIndicator(80);

    const oldZoom = Math.round((80 / currentFov) * 100);

  }

  /**
   * Обновляет индикатор зума в пользовательском интерфейсе
   */
  updateZoomIndicator(fov) {
    const zoomValueElement = document.getElementById('zoom-value');
    if (zoomValueElement) {
      // Преобразуем FOV в понятный процент зума
      // FOV 80° = 100% (базовый уровень)
      // FOV 40° = 200% (приближение в 2 раза)
      // FOV 160° = 50% (отдаление в 2 раза)
      const zoomPercent = Math.round((80 / fov) * 100);
      zoomValueElement.textContent = `${zoomPercent}%`;

      // Добавим цветовое кодирование
      const indicator = document.getElementById('zoom-indicator');
      if (indicator) {
        if (zoomPercent > 150) {
          indicator.style.background = 'rgba(0, 128, 0, 0.8)'; // Зеленый для сильного приближения
        } else if (zoomPercent < 75) {
          indicator.style.background = 'rgba(128, 0, 0, 0.8)'; // Красный для сильного отдаления
        } else {
          indicator.style.background = 'rgba(0, 0, 0, 0.7)'; // Обычный цвет
        }

        // Анимация мигания для привлечения внимания
        indicator.style.transform = 'scale(1.1)';
        indicator.style.transition = 'all 0.2s ease';
        setTimeout(() => {
          indicator.style.transform = 'scale(1)';
        }, 200);
      }

      // ОТКЛЮЧЕНО: убираем всплывающие уведомления о зуме
      // this.showZoomNotification(zoomPercent);

      // Убираем консольные сообщения о зуме (слишком спамят)
      // console.log(`🔍 Зум: ${zoomPercent}% (FOV: ${fov.toFixed(1)}°)`);
    }
  }

  /**
   * Показывает временное уведомление об изменении зума
   */
  showZoomNotification(zoomPercent) {
    // Удаляем предыдущее уведомление
    const existingNotification = document.getElementById('zoom-notification');
    if (existingNotification) {
      existingNotification.remove();
    }

    // Создаем новое уведомление
    const notification = document.createElement('div');
    notification.id = 'zoom-notification';
    notification.style.cssText = `
      position: fixed;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      background: rgba(0, 0, 0, 0.8);
      color: white;
      padding: 15px 25px;
      border-radius: 10px;
      font-size: 24px;
      font-weight: bold;
      z-index: 10000;
      pointer-events: none;
      animation: zoomNotificationFade 1s ease;
    `;
    notification.textContent = `🔍 ${zoomPercent}%`;

    // Добавляем CSS анимацию если её ещё нет
    if (!document.getElementById('zoom-notification-style')) {
      const style = document.createElement('style');
      style.id = 'zoom-notification-style';
      style.textContent = `
        @keyframes zoomNotificationFade {
          0% { opacity: 0; transform: translate(-50%, -50%) scale(0.5); }
          20% { opacity: 1; transform: translate(-50%, -50%) scale(1.1); }
          80% { opacity: 1; transform: translate(-50%, -50%) scale(1); }
          100% { opacity: 0; transform: translate(-50%, -50%) scale(0.9); }
        }
      `;
      document.head.appendChild(style);
    }

    document.body.appendChild(notification);

    // Удаляем уведомление через 1 секунду
    setTimeout(() => {
      if (notification.parentNode) {
        notification.remove();
      }
    }, 1000);
  }

  /**
   * УЛУЧШЕННАЯ система очистки контекстных меню с удалением обработчиков
   */
  cleanupAutoCloseHandlers() {
    // КРИТИЧЕСКИ ВАЖНО: Очищаем все активные auto-close обработчики
    if (this._activeAutoCloseHandlers) {

      this._activeAutoCloseHandlers.forEach(handler => {
        document.removeEventListener('click', handler, true);
        document.removeEventListener('mousedown', handler, true);
      });

      this._activeAutoCloseHandlers.clear();

    }
  }

  /**
   * Получение текущих настроек по умолчанию
   */
  getDefaultSettings() {
    return {
  // Базовые размеры: "Обычный" теперь 0.6 (в 2 раза больше прежнего 0.3)
  hotspotSize: 0.6,
  hotspotColor: '#ffffff',
  infopointSize: 0.6,
  infopointColor: '#ffffff'
    };
  }

  /**
   * Убирает расширение файла из названия
   */
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
   * Удаляет старые элементы из видео-областей
   */
  removeOldDarkElements() {
    // Удаляем старые кнопки воспроизведения (зеленые элементы)
    const oldPlayButtons = document.querySelectorAll('.video-play-button');
    oldPlayButtons.forEach(button => {

      button.remove();
    });

    // Удаляем старые текстовые элементы без подложки
    const oldTitleTexts = document.querySelectorAll('.video-title-text');
    oldTitleTexts.forEach(text => {

      text.remove();
    });

    // Исправляем материалы видео-областей с прозрачными цветами
    const videoPlanes = document.querySelectorAll('[data-video-plane]');
    videoPlanes.forEach(plane => {
      const material = plane.getAttribute('material');
      if (material && material.opacity && parseFloat(material.opacity) < 0.5) {

        plane.setAttribute('material', {
          color: '#666666',
          opacity: 1.0,
          transparent: false,
          side: 'double',
          shader: 'flat'
        });
      }
    });
  }

  /**
   * Создание видео-области с улучшенной интеграцией и поддержкой налипания на объекты сцены
   */
  createVideoArea(hotspot, markerEl) {

    // ОЧИСТКА: Удаляем старые темные элементы если они есть
    this.removeOldDarkElements();

    // Проверяем, что hotspot имеет базовые свойства
    if (!hotspot || !hotspot.id) {
      console.error('❌ Некорректный hotspot - отсутствует id:', hotspot);
      return null;
    }

    // Проверяем и устанавливаем позицию по умолчанию если нужно
    if (!hotspot.position) {

      hotspot.position = { x: 0, y: 0, z: -3 };
    }

    // Если markerEl не передан, создаем его
    if (!markerEl) {

      markerEl = document.createElement('a-entity');
      markerEl.id = `marker-${hotspot.id}`;
      markerEl.setAttribute('data-hotspot-id', hotspot.id);
      markerEl.setAttribute('data-marker-id', hotspot.id);

      // Позиционируем маркер
      const posStr = `${hotspot.position.x} ${hotspot.position.y} ${hotspot.position.z}`;

      markerEl.setAttribute('position', posStr);

      // Устанавливаем класс для интерактивности
      markerEl.className = 'interactive video-area';

      // НОВОЕ: Добавляем улучшенный компонент для постоянной ориентации к камере
      if (!AFRAME.components['face-camera']) {
        AFRAME.registerComponent('face-camera', {
          init: function () {
            this.cameraEl = null;
            this.tick = this.tick.bind(this);
            this.findCamera();

          },

          findCamera: function () {
            // Ищем камеру различными способами
            this.cameraEl = document.querySelector('[camera]') ||
              document.querySelector('a-camera') ||
              document.querySelector('#defaultCamera');

            if (!this.cameraEl) {
              const scene = document.querySelector('a-scene');
              if (scene && scene.camera && scene.camera.el) {
                this.cameraEl = scene.camera.el;
              }
            }

            if (this.cameraEl) {

            } else {

            }
          },

          tick: function () {
            if (!this.cameraEl) {
              this.findCamera();
              return;
            }

            // Получаем мировые позиции камеры и элемента
            const cameraWorldPosition = new THREE.Vector3();
            const elementWorldPosition = new THREE.Vector3();

            this.cameraEl.object3D.getWorldPosition(cameraWorldPosition);
            this.el.object3D.getWorldPosition(elementWorldPosition);

            // Вычисляем направление к камере ТОЛЬКО по горизонтали
            const direction = new THREE.Vector3();
            direction.subVectors(cameraWorldPosition, elementWorldPosition);
            direction.y = 0; // ВАЖНО: игнорируем вертикальное направление
            direction.normalize();

            // Проверяем, что направление корректное
            if (direction.length() > 0) {
              // Вычисляем угол поворота по Y-оси - ИСПРАВЛЕНО: убираем Math.PI для правильной фронтальной ориентации
              const angle = Math.atan2(direction.x, direction.z);

              // Применяем поворот ТОЛЬКО по Y-оси
              this.el.object3D.rotation.set(0, angle, 0);
            }
          }
        });

      }

      // Регистрируем компонент для навигационной стрелки
      if (!AFRAME.components['navigation-arrow']) {
        AFRAME.registerComponent('navigation-arrow', {
          init: function () {
            this.cameraEl = null;
            this.tick = this.tick.bind(this);
            this.findCamera();

          },

          findCamera: function () {
            // Ищем камеру различными способами
            this.cameraEl = document.querySelector('[camera]') ||
              document.querySelector('a-camera') ||
              document.querySelector('#defaultCamera');

            if (!this.cameraEl) {
              const scene = document.querySelector('a-scene');
              if (scene && scene.camera && scene.camera.el) {
                this.cameraEl = scene.camera.el;
              }
            }

            if (this.cameraEl) {

            } else {

            }
          },

          tick: function () {
            if (!this.cameraEl) {
              this.findCamera();
              return;
            }

            // Получаем мировые позиции камеры и элемента
            const cameraWorldPosition = new THREE.Vector3();
            const elementWorldPosition = new THREE.Vector3();

            this.cameraEl.object3D.getWorldPosition(cameraWorldPosition);
            this.el.object3D.getWorldPosition(elementWorldPosition);

            // Вычисляем направление ОТ камеры (противоположное направление)
            const direction = new THREE.Vector3();
            direction.subVectors(elementWorldPosition, cameraWorldPosition);
            direction.y = 0; // Игнорируем вертикальное направление для плоской навигации
            direction.normalize();

            // Проверяем, что направление корректное
            if (direction.length() > 0) {
              // Вычисляем угол поворота по Y-оси для направления ОТ камеры
              const angle = Math.atan2(direction.x, direction.z);

              // Применяем поворот ТОЛЬКО по Y-оси, стрелка указывает вперёд (в направлении от камеры)
              this.el.object3D.rotation.set(0, angle, 0);
            }
          }
        });

      }

      // НЕ применяем компонент face-camera к самому маркеру для избежания конфликтов
      // markerEl.setAttribute('face-camera', '');

      // ВАЖНО: Принудительно устанавливаем видимость маркера
      markerEl.setAttribute('visible', 'true');
    }

    // Создаем плоскость для видео с улучшенным подходом
    const videoPlane = document.createElement('a-plane');// Убеждаемся, что размеры корректные
    let width = parseFloat(hotspot.videoWidth) || 4;
    let height = parseFloat(hotspot.videoHeight) || 3;

    // Дополнительная проверка на NaN
    if (isNaN(width) || width <= 0) width = 4;
    if (isNaN(height) || height <= 0) height = 3;

    // Сохраняем корректные размеры обратно в хотспот
    hotspot.videoWidth = width;
    hotspot.videoHeight = height;

    videoPlane.setAttribute('width', width);
    videoPlane.setAttribute('height', height);
    videoPlane.className = 'interactive video-area video-plane';
    videoPlane.setAttribute('data-video-plane', 'true'); // Для поиска в getResizeHandleAt
    videoPlane.setAttribute('billboard', ''); // Всегда направлено к камере

    // ВАЖНО: Принудительно устанавливаем видимость
    videoPlane.setAttribute('visible', 'true');

    // ЯВНО отключаем любые hover-анимации/пульсации и фиксируем масштаб для видео-области
    try {
      videoPlane.removeAttribute('animation__hover_on');
      videoPlane.removeAttribute('animation__hover_off');
      videoPlane.removeAttribute('animation__pulse');
    } catch (_) { /* no-op */ }
    videoPlane.setAttribute('scale', '1 1 1');
    const __ensureUnitScale = () => { try { videoPlane.setAttribute('scale', '1 1 1'); } catch (_) { } };
    videoPlane.addEventListener('mouseenter', __ensureUnitScale, true);
    videoPlane.addEventListener('mouseleave', __ensureUnitScale, true);

    // ИСПРАВЛЕНО: если есть видео, показываем постер/миниатюру (если доступна) вместо серого и текста
    if (hotspot.videoUrl && hotspot.videoUrl.trim() !== '') {
      let posterUrl = hotspot.poster;
      if ((!posterUrl || !posterUrl.trim()) && window.hotspotManager && typeof window.hotspotManager.getPoster === 'function') {
        posterUrl = window.hotspotManager.getPoster(hotspot.id);
      }

      if (posterUrl) {
        videoPlane.setAttribute('material', { shader: 'flat', side: 'double', src: posterUrl, transparent: false });
      } else {
        // Нейтральный тёмный фон без текста
        videoPlane.setAttribute('material', { shader: 'flat', side: 'double', color: '#222222', transparent: false, alphaTest: 0.1 });
      }
    } else {
      // Если нет видео - устанавливаем материал-заглушку для настройки
      videoPlane.setAttribute('material', {
        shader: 'flat',
        side: 'double',
        color: '#333333', // Темно-серый фон для настройки
        transparent: false,
        alphaTest: 0.1
      });

      // Больше не показываем центральный текст — заглушка только цветом
    }

    // Удаляем рамку по запросу пользователя - видео-область должна быть без дополнительных элементов

    // Подготавливаем видео URL
    // Берем актуальный videoUrl (через HotspotManager c восстановлением)
    let videoUrl = hotspot.videoUrl;
    if ((!videoUrl || !videoUrl.trim()) && window.hotspotManager && typeof window.hotspotManager.getHotspotWithFullData === 'function') {
      const restored = window.hotspotManager.getHotspotWithFullData(hotspot.id);
      if (restored && restored.videoUrl) {
        videoUrl = restored.videoUrl;
        // Синхронизируем обратно в хотспот и в реестр
        hotspot.videoUrl = videoUrl;
        if (typeof window.hotspotManager.registerVideoUrl === 'function') {
          window.hotspotManager.registerVideoUrl(hotspot.id, videoUrl);
        }
      }
    }

    // ВСЕГДА создаем видео элемент для будущего использования
    const videoId = `video-${hotspot.id}`;
    let videoEl = document.getElementById(videoId);

    // Добавляем улучшенный обработчик событий для видео
    if (!videoEl) {

      videoEl = document.createElement('video');
      videoEl.id = videoId;
      videoEl.crossOrigin = 'anonymous';
      videoEl.loop = true;
      videoEl.muted = false; // ИЗМЕНЕНО: начинаем с включенным звуком
      videoEl.autoplay = false; // Автозапуск отключен
      videoEl.controls = false;
      videoEl.style.display = 'none';
      videoEl.preload = 'metadata';

      // НОВОЕ: Добавляем поддержку звука
      videoEl.volume = 0.7; // Устанавливаем громкость по умолчанию
      videoEl.setAttribute('data-has-audio', 'false'); // Флаг наличия звука

      // НОВОЕ: Улучшенное отслеживание состояния видео и звука
      videoEl.addEventListener('loadeddata', () => {

        // КРИТИЧЕСКИ ВАЖНО: Применяем видео-материал КАК ТОЛЬКО данные загружены
        if (videoEl.readyState >= 2 && videoEl.videoWidth > 0 && videoEl.videoHeight > 0) {

          videoPlane.setAttribute('material', {
            src: `#${videoId}`,
            transparent: false,
            side: 'double',
            shader: 'flat'
          });
          // Убираем любой текст-заглушку
          try { videoPlane.removeAttribute('text'); } catch (_) { }

          // Попытка сгенерировать постер из текущего кадра, если он ещё не сохранён
          try {
            const hasPoster = !!hotspot.poster || (window.hotspotManager && typeof window.hotspotManager.getPoster === 'function' && window.hotspotManager.getPoster(hotspot.id));
            if (!hasPoster && window.hotspotManager && typeof window.hotspotManager.registerPoster === 'function') {
              const canvas = document.createElement('canvas');
              const maxW = 640;
              const scale = Math.min(1, maxW / videoEl.videoWidth);
              canvas.width = Math.round(videoEl.videoWidth * scale);
              canvas.height = Math.round(videoEl.videoHeight * scale);
              const ctx = canvas.getContext('2d');
              ctx.drawImage(videoEl, 0, 0, canvas.width, canvas.height);
              const dataUrl = canvas.toDataURL('image/jpeg', 0.7);
              if (dataUrl && dataUrl.startsWith('data:image')) {
                window.hotspotManager.registerPoster(hotspot.id, dataUrl);
              }
            }
          } catch (e) {

          }
        }

        // Проверяем наличие аудиодорожки
        const hasAudio = videoEl.mozHasAudio ||
          Boolean(videoEl.webkitAudioDecodedByteCount) ||
          Boolean(videoEl.audioTracks && videoEl.audioTracks.length) ||
          // Дополнительная проверка через MediaMetadata
          (videoEl.readyState >= 1 && videoEl.duration > 0);

        videoEl.setAttribute('data-has-audio', hasAudio.toString());

        // Аудио управление отключено по запросу пользователя
        // if (hasAudio) {
        //   this.addAudioControls(markerEl, videoEl, hotspot);
        // }

        // Обновляем соотношение сторон видео-области, если необходимо
        if (videoEl.videoWidth && videoEl.videoHeight && videoEl.readyState >= 2) {
          const videoAspect = videoEl.videoWidth / videoEl.videoHeight;

          // Если разница в соотношении сторон значительная, автоматически корректируем
          const currentAspect = width / height;
          if (Math.abs(videoAspect - currentAspect) > 0.1) {
            console.log('🔄 Корректируем соотношение сторон видео-области:',
              `${currentAspect.toFixed(2)} -> ${videoAspect.toFixed(2)}`);

            // Сохраняем текущую площадь
            const currentArea = width * height;

            // Вычисляем новые размеры, сохраняя примерно ту же площадь
            const newHeight = Math.sqrt(currentArea / videoAspect);
            const newWidth = newHeight * videoAspect;

            // Применяем новые размеры
            videoPlane.setAttribute('width', newWidth);
            videoPlane.setAttribute('height', newHeight);

            // Обновляем размеры в данных хотспота
            hotspot.videoWidth = newWidth;
            hotspot.videoHeight = newHeight;

            // Обновляем позиции хэндлов под новые размеры
            this.updateResizeHandles(markerEl, hotspot.videoWidth, hotspot.videoHeight);
          }
        }

        // НОВОЕ: Добавляем индикатор загрузки
        const loadingIndicator = markerEl.querySelector('.video-loading-indicator');
        if (loadingIndicator) {
          loadingIndicator.setAttribute('visible', 'false');
        }
      });

      videoEl.addEventListener('canplay', () => {

        // КРИТИЧЕСКИ ВАЖНО: Убеждаемся, что видео-материал применен
        const currentMaterial = videoPlane.getAttribute('material');
        if (!currentMaterial || !currentMaterial.src || currentMaterial.src !== `#${videoId}`) {

          videoPlane.setAttribute('material', {
            src: `#${videoId}`,
            transparent: false,
            side: 'double',
            shader: 'flat'
          });
          try { videoPlane.removeAttribute('text'); } catch (_) { }

        }

        // НОВОЕ: НЕ показываем кнопку воспроизведения
        // this.showPlayButton(markerEl, videoPlane);
      });

      videoEl.addEventListener('error', (e) => {
        console.error('❌ Ошибка загрузки видео:', e, hotspot.title);

        // Показываем заглушку при ошибке
        videoPlane.setAttribute('material', {
          color: '#cc3333',
          transparent: false,
          side: 'double',
          shader: 'flat'
        });

        // НОВОЕ: Добавляем более заметное сообщение об ошибке
        const errorTextEntity = document.createElement('a-text');
        errorTextEntity.setAttribute('value', `❌ Ошибка загрузки видео\n${hotspot.title || 'Без названия'}`);
        errorTextEntity.setAttribute('align', 'center');
        errorTextEntity.setAttribute('color', '#ffffff');
        errorTextEntity.setAttribute('width', width * 0.75);
        errorTextEntity.setAttribute('position', `0 0 0.01`);
        videoPlane.appendChild(errorTextEntity);

        // Удаляем индикатор загрузки
        const loadingIndicator = markerEl.querySelector('.video-loading-indicator');
        if (loadingIndicator) {
          loadingIndicator.setAttribute('visible', 'false');
        }
      });

      // Добавляем обработчики play/pause (с улучшенными индикаторами)
      videoEl.addEventListener('play', () => {

        // НОВОЕ: Скрываем кнопку воспроизведения
        const playButton = markerEl.querySelector('.video-play-button');
        if (playButton) {
          playButton.setAttribute('visible', 'false');
        }

        // НОВОЕ: Показываем индикатор паузы при наведении
        videoPlane.setAttribute('data-video-playing', 'true');
      });

      videoEl.addEventListener('pause', () => {

        // НОВОЕ: НЕ показываем кнопку воспроизведения
        // this.showPlayButton(markerEl, videoPlane);

        // Обновляем состояние
        videoPlane.setAttribute('data-video-playing', 'false');
      });

      // НОВОЕ: Обработчик окончания видео
      videoEl.addEventListener('ended', () => {

        // this.showPlayButton(markerEl, videoPlane, true); // ОТКЛЮЧЕНО
      });

      // Устанавливаем источник видео
      if (videoUrl) {

        // Проверяем совместимость URL
        const embeddableUrl = this.convertToEmbeddableUrl(videoUrl);

        if (embeddableUrl) {

          videoEl.src = embeddableUrl;

          // ПРИНУДИТЕЛЬНАЯ ЗАГРУЗКА для немедленного применения

          videoEl.load();

          // Дополнительная диагностика
          console.log('🔍 Состояние видео после установки src:', {
            originalUrl: videoUrl,
            processedUrl: embeddableUrl,
            readyState: videoEl.readyState,
            networkState: videoEl.networkState
          });
        } else {
          // Показываем заглушку для неподдерживаемых форматов
          let reason = 'Неподдерживаемый формат';

          if (videoUrl.includes('youtube.com') || videoUrl.includes('youtu.be')) {
            reason = 'YouTube видео не поддерживается';
          } else if (videoUrl.includes('instagram.com')) {
            reason = 'Instagram видео не поддерживается';
          } else if (videoUrl.includes('vkvideo.ru') || videoUrl.includes('vk.com/video')) {
            reason = 'VK Video не поддерживается';
          } else if (videoUrl.includes('tiktok.com')) {
            reason = 'TikTok видео не поддерживается';
          } else if (videoUrl.includes('facebook.com') || videoUrl.includes('fb.watch')) {
            reason = 'Facebook видео не поддерживается';
          }

          this.showVideoPlaceholder(videoPlane, hotspot, reason);
        }
      }

      // Добавляем видео в assets
      let assets = this.aframeScene.querySelector('a-assets');
      if (!assets) {
        assets = document.createElement('a-assets');
        this.aframeScene.appendChild(assets);
      }
      assets.appendChild(videoEl);
    } // Закрываем блок создания видео элемента

    // Принудительно загружаем видео если src установлен
    if (videoEl.src && videoEl.readyState === 0) {

      videoEl.load();
    }

    // Устанавливаем источник видео или показываем заглушку
    if (videoUrl && videoUrl.trim() !== '') {

      // Улучшенная установка видео URL с проверками
      if (videoEl && typeof videoEl.setAttribute === 'function') {
        try {
          // Убеждаемся, что элемент полностью готов
          if (videoEl.readyState !== undefined) {
            videoEl.src = videoUrl;

            // Принудительная загрузка
            videoEl.load();

            // Регистрируем URL в реестре для надежного восстановления
            if (window.hotspotManager && typeof window.hotspotManager.registerVideoUrl === 'function') {
              window.hotspotManager.registerVideoUrl(hotspot.id, videoUrl);
            }
          } else {
            // Если элемент не готов, ждем и повторяем
            setTimeout(() => {
              videoEl.src = videoUrl;
              videoEl.load();

              if (window.hotspotManager && typeof window.hotspotManager.registerVideoUrl === 'function') {
                window.hotspotManager.registerVideoUrl(hotspot.id, videoUrl);
              }
            }, 100);
          }
        } catch (error) {
          console.error('❌ Ошибка установки видео src:', error);
        }
      } else {
        console.error('❌ videoEl недоступен для установки src');
      }
    } else {

      // Устанавливаем видимый серый фон для видео-области без видео
      videoPlane.setAttribute('material', {
        color: '#666666',
        opacity: 1.0,
        transparent: false,
        side: 'double'
      });

      // НЕ создаем текстовый элемент и иконку в центре - оставляем видео-область чистой
    }

    // Добавляем компонент для обработки взаимодействий
    const titleForHandler = hotspot.title && hotspot.title.trim() !== '' ? hotspot.title : 'Видео-область';
    videoPlane.setAttribute('hotspot-handler', `hotspotId: ${hotspot.id}; hotspotTitle: ${titleForHandler}; hotspotType: video-area`);

    // Делаем видео-область перетаскиваемой
    markerEl.className = 'interactive draggable';
    markerEl._isDragging = false;
    markerEl._tooltipVisible = false;
    markerEl._isVideoArea = true; // Помечаем как видео-область

    // ИНДИКАТОРЫ ВОСПРОИЗВЕДЕНИЯ УБРАНЫ ПО ЗАПРОСУ ПОЛЬЗОВАТЕЛЯ

    // Добавляем обработчики для показа курсора при наведении (БЕЗ индикаторов)
    videoPlane.addEventListener('mouseenter', (e) => {
      if (!markerEl._isDragging) {
        document.body.style.cursor = 'pointer';

        // НЕ создаем никаких визуальных индикаторов
      }
    });

    videoPlane.addEventListener('mouseleave', (e) => {
      if (!markerEl._isDragging) {
        document.body.style.cursor = 'default';

        // НЕ удаляем индикаторы, так как не создавали их
      }
    });

    // ОСНОВНОЙ обработчик клика для воспроизведения/паузы видео
    if (!videoPlane._playToggleLock) videoPlane._playToggleLock = false;
    videoPlane.addEventListener('click', (e) => {
      // Проверяем, что это именно левая кнопка мыши (в A-Frame event.button может отсутствовать)

      // Если явно определено, что это не левая кнопка мыши - игнорируем
      if (e.button !== undefined && e.button !== 0) {

        return;
      }

      // Проверяем, что это не событие перетаскивания
      if (markerEl._isDragging) {

        return;
      }

      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation(); // Останавливаем все другие обработчики

      // Анти-дребезг/замок на быстрые клики
      if (videoPlane._playToggleLock) {

        return;
      }
      videoPlane._playToggleLock = true;

      // Получаем актуальные данные хотспота с восстановленными полями
      const fullHotspot = window.hotspotManager ? window.hotspotManager.getHotspotWithFullData(hotspot.id) : hotspot;
      const currentVideoUrl = fullHotspot.videoUrl || videoUrl;

      if (currentVideoUrl && currentVideoUrl.trim() !== '') {
        // Проверяем совместимость URL перед попыткой воспроизведения
        const embeddableUrl = this.convertToEmbeddableUrl(currentVideoUrl);

        if (!embeddableUrl) {
          // Неподдерживаемый формат - показываем сообщение и открываем редактор
          let reason = 'Неподдерживаемый формат видео';

          if (currentVideoUrl.includes('youtube.com') || currentVideoUrl.includes('youtu.be')) {
            reason = 'YouTube ссылки не поддерживаются. Используйте прямые ссылки на видео файлы (.mp4, .webm)';
          } else if (currentVideoUrl.includes('instagram.com')) {
            reason = 'Instagram ссылки не поддерживаются. Используйте прямые ссылки на видео файлы (.mp4, .webm)';
          } else if (currentVideoUrl.includes('vkvideo.ru') || currentVideoUrl.includes('vk.com/video')) {
            reason = 'VK Video ссылки не поддерживаются. Используйте прямые ссылки на видео файлы (.mp4, .webm)';
          } else if (currentVideoUrl.includes('tiktok.com')) {
            reason = 'TikTok ссылки не поддерживаются. Используйте прямые ссылки на видео файлы (.mp4, .webm)';
          } else if (currentVideoUrl.includes('facebook.com') || currentVideoUrl.includes('fb.watch')) {
            reason = 'Facebook ссылки не поддерживаются. Используйте прямые ссылки на видео файлы (.mp4, .webm)';
          }

          // Обновляем заглушку
          this.showVideoPlaceholder(videoPlane, fullHotspot, reason);

          // НЕ открываем редактор автоматически - пользователь может использовать ПКМ

          return;
        }

        const videoEl = document.getElementById(videoId);
        if (videoEl) {
          console.log('🎬 Текущее состояние видео:', {
            paused: videoEl.paused,
            ended: videoEl.ended,
            currentTime: videoEl.currentTime,
            readyState: videoEl.readyState
          });

          if (videoEl.paused || videoEl.ended) {

            // Если видео закончилось, возвращаем к началу
            if (videoEl.ended) {
              videoEl.currentTime = 0;
            }

            // Устанавливаем видео материал если готов
            if (videoEl.readyState >= 2 && videoEl.videoWidth > 0 && videoEl.videoHeight > 0) {
              videoPlane.setAttribute('material', {
                src: `#${videoId}`,
                transparent: false,
                side: 'double',
                shader: 'flat'
              });
              try { videoPlane.removeAttribute('text'); } catch (_) { }

            }

            // Запускаем воспроизведение
            videoEl.play().then(() => {

            }).catch(err => {
              // Игнорируем AbortError (обычно из-за немедленного pause), логируем NotAllowedError
              if (err && err.name === 'AbortError') {

              } else if (err && err.name === 'NotAllowedError') {

                videoEl.muted = true;
                videoEl.play().then(() => {

                }).catch(e => {
                  console.error('❌ Не удалось запустить видео:', e);
                });
              } else {

              }
            }).finally(() => {
              setTimeout(() => { videoPlane._playToggleLock = false; }, 50);
            });
          } else {

            try { videoEl.pause(); } catch (_) { }

            setTimeout(() => { videoPlane._playToggleLock = false; }, 50);
          }
        }
      } else {
        // Нет videoUrl — НЕ открываем редактор по ЛКМ. Показываем заглушку и выходим.

        setTimeout(() => { videoPlane._playToggleLock = false; }, 50);
        try {
          this.showVideoPlaceholder(videoPlane, fullHotspot, 'Видео не настроено');
        } catch (e) { /* no-op */ }
      }
    }, true); // Используем capture phase для приоритета

    // Блокируем ПКМ (без запуска видео)
    videoPlane.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      e.stopPropagation();

    });

    // Добавляем углы для изменения размера
    this.addResizeHandles(markerEl, videoPlane, hotspot);

    // Добавляем обработчики для перетаскивания видео-области
    this.setupVideoAreaDragHandlers(markerEl, videoPlane, hotspot);

    // Устанавливаем начальный материал для видео-области (не переопределяем постер, если он установлен)
    if (videoUrl && videoUrl.trim() !== '') {
      const currentMaterial = videoPlane.getAttribute('material');
      if (!(currentMaterial && currentMaterial.src)) {
        videoPlane.setAttribute('material', {
          color: '#222222',
          opacity: 1.0,
          transparent: false,
          side: 'double',
          shader: 'flat'
        });

      }

      // Если видео уже загружено, сразу применяем видео-материал
      if (videoEl && videoEl.readyState >= 2 && videoEl.videoWidth > 0 && videoEl.videoHeight > 0) {

        videoPlane.setAttribute('material', { src: `#${videoId}`, transparent: false, side: 'double', shader: 'flat' });

      }
    } else {
      // Если нет видео URL - ставим видимый серый материал
      videoPlane.setAttribute('material', {
        color: '#999999',
        opacity: 1.0,
        transparent: false,
        side: 'double',
        shader: 'flat'
      });

    }

    // ИСПРАВЛЕНИЕ: Добавляем face-camera компонент к МАРКЕРУ, а не к видео-плоскости
    // Это обеспечит правильную ориентацию всей видео-области как единого целого
    markerEl.setAttribute('face-camera', '');

    // Добавляем плоскость к маркеру
    markerEl.appendChild(videoPlane);

    // Заголовок создается в обработчике событий мыши для избежания дублирования

    // Устанавливаем поворот если он есть в hotspot
    if (hotspot.rotation) {
      const rotationStr = `${hotspot.rotation.x || 0} ${hotspot.rotation.y || 0} ${hotspot.rotation.z || 0}`;
      markerEl.setAttribute('rotation', rotationStr);

    }

    // Добавляем маркер в сцену
    this.aframeScene.appendChild(markerEl);

    // ФИНАЛЬНАЯ проверка видимости - убеждаемся что маркер видимый
    markerEl.setAttribute('visible', 'true');
    videoPlane.setAttribute('visible', 'true');

    // Дополнительная проверка после добавления
    setTimeout(() => {
      const addedMarker = document.getElementById(`marker-${hotspot.id}`);
      console.log('🔍 Проверяем видимость маркера через 100ms:', {
        found: !!addedMarker,
        visible: addedMarker ? addedMarker.getAttribute('visible') : 'не найден',
        inScene: addedMarker ? this.aframeScene.contains(addedMarker) : false,
        position: addedMarker ? addedMarker.getAttribute('position') : 'не найден'
      });
    }, 100);

    // НАСТРАИВАЕМ перетаскивание через coordinate_manager (ПОСЛЕ добавления в сцену)
    if (this.coordinateManager) {
      this.coordinateManager.setupMarkerDragging(markerEl, hotspot.id, (newPosition) => {
        // Обновляем позицию в менеджере хотспотов
        this.hotspotManager.updateHotspotPosition(hotspot.id, newPosition);
        markerEl._wasDragged = true;

      });
    }

    // Принудительно сохраняем позицию видео-области в hotspotManager
    if (hotspot.position) {

      this.hotspotManager.updateHotspotPosition(hotspot.id, hotspot.position);
    }

    return markerEl;
  }

  /**
   * Конвертация YouTube URL в прямую ссылку
   */
  convertYouTubeUrl(url) {
    const videoIdMatch = url.match(/(?:https?:\/\/)?(?:www\.)?(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})/);
    if (videoIdMatch) {
      // Используем YouTube embed URL (может потребоваться CORS настройка)
      return `https://www.youtube.com/embed/${videoIdMatch[1]}`;
    }
    return null;
  }

  /**
   * Конвертация RuTube URL в прямую ссылку
   */
  convertRuTubeUrl(url) {
    const videoIdMatch = url.match(/(?:https?:\/\/)?(?:www\.)?rutube\.ru\/video\/([a-zA-Z0-9_-]+)/);
    if (videoIdMatch) {
      // Используем RuTube embed URL
      return `https://rutube.ru/play/embed/${videoIdMatch[1]}`;
    }
    return null;
  }

  /**
   * Настройка обработчиков перетаскивания для видео-области
   */
  setupVideoAreaDragHandlers(markerEl, videoPlane, hotspot) {
    // Дебаунсинг для обработчиков наведения
    let mouseEnterTimeout = null;
    let mouseLeaveTimeout = null;

    // Обработчики наведения для показа границ с дебаунсингом
    videoPlane.addEventListener('mouseenter', (e) => {
      if (mouseEnterTimeout) clearTimeout(mouseEnterTimeout);
      mouseEnterTimeout = setTimeout(() => {

        e.stopPropagation();
        if (!markerEl._isDragging) {
          // НЕ меняем материал видео при наведении - только сохраняем информацию о наведении

        }
        // Показ 2D тултипа (Название + Описание) для видео-области
        const hasInfo = (hotspot && (hotspot.title || hotspot.description));
        if (hasInfo && !markerEl._domTooltip) {
          const tip = document.createElement('div');
          tip.className = 'tour-tooltip';
          const title = this.removeFileExtension(hotspot.title || 'Информация');
          const escapeHtml = (s) => String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
          const hasDesc = !!hotspot.description;
          const descHtml = hasDesc ? `<div class=\"desc\">${escapeHtml(hotspot.description).replace(/\\n/g, '<br>')}</div>` : '';
          const sep = hasDesc ? '<hr class=\"tour-tip-sep\" />' : '';
          tip.innerHTML = `<div class=\"title\">${title}</div>${sep}${descHtml}`;
          // Применяем цвет текста тултипа из настроек хотспота
          try { tip.style.color = hotspot.textColor || '#ffffff'; } catch (e) { /* noop */ }
          document.body.appendChild(tip);
          try {
            const titleEl = tip.querySelector('.title');
            const descEl = tip.querySelector('.desc');
            if (titleEl) titleEl.style.color = hotspot.textColor || '#ffffff';
            if (descEl) descEl.style.color = hotspot.textColor || '#ffffff';
          } catch (e) { /* noop */ }
          // Устанавливаем цвет для внутренних элементов, если они переопределены в CSS
          try {
            const titleEl = tip.querySelector('.title');
            const descEl = tip.querySelector('.desc');
            if (titleEl) titleEl.style.color = hotspot.textColor || '#ffffff';
            if (descEl) descEl.style.color = hotspot.textColor || '#ffffff';
          } catch (e) { /* noop */ }
          const move = (ev) => { tip.style.left = (ev.clientX + 12) + 'px'; tip.style.top = (ev.clientY + 12) + 'px'; };
          window.addEventListener('mousemove', move);
          markerEl._domTooltip = tip; markerEl._domTooltipMove = move;
        }
        this._lastHoveredMarker = { element: markerEl, hotspot: hotspot, time: Date.now() };
        // ОТКЛЮЧЕНО: показ resize handles при наведении мыши
        // this.showResizeHandles(markerEl);
      }, 100); // Дебаунсинг 100ms
    });

    videoPlane.addEventListener('mouseleave', (e) => {
      if (mouseLeaveTimeout) clearTimeout(mouseLeaveTimeout);
      mouseLeaveTimeout = setTimeout(() => {

        e.stopPropagation();
        if (!markerEl._isDragging) {
          // НЕ меняем материал видео при mouseleave - только сохраняем информацию

        }
        // Скрытие 2D тултипа
        if (markerEl._domTooltip) {
          window.removeEventListener('mousemove', markerEl._domTooltipMove);
          try { document.body.removeChild(markerEl._domTooltip); } catch (_) { }
          markerEl._domTooltip = null; markerEl._domTooltipMove = null;
        }
        // ОТКЛЮЧЕНО: скрытие resize handles при выходе мыши
        // this.hideResizeHandles(markerEl);
      }, 100); // Дебаунсинг 100ms
    });

    // Обработчики перетаскивания через координатный менеджер для избежания конфликтов
    // УБИРАЕМ DOM-обработчик mousedown - теперь используем только координатный менеджер
    // videoPlane.addEventListener('mousedown', ...) - УДАЛЕН для предотвращения конфликтов

    // Настраиваем перетаскивание через координатный менеджер
    if (this.coordinateManager) {

      // this.coordinateManager.setupDraggable(markerEl, hotspot); - метод не существует
    }

    // Обработчик для предотвращения стандартного контекстного меню - оставляем только этот
    videoPlane.addEventListener('contextmenu', (e) => {

      e.stopPropagation();
      e.preventDefault();
      return false;
    });
  }

  /**
   * Конвертирует YouTube и Instagram ссылки в встраиваемые форматы
   */
  convertToEmbeddableUrl(url) {
    if (!url) return null;

    try {
      // YouTube ссылки
      if (url.includes('youtube.com/watch') || url.includes('youtu.be/')) {
        let videoId = null;

        if (url.includes('youtube.com/watch')) {
          const urlParams = new URLSearchParams(new URL(url).search);
          videoId = urlParams.get('v');
        } else if (url.includes('youtu.be/')) {
          videoId = url.split('youtu.be/')[1] ? url.split('youtu.be/')[1].split('?')[0] : undefined;
        }

        if (videoId) {

          return null; // Пока отключаем встраивание YouTube
        }
      }

      // Instagram ссылки
      if (url.includes('instagram.com/reel/') || url.includes('instagram.com/p/')) {

        return null;
      }

      // VK Video ссылки
      if (url.includes('vkvideo.ru') || url.includes('vk.com/video')) {

        return null;
      }

      // TikTok ссылки
      if (url.includes('tiktok.com') || url.includes('vm.tiktok.com')) {

        return null;
      }

      // Facebook ссылки
      if (url.includes('facebook.com') || url.includes('fb.watch')) {

        return null;
      }

      // Data URL (base64 видео) - поддерживаем напрямую
      if (url.startsWith('data:video/')) {

        return url;
      }

      // Для обычных видео файлов возвращаем как есть
      if (url.match(/\.(mp4|webm|ogg|mov|avi)(\?.*)?$/i)) {

        return url;
      }

      // Для остальных ссылок возвращаем null (неподдерживаемые)

      return null;

    } catch (error) {
      console.error('❌ Ошибка конвертации URL:', error);
      return null;
    }
  }

  /**
   * Показывает заглушку для неподдерживаемых видео
   */
  showVideoPlaceholder(videoPlane, hotspot, reason = 'Неподдерживаемый формат') {

    videoPlane.setAttribute('material', {
      color: '#2a2a2a',
      transparent: false,
      side: 'double',
      shader: 'flat'
    });

    // Добавляем текст с объяснением
    const placeholderText = document.createElement('a-text');
    const title = hotspot.title || 'Видео';
    let message = `🎬 ${reason}\n\n"${title}"`;

    if (reason.includes('YouTube') || reason.includes('Instagram') || reason.includes('VK Video') || reason.includes('TikTok') || reason.includes('Facebook')) {
      message += '\n\nИспользуйте прямые ссылки\nна видео файлы (.mp4, .webm)\n\n🖱️ ПКМ → Редактировать';
    } else {
      message += '\n\n🖱️ ПКМ → Редактировать';
    }

    placeholderText.setAttribute('value', message);
    placeholderText.setAttribute('align', 'center');
    placeholderText.setAttribute('color', '#ffffff');
    placeholderText.setAttribute('width', parseFloat(videoPlane.getAttribute('width')) * 0.8);
    placeholderText.setAttribute('position', '0 0 0.01');
    placeholderText.setAttribute('wrap-count', 25);

    // Очищаем старый текст
    const oldText = videoPlane.querySelector('a-text');
    if (oldText) {
      videoPlane.removeChild(oldText);
    }

    videoPlane.appendChild(placeholderText);
  }

  /**
   * Обновляет источник видео для существующей видео-области
   * @param {Element} markerEl - Маркер видео-области
   * @param {Element} videoPlane - Плоскость видео
   * @param {string} hotspotId - ID хотспота
   * @param {string} videoUrl - Новый URL видео
   */
  updateVideoSource(markerEl, videoPlane, hotspotId, videoUrl) {
    if (!videoUrl || !hotspotId) return;

    // Проверяем, можно ли воспроизвести это видео
    const embeddableUrl = this.convertToEmbeddableUrl(videoUrl);

    if (!embeddableUrl) {
      // Показываем заглушку для неподдерживаемых форматов
      let reason = 'Неподдерживаемый формат';

      if (videoUrl.includes('youtube.com') || videoUrl.includes('youtu.be')) {
        reason = 'YouTube видео не поддерживается';
      } else if (videoUrl.includes('instagram.com')) {
        reason = 'Instagram видео не поддерживается';
      } else if (videoUrl.includes('vkvideo.ru') || videoUrl.includes('vk.com/video')) {
        reason = 'VK Video не поддерживается';
      } else if (videoUrl.includes('tiktok.com')) {
        reason = 'TikTok видео не поддерживается';
      } else if (videoUrl.includes('facebook.com') || videoUrl.includes('fb.watch')) {
        reason = 'Facebook видео не поддерживается';
      }

      this.showVideoPlaceholder(videoPlane, { title: 'Видео' }, reason);
      return;
    }

    // Получаем или создаем видео элемент
    const videoId = `video-${hotspotId}`;
    let videoEl = document.getElementById(videoId);

    if (!videoEl) {
      // Создаем новый видео элемент
      videoEl = document.createElement('video');
      videoEl.id = videoId;
      videoEl.crossOrigin = 'anonymous';
      videoEl.loop = true;
      videoEl.muted = true;
      videoEl.autoplay = false;
      videoEl.controls = false;
      videoEl.style.display = 'none';
      videoEl.preload = 'metadata';

      // Добавляем обработчики событий
      videoEl.addEventListener('loadeddata', () => {

        // Скрываем индикатор загрузки
        const loadingIndicator = markerEl.querySelector('.video-loading-indicator');
        if (loadingIndicator) {
          loadingIndicator.setAttribute('visible', 'false');
        }

        // Очищаем заглушки/ошибки
        const oldText = videoPlane.querySelector('a-text');
        if (oldText) {
          videoPlane.removeChild(oldText);
        }

        // Устанавливаем видео материал
        videoPlane.setAttribute('material', {
          src: `#${videoId}`,
          transparent: false,
          side: 'double',
          shader: 'flat'
        });
      });

      videoEl.addEventListener('error', (e) => {
        console.error('❌ Ошибка загрузки видео:', e, embeddableUrl);
        this.showVideoPlaceholder(videoPlane, { title: 'Видео' }, 'Ошибка загрузки');

        // Скрываем индикатор загрузки
        const loadingIndicator = markerEl.querySelector('.video-loading-indicator');
        if (loadingIndicator) {
          loadingIndicator.setAttribute('visible', 'false');
        }
      });

      // Добавляем в assets
      let assets = this.aframeScene.querySelector('a-assets');
      if (!assets) {
        assets = document.createElement('a-assets');
        this.aframeScene.appendChild(assets);
      }
      assets.appendChild(videoEl);
    }

    // Обновляем источник видео
    videoEl.src = embeddableUrl;
    videoEl.load();

    // Показываем индикатор загрузки
    const loadingIndicator = markerEl.querySelector('.video-loading-indicator');
    if (loadingIndicator) {
      loadingIndicator.setAttribute('visible', 'true');
    } else {
      // Создаем индикатор загрузки, если его нет
      const newLoadingIndicator = document.createElement('a-entity');
      newLoadingIndicator.className = 'video-loading-indicator';

      const spinnerRing = document.createElement('a-ring');
      spinnerRing.setAttribute('radius-inner', '0.4');
      spinnerRing.setAttribute('radius-outer', '0.6');
      spinnerRing.setAttribute('color', '#ffffff');
      spinnerRing.setAttribute('opacity', '0.7');
      spinnerRing.setAttribute('rotation', '0 0 0');
      spinnerRing.setAttribute('animation', {
        property: 'rotation',
        to: '0 0 360',
        dur: 2000,
        easing: 'linear',
        loop: true
      });

      const loadingText = document.createElement('a-text');
      loadingText.setAttribute('value', 'Загрузка...');
      loadingText.setAttribute('align', 'center');
      loadingText.setAttribute('color', '#ffffff');
      loadingText.setAttribute('width', '3');
      loadingText.setAttribute('position', '0 -1 0');

      newLoadingIndicator.appendChild(spinnerRing);
      newLoadingIndicator.appendChild(loadingText);
      newLoadingIndicator.setAttribute('position', '0 0 0.03');

      markerEl.appendChild(newLoadingIndicator);
    }

    // Убираем текущую кнопку воспроизведения, если есть
    const playButton = markerEl.querySelector('.video-play-button');
    if (playButton) {
      playButton.setAttribute('visible', 'false');
    }

    return videoEl;
  }

  /**
   * Показывает прогресс бар для видео
   * @param {Element} markerEl - Маркер видео-области
   * @param {Element} videoPlane - Плоскость видео
   * @param {HTMLVideoElement} videoEl - Элемент видео
   */
  showVideoProgress(markerEl, videoPlane, videoEl) {
    if (!videoEl || !videoPlane) return;

    // Удаляем существующий прогресс бар
    const existingProgress = markerEl.querySelector('.video-progress-container');
    if (existingProgress) {
      existingProgress.parentNode.removeChild(existingProgress);
    }

    // Получаем размеры видео-плоскости
    const width = parseFloat(videoPlane.getAttribute('width')) || 4;
    const height = parseFloat(videoPlane.getAttribute('height')) || 3;

    // Создаем контейнер для прогресс бара
    const progressContainer = document.createElement('a-entity');
    progressContainer.className = 'video-progress-container interactive';
    progressContainer.setAttribute('position', `0 ${-height / 2 - 0.15} 0.02`);

    // Фон прогресс бара
    const progressBg = document.createElement('a-plane');
    progressBg.setAttribute('width', width);
    progressBg.setAttribute('height', '0.1');
    progressBg.setAttribute('color', '#000000');
    progressBg.setAttribute('opacity', '0.7');
    progressBg.setAttribute('shader', 'flat');

    // Индикатор прогресса
    const progressBar = document.createElement('a-plane');
    progressBar.className = 'progress-indicator';
    progressBar.setAttribute('width', 0.01); // Начальная ширина
    progressBar.setAttribute('height', '0.06');
    progressBar.setAttribute('color', '#ffffff');
    progressBar.setAttribute('opacity', '0.9');
    progressBar.setAttribute('shader', 'flat');
    progressBar.setAttribute('position', `${-width / 2 + 0.005} 0 0.01`); // Позиция слева

    // Текст времени
    const timeText = document.createElement('a-text');
    timeText.className = 'time-indicator';
    timeText.setAttribute('value', '0:00 / 0:00');
    timeText.setAttribute('align', 'right');
    timeText.setAttribute('color', '#ffffff');
    timeText.setAttribute('width', '2');
    timeText.setAttribute('position', `${width / 2 - 0.1} 0 0.02`);

    // Добавляем элементы в контейнер
    progressContainer.appendChild(progressBg);
    progressContainer.appendChild(progressBar);
    progressContainer.appendChild(timeText);

    // Добавляем контейнер в маркер
    markerEl.appendChild(progressContainer);

    // Функция форматирования времени
    const formatTime = (seconds) => {
      const minutes = Math.floor(seconds / 60);
      const secs = Math.floor(seconds % 60);
      return `${minutes}:${secs < 10 ? '0' : ''}${secs}`;
    };

    // Обновляем прогресс
    const updateProgress = () => {
      if (videoEl.paused || videoEl.ended) {
        // Останавливаем обновление, если видео не воспроизводится
        return;
      }

      const progress = videoEl.currentTime / videoEl.duration;
      const progressWidth = Math.max(0.01, width * progress);

      // Обновляем ширину и позицию прогресс бара
      progressBar.setAttribute('width', progressWidth);
      progressBar.setAttribute('position', `${-width / 2 + progressWidth / 2} 0 0.01`);

      // Обновляем текст времени
      timeText.setAttribute('value',
        `${formatTime(videoEl.currentTime)} / ${formatTime(videoEl.duration)}`);

      // Продолжаем обновление
      requestAnimationFrame(updateProgress);
    };

    // Запускаем обновление
    updateProgress();

    // Добавляем обработчик клика для перемотки
    progressBg.addEventListener('click', (e) => {
      e.stopPropagation();

      // Получаем локальные координаты клика
      const canvas = document.querySelector('canvas.a-canvas');
      if (!canvas) return;

      // Получаем элемент и его размеры
      const rect = canvas.getBoundingClientRect();

      // Используем raycaster для определения позиции клика
      const raycaster = new THREE.Raycaster();
      const mouse = new THREE.Vector2(
        ((e.clientX - rect.left) / rect.width) * 2 - 1,
        -((e.clientY - rect.top) / rect.height) * 2 + 1
      );

      raycaster.setFromCamera(mouse, this.aframeCamera.getObject3D('camera'));

      // Получаем пересечения с прогресс баром
      const intersects = raycaster.intersectObject(
        progressBg.getObject3D('mesh'), true
      );

      if (intersects.length > 0) {
        // Получаем точку пересечения в локальных координатах
        const point = intersects[0].point;

        // Преобразуем мировые координаты в локальные для прогресс бара
        const progressObject = progressBg.object3D;
        const worldToLocal = new THREE.Vector3();
        worldToLocal.copy(point);
        progressObject.worldToLocal(worldToLocal);

        // Вычисляем процент от -0.5 до 0.5 (ширина плоскости)
        const percent = (worldToLocal.x + 0.5);

        // Устанавливаем новое время видео
        if (videoEl.duration) {
          videoEl.currentTime = videoEl.duration * percent;

          // Обновляем прогресс бар
          const progressWidth = Math.max(0.01, width * percent);
          progressBar.setAttribute('width', progressWidth);
          progressBar.setAttribute('position', `${-width / 2 + progressWidth / 2} 0 0.01`);

          // Обновляем текст времени
          timeText.setAttribute('value',
            `${formatTime(videoEl.currentTime)} / ${formatTime(videoEl.duration)}`);
        }
      }
    });

    return progressContainer;
  }

  /**
   * Проверяет, находится ли мышь точно над видео-областью (строгая версия)
   * с поддержкой всех новых элементов
   */
  isMouseOverVideoArea(event, markerEl, width, height) {
    try {

      // Строгая проверка: только если событие именно от элементов видео-области
      if (event.target) {
        const targetEl = event.target;
        const markerId = markerEl.id;

        // Проверяем классы элемента
  const targetClasses = targetEl.className ? targetEl.className.split(' ') : [];
        const validClasses = [
          'video-area',
          'move-zone',
          'resize-handle',
          'rotation-zone',
          'interactive',
          'video-play-button',
          'video-progress-container',
          'progress-indicator',
          'time-indicator',
          'video-loading-indicator'
        ];

        // Проверяем классы целевого элемента
        const hasValidClass = validClasses.some(cls => targetClasses.includes(cls));

        if (hasValidClass) {

          return true;
        }

        // Проверяем атрибуты элемента
        const validAttributes = [
          'data-video-plane',
          'data-corner',
          'data-rotation-axis',
          'data-arrow-id',
          'data-video-playing'
        ];

        const hasValidAttribute = validAttributes.some(attr =>
          targetEl.hasAttribute && targetEl.hasAttribute(attr)
        );

        if (hasValidAttribute) {

          return true;
        }

        // Проверяем что событие от элементов именно этой видео-области
        if (targetEl.id === markerId ||
          (targetEl.parentElement && targetEl.parentElement.id === markerId) || 
          targetEl.closest(`#${markerId}`) === markerEl) {

          return true;
        }

        // Проверяем родственные связи со стрелками и новыми элементами управления
        const isVideoAreaElement =
          targetEl.closest('.rotation-arrow-indicator') ||
          targetEl.closest('.video-play-button') ||
          targetEl.closest('.video-progress-container') ||
          (targetEl.classList && targetEl.classList.contains('rotation-arrow-indicator'));

        if (isVideoAreaElement && markerEl.contains(targetEl)) {

          return true;
        }

        // Дополнительная проверка для A-Frame событий
        if (event.detail && event.detail.intersection &&
          (event.detail.intersection.object && event.detail.intersection.object.el && event.detail.intersection.object.el.id === markerId)) {

          return true;
        }

        // НОВОЕ: Проверка для элементов внутри маркера видео-области
        if (markerEl.contains && markerEl.contains(targetEl)) {
          // Проверяем, является ли элемент частью интерактивных элементов
          const isInteractiveChild =
            targetEl.tagName === 'A-ENTITY' ||
            targetEl.tagName === 'A-PLANE' ||
            targetEl.tagName === 'A-TEXT' ||
            targetEl.tagName === 'A-SPHERE' ||
            targetEl.tagName === 'A-CIRCLE' ||
            targetEl.tagName === 'A-RING';

          if (isInteractiveChild) {

            return true;
          }
        }
      }

      return false;
    } catch (error) {
      console.error('❌ Ошибка в isMouseOverVideoArea:', error);
      return false; // В случае ошибки запрещаем перетаскивание для безопасности
    }
  }

  /**
   * Показывает кнопку воспроизведения для видео-области
   * @param {Element} markerEl - Маркер видео-области
   * @param {Element} videoPlane - Плоскость видео
   * @param {boolean} isReplay - Признак повторного воспроизведения
   */
  showPlayButton(markerEl, videoPlane, isReplay = false) {
    // Удаляем существующую кнопку, если есть
    const existingButton = markerEl.querySelector('.video-play-button');
    if (existingButton) {
      existingButton.parentNode.removeChild(existingButton);
    }

    // Получаем размеры видео-плоскости
    const width = parseFloat(videoPlane.getAttribute('width')) || 4;
    const height = parseFloat(videoPlane.getAttribute('height')) || 3;

    // Создаем контейнер для кнопки
    const buttonEntity = document.createElement('a-entity');
    buttonEntity.className = 'video-play-button interactive';
    buttonEntity.setAttribute('position', `0 0 0.02`);

    // Создаем фон кнопки (круг)
    const buttonBg = document.createElement('a-circle');
    buttonBg.setAttribute('radius', Math.min(width, height) * 0.2);
    buttonBg.setAttribute('color', '#000000');
    buttonBg.setAttribute('opacity', '0.7');
    buttonBg.setAttribute('shader', 'flat');
    buttonBg.className = 'interactive';

    // Создаем значок кнопки
    const buttonIcon = document.createElement('a-text');
    buttonIcon.setAttribute('value', isReplay ? '🔄' : '▶️');
    buttonIcon.setAttribute('align', 'center');
    buttonIcon.setAttribute('color', '#ffffff');
    buttonIcon.setAttribute('width', Math.min(width, height) * 0.5);
    buttonIcon.setAttribute('position', '0 0 0.01');
    buttonIcon.className = 'interactive';

    // Собираем кнопку
    buttonEntity.appendChild(buttonBg);
    buttonEntity.appendChild(buttonIcon);

    // Добавляем обработчик клика
    buttonEntity.addEventListener('click', (e) => {
      e.stopPropagation();
      e.preventDefault();

      // Получаем видео элемент
      const videoId = videoPlane.parentNode.getAttribute('data-hotspot-id');
      const videoEl = document.getElementById(`video-${videoId}`);

      if (videoEl) {
        // Проверяем, готово ли видео к воспроизведению
        if (videoEl.readyState >= 2) {
          // Если видео закончилось, перематываем к началу
          if (videoEl.ended) {
            videoEl.currentTime = 0;
          }

          // Воспроизводим видео
          videoEl.play().then(() => {

            // Устанавливаем видео материал
            videoPlane.setAttribute('material', {
              src: `#video-${videoId}`,
              shader: 'flat',
              side: 'double',
              transparent: false
            });

            // Скрываем кнопку
            buttonEntity.setAttribute('visible', 'false');
          }).catch(err => {
            console.warn('⚠️ Ошибка воспроизведения:', err);            // Если видео заблокировано политикой автовоспроизведения, пробуем без звука
            if (err.name === 'NotAllowedError') {
              videoEl.muted = true;
              videoEl.play().then(() => {

                // Устанавливаем видео материал
                videoPlane.setAttribute('material', {
                  src: `#video-${videoId}`,
                  shader: 'flat',
                  side: 'double',
                  transparent: false
                });

                // Скрываем кнопку
                buttonEntity.setAttribute('visible', 'false');
              }).catch(e => {
                console.error('❌ Не удалось запустить видео:', e);
              });
            }
          });
        } else {

        }
      }
    });

    // Добавляем кнопку в маркер
    markerEl.appendChild(buttonEntity);

    return buttonEntity;
  }

  /**
   * Обновляет зоны изменения размеров после изменения размеров видео-области
   */
  updateResizeHandles(markerEl, videoPlane, hotspot) {
    // Удаляем существующие зоны
    const existingHandles = markerEl.querySelectorAll('.resize-handle');
    existingHandles.forEach(handle => {
      handle.parentNode.removeChild(handle);
    });

    // Удаляем существующие зоны вращения
    const existingRotationZones = markerEl.querySelectorAll('.rotation-zone');
    existingRotationZones.forEach(zone => {
      zone.parentNode.removeChild(zone);
    });

    // Удаляем существующие стрелки вращения
    const existingArrows = markerEl.querySelectorAll('[id^="arrow-rotate-"]');
    existingArrows.forEach(arrow => {
      arrow.parentNode.removeChild(arrow);
    });

    // Удаляем существующую зону перемещения
    const existingMoveZone = markerEl.querySelector('.move-zone');
    if (existingMoveZone) {
      existingMoveZone.parentNode.removeChild(existingMoveZone);
    }

    // Убеждаемся, что компонент face-camera активен
    if (!markerEl.getAttribute('face-camera')) {
      markerEl.setAttribute('face-camera', '');

    }

    // Пересоздаем невидимые углы изменения размера
    const corners = [
      { position: [-1, 1], corner: 'top-left' },
      { position: [1, 1], corner: 'top-right' },
      { position: [-1, -1], corner: 'bottom-left' },
      { position: [1, -1], corner: 'bottom-right' }
    ];

    corners.forEach(cornerInfo => {
      const resizeHandle = document.createElement('a-box');

      // Устанавливаем размеры и позицию
      resizeHandle.setAttribute('width', '0.3');
      resizeHandle.setAttribute('height', '0.3');
      resizeHandle.setAttribute('depth', '0.05');

      // Позиционируем в углах видео-области
      const width = parseFloat(hotspot.videoWidth) || 4;
      const height = parseFloat(hotspot.videoHeight) || 3;
      const posX = (width / 2) * cornerInfo.position[0];
      const posY = (height / 2) * cornerInfo.position[1];

      resizeHandle.setAttribute('position', `${posX} ${posY} 0.05`);

      // Делаем полностью невидимыми resize handles - убираем любую возможность артефактов
      resizeHandle.setAttribute('material', {
        color: 'red',
        opacity: 0.0,
        transparent: true,
        visible: false
      });

      // Дополнительно скрываем через visibility
      resizeHandle.setAttribute('visible', 'false');

      // Добавляем классы и атрибуты для идентификации
      resizeHandle.classList.add('resize-handle');
      resizeHandle.setAttribute('data-corner', cornerInfo.corner);
      resizeHandle.setAttribute('data-marker-id', hotspot.id);

      // Добавляем raycaster-listen для обработки событий
      resizeHandle.setAttribute('raycaster-listen', '');

      // Добавляем в маркер
      markerEl.appendChild(resizeHandle);
    });

  }  /**
   * Проверяет, находится ли мышь над обычным маркером хотспота
   */
  isMouseOverMarker(event, markerEl) {
    try {

      const canvas = this.aframeScene.canvas;
      if (!canvas) {

        return true;
      }

      // ИСПРАВЛЯЕМ: правильно получаем координаты мыши с проверкой на валидность
      const rect = canvas.getBoundingClientRect();

      // Проверяем, что event содержит валидные координаты
      if (!event || typeof event.clientX !== 'number' || typeof event.clientY !== 'number') {

        // Возвращаем true как fallback - считаем что мышь над маркером
        return true;
      }

      const mouseX = ((event.clientX - rect.left) / rect.width) * 2 - 1;
      const mouseY = -((event.clientY - rect.top) / rect.height) * 2 + 1;

      // Проверяем что координаты не NaN
      if (isNaN(mouseX) || isNaN(mouseY)) {

        return true; // Fallback - считаем что над маркером
      }

      // Создаем raycaster для проверки пересечения
      const camera = this.aframeCamera;
      if (!camera) {

        return true;
      }

      // Проверяем наличие камеры THREE.js
      const threeCamera = camera.getObject3D('camera');
      if (!threeCamera) {

        return true;
      }

      const raycaster = new THREE.Raycaster();
      raycaster.setFromCamera({ x: mouseX, y: mouseY }, threeCamera);

      // Проверяем пересечение с маркером
      const markerObject3D = markerEl.object3D;
      if (!markerObject3D) {

        return true;
      }

      const intersects = raycaster.intersectObject(markerObject3D, true);
      const isOverMarker = intersects.length > 0;

      console.log('🎯 Проверка попадания в маркер:', {
        markerId: markerEl.id,
        intersects: intersects.length,
        isOverMarker: isOverMarker
      });

      return isOverMarker;

    } catch (error) {
      console.error('❌ Ошибка проверки позиции мыши над маркером:', error);
      return true; // В случае ошибки разрешаем действие
    }
  }

  /**
   * Добавляет углы для изменения размера видео-области
   */
  addResizeHandles(markerEl, videoPlane, hotspot) {
    // Удаляем старые углы изменения размера
    const oldHandles = markerEl.querySelectorAll('.resize-handle');
    oldHandles.forEach(handle => handle.remove());

    // Используем согласованные поля размеров видео-области
    const width = parseFloat(hotspot.videoWidth) || 4;
    const height = parseFloat(hotspot.videoHeight) || 3;
    const handleSize = 0.3; // Размер невидимой зоны для захвата
    const handleOffset = handleSize / 2;

    // Позиции углов
    const corners = [
      { name: 'top-left', x: -width / 2 - handleOffset, y: height / 2 + handleOffset, cursor: 'nw-resize' },
      { name: 'top-right', x: width / 2 + handleOffset, y: height / 2 + handleOffset, cursor: 'ne-resize' },
      { name: 'bottom-left', x: -width / 2 - handleOffset, y: -height / 2 - handleOffset, cursor: 'sw-resize' },
      { name: 'bottom-right', x: width / 2 + handleOffset, y: -height / 2 - handleOffset, cursor: 'se-resize' }
    ];

    corners.forEach(corner => {
      // Создаем невидимую зону для захвата
      const handle = document.createElement('a-plane');
      handle.className = 'resize-handle interactive';
      handle.setAttribute('width', handleSize);
      handle.setAttribute('height', handleSize);
      handle.setAttribute('position', `${corner.x} ${corner.y} 0.02`);
      handle.setAttribute('material', 'color: #ffffff; opacity: 0; transparent: true'); // Полностью прозрачный
      handle.setAttribute('data-corner', corner.name);
      handle.setAttribute('data-cursor', corner.cursor);

      // Добавляем обработчики событий для изменения курсора
      handle.addEventListener('mouseenter', (e) => {
        document.body.style.cursor = corner.cursor;

      });

      handle.addEventListener('mouseleave', (e) => {
        if (!this._isResizing) {
          document.body.style.cursor = 'default';
        }
      });

      // Обработчик начала изменения размера
      handle.addEventListener('mousedown', (e) => {
        e.stopPropagation();
        this.startVideoResize(markerEl, videoPlane, hotspot, corner.name, e);
      });

      markerEl.appendChild(handle);
    });

  }

  /**
   * Начинает процесс изменения размера видео-области
   */
  startVideoResize(markerEl, videoPlane, hotspot, cornerName, event) {
    event.stopPropagation();

    this._isResizing = true;
    this._currentResizeHandle = cornerName;

    // Используем согласованные поля videoWidth/videoHeight
    const initialWidth = parseFloat(hotspot.videoWidth) || 4;
    const initialHeight = parseFloat(hotspot.videoHeight) || 3;

    // Сохраняем начальные координаты мыши
    const startMouseX = event.clientX;
    const startMouseY = event.clientY;

    // Функция обработки движения мыши
    const mouseMoveHandler = (e) => {
      const deltaX = (e.clientX - startMouseX) * 0.01; // Масштабируем движение
      const deltaY = (startMouseY - e.clientY) * 0.01; // Инвертируем Y для A-Frame

      let newWidth = initialWidth;
      let newHeight = initialHeight;

      // Вычисляем новые размеры в зависимости от угла
      switch (cornerName) {
        case 'top-right':
          newWidth = Math.max(1, initialWidth + deltaX);
          newHeight = Math.max(0.5, initialHeight + deltaY);
          break;
        case 'top-left':
          newWidth = Math.max(1, initialWidth - deltaX);
          newHeight = Math.max(0.5, initialHeight + deltaY);
          break;
        case 'bottom-right':
          newWidth = Math.max(1, initialWidth + deltaX);
          newHeight = Math.max(0.5, initialHeight - deltaY);
          break;
        case 'bottom-left':
          newWidth = Math.max(1, initialWidth - deltaX);
          newHeight = Math.max(0.5, initialHeight - deltaY);
          break;
      }

      // Обновляем размеры видео-области
      this.updateVideoAreaSize(markerEl, videoPlane, hotspot, newWidth, newHeight);
    };

    // Функция завершения изменения размера
    const mouseUpHandler = (e) => {
      this._isResizing = false;
      this._currentResizeHandle = null;
      document.body.style.cursor = 'default';

      document.removeEventListener('mousemove', mouseMoveHandler);
      document.removeEventListener('mouseup', mouseUpHandler);

      // Сохраняем изменения
      if (this.hotspotManager && this.hotspotManager.saveProject) {
        this.hotspotManager.saveProject();
      }
    };

    // Добавляем обработчики событий
    document.addEventListener('mousemove', mouseMoveHandler);
    document.addEventListener('mouseup', mouseUpHandler);
  }

  /**
   * Обновляет размеры видео-области
   */
  updateVideoAreaSize(markerEl, videoPlane, hotspot, newWidth, newHeight) {
    // Проверяем корректность входных размеров
    newWidth = parseFloat(newWidth);
    newHeight = parseFloat(newHeight);

    if (isNaN(newWidth) || newWidth <= 0) {

      newWidth = 4;
    }
    if (isNaN(newHeight) || newHeight <= 0) {

      newHeight = 3;
    }

    // Обновляем размеры видео-плоскости
    videoPlane.setAttribute('width', newWidth);
    videoPlane.setAttribute('height', newHeight);

    // Обновляем размеры в объекте hotspot (единые поля для видео-области)
    hotspot.videoWidth = newWidth;
    hotspot.videoHeight = newHeight;

    // Обновляем позиции углов изменения размера
    this.updateResizeHandles(markerEl, newWidth, newHeight);

    // Обновляем позицию заголовка если есть
    this.updateVideoAreaTitle(markerEl, newHeight);

  }

  /**
   * Обновляет позицию углов изменения размера
   */
  updateResizeHandles(markerEl, width, height) {
    const handles = markerEl.querySelectorAll('.resize-handle');
    if (handles.length === 0) return;

    const handleSize = 0.3; // Размер невидимой зоны для захвата
    const handleOffset = handleSize / 2;

    // Позиции углов
    const corners = [
      { name: 'top-left', x: -width / 2 - handleOffset, y: height / 2 + handleOffset },
      { name: 'top-right', x: width / 2 + handleOffset, y: height / 2 + handleOffset },
      { name: 'bottom-left', x: -width / 2 - handleOffset, y: -height / 2 - handleOffset },
      { name: 'bottom-right', x: width / 2 + handleOffset, y: -height / 2 - handleOffset }
    ];

    handles.forEach((handle) => {
      const cornerName = handle.getAttribute('data-corner');
      const corner = corners.find(c => c.name === cornerName);
      if (corner) {
        handle.setAttribute('position', `${corner.x} ${corner.y} 0.02`);
      }
    });

  }

  /**
   * Показывает resize handles для видео-области
   */
  showResizeHandles(markerEl) {
    // ОТКЛЮЧЕНО: resize handles отключены
    return;
  }

  /**
   * Скрывает resize handles для видео-области
   */
  hideResizeHandles(markerEl) {
    // ОТКЛЮЧЕНО: resize handles отключены
    return;
  }

  /**
   * Настраивает обработчики для невидимых зон (поворот, изменение размера)
   */
  setupInvisibleZoneHandlers(markerEl, videoPlane, hotspot) {
    // По запросу пользователя, все подсвечивающие линии и круги убраны.

  }

  /**
   * Начинает изменение размера видео-области
   */
  startResize(markerEl, videoPlane, hotspot, corner, startEvent) {
    // Предотвращаем множественные вызовы
    if (this._isResizing) {

      return;
    }

    this._isResizing = true;

    const startWidth = parseFloat(hotspot.videoWidth) || 4;
    const startHeight = parseFloat(hotspot.videoHeight) || 3;

    // Используем координаты события напрямую (canvas или DOM)
    const startMousePos = {
  x: startEvent.clientX || (startEvent.detail && startEvent.detail.clientX) || 0,
  y: startEvent.clientY || (startEvent.detail && startEvent.detail.clientY) || 0
    };

    console.log('🔄 Начальные размеры для изменения:', {
      startWidth,
      startHeight,
      corner,
      startMousePos,
      'hotspot.videoWidth': hotspot.videoWidth,
      'hotspot.videoHeight': hotspot.videoHeight
    });

    // Дебаунсинг для обновления размеров
    let updateTimeout;

    const resizeHandler = (moveEvent) => {
      if (!this._isResizing) return; // Дополнительная защита

      // ИСПРАВЛЯЕМ: изменяем коэффициенты чувствительности
      const deltaX = (moveEvent.clientX - startMousePos.x) * 0.005; // Уменьшаем чувствительность
      const deltaY = (startMousePos.y - moveEvent.clientY) * 0.005; // Инвертируем Y и уменьшаем чувствительность

      let newWidth = startWidth;
      let newHeight = startHeight;

      // Рассчитываем новые размеры в зависимости от угла
      switch (corner) {
        case 'top-right':
          newWidth = Math.max(1.0, startWidth + deltaX);
          newHeight = Math.max(1.0, startHeight + deltaY);
          break;
        case 'bottom-left':
          newWidth = Math.max(1.0, startWidth - deltaX);
          newHeight = Math.max(1.0, startHeight - deltaY);
          break;
        case 'bottom-right':
          newWidth = Math.max(1.0, startWidth + deltaX);
          newHeight = Math.max(1.0, startHeight - deltaY);
          break;
        case 'top-left':
          newWidth = Math.max(1.0, startWidth - deltaX);
          newHeight = Math.max(1.0, startHeight + deltaY);
          break;
      }

      // ИСПРАВЛЯЕМ: проверяем, что размеры корректные и ограничиваем максимум
      if (isNaN(newWidth) || isNaN(newHeight) || newWidth <= 0 || newHeight <= 0) {
        newWidth = startWidth; // Возвращаем к исходным размерам
        newHeight = startHeight;
      }

      // Применяем минимальные ограничения для видимости
      newWidth = Math.max(newWidth, 2); // Минимум 2 единицы для видимости
      newHeight = Math.max(newHeight, 1.5); // Минимум 1.5 единицы для видимости

      // Максимальные ограничения
      newWidth = Math.min(newWidth, 10); // Максимум 10 единиц
      newHeight = Math.min(newHeight, 8); // Максимум 8 единиц

      // Ограничиваем максимальные размеры
      newWidth = Math.min(newWidth, 20);
      newHeight = Math.min(newHeight, 20);

      // Дебаунсим обновления DOM для производительности
      clearTimeout(updateTimeout);
      updateTimeout = setTimeout(() => {
        // ИСПРАВЛЯЕМ: сохраняем текущий материал видео при изменении размера
        const currentMaterial = videoPlane.getAttribute('material');

        // Обновляем размеры видео-области
        videoPlane.setAttribute('width', newWidth);
        videoPlane.setAttribute('height', newHeight);

        // ИСПРАВЛЯЕМ: если есть видео материал, пере-применяем его
        if (currentMaterial && currentMaterial.src) {

          videoPlane.setAttribute('material', currentMaterial);
        }

        // Обновляем позиции углов
        this.updateResizeHandles(markerEl, newWidth, newHeight);

        // Обновляем позицию текста названия
        this.updateVideoAreaTitle(markerEl, newHeight);
      }, 16); // ~60fps
    };

    const stopResizeHandler = () => {

      this._isResizing = false;
      this._currentResizeHandle = null;
      clearTimeout(updateTimeout);

      document.removeEventListener('mousemove', resizeHandler);
      document.removeEventListener('mouseup', stopResizeHandler);

      // Сохраняем новые размеры
      let newWidth = parseFloat(videoPlane.getAttribute('width'));
      let newHeight = parseFloat(videoPlane.getAttribute('height'));

      // ИСПРАВЛЯЕМ: если размеры все еще некорректны, возвращаем к исходным
      if (isNaN(newWidth) || isNaN(newHeight) || newWidth <= 0 || newHeight <= 0) {

        newWidth = startWidth || 4;
        newHeight = startHeight || 3;

        // Обновляем и в DOM
        videoPlane.setAttribute('width', newWidth);
        videoPlane.setAttribute('height', newHeight);
        this.updateResizeHandles(markerEl, newWidth, newHeight);
        this.updateVideoAreaTitle(markerEl, newHeight);
      }

      hotspot.videoWidth = newWidth;
      hotspot.videoHeight = newHeight;

      // Debounce сохранения - сохраняем только после завершения изменения размера
      clearTimeout(this._resizeSaveTimeout);
      this._resizeSaveTimeout = setTimeout(() => {
        if (this.hotspotManager) {
          this.hotspotManager.updateHotspot(hotspot.id, {
            videoWidth: newWidth,
            videoHeight: newHeight
          });
        }

      }, 300); // Ждем 300ms после завершения изменения размера
    };

    document.addEventListener('mousemove', resizeHandler);
    document.addEventListener('mouseup', stopResizeHandler);
  }

  /**
   * Обновляет позицию текста названия видео-области
   */
  updateVideoAreaTitle(markerEl, videoHeight) {
    const textElement = markerEl.querySelector('.video-area-title');
    if (textElement) {
      // Позиционируем текст выше видео-области с большим отступом
      const titleY = (parseFloat(videoHeight) || 3) / 2 + 0.8; // Увеличен отступ
      textElement.setAttribute('position', `0 ${titleY} 0.3`); // Увеличен Z-отступ

    }
  }

  /**
   * Обновляет содержимое названия видео-области
   */
  updateVideoAreaTitleText(markerEl, newTitle) {
    const textElement = markerEl.querySelector('.video-area-title');
    if (textElement) {
      const titleText = newTitle && newTitle.trim() !== '' ? this.removeFileExtension(newTitle.trim()) : '';
      textElement.setAttribute('value', titleText);
      textElement.setAttribute('visible', titleText !== '' ? 'true' : 'false');

    } else if (newTitle && newTitle.trim() !== '') {
      // Создаем новый элемент для названия, если его не было
      const cleanTitle = this.removeFileExtension(newTitle.trim());
      const newTextElement = document.createElement('a-text');
      newTextElement.setAttribute('value', cleanTitle);
      newTextElement.setAttribute('align', 'center');
      newTextElement.setAttribute('color', '#ffffff');
      newTextElement.setAttribute('width', 6);
      newTextElement.setAttribute('billboard', '');
      newTextElement.setAttribute('visible', 'true');
      newTextElement.className = 'video-area-title';

      // Получаем высоту видео для позиционирования
      const videoPlane = markerEl.querySelector('[data-video-plane]');
      const videoHeight = videoPlane ? parseFloat(videoPlane.getAttribute('height')) || 3 : 3;
      const titleY = videoHeight / 2 + 0.8; // Увеличен отступ
      newTextElement.setAttribute('position', `0 ${titleY} 0.3`); // Увеличен Z-отступ

      markerEl.appendChild(newTextElement);

    }
  }

  /**
   * Обновляет позиции углов изменения размера
   */
  updateResizeHandles(markerEl, width, height) {
    // Проверяем корректность входных данных
    width = parseFloat(width);
    height = parseFloat(height);

    if (isNaN(width) || isNaN(height) || width <= 0 || height <= 0) {

      width = 4;
      height = 3;
    }

    const handles = markerEl.querySelectorAll('.resize-handle');

    handles.forEach(handle => {
      const corner = handle.getAttribute('data-corner');
      let x, y;

      switch (corner) {
        case 'top-left':
          x = -width / 2; y = height / 2;
          break;
        case 'top-right':
          x = width / 2; y = height / 2;
          break;
        case 'bottom-left':
          x = -width / 2; y = -height / 2;
          break;
        case 'bottom-right':
          x = width / 2; y = -height / 2;
          break;
        default:

          x = 0; y = 0;
      }

      // Дополнительная проверка на NaN
      if (isNaN(x) || isNaN(y)) {

        x = 0; y = 0;
      }

      handle.setAttribute('position', `${x} ${y} 0.01`);
    });

    // Обновляем позиции кнопок вращения
    const rotationHandles = markerEl.querySelectorAll('.rotation-handle');
    rotationHandles.forEach(handle => {
      const action = handle.getAttribute('data-rotation-action');
      let x, y;

      switch (action) {
        case 'rotate-left':
          x = -width / 2 - 0.5; y = 0;
          break;
        case 'rotate-right':
          x = width / 2 + 0.5; y = 0;
          break;
        case 'rotate-up':
          x = 0; y = height / 2 + 0.3;
          break;
        case 'rotate-down':
          x = 0; y = -height / 2 - 0.3;
          break;
        default:
          x = 0; y = 0;
      }

      handle.setAttribute('position', `${x} ${y} 0.01`);

    });
  }

  /**
   * Вращает видео-область вокруг вертикальной оси
   */
  rotateVideoArea(markerEl, videoPlane, hotspot, action) {

    // Получаем текущий поворот маркера (или устанавливаем по умолчанию)
    let currentRotation = markerEl.getAttribute('rotation');

    // ИСПРАВЛЯЕМ: правильно обрабатываем rotation атрибут
    let rotX = 0, rotY = 0, rotZ = 0;
    if (currentRotation) {
      if (typeof currentRotation === 'string') {
        const parts = currentRotation.split(' ');
        rotX = parseFloat(parts[0]) || 0;
        rotY = parseFloat(parts[1]) || 0;
        rotZ = parseFloat(parts[2]) || 0;
      } else {
        rotX = currentRotation.x || 0;
        rotY = currentRotation.y || 0;
        rotZ = currentRotation.z || 0;
      }
    }

    // Определяем шаг поворота (в градусах)
    const rotationStep = 15; // 15 градусов за один клик

    // Изменяем поворот в зависимости от действия
    if (action === 'rotate-left') {
      // Поворот против часовой стрелки вокруг Y-оси
      rotY = (rotY - rotationStep) % 360;

    } else if (action === 'rotate-right') {
      // Поворот по часовой стрелке вокруг Y-оси
      rotY = (rotY + rotationStep) % 360;

    } else if (action === 'rotate-up') {
      // Поворот вверх вокруг X-оси
      rotX = (rotX - rotationStep) % 360;

    } else if (action === 'rotate-down') {
      // Поворот вниз вокруг X-оси
      rotX = (rotX + rotationStep) % 360;

    }

    // Обновляем поворот маркера
    const newRotationStr = `${rotX} ${rotY} ${rotZ}`;

    markerEl.setAttribute('rotation', newRotationStr);

    // Проверяем, что изменение применилось
    const appliedRotation = markerEl.getAttribute('rotation');

    // Сохраняем изменения поворота в hotspot
    if (!hotspot.rotation) {
      hotspot.rotation = { x: 0, y: 0, z: 0 };
    }
    hotspot.rotation.x = rotX;
    hotspot.rotation.y = rotY;
    hotspot.rotation.z = rotZ;

    // Сохраняем изменения
    if (this.hotspotManager) {
      this.hotspotManager.updateHotspot(hotspot.id, {
        rotation: { x: rotX, y: rotY, z: rotZ }
      });
    }

    console.log('✅ Видео-область повернута:', {
      action,
      newRotation: { x: rotX, y: rotY, z: rotZ }
    });
  }

  /**
   * Добавляет кнопки управления звуком для видео-области
   */
  addAudioControls(markerEl, videoEl, hotspot) {

    // Проверяем, не добавлены ли уже кнопки
    const existingControls = markerEl.querySelector('.audio-controls');
    if (existingControls) {

      return;
    }

    const videoPlane = markerEl.querySelector('[data-video-plane]');
    if (!videoPlane) {

      return;
    }

    // Создаем контейнер для кнопок управления звуком
    const audioControls = document.createElement('a-entity');
    audioControls.className = 'audio-controls';
    audioControls.setAttribute('position', `${hotspot.videoWidth / 2 - 0.3} ${hotspot.videoHeight / 2 - 0.3} 0.01`);

    // Кнопка включения/выключения звука
    const muteButton = document.createElement('a-plane');
    muteButton.className = 'audio-mute-btn interactive';
    muteButton.setAttribute('width', '0.4');
    muteButton.setAttribute('height', '0.4');
    muteButton.setAttribute('color', '#222222'); // Темный цвет вместо зеленого
    muteButton.setAttribute('opacity', '0.8');
    muteButton.setAttribute('position', '0 0 0');

    // Текст на кнопке (иконка звука)
    const muteText = document.createElement('a-text');
    muteText.setAttribute('value', videoEl.muted ? '🔇' : '🔊');
    muteText.setAttribute('align', 'center');
    muteText.setAttribute('position', '0 0 0.01');
    muteText.setAttribute('scale', '0.8 0.8 0.8');
    muteText.setAttribute('color', '#ffffff');

    muteButton.appendChild(muteText);
    audioControls.appendChild(muteButton);

    // Кнопка регулировки громкости (если не выключен звук)
    if (!videoEl.muted) {
      const volumeSlider = this.createVolumeSlider(videoEl, hotspot);
      volumeSlider.setAttribute('position', '0.6 0 0');
      audioControls.appendChild(volumeSlider);
    }

    // Обработчик клика по кнопке звука
    muteButton.addEventListener('click', (e) => {
      e.stopPropagation();

      videoEl.muted = !videoEl.muted;
      muteText.setAttribute('value', videoEl.muted ? '🔇' : '🔊');
      muteButton.setAttribute('color', videoEl.muted ? '#ff4444' : '#222222'); // Темный цвет вместо зеленого

      // Обновляем слайдер громкости
      const existingSlider = audioControls.querySelector('.volume-slider');
      if (existingSlider) {
        existingSlider.remove();
      }

      if (!videoEl.muted) {
        const volumeSlider = this.createVolumeSlider(videoEl, hotspot);
        volumeSlider.setAttribute('position', '0.6 0 0');
        audioControls.appendChild(volumeSlider);
      }
    });

    videoPlane.appendChild(audioControls);

  }

  /**
   * Создает слайдер громкости для видео
   */
  createVolumeSlider(videoEl, hotspot) {
    const sliderContainer = document.createElement('a-entity');
    sliderContainer.className = 'volume-slider';

    // Фон слайдера
    const sliderBg = document.createElement('a-plane');
    sliderBg.setAttribute('width', '0.8');
    sliderBg.setAttribute('height', '0.1');
    sliderBg.setAttribute('color', '#333333');
    sliderBg.setAttribute('opacity', '0.7');

    // Индикатор уровня громкости
    const volumeIndicator = document.createElement('a-plane');
    volumeIndicator.className = 'volume-indicator';
    volumeIndicator.setAttribute('width', 0.8 * videoEl.volume);
    volumeIndicator.setAttribute('height', '0.08');
    volumeIndicator.setAttribute('color', '#2196F3'); // Синий цвет вместо зеленого
    volumeIndicator.setAttribute('position', `${-0.4 + (0.8 * videoEl.volume / 2)} 0 0.01`);

    sliderContainer.appendChild(sliderBg);
    sliderContainer.appendChild(volumeIndicator);

    // Обработчик клика для изменения громкости
    sliderBg.addEventListener('click', (e) => {
      e.stopPropagation();

      // Вычисляем новый уровень громкости на основе позиции клика
      // Это упрощенная реализация - в реальности нужно получить точную позицию клика
      const newVolume = Math.random(); // Заглушка - в реальности должно быть на основе позиции мыши

      videoEl.volume = Math.max(0, Math.min(1, newVolume));

      // Обновляем индикатор
      volumeIndicator.setAttribute('width', 0.8 * videoEl.volume);
      volumeIndicator.setAttribute('position', `${-0.4 + (0.8 * videoEl.volume / 2)} 0 0.01`);

    });

    return sliderContainer;
  }

  // Метод для получения данных маркера по ID
  getHotspotData(hotspotId) {
    if (!this.hotspotManager) {
      return null;
    }

    const hotspots = this.hotspotManager.getHotspots();
    return hotspots.find(h => h.id === hotspotId);
  }

  /**
   * Публичный метод для обновления отображения хотспота после редактирования
   */
  updateHotspotDisplay(hotspotId) {
    const markerEl = document.getElementById(`marker-${hotspotId}`);
    if (!markerEl) {

      return;
    }

    const hotspot = this.getHotspotData(hotspotId);
    if (!hotspot) {

      return;
    }

    // Если это видео-область, обновляем название
    if (hotspot.type === 'video-area' || markerEl._isVideoArea) {
      this.updateVideoAreaTitleText(markerEl, hotspot.title);

    }
  }

  /**
   * Получает текущую позицию камеры
   */
  getCameraPosition() {
    // Пробуем найти камеру разными способами
    let camera = (this.aframeScene && typeof this.aframeScene.querySelector === 'function' ? this.aframeScene.querySelector('a-camera') : null) ||
      (this.aframeScene && typeof this.aframeScene.querySelector === 'function' ? this.aframeScene.querySelector('[camera]') : null) ||
      document.querySelector('a-camera') ||
      document.querySelector('[camera]');

    if (!camera) {

      // Пробуем получить камеру через THREE.js
      try {
  const scene3D = this.aframeScene && this.aframeScene.object3D ? this.aframeScene.object3D : undefined;
        if (scene3D) {
          scene3D.traverse((child) => {
            if (child.isCamera && !camera) {
              camera = child.el; // Получаем A-Frame элемент
            }
          });
        }
      } catch (error) {
        console.error('Ошибка поиска камеры через THREE.js:', error);
      }
    }

    if (!camera) {

      return null;
    }

    try {
      const position = camera.getAttribute('position');
      const rotation = camera.getAttribute('rotation');

      const toNum = (v) => {
        const px = parseFloat(v.x);
        const py = parseFloat(v.y);
        const pz = parseFloat(v.z);
        return {
          x: Number.isFinite(px) ? px : 0,
          y: Number.isFinite(py) ? py : 0,
          z: Number.isFinite(pz) ? pz : 0
        };
      };

      const numericPos = toNum(position || { x: 0, y: 0, z: 0 });
      const numericRot = toNum(rotation || { x: 0, y: 0, z: 0 });

      // A-Frame look-controls не поддерживает roll, поэтому обнуляем z, чтобы избежать наклона камеры
      if (Math.abs(numericRot.z) > 0.001) {
        console.log('🎯 ViewerManager: нормализуем roll камеры (z) c', numericRot.z, 'до 0');
      }
      numericRot.z = 0;

      return { position: numericPos, rotation: numericRot };
    } catch (error) {
      console.error('❌ Ошибка получения позиции камеры:', error);
      return null;
    }
  }  /**
   * Устанавливает позицию камеры
   */
  setCameraPosition(cameraData) {
    // Пробуем найти камеру разными способами
    let camera = this.aframeCamera ||
  (this.aframeScene && typeof this.aframeScene.querySelector === 'function' ? this.aframeScene.querySelector('a-camera') : null) ||
  (this.aframeScene && typeof this.aframeScene.querySelector === 'function' ? this.aframeScene.querySelector('[camera]') : null) ||
      document.querySelector('a-camera') ||
      document.querySelector('[camera]');

    if (!camera || !cameraData) {

      return false;
    }

    try {
      // 🎯 ИСПРАВЛЕНИЕ: НЕ трогаем look-controls здесь - управляется извне
      
      // Сначала FOV, если задан
      if (cameraData.fov != null) {
        const fov = Math.max(10, Math.min(130, parseFloat(cameraData.fov)));
        camera.setAttribute('fov', fov);
        console.log('🎯 ViewerManager: установлен FOV:', fov);
      }

      if (cameraData.position) {
        const p = cameraData.position;
        camera.setAttribute('position', `${p.x || 0} ${p.y || 0} ${p.z || 0}`);
        console.log('🎯 ViewerManager: установлена позиция:', `${p.x || 0} ${p.y || 0} ${p.z || 0}`);
      }

      if (cameraData.rotation) {
        const sanitizeAngle = (val) => {
          const num = Number(val);
          if (!Number.isFinite(num)) return 0;
          let normalized = num % 360;
          if (normalized > 180) normalized -= 360;
          if (normalized < -180) normalized += 360;
          return normalized;
        };

        const inp = cameraData.rotation;
        const rotX = sanitizeAngle(inp.x || 0);
        const rotY = sanitizeAngle(inp.y || 0);
        const rotationString = `${rotX} ${rotY} 0`;

        camera.setAttribute('rotation', rotationString);

        if (camera.object3D) {
          camera.object3D.rotation.set(0, 0, 0, 'XYZ');
          camera.object3D.updateMatrixWorld(true);
        }

        const lookControls = camera.components && camera.components['look-controls'];
        if (lookControls && lookControls.pitchObject && lookControls.yawObject) {
          try {
            const deg2rad = Math.PI / 180;
            lookControls.pitchObject.rotation.set(rotX * deg2rad, 0, 0, 'XYZ');
            lookControls.yawObject.rotation.set(0, rotY * deg2rad, 0, 'YXZ');
            // Полностью сбрасываем паразитные углы для исключения roll/наклона
            lookControls.pitchObject.rotation.y = 0;
            lookControls.pitchObject.rotation.z = 0;
            lookControls.yawObject.rotation.x = 0;
            lookControls.yawObject.rotation.z = 0;

            if (lookControls.el && lookControls.el.object3D) {
              lookControls.el.object3D.rotation.set(0, 0, 0);
              lookControls.el.object3D.updateMatrixWorld(true);
            }

            if (typeof lookControls.updateOrientation === 'function') {
              lookControls.updateOrientation();
            } else if (typeof lookControls.update === 'function') {
              lookControls.update();
            }

            console.log('🎯 ViewerManager: ориентация look-controls синхронизирована:', rotationString);
          } catch (e) {
            console.warn('🎯 ViewerManager: не удалось обновить look-controls:', e.message);
          }
        }

        console.log('🎯 ViewerManager: установлена ориентация:', rotationString);
      }

      return true;
    } catch (error) {
      console.error('❌ Ошибка при установке позиции камеры:', error);
      return false;
    }
  }

  /**
   * Сохраняет текущую позицию камеры для сцены
   */
  saveCameraPositionForScene(sceneId) {
    if (!window.sceneManager) {

      return false;
    }

    const cameraPosition = this.getCameraPosition();
    if (!cameraPosition) {

      return false;
    }

    // Добавим текущий FOV
    try {
  const camComp = this.aframeCamera && typeof this.aframeCamera.getAttribute === 'function' ? this.aframeCamera.getAttribute('camera') : {};
      const fov = parseFloat(camComp.fov);
      if (!isNaN(fov)) cameraPosition.fov = fov;
    } catch {}

    const scene = window.sceneManager.getSceneById(sceneId);
    if (!scene) {

      return false;
    }

  scene.cameraPosition = cameraPosition;

    return true;
  }
}
