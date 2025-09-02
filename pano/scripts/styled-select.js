/**
 * Стилизованный кастомный выпадающий список
 * Решает проблему с фоном опций в Chrome/Edge
 */

// Ждем полной загрузки документа
document.addEventListener('DOMContentLoaded', function () {
  // Находим все обычные select в форме настроек хотспотов
  const selects = document.querySelectorAll('#hotspot-form select');

  // Добавляем стилизацию для всех селектов
  selects.forEach(function (select) {
    // Устанавливаем дополнительные атрибуты для лучшей стилизации
    select.setAttribute('data-styled', 'true');

    // Добавляем CSS-класс для кастомного стиля
    select.classList.add('styled-select');

    // Добавляем обработчик для фокуса и клика на выпадающем списке
    select.addEventListener('mousedown', function (e) {
      // Применяем темный фон для опций принудительно через JS
      setTimeout(() => {
        const options = document.querySelectorAll('#hotspot-form select option');
        options.forEach(option => {
          option.style.backgroundColor = '#2a2a2a';
          option.style.color = 'rgba(255, 255, 255, 0.9)';
        });
      }, 10);
    });

    // Отслеживаем изменение значения
    select.addEventListener('change', function () {
      // Обновляем стилизацию при изменении
      const options = select.querySelectorAll('option');
      options.forEach(option => {
        if (option.selected) {
          option.style.backgroundColor = 'rgba(100, 108, 255, 0.5)';
          option.style.color = '#ffffff';
          option.style.fontWeight = 'bold';
        } else {
          option.style.backgroundColor = '#2a2a2a';
          option.style.color = 'rgba(255, 255, 255, 0.9)';
        }
      });
    });
  });

  // Добавляем стили в head для решения проблемы с темой в Chrome
  const styleElement = document.createElement('style');
  styleElement.textContent = `
    /* Исправление проблемы с фоном option в браузерах на основе Chromium */
    @media screen and (-webkit-min-device-pixel-ratio:0) {
      #hotspot-form select.styled-select option {
        background-color: #2a2a2a !important;
        color: white !important;
      }
      
      #hotspot-form select.styled-select option:hover {
        background-color: rgba(100, 108, 255, 0.3) !important;
      }
      
      #hotspot-form select.styled-select option:checked {
        background-color: rgba(100, 108, 255, 0.5) !important;
      }
    }
  `;
  document.head.appendChild(styleElement);
});