// 🔐 url_normalizer.js
// Централизованная логика приведения любых указанных явно http:// ресурсов к https:// при открытой по HTTPS странице,
// а также безопасное формирование относительных путей к backend API.

(function(){
  function normalizeApiUrl(input) {
    if (!input) return input;
    try {
      // Если уже относительный путь – оставляем
      if (input.startsWith('/')) return input;
      // Если указана переменная окружения через window.__API_ORIGIN
      if (input.startsWith('api:')) {
        const rest = input.slice(4);
        const origin = (window.__API_ORIGIN || '').replace(/\/$/, '');
        if (origin) return origin + rest;
        return rest; // fallback
      }
      // Приводим http→https если страница по https
      if (window.location && window.location.protocol === 'https:' && /^http:\/\//i.test(input)) {
        return input.replace(/^http:\/\//i,'https://');
      }
      return input;
    } catch(e){ return input; }
  }

  // Перехватываем fetch чтобы автоматически нормализовать первый аргумент-URL
  const _origFetch = window.fetch;
  window.fetch = function(resource, init) {
    try {
      if (typeof resource === 'string') {
        resource = normalizeApiUrl(resource);
      } else if (resource && resource.url) {
        // Request объект – не трогаем напрямую.
      }
    } catch(_){}
    return _origFetch.call(this, resource, init);
  };

  window.__normalizeApiUrl = normalizeApiUrl;
  console.log('🔐 URL Normalizer активирован');
})();
