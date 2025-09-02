// Управление проектом: загрузка, сохранение, экспорт
export default class ProjectManager {
    constructor(sceneManager, hotspotManager) {
        this.sceneManager = sceneManager;
        this.hotspotManager = hotspotManager;
    }

    saveProject() {
        try {
            const scenes = this.sceneManager.getAllScenes();
            const hotspots = this.hotspotManager.getAllHotspots();

            const data = {
                version: "1.1", // Обновленная версия с централизованными хотспотами
                created: new Date().toISOString(),
                scenes: scenes.map(s => ({
                    id: s.id,
                    name: s.name,
                    src: s.src,
                    // hotsposts теперь управляются централизованно
                })),
                hotspots: hotspots,
            };

            console.log('Сохраняем проект с данными:', data);
            return JSON.stringify(data, null, 2);
        } catch (error) {
            console.error('Ошибка при сохранении проекта:', error);
            throw error;
        }
    }

    /**
     * Получает информацию о проекте для экспорта
     */
    getProjectInfo() {
        return {
            title: 'Панорамный тур',
            autorotate: false,
            showSceneList: true,
            fullscreenButton: true,
            version: '1.1',
            created: new Date().toISOString()
        };
    }

    async loadProject(json) {
        try {
            const data = typeof json === 'string' ? JSON.parse(json) : json;

            if (!data.scenes || !Array.isArray(data.scenes)) {
                throw new Error('Неверный формат проекта: отсутствует массив scenes');
            }

            console.log('Загружаем проект:', data);

            // Очищаем текущие данные
            this.sceneManager.clearScenes();
            this.hotspotManager.loadHotspots([]); // Очищаем хотспоты

            // Загружаем сцены
            for (const sceneData of data.scenes) {
                await this.sceneManager.addScene({
                    id: sceneData.id,
                    name: sceneData.name,
                    src: sceneData.src,
                    hotspots: [] // Хотспоты будут загружены отдельно
                });
            }

            // Загружаем хотспоты
            if (data.hotspots && Array.isArray(data.hotspots)) {
                this.hotspotManager.loadHotspots(data.hotspots);
            }

            // Переключаемся на первую сцену, если она есть
            const firstScene = this.sceneManager.getAllScenes()[0];
            if (firstScene) {
                this.sceneManager.switchToScene(firstScene.id);
            }

            console.log(`Проект загружен успешно. Загружено сцен: ${data.scenes.length}`);
            return true;

        } catch (error) {
            console.error('Ошибка при загрузке проекта:', error);
            return false;
        }
    }

    // ... (остальные методы без изменений)
}
