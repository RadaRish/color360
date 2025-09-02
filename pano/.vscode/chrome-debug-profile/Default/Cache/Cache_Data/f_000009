/**
 * Менеджер координат и перемещения маркеров
 * Обеспечивает точное позиционирование с поддержкой сферических координат
 */
export default class CoordinateManager {
  constructor(viewerManager = null) {
    this.viewerManager = viewerManager;
    this.isDragging = false;
    this.draggedMarker = null;
    this.dragStartPosition = null;
    this.sphereRadius = 10; // Радиус сферы для позиционирования
    this.scene = null; // A-Frame сцена
    this.camera = null; // A-Frame камера
    this.raycaster = null; // THREE.js raycaster
    this.onPositionUpdateCallback = null; // Callback для обновления позиции
  }

  /**
   * Инициализация координатного менеджера с A-Frame сценой
   */
  initialize(scene) {
    this.scene = scene;
    this.camera = scene.querySelector('a-camera') || scene.querySelector('[camera]');

    if (!this.camera) {
      console.warn('⚠️ Камера не найдена в сцене');
      return;
    }

    // Инициализируем THREE.js raycaster при наличии THREE
    if (typeof THREE !== 'undefined') {
      this.raycaster = new THREE.Raycaster();
      console.log('📐 CoordinateManager инициализирован с THREE.js raycaster');
    } else {
      console.warn('⚠️ THREE.js не доступен, точность перетаскивания может быть снижена');
    }

    // Добавляем глобальные обработчики событий
    this.setupGlobalEventHandlers();

    console.log('✅ CoordinateManager успешно инициализирован');
  }

  /**
   * Настраивает глобальные обработчики событий для перетаскивания
   */
  setupGlobalEventHandlers() {
    // Обработчики движения и отпускания мыши
    document.addEventListener('mousemove', (e) => {
      this.onDrag(e);
    });

    document.addEventListener('mouseup', (e) => {
      this.endDrag(e);
    });

    // Обработчики для сенсорных устройств
    document.addEventListener('touchmove', (e) => {
      this.onDrag(e);
    });

    document.addEventListener('touchend', (e) => {
      this.endDrag(e);
    });

    console.log('🎮 Глобальные обработчики событий для перетаскивания настроены');
  }

  /**
   * Конвертирует 3D координаты в сферические (как в PSV)
   */
  cartesianToSpherical(x, y, z) {
    const radius = Math.sqrt(x * x + y * y + z * z);
    const yaw = Math.atan2(x, z);
    const pitch = Math.asin(y / radius);

    return {
      yaw: yaw,
      pitch: pitch,
      radius: radius
    };
  }

  /**
   * Конвертирует сферические координаты в 3D
   */
  sphericalToCartesian(yaw, pitch, radius = this.sphereRadius) {
    const x = radius * Math.sin(yaw) * Math.cos(pitch);
    const y = radius * Math.sin(pitch);
    const z = radius * Math.cos(yaw) * Math.cos(pitch);

    return { x, y, z };
  }

  /**
   * Получает позицию клика на сфере из события raycaster
   */
  getClickPositionOnSphere(event) {
    const detail = event.detail;
    if (!detail || !detail.intersection) {
      return null;
    }

    const intersection = detail.intersection;
    const point = intersection.point;

    // Нормализуем точку на сферу нужного радиуса
    const normalized = this.normalizeToSphere(point.x, point.y, point.z);

    console.log('🎯 Позиция клика на сфере:', normalized);
    return normalized;
  }

  /**
   * Нормализует точку на сферу заданного радиуса
   */
  normalizeToSphere(x, y, z, radius = this.sphereRadius) {
    const currentRadius = Math.sqrt(x * x + y * y + z * z);
    if (currentRadius === 0) return { x: 0, y: 0, z: radius };

    const scale = radius / currentRadius;
    return {
      x: x * scale,
      y: y * scale,
      z: z * scale
    };
  }

  /**
   * Инициализирует систему перетаскивания для маркера
   */
  /**
   * Настраивает перетаскивание для маркера с callback для обновления позиции
   */
  setupMarkerDragging(markerElement, hotspotId, onPositionUpdate = null) {
    console.log('🔧 Настраиваем перетаскивание для маркера:', hotspotId);

    // Сохраняем callback для обновления позиции
    if (onPositionUpdate) {
      markerElement._onPositionUpdate = onPositionUpdate;
    }

    // Используем A-Frame события вместо DOM событий
    markerElement.addEventListener('mousedown', (event) => {
      // Защита от дублирования событий
      if (markerElement._mousedownInProgress) {
        console.log('🚫 Дублирование mousedown предотвращено для:', hotspotId);
        return;
      }
      markerElement._mousedownInProgress = true;
      setTimeout(() => markerElement._mousedownInProgress = false, 100); // Сброс через 100ms

      // 🔥 ПЕРВАЯ И ГЛАВНАЯ проверка - глобальная блокировка системы перетаскивания
      // ИСКЛЮЧЕНИЕ: видео-области могут перетаскиваться даже при блокировке
      const markerData = this.viewerManager?.getHotspotData(hotspotId);
      const isVideoArea = markerData?.type === 'video-area';

      if (window._dragSystemBlocked && !isVideoArea) {
        console.log('🛑 ГЛОБАЛЬНАЯ БЛОКИРОВКА системы перетаскивания активна - НЕМЕДЛЕННЫЙ ВЫХОД');
        event.preventDefault();
        event.stopPropagation();
        return;
      }

      if (window._dragSystemBlocked && isVideoArea) {
        console.log('🎬 ВИДЕО-ОБЛАСТЬ: игнорируем глобальную блокировку для перетаскивания');
      }

      // Проверяем флаги блокировки на маркере - теперь A-Frame компонент сам управляет ими
      if (markerElement._rightClickHandled || markerElement._doubleClickHandled) {
        console.log('🚫 Координатный менеджер: mousedown заблокирован приоритетными обработчиками на маркере');
        return;
      }

      // РАДИКАЛЬНАЯ ПРОВЕРКА: НЕ запускаем НИЧЕГО если ViewerManager обнаружил правый клик
      const currentTime = Date.now();
      const lastRightClickTime = this.viewerManager ? this.viewerManager._lastRightClickTime : 0;
      const timeSinceRightClick = currentTime - (lastRightClickTime || 0);

      if (timeSinceRightClick < 200) { // Расширяем окно до 200ms
        console.log('🚫 ЖЕСТКАЯ БЛОКИРОВКА: недавний правый клик (', timeSinceRightClick, 'ms назад) - НЕ запускаем перетаскивание');
        event.preventDefault();
        event.stopPropagation();
        return;
      }

      // ПЕРВИЧНАЯ проверка - блокировка от ViewerManager (canvas события)
      if (this.viewerManager && (
        this.viewerManager._blockDraggingForRightClick ||
        this.viewerManager._rightClickInProgress ||
        this.viewerManager._rightClickDetected ||
        this._rightClickDetected
      )) {
        console.log('🚫 Перетаскивание заблокировано - правый клик обнаружен системой');
        event.preventDefault();
        event.stopPropagation();
        return;
      }

      // ВТОРИЧНАЯ проверка - недоступна для A-Frame событий, но добавляем для полноты
      const isRightClick = (event.button === 2) || (event.which === 3) || (event.buttons === 2);

      if (isRightClick) {
        console.log('🚫 CoordinateManager: Определена правая кнопка мыши через A-Frame - НЕ запускаем перетаскивание');
        event.preventDefault();
        event.stopPropagation();
        return;
      }

      console.log('🖱️ A-Frame mousedown перехвачен для маркера (левая кнопка):', hotspotId);      // Предотвращаем стандартное поведение
      event.stopPropagation();
      event.preventDefault();

      // Начинаем перетаскивание
      this.startDrag(event, markerElement, hotspotId);
    }, false); // Добавляем ПОСЛЕ приоритетных обработчиков (bubble phase)

    // Добавляем визуальную обратную связь при наведении
    markerElement.addEventListener('mouseenter', () => {
      if (!this.isDragging) {
        markerElement.setAttribute('scale', '1.1 1.1 1.1');
      }
    });

    markerElement.addEventListener('mouseleave', () => {
      if (!this.isDragging) {
        markerElement.setAttribute('scale', '1 1 1');
      }
    });

    console.log('✅ Перетаскивание настроено для маркера:', hotspotId);
  }

  /**
   * Начинает перетаскивание маркера
   */
  startDrag(event, markerElement, hotspotId) {
    console.log('🖱️ Начало перетаскивания маркера:', hotspotId);

    // Проверяем границы для видео-областей ПЕРЕД началом перетаскивания
    if (markerElement._isVideoArea && this.viewerManager) {
      console.log('🎯 Проверяем границы для видео-области:', hotspotId);
      const hotspot = this.viewerManager.hotspotManager?.findHotspotById(hotspotId);
      if (hotspot) {
        const width = hotspot.videoWidth || 4;
        const height = hotspot.videoHeight || 3;
        console.log('🎯 Размеры видео-области для проверки:', { width, height });
        const isWithinBounds = this.viewerManager.isMouseOverVideoArea(event, markerElement, width, height);

        if (!isWithinBounds) {
          console.log('🚫 Перетаскивание отменено - курсор вне границ видео-области:', hotspotId);
          return;
        }
        console.log('✅ Курсор в границах видео-области - разрешаем перетаскивание:', hotspotId);
      } else {
        console.warn('⚠️ Не найден hotspot для видео-области:', hotspotId);
      }
    } else if (markerElement._isVideoArea) {
      console.warn('⚠️ ViewerManager недоступен для проверки границ видео-области');
    } else {
      // Для обычных хотспотов проверяем попадание в область маркера
      const hotspot = this.viewerManager?.hotspotManager?.findHotspotById(hotspotId);
      if (hotspot && this.viewerManager) {
        console.log('🎯 Проверяем границы для обычного хотспота:', hotspotId);
        const isWithinBounds = this.viewerManager.isMouseOverMarker(event, markerElement);

        if (!isWithinBounds) {
          console.log('🚫 Перетаскивание отменено - курсор вне области маркера:', hotspotId);
          return;
        }
        console.log('✅ Курсор в области маркера - разрешаем перетаскивание:', hotspotId);
      }
    }

    // УЛЬТРА-АГРЕССИВНАЯ ПРОВЕРКА перед началом перетаскивания
    const currentTime = Date.now();
    const lastRightClickTime = this.viewerManager ? this.viewerManager._lastRightClickTime : 0;
    const timeSinceRightClick = currentTime - (lastRightClickTime || 0);

    // ГЛОБАЛЬНАЯ проверка блокировки системы перетаскивания
    if (window._dragSystemBlocked) {
      console.log('🛑 АВАРИЙНАЯ ОСТАНОВКА startDrag: ГЛОБАЛЬНАЯ блокировка системы перетаскивания');
      return;
    }

    if (timeSinceRightClick < 300) { // Еще больше времени
      console.log('🛑 АВАРИЙНАЯ ОСТАНОВКА startDrag: недавний правый клик (', timeSinceRightClick, 'ms назад)');
      return;
    }

    // ПОСЛЕДНЯЯ ПРОВЕРКА перед началом перетаскивания
    if (this.viewerManager && (
      this.viewerManager._blockDraggingForRightClick ||
      this.viewerManager._rightClickInProgress ||
      this.viewerManager._rightClickDetected ||
      this._rightClickDetected
    )) {
      console.log('🚫 startDrag отменен - правый клик обнаружен системой');
      return;
    }

    event.preventDefault();
    event.stopPropagation();

    this.isDragging = true;
    this.draggedMarker = {
      element: markerElement,
      hotspotId: hotspotId
    };

    // Инициализируем флаги перетаскивания
    markerElement._isDragging = true;
    markerElement._wasDragged = false;

    // Сохраняем начальную позицию
    const position = markerElement.getAttribute('position');
    this.dragStartPosition = {
      x: position.x,
      y: position.y,
      z: position.z
    };

    // Визуальная обратная связь
    markerElement.setAttribute('scale', '1.2 1.2 1.2');
    markerElement.style.cursor = 'grabbing';

    // Уведомляем об начале перетаскивания
    markerElement.emit('drag-start', { hotspotId });
  }

  /**
   * Начинает перетаскивание видео-области (специальная версия)
   */
  startVideoAreaDragging(markerElement, videoPlane, hotspot, event) {
    console.log('🎬 Начало перетаскивания видео-области:', hotspot?.id);

    // Проверяем границы видео-области
    if (this.viewerManager) {
      const width = hotspot?.videoWidth || 4;
      const height = hotspot?.videoHeight || 3;
      console.log('🎯 Размеры видео-области для проверки:', { width, height });
      const isWithinBounds = this.viewerManager.isMouseOverVideoArea(event, markerElement, width, height);

      if (!isWithinBounds) {
        console.log('🚫 Перетаскивание видео-области отменено - курсор вне границ');
        return;
      }
      console.log('✅ Курсор в границах видео-области - разрешаем перетаскивание');
    }

    // Используем существующую логику startDrag
    this.startDrag(event, markerElement, hotspot?.id);
  }

  /**
   * Обрабатывает движение мыши во время перетаскивания
   */
  onDrag(event) {
    if (!this.isDragging || !this.draggedMarker) {
      return;
    }

    event.preventDefault();

    // Устанавливаем флаг, что началось перетаскивание
    const markerElement = this.draggedMarker.element;
    markerElement._wasDragged = true;

    // Получаем новую позицию из ray-casting
    const newPosition = this.getMousePositionOnSphere(event);
    if (newPosition) {
      this.updateMarkerPosition(newPosition);
    }
  }

  /**
   * Получает позицию мыши на сфере через ray casting
   */
  getMousePositionOnSphere(event) {
    const camera = document.querySelector('[camera]');
    const scene = document.querySelector('a-scene');

    if (!camera || !scene) return null;

    // Получаем координаты мыши относительно canvas
    const rect = scene.canvas.getBoundingClientRect();
    const x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    const y = -((event.clientY - rect.top) / rect.height) * 2 + 1;

    // Создаем луч от камеры
    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2(x, y);

    raycaster.setFromCamera(mouse, camera.getObject3D('camera'));

    // Пересечение с невидимой сферой
    const sphere = new THREE.Sphere(new THREE.Vector3(0, 0, 0), this.sphereRadius);
    const intersectionPoint = new THREE.Vector3();

    if (raycaster.ray.intersectSphere(sphere, intersectionPoint)) {
      return {
        x: intersectionPoint.x,
        y: intersectionPoint.y,
        z: intersectionPoint.z
      };
    }

    return null;
  }

  /**
   * Обновляет позицию маркера
   */
  updateMarkerPosition(newPosition) {
    if (!this.draggedMarker) return;

    const markerElement = this.draggedMarker.element;
    const hotspotId = this.draggedMarker.hotspotId;

    // Обновляем позицию элемента
    markerElement.setAttribute('position', newPosition);

    // Конвертируем в сферические координаты для отладки
    const spherical = this.cartesianToSpherical(newPosition.x, newPosition.y, newPosition.z);

    console.log('📍 Новая позиция маркера:', {
      cartesian: newPosition,
      spherical: {
        yaw: spherical.yaw * (180 / Math.PI), // в градусах
        pitch: spherical.pitch * (180 / Math.PI),
        radius: spherical.radius
      }
    });

    // Уведомляем об изменении позиции
    markerElement.emit('position-changed', {
      hotspotId,
      position: newPosition,
      spherical: spherical
    });

    // Вызываем callback для обновления позиции в HotspotManager
    if (markerElement._onPositionUpdate) {
      markerElement._onPositionUpdate(newPosition);
    } else if (this.viewerManager && this.viewerManager.hotspotManager) {
      this.viewerManager.hotspotManager.updateHotspotPosition(hotspotId, newPosition);
    }
  }

  /**
   * Завершает перетаскивание
   */
  endDrag(event) {
    if (!this.isDragging || !this.draggedMarker) {
      return;
    }

    console.log('🏁 Завершение перетаскивания маркера:', this.draggedMarker.hotspotId);

    const markerElement = this.draggedMarker.element;
    const hotspotId = this.draggedMarker.hotspotId;

    // Восстанавливаем визуальное состояние
    markerElement.setAttribute('scale', '1 1 1');
    markerElement.style.cursor = 'pointer';

    // Получаем финальную позицию
    const finalPosition = markerElement.getAttribute('position');

    // Сохраняем изменения в hotspot manager
    this.saveMarkerPosition(hotspotId, finalPosition);

    // Уведомляем о завершении
    markerElement.emit('drag-end', {
      hotspotId,
      oldPosition: this.dragStartPosition,
      newPosition: finalPosition
    });

    // Сбрасываем состояние
    this.isDragging = false;
    this.draggedMarker = null;
    this.dragStartPosition = null;

    // Сбрасываем только флаг _isDragging
    // Флаг _wasDragged будет сброшен ViewerManager в click обработчике
    markerElement._isDragging = false;
  }

  /**
   * Сохраняет новую позицию маркера в HotspotManager
   */
  saveMarkerPosition(hotspotId, position) {
    if (window.hotspotManager) {
      try {
        window.hotspotManager.updateHotspotPosition(hotspotId, position);
        console.log('💾 Позиция маркера сохранена:', hotspotId, position);
      } catch (error) {
        console.error('❌ Ошибка сохранения позиции маркера:', error);
      }
    }
  }

  /**
   * Создает маркер с поддержкой перетаскивания
   */
  createDraggableMarker(hotspot, markerElement) {
    // Устанавливаем корректную позицию на сфере
    const spherePosition = this.normalizeToSphere(
      hotspot.position.x || 0,
      hotspot.position.y || 0,
      hotspot.position.z || 5
    );

    markerElement.setAttribute('position', spherePosition);

    // Настраиваем перетаскивание
    this.setupMarkerDragging(markerElement, hotspot.id);

    // Добавляем визуальные индикаторы
    markerElement.style.cursor = 'grab';

    // Добавляем атрибуты для отладки
    markerElement.setAttribute('data-hotspot-id', hotspot.id);
    markerElement.setAttribute('data-draggable', 'true');

    console.log('✅ Создан перетаскиваемый маркер:', hotspot.id, spherePosition);

    return markerElement;
  }

  /**
   * Получает все перетаскиваемые маркеры
   */
  getDraggableMarkers() {
    return document.querySelectorAll('[data-draggable="true"]');
  }

  /**
   * Включает/выключает режим перетаскивания для всех маркеров
   */
  setDragMode(enabled) {
    const markers = this.getDraggableMarkers();
    markers.forEach(marker => {
      if (enabled) {
        marker.style.cursor = 'grab';
        marker.setAttribute('data-drag-enabled', 'true');
      } else {
        marker.style.cursor = 'pointer';
        marker.setAttribute('data-drag-enabled', 'false');
      }
    });

    console.log(`🔄 Режим перетаскивания ${enabled ? 'включен' : 'выключен'} для ${markers.length} маркеров`);
  }

  /**
   * Очищает все связи и обработчики для конкретного маркера
   */
  cleanupMarker(hotspotId) {
    console.log('🧹 Очищаем CoordinateManager связи для маркера:', hotspotId);

    // Если это тот маркер, который сейчас перетаскивается, останавливаем перетаскивание
    if (this.draggedMarker && this.draggedMarker.id === `marker-${hotspotId}`) {
      console.log('🛑 Останавливаем перетаскивание удаляемого маркера');
      this.stopDrag();
    }

    // Очищаем все ссылки на маркер
    if (this.draggedMarker && this.draggedMarker.id === `marker-${hotspotId}`) {
      this.draggedMarker = null;
    }

    console.log('✅ CoordinateManager связи очищены для:', hotspotId);
  }
}
