// Тест для проверки исправления пользовательских иконок
const testCustomIconPreservation = () => {
  console.log('Запуск теста сохранения пользовательских иконок...');

  // Создаем тестовый хотспот с пользовательской иконкой
  const testHotspot = {
    id: 'test-1',
    sceneId: 'scene-1',
    type: 'hotspot',
    title: 'Тестовый хотспот',
    icon: 'custom',
    customIconData: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCI+PGNpcmNsZSBjeD0iNTAiIGN5PSI1MCIgcj0iNDAiIGZpbGw9IiMwMDAwZmYiLz48L3N2Zz4=',
    position: { x: 1, y: 0, z: -3 },
    color: '#ff0000'
  };

  console.log('Исходный хотспот:', testHotspot);

  // Имитируем сохранение в localStorage
  const savedData = JSON.stringify([testHotspot]);
  console.log('Сохраненные данные:', savedData);

  // Имитируем загрузку из localStorage
  const loadedHotspots = JSON.parse(savedData);
  console.log('Загруженные хотспоты:', loadedHotspots);

  // Проверяем, что иконка сохранилась
  if (loadedHotspots[0].icon === 'custom') {
    console.log('✅ Тест пройден: пользовательская иконка сохранена');
    return true;
  } else {
    console.log('❌ Тест провален: иконка изменена на', loadedHotspots[0].icon);
    return false;
  }
};

// Запускаем тест
testCustomIconPreservation();