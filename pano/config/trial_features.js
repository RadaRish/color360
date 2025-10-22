// Конфигурация триальной (бесплатной) версии
// Этот файл определяет, какие функции доступны в бесплатной версии

export const TRIAL_CONFIG = {
  // Флаг триальной версии (установите false для премиум версии)
  isTrialVersion: true,

  // Настройки доступных кнопок в панели управления
  toolbar: {
    fullscreen: false,           // Кнопка "Полный экран"
    clearCameraView: false,       // Кнопка "Очистить вид камеры для сцены"
    retouchObject: false,         // Кнопка "Удалить объект (ретушь)"
    retouchUndo: false,           // Кнопка "Отменить последнюю ретушь"
    saveProject: true,            // Кнопка "Сохранить"
    exportProject: true,          // Кнопка "Экспорт"
    setCameraView: true,          // Кнопка "Установить вид камеры"
    settings: true                // Кнопка "Настройки"
  },

  // Настройки интерфейса
  ui: {
    userAvatar: false,            // Иконка пользователя
    contextMenu: false            // Контекстное меню по ПКМ на сцене
  },

  // Настройки маркеров (хотспотов и инфоточек)
  markers: {
    // Возможность выбора собственной иконки
    customIcon: false,
    // Всплывающее окно по клику на инфоточке
    infoPointPopup: false,
    
    // Ограничения на количество символов
    limits: {
      // Название хотспота/инфоточки
      titleMaxLength: 25,
      
      // Описание
      descriptionMaxLength: 250,
      descriptionLineMaxLength: 36
    }
  },

  // Кнопки создания маркеров в левой панели
  markerButtons: {
    addHotspot: true,             // Кнопка добавления хотспота
    addInfoPoint: true            // Кнопка добавления инфоточки
  }
};

// Функция проверки доступности функции
export function isFeatureEnabled(featurePath) {
  const parts = featurePath.split('.');
  let current = TRIAL_CONFIG;
  
  for (const part of parts) {
    if (current === undefined || current === null) {
      return false;
    }
    current = current[part];
  }
  
  return current === true;
}

// Функция получения значения конфигурации
export function getConfig(configPath) {
  const parts = configPath.split('.');
  let current = TRIAL_CONFIG;
  
  for (const part of parts) {
    if (current === undefined || current === null) {
      return undefined;
    }
    current = current[part];
  }
  
  return current;
}

// Экспорт для использования в других модулях
export default TRIAL_CONFIG;
