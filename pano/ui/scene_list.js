// UI-компонент: список сцен с поддержкой drag&drop и контекстного меню
export default class SceneList {
  constructor(sceneManager, listElement) {
    this.sceneManager = sceneManager;
    this.listElement = listElement;

    if (!this.listElement) {
      console.warn('Элемент списка сцен не найден');
      return;
    }

    this.setupDragAndDrop();
  }

  render() {
    if (!this.listElement) return;

    this.listElement.innerHTML = '';
    const scenes = this.sceneManager.getAllScenes();

    scenes.forEach((scene, index) => {
      const li = this.createSceneElement(scene, index);
      this.listElement.appendChild(li);
    });

    this.highlightCurrentScene();
  }

  createSceneElement(scene, index) {
    const li = document.createElement('li');
    li.className = 'scene-item';
    li.draggable = true;
    li.dataset.sceneId = scene.id;
    li.dataset.index = index;

    // Основное содержимое элемента
    const content = document.createElement('div');
    content.className = 'scene-content';

    const nameSpan = document.createElement('span');
    nameSpan.className = 'scene-name';
    // Убираем расширение файла из отображаемого имени
    nameSpan.textContent = scene.name.replace(/\.[^.]+$/, '');

    const menuBtn = document.createElement('button');
    menuBtn.className = 'scene-menu-btn';
    menuBtn.textContent = '⋮';
    menuBtn.title = 'Меню сцены';

    content.appendChild(nameSpan);
    content.appendChild(menuBtn);
    li.appendChild(content);

    // Обработчики событий
    li.addEventListener('click', (e) => {
      if (e.target === menuBtn) return; // Не переключаем сцену при клике на меню
      this.switchToScene(scene.id);
    });

    // Добавляем редактирование по двойному клику
    nameSpan.addEventListener('dblclick', (e) => {
      e.stopPropagation();
      this.startInlineEdit(nameSpan, scene);
    });

    menuBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      this.showSceneMenu(scene, li, e);
    });

    // Drag & Drop
    li.addEventListener('dragstart', (e) => {
      e.dataTransfer.setData('text/plain', scene.id);
      li.classList.add('dragging');
    });

    li.addEventListener('dragend', () => {
      li.classList.remove('dragging');
    });

    li.addEventListener('dragover', (e) => {
      e.preventDefault();
      li.classList.add('drag-over');
    });

    li.addEventListener('dragleave', () => {
      li.classList.remove('drag-over');
    });

    li.addEventListener('drop', (e) => {
      e.preventDefault();
      li.classList.remove('drag-over');

      const draggedSceneId = e.dataTransfer.getData('text/plain');
      this.reorderScenes(draggedSceneId, scene.id);
    });

    return li;
  }

  setupDragAndDrop() {
    if (!this.listElement) return;

    // Предотвращаем стандартное поведение drag&drop для контейнера
    this.listElement.addEventListener('dragover', (e) => {
      e.preventDefault();
    });
  }

  switchToScene(sceneId) {
    this.sceneManager.switchScene(sceneId).then(success => {
      if (success) {
        this.highlightCurrentScene();
      }
    });
  }

  highlightCurrentScene() {
    if (!this.listElement) return;

    const currentScene = this.sceneManager.getCurrentScene();
    const items = this.listElement.querySelectorAll('.scene-item');

    items.forEach(item => {
      item.classList.remove('selected');
      if (currentScene && item.dataset.sceneId === currentScene.id) {
        item.classList.add('selected');
      }
    });
  }

  showSceneMenu(scene, element, event) {
    // Удаляем предыдущее меню
    this.hideSceneMenu();

    const menu = document.createElement('div');
    menu.className = 'custom-context-menu scene-menu';

    const rect = element.getBoundingClientRect();
    menu.style.left = (rect.right + 5) + 'px';
    menu.style.top = rect.top + 'px';

    menu.innerHTML = `
      <button data-action="rename">Переименовать</button>
      <button data-action="duplicate">Дублировать</button>
      <button data-action="delete" class="danger">Удалить</button>
    `;

    document.body.appendChild(menu);

    // Обработчики меню
    menu.querySelector('[data-action="rename"]').addEventListener('click', () => {
      // Находим span по текущему элементу и запускаем инлайн-редактирование
      const nameSpan = element.querySelector('.scene-name');
      if (nameSpan) {
        this.startInlineEdit(nameSpan, scene);
      } else {
        // Fallback
        this.renameScene(scene);
      }
      this.hideSceneMenu();
    });

    menu.querySelector('[data-action="duplicate"]').addEventListener('click', () => {
      this.duplicateScene(scene);
      this.hideSceneMenu();
    });

    menu.querySelector('[data-action="delete"]').addEventListener('click', () => {
      this.deleteScene(scene);
      this.hideSceneMenu();
    });

    // Закрытие меню при клике вне его
    setTimeout(() => {
      const closeHandler = (e) => {
        if (!menu.contains(e.target)) {
          this.hideSceneMenu();
          document.removeEventListener('click', closeHandler);
        }
      };
      document.addEventListener('click', closeHandler);
    }, 0);
  }

  hideSceneMenu() {
    const existingMenu = document.querySelector('.scene-menu');
    if (existingMenu) {
      existingMenu.remove();
    }
  }

  renameScene(scene) {
    const currentName = scene.name.replace(/\.[^.]+$/, '');
    const newName = prompt('Новое имя сцены:', currentName);

    if (newName && newName.trim() && newName !== currentName) {
      // Добавляем расширение обратно, если оно было
      const extension = scene.name.match(/\.[^.]+$/);
      const fullNewName = newName.trim() + (extension ? extension[0] : '');

      if (this.sceneManager.renameScene(scene.id, fullNewName)) {
        this.render();
      }
    }
  }

  async duplicateScene(scene) {
    const newScene = {
      id: 'scene_' + Date.now() + '_' + Math.floor(Math.random() * 1000),
      name: 'Копия ' + scene.name,
      src: scene.src,
      hotspots: [...(scene.hotspots || [])] // Копируем хотспоты
    };

    const success = await this.sceneManager.addScene(newScene);
    if (success) {
      this.render();
      // scene duplicated
    } else {
      alert('Не удалось дублировать сцену');
    }
  }

  deleteScene(scene) {
    const sceneName = scene.name.replace(/\.[^.]+$/, '');
    if (confirm(`Удалить сцену "${sceneName}"?`)) {
      this.sceneManager.removeScene(scene.id).then(success => {
        if (success) {
          this.render();
          // scene deleted
        } else {
          alert('Не удалось удалить сцену');
        }
      });
    }
  }

  reorderScenes(draggedSceneId, targetSceneId) {
    if (draggedSceneId === targetSceneId) return;

    const scenes = this.sceneManager.getAllScenes();
    const fromIdx = scenes.findIndex(s => s.id === draggedSceneId);
    const toIdx = scenes.findIndex(s => s.id === targetSceneId);

    if (fromIdx !== -1 && toIdx !== -1) {
      if (this.sceneManager.reorderScenes(fromIdx, toIdx)) {
        this.render();
      }
    }
  }

  // Метод для программного добавления сцены в список
  addScene(scene) {
    this.render(); // Просто перерисовываем весь список
  }

  // Метод для обновления отображения конкретной сцены
  updateScene(sceneId) {
    const scene = this.sceneManager.getSceneById(sceneId);
    if (!scene) return;

    const element = this.listElement.querySelector(`[data-scene-id="${sceneId}"]`);
    if (element) {
      const nameSpan = element.querySelector('.scene-name');
      if (nameSpan) {
        nameSpan.textContent = scene.name.replace(/\.[^.]+$/, '');
      }
    }
  }

  /**
   * Начинает инлайн редактирование названия сцены
   */
  startInlineEdit(nameSpan, scene) {
    const currentName = nameSpan.textContent;

    // Создаем поле ввода
    const input = document.createElement('input');
    input.type = 'text';
    input.value = currentName;
    input.className = 'scene-name-edit';

    // Стили для поля ввода
    input.style.background = '#2a2a2a';
    input.style.color = '#fff';
    input.style.border = '1px solid #4CAF50';
    input.style.borderRadius = '3px';
    input.style.padding = '2px 4px';
    input.style.font = 'inherit';
    input.style.width = '100%';

    // Заменяем span на input
    nameSpan.style.display = 'none';
    nameSpan.parentNode.insertBefore(input, nameSpan);

    // Выделяем текст и фокусируемся
    input.select();
    input.focus();

    // Функция завершения редактирования
    const finishEdit = (save = false) => {
      const newName = input.value.trim();

      if (save && newName && newName !== currentName) {
        // Добавляем расширение обратно, если оно было
        const extension = scene.name.match(/\.[^.]+$/);
        const fullNewName = newName + (extension ? extension[0] : '');

        if (this.sceneManager.renameScene(scene.id, fullNewName)) {
          nameSpan.textContent = newName;
          // scene renamed
        } else {
          console.error(`❌ Не удалось переименовать сцену: ${scene.id}`);
        }
      }

      // Возвращаем исходный вид
      input.remove();
      nameSpan.style.display = '';
    };

    // Обработчики событий
    input.addEventListener('blur', () => finishEdit(true));
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        finishEdit(true);
      } else if (e.key === 'Escape') {
        e.preventDefault();
        finishEdit(false);
      }
    });
  }
}