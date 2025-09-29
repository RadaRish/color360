// Ретушь в редакторе: рисование маски поверх текущей панорамы,
// отправка изображения+маски на /api/retouch, замена текстуры и undo.
const DEBUG = false; // production flag: отключаем подробный лог

export default class RetouchManager {
  constructor(viewerManager, sceneManager) {
    this.viewerManager = viewerManager;
    this.sceneManager = sceneManager;
    this overlay = null;
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
      this overlay = overlay;
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
      const targetEl = this.canvas || this overlay;
      if (targetEl && targetEl.getBoundingClientRect) {
        const r = targetEl.getBoundingClientRect();
        this._overlayRect = { left: r.left, top: r.top, width: r.width, height: r.height };
      }
    } catch {}
    // Теперь можно убрать overlay из DOM
    if (this overlay) {
      if (this overlay._cleanup) this overlay._cleanup();
      this overlay.remove();
    }
    this overlay = null;
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
      // === DEBUG: Визуализация контрольных точек overlay на эквирект-маске ===
      // Центр overlay
      const debugPoints = [
        {x: sceneRect.width/2, y: sceneRect.height/2, color: 'red', label: 'center'},
        {x: 0, y: 0, color: 'lime', label: 'top-left'},
        {x: sceneRect.width-1, y: 0, color: 'blue', label: 'top-right'},
        {x: 0, y: sceneRect.height-1, color: 'yellow', label: 'bottom-left'},
        {x: sceneRect.width-1, y: sceneRect.height-1, color: 'cyan', label: 'bottom-right'}
      ];
      for (const pt of debugPoints) {
        const uv = screenToUV(pt.x, pt.y);
        if (uv) {
          const px = Math.floor(uv.u * targetWidth);
          const py = Math.floor(
