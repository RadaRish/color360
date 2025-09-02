// Minimal front-end logic to interact with the demo backend
const modal = document.getElementById('modal');
const modalBody = document.getElementById('modal-body');
const btnLogin = document.getElementById('btn-login');
const btnRegister = document.getElementById('btn-register');
const modalClose = document.getElementById('modal-close');
const newsList = document.getElementById('news-list');
const userMenuPlaceholder = document.getElementById('user-menu-placeholder');

// Initialize parallax effect for hero section
function initParallaxEffect() {
  window.addEventListener('scroll', function() {
    const heroVideo = document.getElementById('hero-video');
    if (heroVideo && heroVideo.readyState >= 2) {
      const scrollPosition = window.scrollY;
      // Применяем эффект параллакса только если видео загружено и готово
      heroVideo.style.transform = `translateX(-50%) translateY(calc(-50% + ${scrollPosition * 0.1}px))`;
    }
  });
}

// Initialize animation for news cards
function initNewsCardAnimations() {
  const newsCards = document.querySelectorAll('.news-card');
  
  if (newsCards.length > 0) {
    newsCards.forEach((card, index) => {
      // Add staggered animation delay
      card.style.opacity = '0';
      card.style.transform = 'translateY(20px)';
      card.style.transition = 'opacity 0.5s ease, transform 0.5s ease';
      card.style.transitionDelay = `${index * 0.1}s`;
      
      // Use Intersection Observer to trigger animations when cards come into view
      const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            card.style.opacity = '1';
            card.style.transform = 'translateY(0)';
            observer.unobserve(card);
          }
        });
      }, { threshold: 0.2 });
      
      observer.observe(card);
    });
  }
}

// Initialize animations for feature cards
function initFeatureCardAnimations() {
  const featureCards = document.querySelectorAll('.feature-card');
  
  if (featureCards.length > 0) {
    featureCards.forEach((card, index) => {
      // Add staggered animation delay
      card.style.opacity = '0';
      card.style.transform = 'translateY(20px)';
      card.style.transition = 'opacity 0.5s ease, transform 0.5s ease';
      card.style.transitionDelay = `${index * 0.1}s`;
      
      // Use Intersection Observer to trigger animations when cards come into view
      const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            card.style.opacity = '1';
            card.style.transform = 'translateY(0)';
            observer.unobserve(card);
          }
        });
      }, { threshold: 0.2 });
      
      observer.observe(card);
    });
  }
}

// Initialize video enhancements
function initVideoEnhancements() {
  const heroVideo = document.getElementById('hero-video');
  const aboutVideo = document.querySelector('.about-video');
  
  // Добавляем обработчик ошибок загрузки для главного видео
  if (heroVideo) {
    // Убедимся, что видео видимо
    heroVideo.style.opacity = '1';
    heroVideo.style.display = 'block';
    
    // Добавляем отладочную информацию
    console.log('Hero video element:', heroVideo);
    console.log('Hero video source:', heroVideo.querySelector('source').src);
    
    heroVideo.addEventListener('error', function(e) {
      console.log('Hero video error:', e);
      console.log('Hero video error code:', heroVideo.error?.code);
      console.log('Hero video network state:', heroVideo.networkState);
      console.log('Hero video ready state:', heroVideo.readyState);
      
      // Показываем резервное изображение
      const fallbackBg = document.querySelector('.fallback-background');
      if (fallbackBg) {
        fallbackBg.style.zIndex = '2'; // Поверх всех слоев
        fallbackBg.style.opacity = '1'; // Make it visible again
      }
    });
    
    heroVideo.addEventListener('loadstart', function() {
      console.log('Hero video load started');
    });
    
    heroVideo.addEventListener('loadedmetadata', function() {
      console.log('Hero video metadata loaded');
      console.log('Video duration:', heroVideo.duration);
      console.log('Video dimensions:', heroVideo.videoWidth, 'x', heroVideo.videoHeight);
      // Небольшая задержка перед попыткой воспроизведения
      setTimeout(() => {
        attemptPlayVideo(heroVideo);
      }, 300);
    });
    
    heroVideo.addEventListener('loadeddata', function() {
      console.log('Hero video data loaded');
      console.log('Hero video ready state:', heroVideo.readyState);
      // Небольшая задержка перед попыткой воспроизведения
      setTimeout(() => {
        attemptPlayVideo(heroVideo);
      }, 300);
    });
    
    heroVideo.addEventListener('canplay', function() {
      console.log('Hero video can play');
      // Небольшая задержка перед попыткой воспроизведения
      setTimeout(() => {
        attemptPlayVideo(heroVideo);
      }, 300);
    });
    
    heroVideo.addEventListener('canplaythrough', function() {
      console.log('Hero video can play through');
      // Небольшая задержка перед попыткой воспроизведения
      setTimeout(() => {
        attemptPlayVideo(heroVideo);
      }, 300);
    });
    
    heroVideo.addEventListener('playing', function() {
      console.log('Hero video is now playing');
      // Hide the fallback background when video starts playing
      const fallbackBg = document.querySelector('.fallback-background');
      if (fallbackBg) {
        // Add a small delay to ensure smooth transition
        setTimeout(() => {
          fallbackBg.style.opacity = '0';
        }, 100);
      }
    });
    
    heroVideo.addEventListener('waiting', function() {
      console.log('Hero video is waiting');
    });
    
    // Принудительная попытка воспроизведения через 1 секунду
    setTimeout(() => {
      console.log('Attempting to play hero video (1s delay)');
      attemptPlayVideo(heroVideo);
    }, 1000);
    
    // Дополнительная попытка через 3 секунды
    setTimeout(() => {
      console.log('Attempting to play hero video (3s delay)');
      attemptPlayVideo(heroVideo);
    }, 3000);
  }
  
  // Обработка видео в разделе о платформе
  if (aboutVideo) {
    // Обработчик ошибок загрузки
    aboutVideo.addEventListener('error', function(e) {
      console.log('About video error:', e);
      // Показываем резервное изображение
      const fallbackImg = document.querySelector('.fallback-image');
      if (fallbackImg) {
        fallbackImg.style.zIndex = '1';
      }
    });
    
    // Используем IntersectionObserver для управления воспроизведением видео
    let isInView = false;
    let isPlaying = false;
    
    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        isInView = entry.isIntersecting;
        updateVideoState();
      });
    }, { threshold: 0.3 });
    
    // Функция для обновления состояния видео
    function updateVideoState() {
      if (isInView && !isPlaying && aboutVideo.readyState >= 2) {
        // Видео в зоне видимости и готово к воспроизведению
        try {
          const playPromise = aboutVideo.play();
          if (playPromise !== undefined) {
            playPromise.then(() => {
              isPlaying = true;
              // Убедимся, что видео отображается корректно
              aboutVideo.style.opacity = '1';
            }).catch(error => {
              // Автовоспроизведение было заблокировано или произошла другая ошибка
              console.log('About video play prevented:', error);
              // Показываем резервное изображение
              const fallbackImg = document.querySelector('.fallback-image');
              if (fallbackImg) {
                fallbackImg.style.zIndex = '1';
              }
            });
          }
        } catch (e) {
          console.log('Error playing about video:', e);
        }
      } else if (!isInView && isPlaying) {
        // Видео вышло из зоны видимости, нужно остановить
        try {
          aboutVideo.pause();
          isPlaying = false;
        } catch (e) {
          console.log('Error pausing video:', e);
        }
      }
    }
    
    // Обработчик для события, когда видео готово к воспроизведению
    aboutVideo.addEventListener('canplay', function() {
      updateVideoState();
    });
    
    // Добавляем обработчик для события loadeddata
    aboutVideo.addEventListener('loadeddata', function() {
      // Убедимся, что видео отображается корректно
      aboutVideo.style.opacity = '1';
      updateVideoState();
    });
    
    observer.observe(aboutVideo);
  }
}

// Функция для попытки воспроизведения видео
function attemptPlayVideo(videoElement) {
  if (!videoElement) return;
  
  // Проверяем, не воспроизводится ли видео уже
  if (!videoElement.paused) {
    console.log('Video is already playing');
    return;
  }
  
  console.log('Attempting to play video, readyState:', videoElement.readyState);
  
  // Проверяем, готово ли видео к воспроизведению
  if (videoElement.readyState < 2) {
    console.log('Video not ready to play yet');
    return;
  }
  
  try {
    const playPromise = videoElement.play();
    if (playPromise !== undefined) {
      playPromise.then(() => {
        console.log('Video playing successfully');
        // Убедимся, что видео отображается корректно
        videoElement.style.opacity = '1';
      }).catch(error => {
        console.log('Video play prevented:', error);
        // В случае ошибки показываем резервное изображение
        showFallbackBackground();
      });
    }
  } catch (e) {
    console.log('Error playing video:', e);
    // В случае ошибки показываем резервное изображение
    showFallbackBackground();
  }
}

// Функция для показа резервного фона
function showFallbackBackground() {
  const fallbackBg = document.querySelector('.fallback-background');
  if (fallbackBg) {
    fallbackBg.style.zIndex = '2'; // Поверх всех слоев
    fallbackBg.style.opacity = '1'; // Make it visible
  }
}

// Check if user is logged in and update UI accordingly
function updateUIForUserStatus() {
  const userToken = localStorage.getItem('color360_token');
  
  if (userToken) {
    // User is logged in, show user menu
    showUserMenu();
  } else {
    // User is not logged in, show login/register buttons
    showLoginRegisterButtons();
  }
}

// Show user menu
function showUserMenu() {
  if (userMenuPlaceholder) {
    // Check if user is admin
    let isAdmin = false;
    const userJson = localStorage.getItem('color360_user');
    if (userJson) {
      try {
        const user = JSON.parse(userJson);
        isAdmin = user.isAdmin || false;
      } catch (e) {
        console.error('Error parsing user data:', e);
      }
    }
    
    // Determine the correct link based on user role
    const cabinetLink = isAdmin ? '/admin' : '/dashboard';
    const cabinetText = isAdmin ? 'Админ панель' : 'Личный кабинет';
    
    userMenuPlaceholder.innerHTML = `
      <div class="user-menu">
        <button class="user-menu-button">
          <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path>
            <circle cx="12" cy="7" r="4"></circle>
          </svg>
        </button>
        <div class="user-dropdown">
          <a href="${cabinetLink}">${cabinetText}</a>
          <a href="#" id="logout-link">Выйти</a>
        </div>
      </div>
    `;
    
    // Add event listener for logout
    const logoutLink = document.getElementById('logout-link');
    if (logoutLink) {
      logoutLink.addEventListener('click', (e) => {
        e.preventDefault();
        // Удаляем токен и информацию о пользователе
        localStorage.removeItem('color360_token');
        localStorage.removeItem('color360_user');
        updateUIForUserStatus();
        window.location.href = '/';
      });
    }
    
    // Add dropdown functionality
    const userMenuButton = document.querySelector('.user-menu-button');
    const userDropdown = document.querySelector('.user-dropdown');
    
    if (userMenuButton && userDropdown) {
      // Remove any existing event listeners to prevent duplicates
      userMenuButton.removeEventListener('click', handleUserMenuClick);
      userMenuButton.addEventListener('click', handleUserMenuClick);
    }
  }
  
  // Hide login/register buttons
  if (btnLogin) btnLogin.style.display = 'none';
  if (btnRegister) btnRegister.style.display = 'none';
}

// Handle user menu click
function handleUserMenuClick(e) {
  e.stopPropagation();
  const userDropdown = document.querySelector('.user-dropdown');
  if (userDropdown) {
    userDropdown.classList.toggle('show');
  }
}

// Close dropdown when clicking outside
function closeDropdownOutside(e) {
  const userMenuButton = document.querySelector('.user-menu-button');
  const userDropdown = document.querySelector('.user-dropdown');
  
  if (userDropdown && userDropdown.classList.contains('show') && 
      userMenuButton && !userMenuButton.contains(e.target) && 
      userDropdown && !userDropdown.contains(e.target)) {
    userDropdown.classList.remove('show');
  }
}

// Show login/register buttons
function showLoginRegisterButtons() {
  if (userMenuPlaceholder) {
    userMenuPlaceholder.innerHTML = '';
  }
  
  // Show login/register buttons
  if (btnLogin) btnLogin.style.display = 'block';
  if (btnRegister) btnRegister.style.display = 'block';
}

// Initialize visual effects on page load
document.addEventListener('DOMContentLoaded', function() {
  // Initialize FAQ accordion
  const faqItems = document.querySelectorAll('.faq-item');
  
  faqItems.forEach(item => {
    const question = item.querySelector('.faq-question');
    
    question.addEventListener('click', () => {
      // Close all other FAQ items
      faqItems.forEach(otherItem => {
        if (otherItem !== item) {
          otherItem.classList.remove('active');
        }
      });
      
      // Toggle current item
      item.classList.toggle('active');
    });
  });
  
  // Проверяем, загрузились ли видео
  const heroVideo = document.getElementById('hero-video');
  const aboutVideo = document.querySelector('.about-video');
  
  if (heroVideo) {
    // Проверяем и показываем фоновое изображение, если видео не загрузилось
    heroVideo.addEventListener('error', function() {
      console.log('Hero video could not be loaded');
      const fallbackBg = document.querySelector('.fallback-background');
      if (fallbackBg) {
        fallbackBg.style.zIndex = '2';
        fallbackBg.style.opacity = '1'; // Make it visible
      }
    });
  }
  
  if (aboutVideo) {
    // Проверяем и показываем фоновое изображение, если видео не загрузилось
    aboutVideo.addEventListener('error', function() {
      console.log('About video could not be loaded');
      document.querySelector('.fallback-image').style.zIndex = '1';
    });
  }
  
  // Initialize visual enhancements
  initParallaxEffect();
  initNewsCardAnimations();
  initFeatureCardAnimations();
  initVideoEnhancements();
  
  // Add pulse animation to CTA button
  const ctaButton = document.getElementById('app-link');
  if (ctaButton) {
    ctaButton.classList.add('animate-pulse');
  }
  
  // Load news
  loadNews();
  
  // Update UI based on user status
  updateUIForUserStatus();
});

// Contact Form Submission
document.addEventListener('DOMContentLoaded', function() {
  const contactForm = document.getElementById('contact-form');
  
  if (contactForm) {
    contactForm.addEventListener('submit', function(e) {
      e.preventDefault();
      
      // Get form data
      const formData = new FormData(contactForm);
      const data = Object.fromEntries(formData);
      
      // In a real application, you would send this data to your server
      console.log('Form submitted:', data);
      
      // Show success message in the form instead of alert
      const submitButton = contactForm.querySelector('button[type="submit"]');
      const originalText = submitButton.textContent;
      submitButton.textContent = 'Сообщение отправлено!';
      submitButton.disabled = true;
      
      // Reset form after 2 seconds
      setTimeout(() => {
        contactForm.reset();
        submitButton.textContent = originalText;
        submitButton.disabled = false;
      }, 2000);
    });
  }
});

function openModal(html){
  modalBody.innerHTML = html;
  modal.classList.remove('hidden');
}
function closeModal(){
  modal.classList.add('hidden');
  modalBody.innerHTML = '';
}
modalClose.addEventListener('click', closeModal);
modal.addEventListener('click', (e)=>{ if(e.target===modal) closeModal(); });

btnLogin.addEventListener('click', ()=>{
  openModal(`
    <h3>Вход в систему</h3>
    <form id="login-form">
      <label>Электронная почта</label>
      <input name="email" type="email" required placeholder="your@email.com" />
      <label>Пароль</label>
      <input name="password" type="password" required placeholder="••••••••" />
      <button class="btn primary login-submit-btn" type="submit">Войти</button>
      <div class="message" id="login-msg"></div>
    </form>
  `);
  
  // Add the margin-top style via JavaScript to avoid CSP issues
  const loginSubmitBtn = document.querySelector('.login-submit-btn');
  if (loginSubmitBtn) {
    loginSubmitBtn.style.marginTop = '12px';
  }
  
  document.getElementById('login-form').addEventListener('submit', async (e)=>{
    e.preventDefault();
    const f = Object.fromEntries(new FormData(e.target));
    const res = await fetch('./api/login', {method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(f)});
    const j = await res.json();
    if(res.ok) {
      // Store token and user info in localStorage
      localStorage.setItem('color360_token', j.token);
      if (j.user) {
        localStorage.setItem('color360_user', JSON.stringify(j.user));
      }
      // Update UI
      updateUIForUserStatus();
      // Close modal
      closeModal();
      
      // Перенаправляем на соответствующую страницу в зависимости от роли пользователя
      if (j.user && j.user.isAdmin) {
        window.location.href = './admin';
      } else {
        window.location.href = './dashboard';
      }
    } else {
      document.getElementById('login-msg').textContent = j.message || 'Ошибка входа';
    }
  });
});

btnRegister.addEventListener('click', ()=>{
  openModal(`
    <h3>Регистрация</h3>
    <form id="register-form">
      <label>Имя</label>
      <input name="name" required placeholder="Ваше имя" />
      <label>Электронная почта</label>
      <input name="email" type="email" required placeholder="your@email.com" />
      <label>Пароль</label>
      <input name="password" type="password" required placeholder="••••••••" />
      <button class="btn primary register-submit-btn" type="submit">Зарегистрироваться</button>
      <div class="message" id="reg-msg"></div>
    </form>
  `);
  
  // Add the margin-top style via JavaScript to avoid CSP issues
  const registerSubmitBtn = document.querySelector('.register-submit-btn');
  if (registerSubmitBtn) {
    registerSubmitBtn.style.marginTop = '12px';
  }
  
  document.getElementById('register-form').addEventListener('submit', async (e)=>{
    e.preventDefault();
    const f = Object.fromEntries(new FormData(e.target));
    const res = await fetch('./api/register', {method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(f)});
    const j = await res.json();
    
    // Check if there are validation errors
    if (j.errors && Array.isArray(j.errors)) {
      // Display validation errors
      const errorMessages = j.errors.map(error => error.msg).join(', ');
      document.getElementById('reg-msg').textContent = errorMessages;
    } else if (j.message) {
      // Display server message
      document.getElementById('reg-msg').textContent = j.message;
    } else {
      // Fallback message
      document.getElementById('reg-msg').textContent = 'Ошибка регистрации';
    }
    
    if(res.ok) {
      document.getElementById('reg-msg').textContent = 'Готово! Можно войти.';
    }
  });
});

// Load sample news
async function loadNews(){
  try{
    // Using relative path for server compatibility
    const res = await fetch('./api/news');
    const j = await res.json();
    // Check if newsList element exists before trying to modify it
    if (newsList) {
      newsList.innerHTML = '';
      j.forEach(n => {
        const li = document.createElement('li');
        li.innerHTML = `<strong>${n.title}</strong> — <small>${n.date}</small><p>${n.text}</p>`;
        newsList.appendChild(li);
      });
    }
  }catch(e){
    // Check if newsList element exists before trying to modify it
    if (newsList) {
      newsList.innerHTML = '<li>Не удалось загрузить новости.</li>';
    }
    console.error('Error loading news:', e);
  }
}

// Load news on page load
document.addEventListener('DOMContentLoaded', loadNews);

// Smooth scrolling for anchor links
document.addEventListener('DOMContentLoaded', function() {
  // Smooth scrolling for anchor links
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
      const href = this.getAttribute('href');
      
      // If it's a modal trigger or empty hash, don't prevent default
      if (href === '#' || href === '#modal' || this.classList.contains('btn')) {
        return;
      }
      
      e.preventDefault();
      
      const target = document.querySelector(href);
      if (target) {
        window.scrollTo({
          top: target.offsetTop - 80,
          behavior: 'smooth'
        });
      }
    });
  });
});

// Header scroll effect
window.addEventListener('scroll', function() {
  const header = document.querySelector('.site-header');
  if (window.scrollY > 50) {
    header.style.boxShadow = '0 4px 20px rgba(0, 0, 0, 0.1)';
    header.style.background = 'rgba(255, 255, 255, 0.98)';
  } else {
    header.style.boxShadow = '0 2px 10px rgba(0, 0, 0, 0.05)';
    header.style.background = 'rgba(255, 255, 255, 0.95)';
  }
});

// Update UI based on user status when page loads
document.addEventListener('DOMContentLoaded', updateUIForUserStatus);

// Close dropdown when clicking outside
document.addEventListener('click', closeDropdownOutside);