// Retouch Watchdog: гарантирует привязку обработчика к #retouch-btn и готовность RetouchManager
// Используется как страховка против зацикленного внешнего ретуш-интегратора, который спамит "Кнопка ретуши не найдена".

console.log('🛡 RetouchWatchdog: старт');

const MAX_ATTEMPTS = 200; // ~100 секунд при 500мс интервале
let attempts = 0;
let attached = false;

function bindRetouchButton() {
  attempts++;
  const btn = document.getElementById('retouch-btn');
  const undoBtn = document.getElementById('retouch-undo-btn');
  const rm = (window.app && window.app.retouchManager) || window.retouchManager || window._retouchManager;

  if (!btn) {
    if (attempts % 20 === 0) console.warn('🛡 RetouchWatchdog: кнопка ещё не найдена (attempt=' + attempts + ')');
    return false;
  }
  if (!rm) {
    if (attempts % 20 === 0) console.warn('🛡 RetouchWatchdog: RetouchManager ещё не инициализирован');
    return false;
  }

  if (btn.__retouchBound) {
    if (!attached) {
      console.log('🛡 RetouchWatchdog: обработчик уже был привязан (внешним кодом)');
      attached = true;
    }
    return true;
  }

  btn.__retouchBound = true;
  btn.addEventListener('click', async () => {
    try {
      const sceneManager = window.sceneManager || (window.app && window.app.sceneManager);
      const scene = sceneManager && sceneManager.getCurrentScene ? sceneManager.getCurrentScene() : null;
      if (!scene) {
        console.warn('🛡 RetouchWatchdog: нет текущей сцены');
        return;
      }
      console.log('🛡 RetouchWatchdog: запуск mask draw через watchdog');
      const ok = await rm.startMaskDraw(scene);
      if (ok) {
        console.log('🛡 RetouchWatchdog: применяем ретушь');
        const res = await rm.applyRetouch(scene);
        console.log('🛡 RetouchWatchdog: результат applyRetouch=', res);
        if (undoBtn) undoBtn.disabled = !rm.canUndo(scene.id);
      } else {
        console.log('🛡 RetouchWatchdog: отмена пользователем');
      }
    } catch(e) {
      console.error('🛡 RetouchWatchdog: ошибка ретуши', e);
    }
  }, { once: false });

  console.log('🛡 RetouchWatchdog: обработчик привязан успешно');
  attached = true;
  window.dispatchEvent(new CustomEvent('retouch-watchdog-attached'));
  return true;
}

// Публикуем дружелюбный API для внешнего интегратора
window.__retouchWatchdogForceBind = () => bindRetouchButton();

// Если внешний интегратор вызывает patchRetouchButton – заменим его безопасной заглушкой
if (!window.patchRetouchButton) {
  window.patchRetouchButton = function() {
    return bindRetouchButton();
  };
} else {
  try {
    const original = window.patchRetouchButton;
    window.patchRetouchButton = function() {
      const r = bindRetouchButton();
      if (!r) return original.apply(this, arguments);
      return r;
    };
  } catch(e) {}
}

const interval = setInterval(() => {
  if (attached) { clearInterval(interval); return; }
  if (attempts >= MAX_ATTEMPTS) {
    console.warn('🛡 RetouchWatchdog: превышен лимит попыток');
    clearInterval(interval);
    return;
  }
  bindRetouchButton();
}, 500);

window.addEventListener('retouch-manager-ready', () => {
  console.log('🛡 RetouchWatchdog: получено событие retouch-manager-ready');
  bindRetouchButton();
});
