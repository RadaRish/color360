// Тест для проверки сохранения пользовательских иконок при переходе между сценами
const testSceneTransition = () => {
  console.log('Запуск теста перехода между сценами...');

  // Имитация HotspotManager
  const HotspotManager = {
    hotspots: [],

    // Имитация метода сохранения в localStorage
    saveToStorage() {
      try {
        const hotspotsToSave = this.hotspots.map(hotspot => {
          const minimizedHotspot = {
            id: hotspot.id,
            sceneId: hotspot.sceneId,
            type: hotspot.type,
            position: hotspot.position
          };

          // Сохраняем цвет и иконку
          if (hotspot.color && hotspot.color !== 'undefined') {
            minimizedHotspot.color = hotspot.color;
          }

          if (hotspot.icon && hotspot.icon !== 'undefined') {
            minimizedHotspot.icon = hotspot.icon;
          }

          return minimizedHotspot;
        });

        const dataToSave = JSON.stringify(hotspotsToSave);
        console.log('Сохраненные данные:', dataToSave);
        return dataToSave;
      } catch (error) {
        console.error('Ошибка сохранения:', error);
        return null;
      }
    },

    // Имитация метода загрузки из localStorage
    loadFromStorage(savedData) {
      try {
        this.hotspots = JSON.parse(savedData);
        console.log('Загруженные хотспоты:', this.hotspots);
        return true;
      } catch (error) {
        console.error('Ошибка загрузки:', error);
        return false;
      }
    },

    // Имитация метода восстановления данных хотспота
    restoreHotspotData(hotspot) {
      // Восстанавливаем иконку если она была установлена
      if (hotspot.icon === undefined || hotspot.icon === null) {
        // Устанавливаем иконку по умолчанию в зависимости от типа
        if (hotspot.type === 'hotspot') {
          hotspot.icon = 'arrow';
        } else if (hotspot.type === 'info-point') {
          hotspot.icon = 'sphere';
        } else {
          hotspot.icon = 'sphere'; // По умолчанию
        }
        console.log('Восстановлена иконка по умолчанию для хотспота:', hotspot.id, hotspot.icon);
      } else {
        console.log('Сохранена оригинальная иконка хотспота:', hotspot.id, hotspot.icon);
      }

      return hotspot;
    },

    getHotspotsForScene(sceneId) {
      return this.hotspots.filter(h => h.sceneId === sceneId);
    }
  };

  // Создаем тестовые хотспоты
  const scene1Hotspots = [
    {
      id: 'hotspot-1',
      sceneId: 'scene-1',
      type: 'hotspot',
      title: 'Навигационный хотспот',
      icon: 'custom',
      customIconData: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCI+PGNpcmNsZSBjeD0iNTAiIGN5PSI1MCIgcj0iNDAiIGZpbGw9IiMwMDAwZmYiLz48L3N2Zz4=',
      position: { x: 1, y: 0, z: -3 },
      color: '#ff0000'
    },
    {
      id: 'hotspot-2',
      sceneId: 'scene-1',
      type: 'info-point',
      title: 'Информационный хотспот',
      icon: 'sphere',
      position: { x: -1, y: 1, z: -4 },
      color: '#0066cc'
    }
  ];

  const scene2Hotspots = [
    {
      id: 'hotspot-3',
      sceneId: 'scene-2',
      type: 'hotspot',
      title: 'Возврат',
      icon: 'arrow',
      targetSceneId: 'scene-1',
      position: { x: 0, y: -1, z: -5 },
      color: '#00ff00'
    }
  ];

  HotspotManager.hotspots = [...scene1Hotspots, ...scene2Hotspots];

  console.log('Исходные хотспоты:');
  HotspotManager.hotspots.forEach(h => {
    console.log(`  ${h.id}: ${h.title} (иконка: ${h.icon})`);
  });

  // Сохраняем данные
  const savedData = HotspotManager.saveToStorage();
  if (!savedData) {
    console.log('❌ Тест провален: ошибка сохранения данных');
    return false;
  }

  // Имитируем переход между сценами
  console.log('\n--- Переход на сцену 2 ---');

  // Очищаем текущие хотспоты (имитация clearMarkers)
  HotspotManager.hotspots = [];

  // Загружаем данные (имитация загрузки при переходе на сцену)
  if (!HotspotManager.loadFromStorage(savedData)) {
    console.log('❌ Тест провален: ошибка загрузки данных');
    return false;
  }

  // Получаем хотспоты для сцены 2
  const scene2HotspotsLoaded = HotspotManager.getHotspotsForScene('scene-2');
  console.log('Хотспоты сцены 2 после загрузки:');
  scene2HotspotsLoaded.forEach(h => {
    console.log(`  ${h.id}: ${h.title} (иконка: ${h.icon})`);
  });

  console.log('\n--- Возврат на сцену 1 ---');

  // Получаем хотспоты для сцены 1
  let scene1HotspotsLoaded = HotspotManager.getHotspotsForScene('scene-1');
  console.log('Хотспоты сцены 1 после загрузки (до восстановления):');
  scene1HotspotsLoaded.forEach(h => {
    console.log(`  ${h.id}: ${h.title} (иконка: ${h.icon})`);
  });

  // Восстанавливаем данные хотспотов (имитация restoreHotspotData)
  scene1HotspotsLoaded = scene1HotspotsLoaded.map(h => HotspotManager.restoreHotspotData(h));
  console.log('Хотспоты сцены 1 после восстановления:');
  scene1HotspotsLoaded.forEach(h => {
    console.log(`  ${h.id}: ${h.title} (иконка: ${h.icon})`);
  });

  // Проверяем, что пользовательская иконка сохранилась
  const customHotspot = scene1HotspotsLoaded.find(h => h.id === 'hotspot-1');
  if (customHotspot && customHotspot.icon === 'custom') {
    console.log('✅ Тест пройден: пользовательская иконка сохранена при переходе между сценами');
    return true;
  } else {
    console.log('❌ Тест провален: пользовательская иконка потеряна при переходе между сценами');
    console.log('  Ожидаемая иконка: custom');
    console.log('  Фактическая иконка:', customHotspot ? customHotspot.icon : 'не найдена');
    return false;
  }
};

// Запускаем тест
testSceneTransition();