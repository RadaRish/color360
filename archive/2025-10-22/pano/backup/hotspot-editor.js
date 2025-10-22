// UI-компонент: редактор хотспотов
export default class HotspotEditor {
  constructor(modalId) {
    this.modalId = modalId;
    this.modal = document.getElementById(modalId);
    this.form = this.modal?.querySelector('#hotspot-form');
    this.isEditMode = false; // Флаг режима редактирования
    this.editingHotspot = null; // Редактируемый маркер
    this.setupEventHandlers();
  }

  setupEventHandlers() {
    if (!this.modal || !this.form) return;

    // Закрытие модального окна
    const closeBtn = this.modal.querySelector('.close-btn');
    if (closeBtn) {
      closeBtn.addEventListener('click', () => this.hide());
    }

    // Закрытие при клике вне модального окна
    this.modal.addEventListener('click', (e) => {
      if (e.target === this.modal) {
        this.hide();
      }
    });

    // Закрытие по клавише Escape (обработчик добавляется при show и удаляется при hide)
    this.escapeHandler = (e) => {
      if (e.key === 'Escape') {
        // close editor via Esc
        this.hide();
      }
    };

    // Обработка отправки формы
    this.form.addEventListener('submit', (e) => {
      e.preventDefault();
      this.handleSubmit();
    });

    // Кнопка "Установить по умолчанию"
    const setDefaultBtn = this.form.querySelector('#set-as-default-btn');
    if (setDefaultBtn) {
      setDefaultBtn.addEventListener('click', () => {
        this.setAsDefault();
      });
    }

    // Обработчик изменения значения в селекте иконки
    const markerIconSelect = this.form.querySelector('#hotspot-marker-icon');
    const customIconGroup = this.form.querySelector('#custom-icon-group');
    if (markerIconSelect && customIconGroup) {
      markerIconSelect.addEventListener('change', (e) => {
        // Показываем группу пользовательской иконки если выбрана custom
        customIconGroup.style.display = e.target.value === 'custom' ? 'block' : 'none';
        
        // Если выбрана иконка профиля, показываем предпросмотр
        if (e.target.value === 'profile') {
          this.showProfileIconPreview();
        }
      });
    }

    // Обработчик удаления пользовательской иконки
    const removeCustomIconBtn = this.form.querySelector('#remove-custom-icon');
    const customIconPreview = this.form.querySelector('#custom-icon-preview');
    const customIconImg = this.form.querySelector('#custom-icon-img');
    if (removeCustomIconBtn && customIconPreview && customIconImg) {
      removeCustomIconBtn.addEventListener('click', () => {
        customIconPreview.style.display = 'none';
        customIconImg.src = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==';
        
        // Если выбрана иконка профиля, показываем предпросмотр
        const markerIconSelect = this.form.querySelector('#hotspot-marker-icon');
        if (markerIconSelect && markerIconSelect.value === 'profile') {
          this.showProfileIconPreview();
        }
      });
    }

    // Удален слайдер для размера текста — используется select

    // Удален слайдер для размера маркера — используется select
  }

  /**
   * Показывает предпросмотр иконки профиля
   */
  showProfileIconPreview() {
    const customIconPreview = this.form.querySelector('#custom-icon-preview');
    const customIconImg = this.form.querySelector('#custom-icon-img');
    
    if (customIconPreview && customIconImg) {
      // Создаем SVG иконку по умолчанию (портретная фигура человечка)
      const defaultUserIcon = `
        <svg xmlns="http://www.w3.org/2000/svg" width="60" height="60" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path>
          <circle cx="12" cy="7" r="4"></circle>
        </svg>
      `;
      // Преобразуем SVG в Data URL
      const svgBlob = new Blob([defaultUserIcon], {type: 'image/svg+xml'});
      const url = URL.createObjectURL(svgBlob);
      customIconImg.src = url;
      customIconPreview.style.display = 'flex';
    }
  }

  show(options = {}) {
    return new Promise((resolve) => {
      this.resolve = resolve;
      this.isEditMode = false;
      this.editingHotspot = null;

      const { type = 'hotspot', values = {}, scenes = [] } = options;

      // Запоминаем текущий тип для проверок в handleSubmit
      this.currentType = type;

      // Настраиваем заголовок
      const title = this.modal.querySelector('#hotspot-editor-title');
      if (title) {
        const titleText = type === 'hotspot' ? 'Настроить хотспот' :
          type === 'info-point' ? 'Настроить инфоточку' :
            type === 'animated-object' ? 'Настроить анимированный объект' :
              type === 'iframe-3d' ? 'Настроить 3D-iframe' :
                'Настроить видео-область';
        title.textContent = titleText;
      }

      // Заполняем форму
      this.populateForm(values, scenes, type);

      // Показываем/скрываем поля в зависимости от типа
      this.toggleFieldsByType(type);

      // Добавляем обработчик Esc
      document.addEventListener('keydown', this.escapeHandler);

      // Показываем модальное окно
      this.modal.style.display = 'flex';
    });
  }

  /**
   * Показывает редактор в режиме редактирования существующего маркера
   */
  showEditMode(hotspot) {
    return new Promise((resolve) => {
      this.resolve = resolve;
      this.isEditMode = true;
      this.editingHotspot = hotspot;

      // Настраиваем заголовок для режима редактирования
      const title = this.modal.querySelector('#hotspot-editor-title');
      if (title) {
        const typeText = hotspot.type === 'hotspot' ? 'хотспота' :
          (hotspot.type === 'info-point' ? 'инфоточки' :
            (hotspot.type === 'animated-object' ? 'анимированный объект' :
              (hotspot.type === 'iframe-3d' ? '3D-iframe' : 'видео-область')));
        title.textContent = `Редактировать ${typeText}`;
      }

      // Получаем список сцен (если нужно)
      const scenes = window.app?.sceneManager?.getAllScenes() || [];

      // Заполняем форму данными маркера
      this.populateForm(hotspot, scenes, hotspot.type);

      // Показываем/скрываем поля в зависимости от типа
      this.toggleFieldsByType(hotspot.type);

      // Добавляем обработчик Esc
      document.addEventListener('keydown', this.escapeHandler);

      // Показываем модальное окно
      this.modal.style.display = 'flex';

      // editor opened for hotspot
    });
  }

  hide() {
    this.modal.style.display = 'none';

    // Удаляем обработчик Esc
    document.removeEventListener('keydown', this.escapeHandler);

    if (this.resolve) {
      this.resolve(null); // Отмена
      this.resolve = null;
    }
  }

  populateForm(values, scenes, type) {
    // Загружаем настройки по умолчанию для данного типа
    const defaults = this.loadDefaults(type);

    // Заполняем основные поля
    const titleInput = this.form.querySelector('#hotspot-title');
    const descriptionInput = this.form.querySelector('#hotspot-description');
    const targetSceneSelect = this.form.querySelector('#hotspot-target-scene');

    if (titleInput) titleInput.value = values.title || '';
    if (descriptionInput) descriptionInput.value = values.description || '';

    // Заполняем список сцен для хотспотов
    if (targetSceneSelect && type === 'hotspot') {
      targetSceneSelect.innerHTML = '<option value="">Выберите сцену</option>';
      scenes.forEach(scene => {
        const option = document.createElement('option');
        option.value = scene.id;
        option.textContent = scene.name.replace(/\.[^.]+$/, '');
        if (values.targetSceneId === scene.id) {
          option.selected = true;
        }
        targetSceneSelect.appendChild(option);
      });
    }

    // Заполняем поля стилизации текста (для hotspot и info-point)
    if (type === 'info-point' || type === 'hotspot') {
      const textColorInput = this.form.querySelector('#hotspot-text-color');
      const textSizeInput = this.form.querySelector('#hotspot-text-size');
      const textFamilySelect = this.form.querySelector('#hotspot-text-family');
      const textBoldInput = this.form.querySelector('#hotspot-text-bold');
      const textUnderlineInput = this.form.querySelector('#hotspot-text-underline');

      if (textColorInput) textColorInput.value = values.textColor || defaults.textColor;
      if (textSizeInput) textSizeInput.value = values.textSize || defaults.textSize;
      if (textFamilySelect) textFamilySelect.value = values.textFamily || defaults.textFamily || 'Arial, sans-serif';
      if (textBoldInput) textBoldInput.checked = !!(values.textBold ?? defaults.textBold);
      if (textUnderlineInput) textUnderlineInput.checked = !!(values.textUnderline ?? defaults.textUnderline);
    }

    // Заполняем поля настройки маркера (для всех типов) с использованием настроек по умолчанию
    const markerColorInput = this.form.querySelector('#hotspot-marker-color');
    const markerSizeInput = this.form.querySelector('#hotspot-marker-size');
    const markerSizeValue = this.form.querySelector('#marker-size-value');
    const markerIconSelect = this.form.querySelector('#hotspot-marker-icon');
    const markerNoFillInput = this.form.querySelector('#hotspot-marker-no-fill');
    const customIconGroup = this.form.querySelector('#custom-icon-group');
    const customIconPreview = this.form.querySelector('#custom-icon-preview');
    const customIconImg = this.form.querySelector('#custom-icon-img');

    if (markerColorInput) {
      markerColorInput.value = values.color || defaults.markerColor;
    }
    if (markerSizeInput) {
      const sizeValue = values.size || defaults.markerSize;
      markerSizeInput.value = sizeValue;
      
      // ИСПРАВЛЕНИЕ БАГА: устанавливаем правильный selected для option
      const options = markerSizeInput.querySelectorAll('option');
      options.forEach(option => {
        option.selected = false; // сначала убираем все selected
        if (option.value === String(sizeValue)) {
          option.selected = true; // затем помечаем нужную
        }
      });
    }
    if (markerNoFillInput) markerNoFillInput.checked = !!(values.noFill ?? defaults.markerNoFill);
    if (markerIconSelect) {
      // Гарантируем, что по умолчанию выбран современный маркер 'arrow' для хотспотов
      markerIconSelect.value = values.icon || defaults.markerIcon || (type === 'hotspot' ? 'arrow' : 'sphere');

      // Показываем группу пользовательской иконки если выбрана custom
      if (customIconGroup) {
        customIconGroup.style.display = (values.icon || defaults.markerIcon) === 'custom' ? 'block' : 'none';
      }
    }

    // Загружаем пользовательскую иконку если есть
    if (values.customIconData && customIconImg && customIconPreview) {
      customIconImg.src = values.customIconData;
      customIconPreview.style.display = 'flex';
    } else if (customIconPreview) {
      // Если пользовательская иконка не выбрана, но выбрана иконка профиля,
      // показываем иконку по умолчанию (портретная фигура человечка)
      const markerIconSelect = this.form.querySelector('#hotspot-marker-icon');
      if (markerIconSelect && markerIconSelect.value === 'profile') {
        this.showProfileIconPreview();
      } else if (markerIconSelect && markerIconSelect.value !== 'custom') {
        // Если не выбрана пользовательская иконка и не выбрана иконка профиля, скрываем предпросмотр
        customIconPreview.style.display = 'none';
      }
    }

    // Заполняем поля видео-области и анимированного объекта
    if (type === 'video-area' || type === 'animated-object') {
      const videoSourceSelect = this.form.querySelector('#hotspot-video-source');
      const videoUrlInput = this.form.querySelector('#hotspot-video-url');
      const videoWidthInput = this.form.querySelector('#hotspot-video-width');
      const videoHeightInput = this.form.querySelector('#hotspot-video-height');

      if (videoSourceSelect) videoSourceSelect.value = values.videoSource || '';
      if (videoUrlInput) videoUrlInput.value = values.videoUrl || '';
      if (videoWidthInput) videoWidthInput.value = values.videoWidth || (type === 'animated-object' ? '2' : '4');
      if (videoHeightInput) videoHeightInput.value = values.videoHeight || (type === 'animated-object' ? String((2 * 9 / 16).toFixed(2)) : '3');

      // Параметры хромакея только для animated-object
      if (type === 'animated-object') {
        const chromaEnabled = this.form.querySelector('#hotspot-chroma-enabled');
        const chromaColor = this.form.querySelector('#hotspot-chroma-color');
        const chromaSimilarity = this.form.querySelector('#hotspot-chroma-similarity');
        const chromaSmoothness = this.form.querySelector('#hotspot-chroma-smoothness');
        const chromaThreshold = this.form.querySelector('#hotspot-chroma-threshold');

        if (chromaEnabled) chromaEnabled.checked = !!values.chromaEnabled;
        if (chromaColor) chromaColor.value = values.chromaColor || '#00ff00';
        if (chromaSimilarity) chromaSimilarity.value = values.chromaSimilarity ?? 0.4;
        if (chromaSmoothness) chromaSmoothness.value = values.chromaSmoothness ?? 0.1;
        if (chromaThreshold) chromaThreshold.value = values.chromaThreshold ?? 0.0;
      }
    }

    // Поля для 3D-iframe
    if (type === 'iframe-3d') {
      const iframeUrlInput = this.form.querySelector('#hotspot-iframe-url');
      const widthInput = this.form.querySelector('#hotspot-video-width');
      const heightInput = this.form.querySelector('#hotspot-video-height');

      if (iframeUrlInput) iframeUrlInput.value = values.iframeUrl || '';
      if (widthInput) widthInput.value = values.videoWidth || '4';
      if (heightInput) heightInput.value = values.videoHeight || '3';
    }
  }

  toggleFieldsByType(type) {
    const targetSceneGroup = this.form.querySelector('.form-group-target-scene');
    const textStyleSections = this.form.querySelectorAll('.form-section.form-group-text-style');
    const markerStyleSections = this.form.querySelectorAll('.form-section.form-group-marker-style');
    const videoSections = this.form.querySelectorAll('.form-section.form-group-video');
    const videoSizeSections = this.form.querySelectorAll('.form-section.form-group-video-size');
    const chromaSections = this.form.querySelectorAll('.form-section.form-group-chroma');
    const iframeSections = this.form.querySelectorAll('.form-section.form-group-iframe');

    if (targetSceneGroup) {
      targetSceneGroup.style.display = type === 'hotspot' ? 'block' : 'none';
    }

    textStyleSections.forEach(section => {
      section.style.display = (type === 'info-point' || type === 'hotspot') ? 'block' : 'none';
    });

    // Видео поля показываем для video-area и animated-object
    const showVideo = (type === 'video-area' || type === 'animated-object');
    videoSections.forEach(section => {
      section.style.display = showVideo ? 'block' : 'none';
    });

    // Размеры показываем также для iframe-3d
    videoSizeSections.forEach(section => {
      section.style.display = (showVideo || type === 'iframe-3d') ? 'block' : 'none';
    });

    // Параметры хромакея только для animated-object
    chromaSections.forEach(section => {
      section.style.display = type === 'animated-object' ? 'block' : 'none';
    });

    // Поля настройки маркера доступны для hotspot и info-point, но не для video-area и iframe-3d
    markerStyleSections.forEach(section => {
      section.style.display = (type !== 'video-area' && type !== 'iframe-3d') ? 'block' : 'none';
    });

    // Поле iframe URL только для iframe-3d
    iframeSections.forEach(section => {
      section.style.display = (type === 'iframe-3d') ? 'block' : 'none';
    });
  }

  async handleSubmit() {
    const formData = new FormData(this.form);
    const rawMarkerSize = formData.get('markerSize');
    const parsedMarkerSize = rawMarkerSize != null ? parseFloat(String(rawMarkerSize).replace(',', '.')) : undefined;
    const data = {
      title: formData.get('title'),
      description: formData.get('description'),
      targetSceneId: formData.get('targetSceneId') || null,
      textColor: formData.get('textColor') || '#ffffff',
      textSize: formData.get('textSize') || '1',
      textFamily: formData.get('textFamily') || 'Arial, sans-serif',
      textBold: !!formData.get('textBold'),
      textUnderline: !!formData.get('textUnderline'),
      color: formData.get('markerColor'),
      size: isNaN(parsedMarkerSize) ? undefined : parsedMarkerSize,
      icon: formData.get('markerIcon') || (this.currentType === 'hotspot' ? 'arrow' : 'sphere'),
      noFill: !!formData.get('markerNoFill')
    };

    console.log('📝 Payload формы хотспота:', {
      type: this.currentType,
      title: data.title,
      color: data.color,
      size: data.size,
      icon: data.icon,
      noFill: data.noFill
    });

    // Обработка видео-области
    const videoSource = formData.get('videoSource');
    const videoWidth = formData.get('videoWidth');
    const videoHeight = formData.get('videoHeight');

    // ПРОВЕРКА: для video-area/animated-object источник видео ОБЯЗАТЕЛЕН
    if ((this.currentType === 'video-area' || this.currentType === 'animated-object') && !videoSource) {

      return;
    }

    if (videoSource) {
      data.videoSource = videoSource;
      data.videoWidth = parseFloat(videoWidth) || 4;
      data.videoHeight = parseFloat(videoHeight) || 3;

      if (videoSource === 'file') {
        // Обработка локального файла
        const videoFileInput = this.form.querySelector('#hotspot-video-file');
        if (videoFileInput && videoFileInput.files[0]) {
          const file = videoFileInput.files[0];
          const reader = new FileReader();

          const videoData = await new Promise((resolve) => {
            reader.onload = (e) => resolve(e.target.result);
            reader.readAsDataURL(file);
          });

          data.videoData = videoData;
          data.videoUrl = videoData; // Используем Data URL
        } else {

          return;
        }
      } else if (videoSource === 'url') {
        // Обработка онлайн URL
        const videoUrl = formData.get('videoUrl');
        if (videoUrl) {
          data.videoUrl = videoUrl;

          // Валидация URL
          if (!this.isValidVideoUrl(videoUrl, videoSource)) {

            return;
          }
        } else {

          return;
        }
      }
    }

    // Обработка 3D-iframe
    if (this.currentType === 'iframe-3d') {
      const iframeUrlRaw = formData.get('iframeUrl') || '';
      const iframeUrl = this.toIframeEmbedUrl((iframeUrlRaw || '').trim());
      if (!iframeUrl) {
        alert('Введите корректную ссылку для 3D-iframe');
        return;
      }
      data.iframeUrl = iframeUrl;
      data.videoWidth = parseFloat(videoWidth) || 4;
      data.videoHeight = parseFloat(videoHeight) || 3;
    }

    // Обработка пользовательской иконки
    if (data.icon === 'custom') {
      const customIconInput = this.form.querySelector('#hotspot-custom-icon');
      const customIconImg = this.form.querySelector('#custom-icon-img');

      if (customIconInput && customIconInput.files[0]) {
        // Новый файл загружен
        const file = customIconInput.files[0];
        const reader = new FileReader();

        const imageData = await new Promise((resolve) => {
          reader.onload = (e) => resolve(e.target.result);
          reader.readAsDataURL(file);
        });

        data.customIconData = imageData;
      } else if (customIconImg && customIconImg.src && customIconImg.src.startsWith('data:')) {
        // Используем существующую загруженную иконку
        // Проверяем, является ли это иконкой по умолчанию (SVG)
        if (customIconImg.src.includes('blob:')) {
          // Это иконка по умолчанию, не сохраняем её как пользовательскую
          // Удаляем customIconData, чтобы использовать иконку по умолчанию
          delete data.customIconData;
        } else {
          data.customIconData = customIconImg.src;
        }
      } else {
        // Нет пользовательской иконки

        return;
      }
    } else if (data.icon === 'profile') {
      // Для иконки профиля удаляем пользовательские данные, чтобы использовать иконку по умолчанию
      delete data.customIconData;
    }

    // Хромакей параметры для animated-object
    if (this.currentType === 'animated-object') {
      data.chromaEnabled = !!formData.get('chromaEnabled');
      data.chromaColor = formData.get('chromaColor') || '#00ff00';
      data.chromaSimilarity = parseFloat(formData.get('chromaSimilarity'));
      data.chromaSmoothness = parseFloat(formData.get('chromaSmoothness'));
      data.chromaThreshold = parseFloat(formData.get('chromaThreshold'));
    }

    // Валидация
    if (!data.title.trim()) {

      return;
    }

    // Если это режим редактирования, обновляем существующий маркер
    if (this.isEditMode && this.editingHotspot) {
      if (window.app && window.app.hotspotManager) {
        const success = window.app.hotspotManager.updateHotspot(this.editingHotspot.id, data);
        if (success) {
          // hotspot updated

          // Возвращаем обновленные данные
          if (this.resolve) {
            this.resolve({ ...this.editingHotspot, ...data });
            this.resolve = null;
          }
        } else {
          console.error('Ошибка при обновлении маркера');
          return;
        }
      }
    } else {
      // Обычный режим создания - возвращаем данные
      if (this.resolve) {
        this.resolve(data);
        this.resolve = null;
      }
    }

    this.hide();
  }

  // Преобразует популярные ссылки (YouTube) в embed-форму, остальные возвращает как есть
  toIframeEmbedUrl(url) {
    try {
      const u = new URL(url);
      const host = u.hostname.replace('www.', '');
      // YouTube
      if (host === 'youtube.com' || host === 'm.youtube.com') {
        const vid = u.searchParams.get('v');
        if (vid) return `https://www.youtube.com/embed/${vid}?rel=0&playsinline=1`;
      }
      if (host === 'youtu.be') {
        const vid = u.pathname.split('/').filter(Boolean)[0];
        if (vid) return `https://www.youtube.com/embed/${vid}?rel=0&playsinline=1`;
      }
      // В остальных случаях возвращаем URL как есть
      return url;
    } catch {
      return '';
    }
  }

  isValidVideoUrl(url, source) {
    if (source === 'url') {
      // Поддержка Data URL (base64 видео)
      if (url.startsWith('data:video/')) {

        return true;
      }

      // Проверяем, что это валидный URL
      try {
        const urlObj = new URL(url);

        // Проверяем на неподдерживаемые платформы
        if (url.includes('youtube.com') || url.includes('youtu.be')) {
          alert('⚠️ YouTube ссылки не поддерживаются\n\nИспользуйте прямые ссылки на видео файлы (.mp4, .webm, .ogg)');
          return false;
        }

        if (url.includes('instagram.com')) {
          alert('⚠️ Instagram ссылки не поддерживаются\n\nИспользуйте прямые ссылки на видео файлы (.mp4, .webm, .ogg)');
          return false;
        }

        if (url.includes('vkvideo.ru') || url.includes('vk.com/video')) {
          alert('⚠️ VK Video ссылки не поддерживаются\n\nИспользуйте прямые ссылки на видео файлы (.mp4, .webm, .ogg)');
          return false;
        }

        if (url.includes('tiktok.com')) {
          alert('⚠️ TikTok ссылки не поддерживаются\n\nИспользуйте прямые ссылки на видео файлы (.mp4, .webm, .ogg)');
          return false;
        }

        if (url.includes('facebook.com') || url.includes('fb.watch')) {
          alert('⚠️ Facebook ссылки не поддерживаются\n\nИспользуйте прямые ссылки на видео файлы (.mp4, .webm, .ogg)');
          return false;
        }

        // Предупреждение если ссылка не заканчивается расширением видео
        if (!url.match(/\.(mp4|webm|ogg|mov|avi)(\?.*)?$/i)) {
          const confirmed = confirm('⚠️ Ссылка может не работать\n\nРекомендуется использовать прямые ссылки на видео файлы, заканчивающиеся на .mp4, .webm или .ogg\n\nВсё равно продолжить?');
          if (!confirmed) {
            return false;
          }
        }

        return true;
      } catch {
        alert('❌ Введите корректный URL адрес');
        return false;
      }
    }
    return true; // Для других источников всегда true
  }

  /**
   * Сохраняет текущие настройки формы как настройки по умолчанию
   */
  setAsDefault() {
    const formData = new FormData(this.form);
    const currentSettings = {
      textColor: formData.get('textColor') || '#ffffff',
      textSize: formData.get('textSize') || '1',
      textFamily: formData.get('textFamily') || 'Arial, sans-serif',
      textBold: !!formData.get('textBold'),
      textUnderline: !!formData.get('textUnderline'),
      markerColor: formData.get('markerColor') || '#00ff00',
  markerSize: formData.get('markerSize') || '0.6',
  markerIcon: (formData.get('markerIcon') === 'scene-transition' ? 'arrow' : (formData.get('markerIcon') || 'arrow')),
      markerNoFill: !!formData.get('markerNoFill')
    };

    // Сохраняем в localStorage отдельно для каждого типа
    const storageKey = `${this.currentType || 'hotspot'}_defaults`;
    localStorage.setItem(storageKey, JSON.stringify(currentSettings));

    // Показываем уведомление
    this.showNotification('Настройки сохранены как настройки по умолчанию! ⭐');
  }

  /**
   * Загружает настройки по умолчанию для указанного типа
   */
  loadDefaults(type) {
    const storageKey = `${type}_defaults`;
    const savedDefaults = localStorage.getItem(storageKey);

    if (savedDefaults) {
      try {
        return JSON.parse(savedDefaults);
      } catch (error) {

      }
    }

    // Возвращаем стандартные настройки по умолчанию
    return this.getStandardDefaults(type);
  }

  /**
   * Возвращает стандартные настройки по умолчанию для типа
   */
  getStandardDefaults(type) {
    switch (type) {
      case 'hotspot':
        return {
          textColor: '#ffffff',
          textSize: '1',
          textFamily: 'Arial, sans-serif',
          textBold: false,
          textUnderline: false,
          markerColor: '#00ff00',
          markerSize: '0.6',
          markerIcon: 'arrow',
          markerNoFill: false
        };
      case 'info-point':
        return {
          textColor: '#ffffff',
          textSize: '1',
          textFamily: 'Arial, sans-serif',
          textBold: false,
          textUnderline: false,
          markerColor: '#ffcc00',
          markerSize: '0.6',
          markerIcon: 'sphere',
          markerNoFill: false
        };
      case 'video-area':
        return {
          textColor: '#ffffff',
          textSize: '1',
          textFamily: 'Arial, sans-serif',
          textBold: false,
          textUnderline: false,
          markerColor: '#ff6600',
          markerSize: '0.6',
          markerIcon: 'cube',
          markerNoFill: false
        };
      default:
        return {
          textColor: '#ffffff',
          textSize: '1',
          textFamily: 'Arial, sans-serif',
          textBold: false,
          textUnderline: false,
          markerColor: '#00ff00',
          markerSize: '0.6',
          markerIcon: 'arrow',
          markerNoFill: false
        };
    }
  }

  /**
   * Показывает временное уведомление
   */
  showNotification(message) {
    // Создаем элемент уведомления
    const notification = document.createElement('div');
    notification.className = 'default-settings-notification';
    notification.textContent = message;
    notification.style.cssText = `
      position: fixed;
      top: 20px;
      right: 80px; /* смещаем левее, чтобы не перекрывать аватар */
      background: #4CAF50;
      color: white;
      padding: 12px 20px;
      border-radius: 6px;
      font-size: 14px;
      font-weight: 500;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
      z-index: 10000;
      transform: translateX(100%);
      transition: transform 0.3s ease;
    `;

    // Добавляем в документ
    document.body.appendChild(notification);

    // Анимация появления
    setTimeout(() => {
      notification.style.transform = 'translateX(0)';
    }, 100);

    // Удаляем через 3 секунды
    setTimeout(() => {
      notification.style.transform = 'translateX(100%)';
      setTimeout(() => {
        if (notification.parentNode) {
          notification.parentNode.removeChild(notification);
        }
      }, 300);
    }, 3000);
  }
}
