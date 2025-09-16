// Ретушь в редакторе: рисование маски поверх текущей панорамы,
// отправка изображения+маски на /api/retouch, замена текстуры и undo.
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
    overlay.style.cssText = `
      position: fixed; inset: 0 0 0 300px; /* с учётом сайдбара */
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
      ctx.lineWidth = 20;
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
    const onDown = (e) => { e.preventDefault(); this._drawing = true; this._points.push([]); const p=toLocal(e); this._points[this._points.length-1].push(p); this._last = p; this._redraw(); };
    const onMove = (e) => { if (!this._drawing) return; const p=toLocal(e); this._points[this._points.length-1].push(p); this._last = p; this._redraw(); };
    const onUp = (e) => { if (!this._drawing) return; this._drawing = false; this._last = null; this._redraw(); };

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
    overlay.querySelector('#retouch-apply').addEventListener('click', () => {
      this._maskDataUrl = this._exportMask();
      this._resolveFinish(true);
    });
    overlay.querySelector('#retouch-cancel').addEventListener('click', () => {
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
    if (!this.canvas) return null;
    // Маска: заполняем нарисованные полигоны белым на чёрном фоне
    const tmp = document.createElement('canvas');
    const rect = this.canvas.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    tmp.width = Math.max(1, Math.floor(rect.width * dpr));
    tmp.height = Math.max(1, Math.floor(rect.height * dpr));
    const ctx = tmp.getContext('2d');
    ctx.scale(dpr, dpr);
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, rect.width, rect.height);
    ctx.fillStyle = '#fff';
    for (const poly of this._points) {
      if (!poly || poly.length < 2) continue;
      ctx.beginPath();
      ctx.moveTo(poly[0].x, poly[0].y);
      for (let i=1;i<poly.length;i++) ctx.lineTo(poly[i].x, poly[i].y);
      ctx.closePath();
      ctx.fill();
    }
    return tmp.toDataURL('image/png');
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
    if (this.overlay) {
      if (this.overlay._cleanup) this.overlay._cleanup();
      this.overlay.remove();
    }
    this.overlay = null;
    this.canvas = null;
    this.ctx = null;
    this._points = [];
    this._last = null;
    this._maskDataUrl = null;
  }

  async _getCurrentPanoramaBlobUrl() {
    // Получаем src текущей сцены
    const currentScene = this.sceneManager.getCurrentScene();
    const src = currentScene?.src || this.viewerManager?.currentPanorama;
    if (!src) throw new Error('Источник панорамы не найден');

    if (src.startsWith('blob:') || src.startsWith('http')) return src;
    if (src.startsWith('data:')) {
      // Конвертируем в blob url
      const blob = this._dataURLtoBlob(src);
      return URL.createObjectURL(blob);
    }
    // Локальный относительный путь — возвращаем как есть, сервер отдаст
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

  async applyRetouch(scene) {
    // Пользователь мог нажать "Отмена"
    if (!this._maskDataUrl) return { applied: false };

    // Укладываем в undo стек исходник сцены
    const sceneId = scene.id;
    const stack = this._undoStacks.get(sceneId) || [];
    stack.push({ src: scene.src });
    this._undoStacks.set(sceneId, stack);

    try {
      // Готовим multipart
      const imageUrl = await this._getCurrentPanoramaBlobUrl();
      const imageResp = await fetch(imageUrl);
      const imageBlob = await imageResp.blob();

      const maskBlob = await (await fetch(this._maskDataUrl)).blob();
      const fd = new FormData();
      fd.append('image', imageBlob, 'image.png');
      fd.append('mask', maskBlob, 'mask.png');

      // Отправка на backend, который проксирует в AI
      const resp = await fetch('/api/retouch', { method: 'POST', body: fd });
      if (!resp.ok) throw new Error('HTTP ' + resp.status);

      // Ответ может быть как json { imageBase64 } так и прямой image/* поток
      let resultDataUrl;
      const ct = resp.headers.get('content-type') || '';
      if (ct.includes('application/json')) {
        const json = await resp.json();
        if (json.imageBase64) resultDataUrl = 'data:image/png;base64,' + json.imageBase64;
      } else if (ct.startsWith('image/')) {
        const outBlob = await resp.blob();
        resultDataUrl = URL.createObjectURL(outBlob);
      } else {
        // Пытаемся как текст
        const txt = await resp.text();
        if (txt.startsWith('data:image/')) resultDataUrl = txt;
      }

      if (!resultDataUrl) throw new Error('Неподдерживаемый ответ сервера ретуши');

      // Применяем к текущей сцене и viewer
      await this._applyPanoramaToScene(scene, resultDataUrl);
      return { applied: true };
    } finally {
      // Сбросим оверлей и маску в любом случае
      this._teardownOverlay();
    }
  }

  async _applyPanoramaToScene(scene, src) {
    // Обновляем модель сцены
    scene.src = src;
    // Обновляем viewer
    await this.viewerManager.setPanorama(src);
    // Восстановим маркеры по сцене
    this.viewerManager.restoreMarkersForScene?.(scene.id);
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
