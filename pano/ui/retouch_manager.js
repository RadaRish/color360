// Ретушь в редакторе: рисование маски поверх текущей панорамы,
// отправка изображения+маски на /api/retouch, замена текстуры и undo.
const DEBUG = false; // production flag: отключаем подробный лог

export default class RetouchManager {
  constructor(viewerManager, sceneManager) {
    this.viewerManager = viewerManager;
    this.sceneManager = sceneManager;
    this.overlay = null;
    this.canvas = null;
    this.ctx = null;
    this._drawing = false;
    this._points = [];
    this._last = null;
    this._undoStacks = new Map(); // sceneId -> [{ src, blobUrl? }]
    this._maskDataUrl = null;
    this._finishResolver = null;
  }

  canUndo(sceneId) {
    const st = this._undoStacks.get(sceneId);
    return Array.isArray(st) && st.length > 0;
  }

  async startMaskDraw(scene) {
    // Создаём прозрачный overlay поверх viewer-container
    const container = document.getElementById('viewer-container');
    if (!container) throw new Error('viewer-container не найден');

    // Если уже открыт — закрываем предыдущий
    this._teardownOverlay();

    const overlay = document.createElement('div');
    overlay.id = 'retouch-overlay';
    // Гарантируем, что контейнер позиционирован (для абсолютного позиционирования overlay)
    try {
      const pos = window.getComputedStyle(container).position;
      if (!pos || pos === 'static') container.style.position = 'relative';
    } catch {}
    overlay.style.cssText = `
      position: absolute; inset: 0; /* полностью поверх viewer-container */
      z-index: 10000; cursor: crosshair; background: rgba(0,0,0,0.0);
    `;

    const canvas = document.createElement('canvas');
    canvas.style.cssText = 'position:absolute; left:0; top:0; width:100%; height:100%;';
    overlay.appendChild(canvas);

    const toolbar = document.createElement('div');
    toolbar.style.cssText = `
      position:absolute; right:80px; top:16px; display:flex; gap:12px; /* смещаем левее аватара, увеличиваем gap */
      background: rgba(18,18,18,0.85); border:1px solid rgba(255,255,255,0.15);
      padding:12px 16px; border-radius:10px; color:#fff; font-family:system-ui; align-items:center; /* увеличиваем padding */
      min-width: 300px; /* обеспечиваем минимальную ширину */
    `;
    toolbar.innerHTML = `
      <span style="opacity:.9; flex-shrink:0;">Рисуйте область для удаления</span>
      <button id="retouch-apply" class="icon-btn modern-icon-btn" style="padding:8px 16px; white-space:nowrap;">Готово</button>
      <button id="retouch-cancel" class="icon-btn modern-icon-btn" style="padding:8px 16px; white-space:nowrap;">Отмена</button>
    `;
    overlay.appendChild(toolbar);

    container.appendChild(overlay);

    // Инициализация canvas
    const dpr = window.devicePixelRatio || 1;
    const resize = () => {
      const rect = overlay.getBoundingClientRect();
      canvas.width = Math.max(1, Math.floor(rect.width * dpr));
      canvas.height = Math.max(1, Math.floor(rect.height * dpr));
      const ctx = canvas.getContext('2d');
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.lineWidth = 10; // Делаем кисть еще тоньше для более точного выделения
      ctx.lineJoin = 'round';
      ctx.lineCap = 'round';
      ctx.strokeStyle = 'rgba(255,0,0,0.9)';
      ctx.fillStyle = 'rgba(255,0,0,0.6)';
      this.ctx = ctx;
      this.canvas = canvas;
      this.overlay = overlay;
      this._redraw();
    };
    resize();
    window.addEventListener('resize', resize);
    overlay._onResize = resize;

    // Обработчики рисования
    const toLocal = (e) => {
      const rect = canvas.getBoundingClientRect();
      const clientX = e.touches ? e.touches[0].clientX : e.clientX;
      const clientY = e.touches ? e.touches[0].clientY : e.clientY;
      return { x: clientX - rect.left, y: clientY - rect.top };
    };
    const onDown = (e) => { 
      e.preventDefault(); 
  if (DEBUG) console.log('RetouchManager: mousedown/touchstart'); 
      this._drawing = true; 
      this._points.push([]); 
      const p=toLocal(e); 
      this._points[this._points.length-1].push(p); 
      this._last = p; 
      this._redraw(); 
    };
    const onMove = (e) => { 
      if (!this._drawing) return; 
      const p=toLocal(e); 
      this._points[this._points.length-1].push(p); 
      this._last = p; 
      this._redraw(); 
    };
    const onUp = (e) => { 
      if (!this._drawing) return; 
  if (DEBUG) console.log('RetouchManager: mouseup/touchend'); 
      this._drawing = false; 
      this._last = null; 
      this._redraw(); 
    };

    overlay.addEventListener('mousedown', onDown);
    overlay.addEventListener('mousemove', onMove);
    overlay.addEventListener('mouseup', onUp);
    overlay.addEventListener('mouseleave', onUp);
    overlay.addEventListener('touchstart', onDown, { passive:false });
    overlay.addEventListener('touchmove', onMove, { passive:false });
    overlay.addEventListener('touchend', onUp);

    overlay._cleanup = () => {
      window.removeEventListener('resize', resize);
      overlay.removeEventListener('mousedown', onDown);
      overlay.removeEventListener('mousemove', onMove);
      overlay.removeEventListener('mouseup', onUp);
      overlay.removeEventListener('mouseleave', onUp);
      overlay.removeEventListener('touchstart', onDown);
      overlay.removeEventListener('touchmove', onMove);
      overlay.removeEventListener('touchend', onUp);
    };

    // Кнопки
    overlay.querySelector('#retouch-apply').addEventListener('click', (e) => {
  if (DEBUG) console.log('RetouchManager: click APPLY, points:', this._points?.length);
      
      // Предотвращаем всплытие события и рисование на canvas
      e.preventDefault();
      e.stopPropagation();
      
      // Если пользователь ничего не нарисовал, создаем тестовую маску в центре
      if (this._points.length === 0 || this._points.every(poly => !poly || poly.length < 2)) {
  if (DEBUG) console.log('RetouchManager: creating test mask');
        const rect = this.canvas.getBoundingClientRect();
        const centerX = rect.width / 2;
        const centerY = rect.height / 2;
        const radius = 50;
        
        // Создаем круглую маску в центре
        const circle = [];
        for (let i = 0; i <= 20; i++) {
          const angle = (i / 20) * 2 * Math.PI;
          circle.push({
            x: centerX + Math.cos(angle) * radius,
            y: centerY + Math.sin(angle) * radius
          });
        }
        this._points = [circle];
        this._redraw();
  if (DEBUG) console.log('RetouchManager: test mask created');
      }
      
      this._maskDataUrl = this._exportMask();
  if (DEBUG) console.log('RetouchManager: mask data prepared');
      this._resolveFinish(true);
    });
    overlay.querySelector('#retouch-cancel').addEventListener('click', (e) => {
  if (DEBUG) console.log('RetouchManager: click CANCEL');
      
      // Предотвращаем всплытие события и рисование на canvas
      e.preventDefault();
      e.stopPropagation();
      
      this._maskDataUrl = null; // Очищаем маску при отмене
      this._resolveFinish(false);
    });

    // Блокируем перетаскивание маркеров в это время
    window._dragSystemBlocked = true;

    // Возвращаем промис завершения рисования
    return new Promise((res) => { this._finishResolver = res; });
  }

  _resolveFinish(applied) {
    try {
      this._teardownOverlay();
    } finally {
      window._dragSystemBlocked = false;
    }
    const r = this._finishResolver; this._finishResolver = null;
    if (r) r(applied);
  }

  _exportMask() {
  if (DEBUG) console.log('RetouchManager: _exportMask run');
    
    if (!this.canvas) {
      console.log('🎨 Debug RetouchManager: canvas отсутствует, возвращаем null');
      return null;
    }
    
    // Маска: заполняем нарисованные полигоны белым на чёрном фоне
    const tmp = document.createElement('canvas');
    const rect = this.canvas.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    tmp.width = Math.max(1, Math.floor(rect.width * dpr));
    tmp.height = Math.max(1, Math.floor(rect.height * dpr));
    
  if (DEBUG) console.log('RetouchManager: temp canvas:', tmp.width, 'x', tmp.height);
    
  const ctx = tmp.getContext('2d', { willReadFrequently: true });
    ctx.scale(dpr, dpr);
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, rect.width, rect.height);
    ctx.fillStyle = '#fff';
    
    let drawnPolygons = 0;
    for (const poly of this._points) {
      if (!poly || poly.length < 2) {
  if (DEBUG) console.log('RetouchManager: skip poly');
        continue;
      }
  if (DEBUG) console.log('RetouchManager: draw poly');
      ctx.beginPath();
      ctx.moveTo(poly[0].x, poly[0].y);
      for (let i=1;i<poly.length;i++) ctx.lineTo(poly[i].x, poly[i].y);
      ctx.closePath();
      ctx.fill();
      drawnPolygons++;
    }
    
  if (DEBUG) console.log('RetouchManager: polygons drawn:', drawnPolygons);
    const result = tmp.toDataURL('image/png');
  if (DEBUG) console.log('RetouchManager: mask dataURL ready');
    
    return result;
  }

  _redraw() {
    if (!this.ctx || !this.canvas) return;
    const { ctx, canvas } = this;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.save();
    // рисуем текущие полигоны
    ctx.globalCompositeOperation = 'source-over';
    ctx.strokeStyle = 'rgba(255,0,0,0.95)';
    ctx.fillStyle = 'rgba(255,0,0,0.35)';
    for (const poly of this._points) {
      if (poly.length === 0) continue;
      ctx.beginPath();
      ctx.moveTo(poly[0].x, poly[0].y);
      for (let i=1;i<poly.length;i++) ctx.lineTo(poly[i].x, poly[i].y);
      if (!this._drawing) ctx.closePath();
      ctx.stroke();
      if (!this._drawing) ctx.fill();
    }
    ctx.restore();
  }

  _teardownOverlay() {
  if (DEBUG) console.log('RetouchManager: teardown overlay');
    // Сохраним последние полигоны и геометрию ОПЕРЕЖАЮЩЕ, до удаления из DOM
    try {
      if (Array.isArray(this._points) && this._points.length) {
        this._savedPolygons = this._points.map(poly => (poly || []).map(p => ({ x: p.x, y: p.y })));
      }
      // Берем геометрию overlay/canvas ДО remove(), иначе getBoundingClientRect() вернёт нули
      const targetEl = this.canvas || this.overlay;
      if (targetEl && targetEl.getBoundingClientRect) {
        const r = targetEl.getBoundingClientRect();
        this._overlayRect = { left: r.left, top: r.top, width: r.width, height: r.height };
      }
    } catch {}
    // Теперь можно убрать overlay из DOM
    if (this.overlay) {
      if (this.overlay._cleanup) this.overlay._cleanup();
      this.overlay.remove();
    }
    this.overlay = null;
    this.canvas = null;
    this.ctx = null;
    this._points = [];
    this._last = null;
    // НЕ очищаем _maskDataUrl здесь! Она нужна для applyRetouch()
    // this._maskDataUrl = null;
  if (DEBUG) console.log('RetouchManager: overlay removed');
  }

  async _getCurrentPanoramaBlob() {
    // Получаем src текущей сцены
    const currentScene = this.sceneManager.getCurrentScene();
  const src = (currentScene && currentScene.src ? currentScene.src : (this.viewerManager && this.viewerManager.currentPanorama ? this.viewerManager.currentPanorama : undefined));
  if (DEBUG) console.log('RetouchManager: get panorama blob');
    if (!src) throw new Error('Источник панорамы не найден');

    if (src.startsWith('data:')) {
      // Конвертируем data: URL напрямую в blob
  if (DEBUG) console.log('RetouchManager: convert dataURL->blob');
      return this._dataURLtoBlob(src);
    }
    
    if (src.startsWith('blob:') || src.startsWith('http')) {
      // Для blob: и http: URLs делаем fetch
  if (DEBUG) console.log('RetouchManager: fetch blob/http');
      const response = await fetch(src);
      return await response.blob();
    }
    
    // Локальный относительный путь - делаем fetch к серверу
  if (DEBUG) console.log('RetouchManager: fetch relative');
    const response = await fetch(src);
    return await response.blob();
  }

  async _getCurrentPanoramaBlobUrl() {
    // Получаем src текущей сцены
    const currentScene = this.sceneManager.getCurrentScene();
    const src = currentScene?.src || this.viewerManager?.currentPanorama;
    console.log('🎨 Debug RetouchManager: _getCurrentPanoramaBlobUrl src:', src ? src.substring(0, 50) + '...' : 'null');
    if (!src) throw new Error('Источник панорамы не найден');

    if (src.startsWith('blob:') || src.startsWith('http')) {
      console.log('🎨 Debug RetouchManager: возвращаем существующий blob/http URL');
      return src;
    }
    if (src.startsWith('data:')) {
      // Конвертируем в blob url
      console.log('🎨 Debug RetouchManager: конвертируем data: URL в blob:');
      const blob = this._dataURLtoBlob(src);
      const blobUrl = URL.createObjectURL(blob);
      console.log('🎨 Debug RetouchManager: создан blob URL:', blobUrl);
      return blobUrl;
    }
    // Локальный относительный путь — возвращаем как есть, сервер отдаст
    console.log('🎨 Debug RetouchManager: возвращаем относительный путь как есть');
    return src;
  }

  _dataURLtoBlob(dataurl) {
    const arr = dataurl.split(',');
    const mime = arr[0].match(/:(.*?);/)[1];
    const bstr = atob(arr[1]);
    let n = bstr.length;
    const u8arr = new Uint8Array(n);
    while (n--) u8arr[n] = bstr.charCodeAt(n);
    return new Blob([u8arr], { type: mime });
  }

  _blobToDataURL(blob) {
    return new Promise((resolve) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.readAsDataURL(blob);
    });
  }

  async _getImageSizeFromBlob(blob) {
    try {
      const url = URL.createObjectURL(blob);
      const img = new Image();
      const loaded = new Promise((res) => { img.onload = () => res(true); });
      img.src = url;
      await loaded;
      const size = { width: img.naturalWidth || img.width, height: img.naturalHeight || img.height };
      URL.revokeObjectURL(url);
      return size;
    } catch (e) {
      console.warn('🎨 Warning RetouchManager: не удалось определить размер изображения:', e && e.message);
      return null;
    }
  }

  // Пересчёт экранных координат полигона в эквирект-UV и отрисовка маски указанного размера
  async _exportMaskEquirect(targetWidth, targetHeight, options) {
    try {
      if (!this._savedPolygons || !this._savedPolygons.length) return null;
      const aScene = document.querySelector('a-scene');
      const cameraEl = aScene && typeof aScene.querySelector === 'function' ? aScene.querySelector('[camera]') : undefined;
      if (!aScene || !cameraEl || typeof THREE === 'undefined') return null;

      const camera = cameraEl.getObject3D('camera');
      const renderer = aScene.renderer;
      const canvas = renderer && renderer.domElement;
      if (!camera || !renderer || !canvas) return null;
      // Сохраняем исходную ориентацию/позицию камеры (на всякий случай - сейчас мы её не меняем, но оставляем для будущих улучшений)
      const originalRotation = camera.rotation.clone();
      const originalPosition = camera.position.clone();
      const toDeg = (rad) => (THREE && THREE.MathUtils && typeof THREE.MathUtils.radToDeg === 'function')
        ? THREE.MathUtils.radToDeg(rad)
        : (rad * 180) / Math.PI;
      console.log('🎯 Debug RetouchManager: текущая ориентация камеры (deg):',
        `rotation: pitch:${toDeg(originalRotation.x).toFixed(2)}, yaw:${toDeg(originalRotation.y).toFixed(2)}, roll:${toDeg(originalRotation.z).toFixed(2)}`,
        `position: x:${originalPosition.x.toFixed(3)}, y:${originalPosition.y.toFixed(3)}, z:${originalPosition.z.toFixed(3)}`);

      if (typeof camera.updateWorldMatrix === 'function') {
        camera.updateWorldMatrix(true, true);
      } else {
        camera.updateMatrix();
        camera.updateMatrixWorld(true);
      }
      if (camera.updateProjectionMatrix) {
        camera.updateProjectionMatrix();
      }

  const sphereRadius = (this.viewerManager && this.viewerManager.coordinateManager && this.viewerManager.coordinateManager.sphereRadius) ? this.viewerManager.coordinateManager.sphereRadius : 10;
      const sceneRect = canvas.getBoundingClientRect();

      const mappingCamera = camera;
      const raycaster = new THREE.Raycaster();
      const ndc = new THREE.Vector2();
      const sphere = new THREE.Sphere(new THREE.Vector3(0, 0, 0), sphereRadius);
      const intersectionPoint = new THREE.Vector3();
      const normalVector = new THREE.Vector3();

      const screenToUV = (localX, localY) => {
        const nx = (localX / sceneRect.width) * 2 - 1; // [0..w] -> [-1..1]
        const ny = -(localY / sceneRect.height) * 2 + 1; // [0..h] -> [-1..1] и инвертируем Y
        ndc.set(nx, ny);
        raycaster.setFromCamera(ndc, mappingCamera);
        const hit = raycaster.ray.intersectSphere(sphere, intersectionPoint);
        if (!hit) return null;
        normalVector.copy(intersectionPoint).normalize();
        const theta = Math.atan2(normalVector.x, normalVector.z); // горизонт
        const phi = Math.asin(Math.max(-1, Math.min(1, normalVector.y))); // вертикаль
        let u = 0.5 + theta / (2 * Math.PI);
        let v = 0.5 - phi / Math.PI;
        u = ((u % 1) + 1) % 1; // wrap
        v = Math.max(0, Math.min(1, v));
        return { u, v };
      };

      // Целевая эквирект-маска, которую отправим в AI
  const mask = document.createElement('canvas');
  mask.width = targetWidth;
  mask.height = targetHeight;
  const mctx = mask.getContext('2d', { willReadFrequently: true });
      mctx.fillStyle = '#000';
      mctx.fillRect(0, 0, targetWidth, targetHeight);
      mctx.fillStyle = '#fff';

      // 🎯 КРИТИЧЕСКИ ВАЖНО: получаем точные координаты renderer canvas
      const ov = this._overlayRect || sceneRect;
      
      // Проверяем совпадение overlay и renderer canvas
      const overlayOffsetX = (ov.left || 0) - (sceneRect.left || 0);
      const overlayOffsetY = (ov.top || 0) - (sceneRect.top || 0);
      
      const scaleX = sceneRect.width > 0 && ov.width > 0 ? (sceneRect.width / ov.width) : 1;
      const scaleY = sceneRect.height > 0 && ov.height > 0 ? (sceneRect.height / ov.height) : 1;
      
      console.log('🎨 Debug RetouchManager: sceneRect=', sceneRect, ' overlayRect=', ov, ' scale=', scaleX.toFixed(4), scaleY.toFixed(4));
      console.log('🎯 Debug RetouchManager: overlay offset=', overlayOffsetX.toFixed(2), overlayOffsetY.toFixed(2));

      // ================= FAST / SAFE FALLBACK =================
      // Частая причина зависания: тяжёлый перебор пикселей + getImageData на огромных canvas (6K панорамы).
      // Для устранения подвисаний вводим быстрый путь: просто масштабируем экранную (screen-space) маску
      // до размера панорамы без сферического перерасчёта. Даёт достаточную точность для вырезания LaMa,
      // но в разы быстрее. При необходимости можно отключить: window.__DISABLE_SIMPLE_EQUIRECT = true
      const simpleEnabled = false; // FastMask отключён, всегда используем HeavyMask
      // ================= /FAST / SAFE FALLBACK =================

      // 1) Построим экранную маску (в координатах renderer canvas) из сохранённых полигонов
      const scrW = Math.max(1, Math.round(sceneRect.width));
      const scrH = Math.max(1, Math.round(sceneRect.height));
  const scr = document.createElement('canvas');
  scr.width = scrW; scr.height = scrH;
  const scrCtx = scr.getContext('2d', { willReadFrequently: true });
      scrCtx.fillStyle = '#000'; scrCtx.fillRect(0,0,scrW,scrH);
      scrCtx.fillStyle = '#fff';
      scrCtx.beginPath();
      let drewAny = false;
      for (const poly of this._savedPolygons) {
        if (!poly || poly.length < 3) continue;
        // 🎯 Учитываем offset overlay относительно renderer canvas
        const sx0 = (poly[0].x - overlayOffsetX) * scaleX, sy0 = (poly[0].y - overlayOffsetY) * scaleY;
        scrCtx.moveTo(sx0, sy0);
        for (let i=1; i<poly.length; i++) {
          scrCtx.lineTo((poly[i].x - overlayOffsetX) * scaleX, (poly[i].y - overlayOffsetY) * scaleY);
        }
        scrCtx.closePath();
        drewAny = true;
      }
      if (drewAny) scrCtx.fill();

      // 2) Отобразим каждый белый пиксель экранной маски в эквирект с адаптивным сплэтом
  console.log('⏳ HeavyMask: старт вычисления spherical mapping (может быть тяжело)');
      const scrImg = scrCtx.getImageData(0,0,scrW,scrH);
      const scrData = scrImg.data;
      // Подсчитаем площадь белой маски на экране
      let screenWhite = 0;
      for (let i = 0; i < scrData.length; i += 4) {
        if (scrData[i] >= 200 && scrData[i+1] >= 200 && scrData[i+2] >= 200) screenWhite++;
      }
      // Соответствие масштабов: сколько пикселей эквиректа приходится на 1 пиксель экрана
      const scaleUF = targetWidth / Math.max(1, sceneRect.width);
      const scaleVF = targetHeight / Math.max(1, sceneRect.height);
      const baseSplat = Math.ceil(Math.min(80, Math.max(8, Math.max(scaleUF, scaleVF) * 1.5))); // Увеличили покрытие
      // Адаптивная дискретизация по бюджету пикселей (не более ~600k рейкастов)
  const pixelBudget = 150000; // уменьшено для снижения нагрузки
      const step = Math.max(1, Math.floor(Math.sqrt((scrW * scrH) / pixelBudget)));

      const optInvertU = !!(options && options.invertU);
      const mapWithSplat = (splat, invertU=false) => {
        mctx.clearRect(0, 0, targetWidth, targetHeight);
        mctx.fillStyle = '#000'; 
        mctx.fillRect(0, 0, targetWidth, targetHeight);
        
        let mappedCount = 0;
        
        // 🎨 УЛУЧШЕННЫЙ АЛГОРИТМ: Создаем круглую кисть для лучшего качества
        const createCircularBrush = (radius) => {
          const size = radius * 2 + 1;
          const brush = new Array(size * size);
          const center = radius;
          
          for (let y = 0; y < size; y++) {
            for (let x = 0; x < size; x++) {
              const dx = x - center;
              const dy = y - center;
              const distance = Math.sqrt(dx*dx + dy*dy);
              
              if (distance <= radius) {
                // Антиалиасинг: плавный переход от центра к краю
                const alpha = Math.max(0, 1 - distance / radius);
                brush[y * size + x] = Math.floor(alpha * 255);
              } else {
                brush[y * size + x] = 0;
              }
            }
          }
          return { data: brush, size, center };
        };
        
        const brush = createCircularBrush(Math.max(1, splat));
        
        for (let y=0; y<scrH; y+=step) {
          for (let x=0; x<scrW; x+=step) {
            const off = (y*scrW + x) * 4;
            if (scrData[off] < 200 || scrData[off+1] < 200 || scrData[off+2] < 200) continue;
            
            const uv = screenToUV(x, y);
            if (!uv) continue;
            
            const uu = (invertU || optInvertU) ? (1 - uv.u) : uv.u;
            const px = Math.floor(uu * targetWidth);
            const py = Math.floor(uv.v * targetHeight);
            
            // Применяем круглую кисть
            for (let by = 0; by < brush.size; by++) {
              for (let bx = 0; bx < brush.size; bx++) {
                const brushValue = brush.data[by * brush.size + bx];
                if (brushValue === 0) continue;
                
                const drawX = px - brush.center + bx;
                const drawY = py - brush.center + by;
                
                if (drawX >= 0 && drawX < targetWidth && drawY >= 0 && drawY < targetHeight) {
                  mctx.fillStyle = `rgb(${brushValue},${brushValue},${brushValue})`;
                  mctx.fillRect(drawX, drawY, 1, 1);
                }
              }
            }
            
            mappedCount++;
          }
        }
        return mappedCount;
      };

      // Первая попытка с базовым сплэтом
      let splat = Math.max(baseSplat, step);
      let mapped = mapWithSplat(splat, false);
      console.log('🧭 Debug RetouchManager: screen->equirect mapped pixels:', mapped, 'of', scrW*scrH, 'splat=', splat, 'scaleUF/VF=', scaleUF.toFixed(2), scaleVF.toFixed(2), 'screenWhite=', screenWhite);
      
      // Диагностика: проверяем несколько контрольных точек маппинга
      if (mapped > 0) {
        const testPoints = [
          {x: scrW/4, y: scrH/4, name: 'top-left'},
          {x: scrW/2, y: scrH/2, name: 'center'}, 
          {x: 3*scrW/4, y: 3*scrH/4, name: 'bottom-right'}
        ];
        console.log('🔍 Debug RetouchManager: UV mapping samples:');
        for (const pt of testPoints) {
          const uv = screenToUV(pt.x, pt.y);
          if (uv) {
            const eqX = Math.floor(uv.u * targetWidth);
            const eqY = Math.floor(uv.v * targetHeight);
            console.log(`  ${pt.name}: screen(${Math.round(pt.x)},${Math.round(pt.y)}) -> UV(${uv.u.toFixed(3)},${uv.v.toFixed(3)}) -> equirect(${eqX},${eqY})`);
          }
        }
      }

      // Оценим площадь белой маски; если она слишком мала — попробуем инвертировать U (внутренние сферы могут зеркалить текстуру)
      try {
        const imgData = mctx.getImageData(0, 0, targetWidth, targetHeight);
        const data = imgData.data;
        let whiteCount = 0;
        for (let i = 0; i < data.length; i += 4) {
          if (data[i] > 0 || data[i+1] > 0 || data[i+2] > 0) whiteCount++;
        }
        // Ожидаемая площадь ~ экранная площадь, умноженная на масштаб по U и V
        const expected = Math.max(1, Math.floor(screenWhite * scaleUF * scaleVF));
        const minPixels = Math.max(8000, Math.floor(expected * 0.6)); // увеличили до 8000px и 60% от ожидаемой
  console.log('📐 Debug RetouchManager: mask whiteCount=', whiteCount, 'minPixels=', minPixels, 'size=', targetWidth+'x'+targetHeight);
        if (whiteCount < minPixels) {
          // Увеличиваем сплэт и пробуем ещё раз (до трех попыток с большими коэффициентами)
          let improved = false;
          for (let factor of [2.0, 3.0, 4.0]) {
            const newSplat = Math.min(150, Math.max(splat, Math.ceil(baseSplat * factor))); // увеличили лимит до 150
            if (newSplat === splat) continue;
            splat = newSplat;
            mapped = mapWithSplat(splat, false);
            const imgData2 = mctx.getImageData(0, 0, targetWidth, targetHeight);
            const data2 = imgData2.data;
            whiteCount = 0; for (let i = 0; i < data2.length; i += 4) { if (data2[i] | data2[i+1] | data2[i+2]) whiteCount++; }
            console.log('📐 Debug RetouchManager: recheck whiteCount=', whiteCount, 'splat=', splat);
            if (whiteCount >= minPixels) { improved = true; break; }
          }
          if (!improved && screenWhite > 0) {
            // Попытка с инверсией U
            const mapped2 = mapWithSplat(splat, true);
            const imgData3 = mctx.getImageData(0, 0, targetWidth, targetHeight);
            const data3 = imgData3.data;
            let wc3 = 0; for (let i = 0; i < data3.length; i += 4) { if (data3[i] | data3[i+1] | data3[i+2]) wc3++; }
            console.warn('🎨 Warning RetouchManager: площадь мала, пробуем u->1-u; mapped2=', mapped2, 'wc3=', wc3);
          }
        }
  } catch (e) { console.warn('🎨 Warning RetouchManager: не удалось оценить/исправить площадь маски:', e && e.message); }

      // 🔧 Восстанавливаем исходную позицию и ориентацию камеры
      // Камеру мы не меняли (оставили реальную), но на всякий случай откатываем
      try {
        camera.position.copy(originalPosition);
        camera.rotation.copy(originalRotation);
        camera.updateMatrix();
        camera.updateMatrixWorld(true);
        if (camera.updateProjectionMatrix) camera.updateProjectionMatrix();
        console.log('🎯 Debug RetouchManager: восстановлена исходная позиция и ориентация камеры');
      } catch(_){ }
  console.log('✅ HeavyMask: вычисление завершено успешно');

      // --- DEBUG: автоматическое сохранение маски для визуального контроля ---
      if (window && window.__DEBUG_SAVE_MASK) {
        try {
          const link = document.createElement('a');
          link.href = mask.toDataURL('image/png');
          link.download = 'debug_mask.png';
          document.body.appendChild(link);
          link.click();
          document.body.removeChild(link);
        } catch(e) { console.warn('Не удалось сохранить debug_mask:', e); }
      }
      return mask.toDataURL('image/png');
    } catch (e) {
  console.warn('🎨 Warning RetouchManager: _exportMaskEquirect failed:', e && e.message);
      
      // 🔧 Восстанавливаем камеру даже в случае ошибки
      // camera восстановление не критично (мы её не модифицировали), но оставляем блок для совместимости
      
      return null;
    }
  }

  async applyRetouch(scene) {
    console.log('🎨 Debug RetouchManager: applyRetouch вызван');
    // --- DEBUG: автоматическое сохранение исходного изображения для контроля ---
    if (window && window.__DEBUG_SAVE_IMAGE && scene && scene.src && scene.src.startsWith('data:image')) {
      try {
        const link = document.createElement('a');
        link.href = scene.src;
        link.download = 'debug_image.jpg';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
      } catch(e) { console.warn('Не удалось сохранить debug_image:', e); }
    }
    if (!this.__versionLogged) {
      try {
        const buildMeta = document.querySelector('meta[name="x-build-version"]');
        console.log('🧾 RetouchManager Build Version:', buildMeta ? buildMeta.getAttribute('content') : 'unknown');
      } catch(_){}
      this.__versionLogged = true;
    }
    console.log('🎨 Debug RetouchManager: _maskDataUrl:', !!this._maskDataUrl);
    if (this._applying) {
      console.warn('⛔ RetouchManager: попытка повторного apply пока предыдущий не завершён');
      return { applied: false, reason: 'already-applying' };
    }
    this._applying = true;
    
    // Пользователь мог нажать "Отмена"
    if (!this._maskDataUrl) {
      console.log('🎨 Debug RetouchManager: _maskDataUrl пустой, возвращаем applied: false');
      return { applied: false };
    }

    // Укладываем в undo стек исходник сцены
    const sceneId = scene.id;
    const stack = this._undoStacks.get(sceneId) || [];
    stack.push({ src: scene.src });
    this._undoStacks.set(sceneId, stack);

    try {
  // Готовим multipart - обходим CSP проблему с blob URLs
      const imageBlob = await this._getCurrentPanoramaBlob(); // Получаем blob напрямую
      console.log('🎨 Debug RetouchManager: получили imageBlob:', !!imageBlob);

      // Определим размер исходной панорамы (ширина/высота) для корректной маски
      const imgSize = await this._getImageSizeFromBlob(imageBlob);
      // Если есть сохранённые полигоны и доступен THREE+камера — строим маску в эквирект-проекции
      let maskBlob;
      let maskDataUrlEq = null;
      if (imgSize && imgSize.width > 0 && imgSize.height > 0) {
        try {
          maskDataUrlEq = await this._exportMaskEquirect(imgSize.width, imgSize.height);
          if (maskDataUrlEq) {
            maskBlob = this._dataURLtoBlob(maskDataUrlEq);
            console.log('🎨 Debug RetouchManager: использована эквирект-маска', imgSize.width + 'x' + imgSize.height);
          }
  } catch (e) { console.warn('🎨 Warning RetouchManager: не удалось построить эквирект-маску, используем screen-маску:', e && e.message); }
      }
      if (!maskBlob) {
        console.log('🎨 Debug RetouchManager: используем ранее сохранённую screen-маску');
        maskBlob = this._dataURLtoBlob(this._maskDataUrl);
      }
      
      const fd = new FormData();
      fd.append('image', imageBlob, 'image.png');
      fd.append('mask', maskBlob, 'mask.png');

      // Добавляем улучшенные настройки AI для высококачественной ретуши панорам
      try {
        // 🎨 УЛУЧШЕННЫЕ ПАРАМЕТРЫ для панорамных изображений
        fd.append('prompt', 'remove object completely and seamlessly, fill with natural background texture, photorealistic inpainting, preserve architectural details and perspective, high resolution, detailed restoration, perfect integration');
        fd.append('negative_prompt', 'object remains visible, incomplete removal, artifacts, seams, blurry edges, spherical distortion, warping, unnatural texture, low quality, pixelated, cartoon, painting, watermark, text, borders');
        
        // Параметры оптимизированные для архитектурных панорам
        fd.append('guidance_scale', '15.0'); // Повышен для лучшего следования prompt'у
        fd.append('num_inference_steps', '75'); // Увеличен для максимального качества  
        fd.append('strength', '1.0'); // Максимальная сила для полного удаления
        
        // LaMa-specific параметры для лучшего качества
        fd.append('model', 'lama'); // Явно указываем LaMa модель
        fd.append('device', 'cpu'); // Принудительно CPU для стабильности
        fd.append('hd_strategy', 'Resize'); // Стратегия для высокого разрешения
        fd.append('hd_strategy_resize_limit', '4096'); // Лимит для HD обработки
        fd.append('ldm_steps', '75'); // LDM steps для лучшего качества
        fd.append('ldm_sampler', 'ddim'); // Лучший сэмплер для архитектуры
        
        // Переопределяем пользовательскими настройками если есть
        if (typeof window.getAISettings === 'function') {
          const aiSettings = window.getAISettings();
          console.log('🎨 Debug RetouchManager: добавляем AI настройки:', aiSettings);
          
          // Переопределяем только если пользователь задал специфичные настройки
          if (aiSettings.prompt && aiSettings.prompt.length > 10) {
            fd.set('prompt', aiSettings.prompt);
          }
          if (aiSettings.negative_prompt && aiSettings.negative_prompt.length > 5) {
            fd.set('negative_prompt', aiSettings.negative_prompt);
          }
          if (aiSettings.guidance_scale && aiSettings.guidance_scale > 0) {
            fd.set('guidance_scale', Math.min(20, Math.max(1, aiSettings.guidance_scale)).toString());
          }
          if (aiSettings.num_inference_steps && aiSettings.num_inference_steps > 0) {
            fd.set('num_inference_steps', Math.min(100, Math.max(10, aiSettings.num_inference_steps)).toString());
          }
          if (aiSettings.strength && aiSettings.strength > 0) {
            fd.set('strength', Math.min(1.0, Math.max(0.1, aiSettings.strength)).toString());
          }
        }
      } catch (error) {
        console.warn('🎨 Warning RetouchManager: ошибка при добавлении AI настроек:', error);
      }

      // Отправка на backend, который проксирует в AI
  // Первичным делаем /api/retouch (Node proxy), т.к. в проде отсутствует /api/lama/inpaint → 405
  const preferredEndpoint = (window && window.__RETOUCH_ENDPOINT) ? window.__RETOUCH_ENDPOINT : '/api/retouch';
  let endpointUsed = preferredEndpoint;
      // 🔐 Автокоррекция схемы: если страница по HTTPS, а endpoint http:// — переписываем во избежание Mixed Content
      try {
        if (window.location && window.location.protocol === 'https:' && /^http:\/\//i.test(endpointUsed)) {
          const httpsEndpoint = endpointUsed.replace(/^http:\/\//i,'https://');
          console.warn('🔐 RetouchManager: endpoint имел небезопасную схему, переписываем', endpointUsed, '→', httpsEndpoint);
          endpointUsed = httpsEndpoint;
        }
      } catch(_){}
  if (DEBUG) console.log('RetouchManager: POST', endpointUsed);
      
      const applyStartTs = performance.now();
      try {
        console.log('🧪 RetouchManager Diagnostics: FormData keys перед отправкой:', Array.from(fd.keys()));
        const imgField = fd.get('image');
        const maskField = fd.get('mask');
        console.log('🧪 RetouchManager Diagnostics: image exists:', !!imgField, 'mask exists:', !!maskField,
          'image size ~bytes:', imgField && imgField.size, 'mask size ~bytes:', maskField && maskField.size);
      } catch(diagErr) { console.warn('🧪 RetouchManager Diagnostics: ошибка чтения FormData', diagErr); }
      let stallTimer = setTimeout(()=>{
        console.warn('⏱️ Warning RetouchManager: fetch ещё не вернулся спустя 30s, возможно зависание backend. endpoint=', endpointUsed);
      }, 30000);
      let originalRespStatus = null;
      let resp = await fetch(endpointUsed, { method: 'POST', body: fd, timeout: 300000 });
      originalRespStatus = resp.status;
      if (DEBUG) console.log('RetouchManager: response status', resp.status);
      console.log('🎨 Debug RetouchManager: получен ответ:', resp.status, resp.statusText);
      clearTimeout(stallTimer);
      console.log('⏱️ Timing RetouchManager: total fetch duration ms=', Math.round(performance.now()-applyStartTs));
      
      if (!resp.ok) {
        // Обработка специфичных ошибок
        if (resp.status === 413) {
          throw new Error('Файл панорамы слишком большой для обработки. Попробуйте уменьшить разрешение.');
        } else if (resp.status === 503) {
          throw new Error('AI сервис временно недоступен. Попробуйте позже.');
        } else if (resp.status === 500) {
          const errorText = await resp.text().catch(() => 'Unknown server error');
          throw new Error(`Внутренняя ошибка сервера: ${errorText}`);
        } else if (resp.status === 400 || resp.status === 404 || resp.status === 405 || (originalRespStatus === 400 && !resp.ok)) {
          let details = '';
          try { details = await resp.text(); } catch(_){}
          console.warn(`⚠️ RetouchManager: статус ${resp.status} (original=${originalRespStatus}) - пробуем JSON fallback /api/retouch-json`);
          try {
            const jsonFallbackBody = JSON.stringify({
              imageData: this._lastPanoramaDataUrl || null,
              maskData: maskDataUrlEq || this._maskDataUrl || null,
              prompt: fd.get('prompt'),
              negative_prompt: fd.get('negative_prompt'),
              num_inference_steps: fd.get('num_inference_steps'),
              guidance_scale: fd.get('guidance_scale'),
              strength: fd.get('strength')
            });
            const jfResp = await fetch('/api/retouch-json', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: jsonFallbackBody,
              timeout: 300000
            });
            console.log('🧪 RetouchManager JSON fallback статус:', jfResp.status);
            if (jfResp.ok) {
              // Получим blob и применим как панораму
              const outBlob = await jfResp.blob();
              const outUrl = URL.createObjectURL(outBlob);
              console.log('🧪 RetouchManager: JSON fallback успех, применяем результат');
              await this._applyResultTexture(outUrl, scene);
              this._applying = false; this._maskDataUrl = null; return { applied: true, method: 'json-fallback' };
            } else {
              let jfTxt = await jfResp.text().catch(()=> '');
              throw new Error('JSON fallback не сработал ('+jfResp.status+'): '+jfTxt);
            }
          } catch(jsonFbErr) {
            throw new Error('Некорректный multipart (400) и JSON fallback провалился: '+ jsonFbErr.message +' | details: '+ (details || 'нет деталей'));
          }
        } else {
          throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
        }
      }

  // Диагностика статуса ретуши: сервер выставляет X-Retouch-Status
  const xStatus = resp.headers.get('x-retouch-status');
  const xError = resp.headers.get('x-retouch-error');
  const xMessage = resp.headers.get('x-retouch-message');
  if (xStatus) console.log('🎨 Debug RetouchManager: X-Retouch-Status:', xStatus);
  if (xError) console.warn('🎨 Debug RetouchManager: X-Retouch-Error:', xError);
  if (xMessage) console.log('🎨 Debug RetouchManager: X-Retouch-Message:', xMessage);
  
  // Обрабатываем разные статусы
  if (xStatus) {
    if (xStatus === 'error' && /original|fallback/i.test(xMessage || '')) {
      try { if (this.viewerManager && typeof this.viewerManager.showToast === 'function') this.viewerManager.showToast('AI ретушь недоступна. Показан оригинал.', 'warning', 4000); } catch(e){}
      throw new Error('AI service unavailable: ' + xStatus + (xMessage ? (' - ' + xMessage) : ''));
    } else if (xStatus === 'simulated') {
      try { if (this.viewerManager && typeof this.viewerManager.showToast === 'function') this.viewerManager.showToast('Применена базовая симуляция ретуши', 'info', 3000); } catch(e){}
    } else if (xStatus === 'success') {
      try { if (this.viewerManager && typeof this.viewerManager.showToast === 'function') this.viewerManager.showToast('AI ретушь успешно применена!', 'success', 2000); } catch(e){}
    }
  }

      // Ответ может быть как json { imageBase64 } так и прямой image/* поток
      let resultDataUrl;
      const ct = resp.headers.get('content-type') || '';
      console.log('🎨 Debug RetouchManager: content-type ответа:', ct);
      if (ct.includes('application/json')) {
        const json = await resp.json();
        console.log('🎨 Debug RetouchManager: JSON ответ получен, imageBase64:', !!json.imageBase64);
        if (json.imageBase64) resultDataUrl = 'data:image/png;base64,' + json.imageBase64;
      } else if (ct.startsWith('image/')) {
        console.log('🎨 Debug RetouchManager: получен image blob, конвертируем в data: URL');
        const outBlob = await resp.blob();
        // Конвертируем blob напрямую в data: URL, чтобы избежать CSP проблем с blob URLs
        resultDataUrl = await this._blobToDataURL(outBlob);
        console.log('🎨 Debug RetouchManager: конвертировали ответ image blob в data: URL, длина:', resultDataUrl ? resultDataUrl.length : 'null');
      } else {
        // Пытаемся как текст
        console.log('🎨 Debug RetouchManager: пытаемся получить как текст');
        const txt = await resp.text();
        console.log('🎨 Debug RetouchManager: текстовый ответ длина:', txt.length);
        if (txt.startsWith('data:image/')) resultDataUrl = txt;
      }

      console.log('🎨 Debug RetouchManager: resultDataUrl готов:', !!resultDataUrl, resultDataUrl ? 'длина: ' + resultDataUrl.length : 'пустой');
      if (!resultDataUrl) throw new Error('Неподдерживаемый ответ сервера ретуши');

      // Проверка эффекта ретуши по разнице в пределах маски; при отсутствии эффекта — автоповтор с инверсией U
      const calcMaskedDiff = async (origBlob, resDataUrl, maskDataUrl, size) => {
        try {
          const [origImg, resImg, maskImg] = [new Image(), new Image(), new Image()];
          const [origUrl, maskUrl] = [URL.createObjectURL(origBlob), maskDataUrl];
          const load = (img, src) => new Promise((res, rej) => { img.onload = () => res(); img.onerror = rej; img.src = src; });
          await Promise.all([load(origImg, origUrl), load(resImg, resDataUrl), load(maskImg, maskUrl)]);
          const w = size.width, h = size.height;
          const cO = document.createElement('canvas'); cO.width = w; cO.height = h;
          const cR = document.createElement('canvas'); cR.width = w; cR.height = h;
          const cM = document.createElement('canvas'); cM.width = w; cM.height = h;
          const octx = cO.getContext('2d'); const rctx = cR.getContext('2d'); const mctx = cM.getContext('2d');
          octx.drawImage(origImg, 0, 0, w, h);
          rctx.drawImage(resImg, 0, 0, w, h);
          mctx.drawImage(maskImg, 0, 0, w, h);
          const oData = octx.getImageData(0,0,w,h).data;
          const rData = rctx.getImageData(0,0,w,h).data;
          const mData = mctx.getImageData(0,0,w,h).data;
          let sum = 0, cnt = 0;
          const stride = Math.max(1, Math.floor(Math.sqrt((w*h)/300000)));
          for (let y=0; y<h; y+=stride) {
            for (let x=0; x<w; x+=stride) {
              const i = (y*w + x) * 4;
              if (mData[i] < 128 && mData[i+1] < 128 && mData[i+2] < 128) continue;
              const dr = Math.abs(oData[i] - rData[i]);
              const dg = Math.abs(oData[i+1] - rData[i+1]);
              const db = Math.abs(oData[i+2] - rData[i+2]);
              sum += (dr + dg + db) / 3; cnt++;
            }
          }
          URL.revokeObjectURL(origUrl);
          return cnt ? (sum / cnt) : 0;
  } catch(e) { console.warn('🎨 Warning RetouchManager: diff calc failed', e && e.message); return 999; }
      };

      let appliedSrc = resultDataUrl;
      if (maskDataUrlEq) {
        const diffMean = await calcMaskedDiff(imageBlob, resultDataUrl, maskDataUrlEq, imgSize);
        console.log('🧪 Debug RetouchManager: masked mean diff =', diffMean.toFixed(2));
        
        // Временно отключаем проверку различий - принимаем любой результат AI
        console.log('🎯 Debug RetouchManager: Принимаем результат AI без проверки различий');
        /* if (diffMean < 1.5) { // Снизили порог для более мягкой проверки
          console.warn('🎨 Warning RetouchManager: низкая разница внутри маски, пробуем инверсию U');
          const maskEqU = await this._exportMaskEquirect(imgSize.width, imgSize.height, { invertU: true });
          if (maskEqU) {
            const fd2 = new FormData();
            fd2.append('image', imageBlob, 'image.png');
            fd2.append('mask', this._dataURLtoBlob(maskEqU), 'mask.png');
            
            // Add AI settings for retry request as well
            try {
              if (typeof window.getAISettings === 'function') {
                const aiSettings = window.getAISettings();
                if (aiSettings.prompt) {
                  fd2.append('prompt', aiSettings.prompt);
                }
                if (aiSettings.negative_prompt) {
                  fd2.append('negative_prompt', aiSettings.negative_prompt);
                }
                if (aiSettings.guidance_scale) {
                  fd2.append('guidance_scale', aiSettings.guidance_scale.toString());
                }
                if (aiSettings.num_inference_steps) {
                  fd2.append('num_inference_steps', aiSettings.num_inference_steps.toString());
                }
                if (aiSettings.strength) {
                  fd2.append('strength', aiSettings.strength.toString());
                }
              }
            } catch (error) {
              console.warn('🎨 Warning RetouchManager: ошибка при добавлении AI настроек в повтор:', error);
            }
            
            const resp2 = await fetch('/api/retouch', { method: 'POST', body: fd2 });
            if (resp2.ok && (resp2.headers.get('content-type')||'').startsWith('image/')) {
              const out2 = await resp2.blob();
              appliedSrc = await this._blobToDataURL(out2);
              console.log('✅ Debug RetouchManager: повтор с U-инверсией выполнен');
            } else {
              console.warn('🎨 Warning RetouchManager: повтор с U-инверсией вернул не image/*');
            }
          }
        } */
      }

      // На этом этапе xStatus не содержит fallback/lama-unavailable — можно применять результат

      // Сохраняем результат для отладки
      // Убираем автоскачивание и открытие масок/результатов — пользователю не показываем служебные артефакты

      // Применяем к текущей сцене и viewer
      console.log('🎨 Debug RetouchManager: применяем результат к сцене');
  await this._applyPanoramaToScene(scene, appliedSrc);
      console.log('🎨 Debug RetouchManager: Ретушь успешно применена, очищаем _maskDataUrl');
      this._maskDataUrl = null; // Очищаем после успешного применения
      return { applied: true };
    } catch (error) {
      console.error('🎨 Debug RetouchManager: Ошибка при применении ретуши:', error);
      this._maskDataUrl = null; // Очищаем при ошибке
      throw error;
    } finally {
      this._applying = false;
      // Сбросим оверлей в любом случае (но не маску - она уже очищена выше)
      if (this.overlay) {
        if (this.overlay._cleanup) this.overlay._cleanup();
        this.overlay.remove();
        this.overlay = null;
        this.canvas = null;
        this.ctx = null;
        this._points = [];
        this._last = null;
      }
    }
  }

  async _applyPanoramaToScene(scene, src) {
    console.log('🎨 Debug RetouchManager: _applyPanoramaToScene src тип:', src.startsWith('data:') ? 'data:' : src.startsWith('blob:') ? 'blob:' : src.startsWith('http') ? 'http:' : 'other');
    
    let finalSrc = src;
    
    // Если получили data: URL, конвертируем в HTTP URL для CSP
    if (src.startsWith('data:')) {
      try {
        console.log('🎨 Debug RetouchManager: конвертируем data: URL в HTTP URL');
        
        const response = await fetch('/api/temp-file-from-data', {
          method: 'POST',
          headers: {
            'Content-Type': 'text/plain'
          },
          body: src
        });
        
        if (response.ok) {
          const result = await response.json();
          finalSrc = result.url;
          console.log('🎨 Debug RetouchManager: data: URL конвертирован в HTTP URL:', finalSrc);
        } else {
          console.error('🎨 Error RetouchManager: ошибка конвертации data: URL:', response.statusText);
        }
      } catch (error) {
        console.error('🎨 Error RetouchManager: ошибка при конвертации data: URL:', error);
      }
    }
    
    scene.src = finalSrc;
    console.log('🎨 Debug RetouchManager: сцена обновлена с URL:', finalSrc.substring(0, 50));

    // Отдаём установку панорамы централизованно ViewerManager — он сам
    // создаёт/использует a-assets, ждёт decode()/load и только затем
    // привязывает изображение к a-sky, что исключает "image is incomplete".
    await this.viewerManager.setPanorama(finalSrc);
    console.log('🎨 Debug RetouchManager: viewerManager.setPanorama завершен');
    
    // Восстановим маркеры по сцене
  if (this.viewerManager && typeof this.viewerManager.restoreMarkersForScene === 'function') this.viewerManager.restoreMarkersForScene(scene.id);
    console.log('🎨 Debug RetouchManager: маркеры восстановлены для сцены', scene.id);
  }

  async undo(scene) {
    const sceneId = scene.id;
    const stack = this._undoStacks.get(sceneId) || [];
    const prev = stack.pop();
    if (!prev) return false;
    await this._applyPanoramaToScene(scene, prev.src);
    return true;
  }
}
