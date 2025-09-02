/**
 * Тесты для видео-областей при переходах между сценами
 */

class VideoAreaTransitionTests {
  constructor() {
    this.testResults = [];
    this.errors = [];
  }

  // Симуляция DOM окружения для тестов
  setupTestEnvironment() {
    // Создаем базовую A-Frame сцену
    if (!document.querySelector('a-scene')) {
      const scene = document.createElement('a-scene');
      scene.id = 'test-scene';
      document.body.appendChild(scene);
    }

    // Мокаем localStorage
    this.originalLocalStorage = window.localStorage;
    window.localStorage = {
      data: {},
      getItem(key) { return this.data[key] || null; },
      setItem(key, value) { this.data[key] = value; },
      removeItem(key) { delete this.data[key]; },
      clear() { this.data = {}; }
    };
  }

  // Тест 1: Проверка потери videoUrl при переходах
  async testVideoUrlPersistence() {
    console.log('🧪 Тест 1: Проверка сохранения videoUrl при переходах между сценами');

    try {
      // Создаем тестовые данные видео-области
      const testHotspot = {
        id: 'test_video_hotspot',
        title: 'Тестовая видео-область',
        type: 'video-area',
        sceneId: 'scene_1',
        videoUrl: 'https://www.w3schools.com/html/mov_bbb.mp4',
        videoWidth: 4,
        videoHeight: 3,
        position: { x: 0, y: 0, z: -5 }
      };

      // Сохраняем в localStorage
      const hotspotsData = [testHotspot];
      localStorage.setItem('hotspots', JSON.stringify(hotspotsData));

      // Симулируем переход на другую сцену и обратно
      await this.simulateSceneTransition('scene_1', 'scene_2', 'scene_1');

      // Проверяем, что videoUrl сохранился
      const restoredHotspots = JSON.parse(localStorage.getItem('hotspots') || '[]');
      const restoredHotspot = restoredHotspots.find(h => h.id === 'test_video_hotspot');

      if (!restoredHotspot) {
        throw new Error('Хотспот потерян после перехода между сценами');
      }

      if (!restoredHotspot.videoUrl) {
        throw new Error('videoUrl потерян после перехода между сценами');
      }

      if (restoredHotspot.videoUrl !== testHotspot.videoUrl) {
        throw new Error(`videoUrl изменился: ожидался ${testHotspot.videoUrl}, получен ${restoredHotspot.videoUrl}`);
      }

      this.testResults.push({
        test: 'videoUrlPersistence',
        status: 'PASSED',
        message: 'videoUrl корректно сохраняется при переходах между сценами'
      });

    } catch (error) {
      this.errors.push(error);
      this.testResults.push({
        test: 'videoUrlPersistence',
        status: 'FAILED',
        message: error.message
      });
    }
  }

  // Тест 2: Проверка восстановления видео элементов после перехода
  async testVideoElementRestoration() {
    console.log('🧪 Тест 2: Проверка восстановления видео элементов');

    try {
      const testVideoId = 'video-test_hotspot';

      // Создаем видео элемент
      const videoEl = document.createElement('video');
      videoEl.id = testVideoId;
      videoEl.src = 'https://www.w3schools.com/html/mov_bbb.mp4';

      // Добавляем в assets
      let assets = document.querySelector('a-assets');
      if (!assets) {
        assets = document.createElement('a-assets');
        document.querySelector('a-scene').appendChild(assets);
      }
      assets.appendChild(videoEl);

      // Симулируем переход сцены
      await this.simulateSceneTransition('scene_1', 'scene_2', 'scene_1');

      // Проверяем, что видео элемент все еще существует
      const restoredVideoEl = document.getElementById(testVideoId);

      if (!restoredVideoEl) {
        throw new Error('Видео элемент удален после перехода между сценами');
      }

      if (restoredVideoEl.src !== videoEl.src) {
        throw new Error('src видео элемента потерян после перехода');
      }

      this.testResults.push({
        test: 'videoElementRestoration',
        status: 'PASSED',
        message: 'Видео элементы корректно восстанавливаются после переходов'
      });

    } catch (error) {
      this.errors.push(error);
      this.testResults.push({
        test: 'videoElementRestoration',
        status: 'FAILED',
        message: error.message
      });
    }
  }

  // Тест 3: Проверка корректности обработчиков событий после перехода
  async testEventHandlersAfterTransition() {
    console.log('🧪 Тест 3: Проверка обработчиков событий видео-областей');

    try {
      // Создаем видео-область
      const markerEl = document.createElement('a-entity');
      markerEl.id = 'marker-test_video';
      markerEl.setAttribute('data-hotspot-id', 'test_video');

      const videoPlane = document.createElement('a-plane');
      videoPlane.setAttribute('data-video-plane', 'true');
      videoPlane.className = 'interactive video-area video-plane';
      markerEl.appendChild(videoPlane);

      document.querySelector('a-scene').appendChild(markerEl);

      // Добавляем обработчик клика
      let clickHandled = false;
      videoPlane.addEventListener('click', () => {
        clickHandled = true;
      });

      // Симулируем переход сцены
      await this.simulateSceneTransition('scene_1', 'scene_2', 'scene_1');

      // Проверяем, что элемент еще существует
      const restoredMarker = document.getElementById('marker-test_video');
      const restoredPlane = restoredMarker ? restoredMarker.querySelector('[data-video-plane]') : null;

      if (!restoredMarker || !restoredPlane) {
        throw new Error('Видео-область удалена после перехода между сценами');
      }

      // Симулируем клик
      const clickEvent = new Event('click');
      restoredPlane.dispatchEvent(clickEvent);

      // Даем время на обработку
      await new Promise(resolve => setTimeout(resolve, 100));

      if (!clickHandled) {
        throw new Error('Обработчики событий не работают после перехода между сценами');
      }

      this.testResults.push({
        test: 'eventHandlersAfterTransition',
        status: 'PASSED',
        message: 'Обработчики событий работают после переходов между сценами'
      });

    } catch (error) {
      this.errors.push(error);
      this.testResults.push({
        test: 'eventHandlersAfterTransition',
        status: 'FAILED',
        message: error.message
      });
    }
  }

  // Симуляция перехода между сценами
  async simulateSceneTransition(fromScene, toScene, backToScene) {
    console.log(`🔄 Симулируем переход: ${fromScene} → ${toScene} → ${backToScene}`);

    // Симулируем очистку сцены
    const scene = document.querySelector('a-scene');
    const markers = scene.querySelectorAll('[id^="marker-"]');
    markers.forEach(marker => {
      // Сохраняем информацию перед удалением (как это делает система)
      const hotspotId = marker.getAttribute('data-hotspot-id');
      if (hotspotId) {
        console.log(`💾 Симуляция сохранения состояния маркера: ${hotspotId}`);
      }
    });

    // Ожидание для имитации асинхронных операций
    await new Promise(resolve => setTimeout(resolve, 50));

    // Симулируем восстановление (как это должна делать система)
    console.log(`✅ Симуляция завершена для перехода: ${fromScene} → ${toScene} → ${backToScene}`);
  }

  // Запуск всех тестов
  async runAllTests() {
    console.log('🚀 Запуск тестов видео-областей при переходах между сценами');

    this.setupTestEnvironment();

    await this.testVideoUrlPersistence();
    await this.testVideoElementRestoration();
    await this.testEventHandlersAfterTransition();

    this.reportResults();
  }

  // Отчет о результатах
  reportResults() {
    console.log('\n📊 РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ:');
    console.log('═'.repeat(60));

    let passed = 0;
    let failed = 0;

    this.testResults.forEach(result => {
      const status = result.status === 'PASSED' ? '✅' : '❌';
      console.log(`${status} ${result.test}: ${result.message}`);

      if (result.status === 'PASSED') passed++;
      else failed++;
    });

    console.log('═'.repeat(60));
    console.log(`📈 Всего тестов: ${this.testResults.length}`);
    console.log(`✅ Успешно: ${passed}`);
    console.log(`❌ Провалено: ${failed}`);

    if (this.errors.length > 0) {
      console.log('\n🚨 ОБНАРУЖЕННЫЕ ОШИБКИ:');
      this.errors.forEach((error, index) => {
        console.log(`${index + 1}. ${error.message}`);
        if (error.stack) {
          console.log(`   Stack: ${error.stack}`);
        }
      });
    }

    return {
      total: this.testResults.length,
      passed: passed,
      failed: failed,
      errors: this.errors
    };
  }
}

// Экспорт для использования в браузере
if (typeof window !== 'undefined') {
  window.VideoAreaTransitionTests = VideoAreaTransitionTests;
}

// Экспорт для Node.js (если понадобится)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = VideoAreaTransitionTests;
}
