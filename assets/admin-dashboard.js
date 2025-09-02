// Admin Dashboard JavaScript for Color360 (combining admin panel and user dashboard)
const modal = document.getElementById('modal');
const modalBody = document.getElementById('modal-body');
const modalClose = document.getElementById('modal-close');
const btnLogout = document.getElementById('btn-logout');
const btnDeleteAccount = document.getElementById('btn-delete-account');
const btnChangePassword = document.getElementById('btn-change-password');
const refreshUsersBtn = document.getElementById('refresh-users');
const addNewsBtn = document.getElementById('add-news-btn');
const refreshNewsBtn = document.getElementById('refresh-news');

// Get user token from localStorage or redirect to login
const userToken = localStorage.getItem('color360_token');
if (!userToken) {
  window.location.href = './';
}

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

// Function to open modal
function openModal(html) {
  modalBody.innerHTML = html;
  modal.classList.remove('hidden');
}

// Function to close modal
function closeModal() {
  modal.classList.add('hidden');
  modalBody.innerHTML = '';
}

// Event listeners for modal
modalClose.addEventListener('click', closeModal);
modal.addEventListener('click', (e) => {
  if (e.target === modal) closeModal();
});

// Logout functionality
btnLogout.addEventListener('click', () => {
  localStorage.removeItem('color360_token');
  localStorage.removeItem('color360_user');
  window.location.href = './';
});

// Change password functionality
btnChangePassword.addEventListener('click', () => {
  openModal(`
    <h3>Изменение пароля</h3>
    <form id="change-password-form">
      <label>Текущий пароль</label>
      <input name="currentPassword" type="password" required placeholder="••••••••" />
      <label>Новый пароль</label>
      <input name="newPassword" type="password" required placeholder="••••••••" />
      <label>Подтверждение нового пароля</label>
      <input name="confirmPassword" type="password" required placeholder="••••••••" />
      <button class="btn primary change-password-submit-btn" type="submit">Изменить пароль</button>
      <div class="message" id="change-password-msg"></div>
    </form>
  `);
  
  // Add the margin-top style via JavaScript to avoid CSP issues
  const changePasswordSubmitBtn = document.querySelector('.change-password-submit-btn');
  if (changePasswordSubmitBtn) {
    changePasswordSubmitBtn.style.marginTop = '12px';
  }
  
  document.getElementById('change-password-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const formData = new FormData(e.target);
    const data = Object.fromEntries(formData);
    
    if (data.newPassword !== data.confirmPassword) {
      document.getElementById('change-password-msg').textContent = 'Новые пароли не совпадают';
      return;
    }
    
    try {
      const response = await fetch('./api/change-password', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${userToken}`
        },
        body: JSON.stringify({
          currentPassword: data.currentPassword,
          newPassword: data.newPassword
        })
      });
      
      const result = await response.json();
      
      if (response.ok) {
        document.getElementById('change-password-msg').textContent = 'Пароль успешно изменен';
        setTimeout(() => {
          closeModal();
        }, 2000);
      } else {
        document.getElementById('change-password-msg').textContent = result.message || 'Ошибка при изменении пароля';
      }
    } catch (error) {
      document.getElementById('change-password-msg').textContent = 'Ошибка при изменении пароля';
    }
  });
});

// Delete account functionality
btnDeleteAccount.addEventListener('click', () => {
  openModal(`
    <h3>Подтверждение удаления аккаунта</h3>
    <p>Вы уверены, что хотите удалить свой аккаунт? Это действие невозможно отменить.</p>
    <div class="modal-actions">
      <button id="confirm-delete" class="btn danger">Удалить аккаунт</button>
      <button id="cancel-delete" class="btn secondary">Отмена</button>
    </div>
  `);
  
  document.getElementById('confirm-delete').addEventListener('click', async () => {
    try {
      const response = await fetch('./api/delete-account', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${userToken}`
        }
      });
      
      const result = await response.json();
      
      if (response.ok) {
        localStorage.removeItem('color360_token');
        localStorage.removeItem('color360_user');
        openModal(`
          <h3>Аккаунт удален</h3>
          <p>Ваш аккаунт был успешно удален.</p>
          <button id="close-modal" class="btn primary">OK</button>
        `);
        document.getElementById('close-modal').addEventListener('click', () => {
          closeModal();
          window.location.href = './';
        });
      } else {
        openModal(`
          <h3>Ошибка</h3>
          <p>${result.message || 'Ошибка при удалении аккаунта.'}</p>
          <button id="close-modal" class="btn primary">OK</button>
        `);
        document.getElementById('close-modal').addEventListener('click', closeModal);
      }
    } catch (error) {
      openModal(`
        <h3>Ошибка</h3>
        <p>Ошибка при удалении аккаунта.</p>
        <button id="close-modal" class="btn primary">OK</button>
      `);
      document.getElementById('close-modal').addEventListener('click', closeModal);
    }
  });
  
  document.getElementById('cancel-delete').addEventListener('click', closeModal);
});

// Load user profile with subscription info
async function loadUserProfile() {
  try {
    const response = await fetch('./api/profile', {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${userToken}`
      }
    });
    
    if (response.ok) {
      const userData = await response.json();
      document.getElementById('user-name').textContent = userData.name;
      document.getElementById('user-email').textContent = userData.email;
      document.getElementById('user-registered').textContent = new Date(userData.registered).toLocaleDateString('ru-RU');
      
      // Display subscription info
      if (userData.subscription) {
        document.getElementById('subscription-plan').textContent = getPlanName(userData.subscription.plan);
        document.getElementById('subscription-status').textContent = getStatusName(userData.subscription.status);
        document.getElementById('subscription-limit').textContent = userData.subscription.maxEditorSessions === Infinity 
          ? 'Без ограничений' 
          : userData.subscription.maxEditorSessions;
      }
    } else {
      // If unauthorized, redirect to login
      if (response.status === 401) {
        localStorage.removeItem('color360_token');
        localStorage.removeItem('color360_user');
        window.location.href = './';
      }
    }
  } catch (error) {
    console.error('Error loading user profile:', error);
  }
}

// Helper functions for subscription display
function getPlanName(plan) {
  switch(plan) {
    case 'free': return 'Бесплатный';
    case 'professional': return 'Профессионал';
    case 'business': return 'Бизнес';
    default: return plan;
  }
}

function getStatusName(status) {
  switch(status) {
    case 'active': return 'Активна';
    case 'inactive': return 'Неактивна';
    case 'expired': return 'Истекла';
    default: return status;
  }
}

// Load active sessions
async function loadActiveSessions() {
  try {
    const response = await fetch('./api/sessions', {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${userToken}`
      }
    });
    
    if (response.ok) {
      const sessions = await response.json();
      const sessionsListBody = document.getElementById('sessions-list-body');
      const sessionCount = document.getElementById('session-count');
      
      sessionsListBody.innerHTML = '';
      sessionCount.textContent = sessions.length;
      
      sessions.forEach(session => {
        const row = document.createElement('tr');
        row.innerHTML = `
          <td>${session.device || 'Неизвестное устройство'}</td>
          <td>${new Date(session.loginTime).toLocaleString('ru-RU')}</td>
          <td>
            ${session.current ? 
              '<span class="current-session">Текущая</span>' : 
              `<button class="btn small danger terminate-session" data-session-id="${session.id}">Завершить</button>`
            }
          </td>
        `;
        sessionsListBody.appendChild(row);
      });
      
      // Add event listeners to terminate buttons
      document.querySelectorAll('.terminate-session').forEach(button => {
        button.addEventListener('click', async (e) => {
          const sessionId = e.target.getAttribute('data-session-id');
          await terminateSession(sessionId);
        });
      });
    } else {
      // If unauthorized, redirect to login
      if (response.status === 401) {
        localStorage.removeItem('color360_token');
        localStorage.removeItem('color360_user');
        window.location.href = './';
      }
    }
  } catch (error) {
    console.error('Error loading sessions:', error);
  }
}

// Terminate a session
async function terminateSession(sessionId) {
  try {
    const response = await fetch('./api/terminate-session', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${userToken}`
      },
      body: JSON.stringify({ sessionId })
    });
    
    if (response.ok) {
      loadActiveSessions(); // Refresh the sessions list
    } else {
      openModal(`
        <h3>Ошибка</h3>
        <p>Ошибка при завершении сессии.</p>
        <button id="close-modal" class="btn primary">OK</button>
      `);
      document.getElementById('close-modal').addEventListener('click', closeModal);
    }
  } catch (error) {
    openModal(`
      <h3>Ошибка</h3>
      <p>Ошибка при завершении сессии.</p>
      <button id="close-modal" class="btn primary">OK</button>
    `);
    document.getElementById('close-modal').addEventListener('click', closeModal);
  }
}

// Load admin stats
async function loadAdminStats() {
  // Only load admin stats for admin users
  if (!isAdmin) {
    // Hide admin sections for non-admin users
    const adminSections = document.querySelectorAll('.admin-dashboard, .users-table, .news-management');
    adminSections.forEach(section => {
      section.style.display = 'none';
    });
    return;
  }
  
  try {
    const response = await fetch('./api/admin/stats', {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${userToken}`
      }
    });
    
    if (response.ok) {
      const stats = await response.json();
      document.getElementById('total-users').textContent = stats.totalUsers;
      document.getElementById('active-sessions').textContent = stats.activeSessions;
      document.getElementById('user-limit').textContent = stats.userLimit;
      // Remove any existing error messages
      const existingError = document.querySelector('.error-message');
      if (existingError) {
        existingError.remove();
      }
    } else {
      // If unauthorized, redirect to login
      if (response.status === 401 || response.status === 403) {
        localStorage.removeItem('color360_token');
        localStorage.removeItem('color360_user');
        // Remove any existing error messages
        const existingError = document.querySelector('.error-message');
        if (existingError) {
          existingError.remove();
        }
        // Add new error message
        const errorMessage = document.createElement('div');
        errorMessage.className = 'error-message';
        errorMessage.textContent = 'Доступ запрещен. Только для администраторов.';
        document.body.appendChild(errorMessage);
        setTimeout(() => {
          window.location.href = './';
        }, 3000);
      }
    }
  } catch (error) {
    console.error('Error loading admin stats:', error);
  }
}

// Load users list
async function loadUsersList() {
  // Only load users list for admin users
  if (!isAdmin) return;
  
  try {
    const response = await fetch('./api/admin/users', {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${userToken}`
      }
    });
    
    if (response.ok) {
      const users = await response.json();
      const usersListBody = document.getElementById('users-list-body');
      
      usersListBody.innerHTML = '';
      
      users.forEach(user => {
        const row = document.createElement('tr');
        row.innerHTML = `
          <td>${user.name}</td>
          <td>${user.email}</td>
          <td>${new Date(user.registered).toLocaleDateString('ru-RU')}</td>
          <td>${user.sessionCount}</td>
          <td>
            <button class="btn small warning reset-password" data-email="${user.email}">Сброс пароля</button>
            <button class="btn small danger delete-user" data-email="${user.email}">Удалить</button>
          </td>
        `;
        usersListBody.appendChild(row);
      });
      
      // Add event listeners to action buttons
      document.querySelectorAll('.reset-password').forEach(button => {
        button.addEventListener('click', async (e) => {
          const email = e.target.getAttribute('data-email');
          await resetUserPassword(email);
        });
      });
      
      document.querySelectorAll('.delete-user').forEach(button => {
        button.addEventListener('click', async (e) => {
          const email = e.target.getAttribute('data-email');
          await deleteUser(email);
        });
      });
    } else {
      // If unauthorized, redirect to login
      if (response.status === 401 || response.status === 403) {
        localStorage.removeItem('color360_token');
        localStorage.removeItem('color360_user');
        // Remove any existing error messages
        const existingError = document.querySelector('.error-message');
        if (existingError) {
          existingError.remove();
        }
        // Add new error message
        const errorMessage = document.createElement('div');
        errorMessage.className = 'error-message';
        errorMessage.textContent = 'Доступ запрещен. Только для администраторов.';
        document.body.appendChild(errorMessage);
        setTimeout(() => {
          window.location.href = './';
        }, 3000);
      }
    }
  } catch (error) {
    console.error('Error loading users list:', error);
  }
}

// Reset user password
async function resetUserPassword(email) {
  // Only allow for admin users
  if (!isAdmin) return;
  
  // Create a modal for confirmation instead of using confirm dialog
  openModal(`
    <h3>Сброс пароля</h3>
    <p>Вы уверены, что хотите сбросить пароль для пользователя ${email}?</p>
    <div class="modal-actions">
      <button id="confirm-reset" class="btn warning">Сбросить пароль</button>
      <button id="cancel-reset" class="btn secondary">Отмена</button>
    </div>
  `);
  
  document.getElementById('confirm-reset').addEventListener('click', async () => {
    closeModal();
    try {
      const response = await fetch('./api/admin/reset-password', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${userToken}`
        },
        body: JSON.stringify({ email })
      });
      
      if (response.ok) {
        // Show success message in modal instead of alert
        openModal(`
          <h3>Пароль сброшен</h3>
          <p>Пароль успешно сброшен. Новый пароль отправлен пользователю.</p>
          <button id="close-modal" class="btn primary">OK</button>
        `);
        document.getElementById('close-modal').addEventListener('click', () => {
          closeModal();
          loadUsersList(); // Refresh the users list
        });
      } else {
        const result = await response.json();
        // Show error message in modal instead of alert
        openModal(`
          <h3>Ошибка</h3>
          <p>${result.message || 'Ошибка при сбросе пароля.'}</p>
          <button id="close-modal" class="btn primary">OK</button>
        `);
        document.getElementById('close-modal').addEventListener('click', closeModal);
      }
    } catch (error) {
      // Show error message in modal instead of alert
      openModal(`
        <h3>Ошибка</h3>
        <p>Ошибка при сбросе пароля.</p>
        <button id="close-modal" class="btn primary">OK</button>
      `);
      document.getElementById('close-modal').addEventListener('click', closeModal);
    }
  });
  
  document.getElementById('cancel-reset').addEventListener('click', closeModal);
}

// Delete user
async function deleteUser(email) {
  // Only allow for admin users
  if (!isAdmin) return;
  
  // Create a modal for confirmation instead of using confirm dialog
  openModal(`
    <h3>Удаление пользователя</h3>
    <p>Вы уверены, что хотите удалить пользователя ${email}? Это действие невозможно отменить.</p>
    <div class="modal-actions">
      <button id="confirm-delete" class="btn danger">Удалить пользователя</button>
      <button id="cancel-delete" class="btn secondary">Отмена</button>
    </div>
  `);
  
  document.getElementById('confirm-delete').addEventListener('click', async () => {
    closeModal();
    try {
      const response = await fetch('./api/admin/delete-user', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${userToken}`
        },
        body: JSON.stringify({ email })
      });
      
      if (response.ok) {
        // Show success message in modal instead of alert
        openModal(`
          <h3>Пользователь удален</h3>
          <p>Пользователь успешно удален.</p>
          <button id="close-modal" class="btn primary">OK</button>
        `);
        document.getElementById('close-modal').addEventListener('click', () => {
          closeModal();
          loadUsersList(); // Refresh the users list
          loadAdminStats(); // Refresh stats
        });
      } else {
        const result = await response.json();
        // Show error message in modal instead of alert
        openModal(`
          <h3>Ошибка</h3>
          <p>${result.message || 'Ошибка при удалении пользователя.'}</p>
          <button id="close-modal" class="btn primary">OK</button>
        `);
        document.getElementById('close-modal').addEventListener('click', closeModal);
      }
    } catch (error) {
      // Show error message in modal instead of alert
      openModal(`
        <h3>Ошибка</h3>
        <p>Ошибка при удалении пользователя.</p>
        <button id="close-modal" class="btn primary">OK</button>
      `);
      document.getElementById('close-modal').addEventListener('click', closeModal);
    }
  });
  
  document.getElementById('cancel-delete').addEventListener('click', closeModal);
}

// Load news list
async function loadNewsList() {
  try {
    const response = await fetch('./api/news', {
      method: 'GET'
    });
    
    if (response.ok) {
      const newsItems = await response.json();
      const newsListBody = document.getElementById('news-list-body');
      
      newsListBody.innerHTML = '';
      
      newsItems.forEach(news => {
        const row = document.createElement('tr');
        // Truncate text for display
        const truncatedText = news.text.length > 100 ? news.text.substring(0, 100) + '...' : news.text;
        
        row.innerHTML = `
          <td>${news.title}</td>
          <td>${news.date}</td>
          <td>${truncatedText}</td>
          <td>
            ${isAdmin ? 
              `<button class="btn small secondary edit-news" data-id="${news.id}">Редактировать</button>
               <button class="btn small danger delete-news" data-id="${news.id}">Удалить</button>` : 
              ''
            }
          </td>
        `;
        newsListBody.appendChild(row);
      });
      
      // Add event listeners to action buttons (only for admin users)
      if (isAdmin) {
        document.querySelectorAll('.edit-news').forEach(button => {
          button.addEventListener('click', async (e) => {
            const id = e.target.getAttribute('data-id');
            const newsItem = newsItems.find(n => n.id == id);
            if (newsItem) {
              openEditNewsModal(newsItem);
            }
          });
        });
        
        document.querySelectorAll('.delete-news').forEach(button => {
          button.addEventListener('click', async (e) => {
            const id = e.target.getAttribute('data-id');
            await deleteNews(id);
          });
        });
      }
    }
  } catch (error) {
    console.error('Error loading news list:', error);
  }
}

// Open add news modal
function openAddNewsModal() {
  // Only allow for admin users
  if (!isAdmin) return;
  
  openModal(`
    <h3>Добавить новость</h3>
    <form id="add-news-form">
      <label>Заголовок</label>
      <input name="title" type="text" required placeholder="Заголовок новости" />
      <label>Дата</label>
      <input name="date" type="date" required />
      <label>Текст</label>
      <textarea name="text" required placeholder="Текст новости" rows="5"></textarea>
      <button class="btn primary add-news-submit-btn" type="submit">Добавить новость</button>
      <div class="message" id="add-news-msg"></div>
    </form>
  `);
  
  // Set today's date as default
  const today = new Date().toISOString().split('T')[0];
  document.querySelector('input[name="date"]').value = today;
  
  // Add the margin-top style via JavaScript to avoid CSP issues
  const addNewsSubmitBtn = document.querySelector('.add-news-submit-btn');
  if (addNewsSubmitBtn) {
    addNewsSubmitBtn.style.marginTop = '12px';
  }
  
  document.getElementById('add-news-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const formData = new FormData(e.target);
    const data = Object.fromEntries(formData);
    
    try {
      const response = await fetch('./api/admin/news', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${userToken}`
        },
        body: JSON.stringify(data)
      });
      
      const result = await response.json();
      
      if (response.ok) {
        document.getElementById('add-news-msg').textContent = 'Новость добавлена';
        setTimeout(() => {
          closeModal();
          loadNewsList(); // Refresh the news list
        }, 1000);
      } else {
        document.getElementById('add-news-msg').textContent = result.message || 'Ошибка при добавлении новости';
      }
    } catch (error) {
      document.getElementById('add-news-msg').textContent = 'Ошибка при добавлении новости';
    }
  });
}

// Open edit news modal
function openEditNewsModal(newsItem) {
  // Only allow for admin users
  if (!isAdmin) return;
  
  openModal(`
    <h3>Редактировать новость</h3>
    <form id="edit-news-form">
      <input type="hidden" name="id" value="${newsItem.id}" />
      <label>Заголовок</label>
      <input name="title" type="text" required placeholder="Заголовок новости" value="${newsItem.title}" />
      <label>Дата</label>
      <input name="date" type="date" required value="${newsItem.date}" />
      <label>Текст</label>
      <textarea name="text" required placeholder="Текст новости" rows="5">${newsItem.text}</textarea>
      <button class="btn primary edit-news-submit-btn" type="submit">Сохранить изменения</button>
      <div class="message" id="edit-news-msg"></div>
    </form>
  `);
  
  // Add the margin-top style via JavaScript to avoid CSP issues
  const editNewsSubmitBtn = document.querySelector('.edit-news-submit-btn');
  if (editNewsSubmitBtn) {
    editNewsSubmitBtn.style.marginTop = '12px';
  }
  
  document.getElementById('edit-news-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const formData = new FormData(e.target);
    const data = Object.fromEntries(formData);
    const id = data.id;
    
    try {
      const response = await fetch(`./api/admin/news/${id}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${userToken}`
        },
        body: JSON.stringify({
          title: data.title,
          date: data.date,
          text: data.text
        })
      });
      
      const result = await response.json();
      
      if (response.ok) {
        document.getElementById('edit-news-msg').textContent = 'Новость обновлена';
        setTimeout(() => {
          closeModal();
          loadNewsList(); // Refresh the news list
        }, 1000);
      } else {
        document.getElementById('edit-news-msg').textContent = result.message || 'Ошибка при обновлении новости';
      }
    } catch (error) {
      document.getElementById('edit-news-msg').textContent = 'Ошибка при обновлении новости';
    }
  });
}

// Delete news
async function deleteNews(id) {
  // Only allow for admin users
  if (!isAdmin) return;
  
  // Create a modal for confirmation
  openModal(`
    <h3>Удаление новости</h3>
    <p>Вы уверены, что хотите удалить эту новость? Это действие невозможно отменить.</p>
    <div class="modal-actions">
      <button id="confirm-delete-news" class="btn danger">Удалить новость</button>
      <button id="cancel-delete-news" class="btn secondary">Отмена</button>
    </div>
  `);
  
  document.getElementById('confirm-delete-news').addEventListener('click', async () => {
    closeModal();
    try {
      const response = await fetch(`./api/admin/news/${id}`, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${userToken}`
        }
      });
      
      if (response.ok) {
        loadNewsList(); // Refresh the news list
      } else {
        const result = await response.json();
        openModal(`
          <h3>Ошибка</h3>
          <p>${result.message || 'Ошибка при удалении новости.'}</p>
          <button id="close-modal" class="btn primary">OK</button>
        `);
        document.getElementById('close-modal').addEventListener('click', closeModal);
      }
    } catch (error) {
      openModal(`
        <h3>Ошибка</h3>
        <p>Ошибка при удалении новости.</p>
        <button id="close-modal" class="btn primary">OK</button>
      `);
      document.getElementById('close-modal').addEventListener('click', closeModal);
    }
  });
  
  document.getElementById('cancel-delete-news').addEventListener('click', closeModal);
}

// Load editor sessions
async function loadEditorSessions() {
  try {
    const response = await fetch('./api/editor-sessions', {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${userToken}`
      }
    });
    
    if (response.ok) {
      const sessions = await response.json();
      const sessionsListBody = document.getElementById('editor-sessions-list-body');
      const sessionCount = document.getElementById('editor-session-count');
      
      sessionsListBody.innerHTML = '';
      sessionCount.textContent = sessions.length;
      
      sessions.forEach(session => {
        const row = document.createElement('tr');
        row.innerHTML = `
          <td>${session.name}</td>
          <td>${new Date(session.created).toLocaleString('ru-RU')}</td>
          <td>${new Date(session.lastAccessed).toLocaleString('ru-RU')}</td>
          <td>
            <button class="btn small secondary restore-session" data-session-id="${session.id}">Восстановить</button>
            <button class="btn small warning rename-session" data-session-id="${session.id}">Переименовать</button>
            <button class="btn small danger delete-session" data-session-id="${session.id}">Удалить</button>
          </td>
        `;
        sessionsListBody.appendChild(row);
      });
      
      // Add event listeners
      document.querySelectorAll('.restore-session').forEach(button => {
        button.addEventListener('click', async (e) => {
          const sessionId = e.target.getAttribute('data-session-id');
          await restoreEditorSession(sessionId);
        });
      });
      
      document.querySelectorAll('.rename-session').forEach(button => {
        button.addEventListener('click', async (e) => {
          const sessionId = e.target.getAttribute('data-session-id');
          await renameEditorSession(sessionId);
        });
      });
      
      document.querySelectorAll('.delete-session').forEach(button => {
        button.addEventListener('click', async (e) => {
          const sessionId = e.target.getAttribute('data-session-id');
          await deleteEditorSession(sessionId);
        });
      });
    } else {
      // If unauthorized, redirect to login
      if (response.status === 401) {
        localStorage.removeItem('color360_token');
        localStorage.removeItem('color360_user');
        window.location.href = './';
      }
    }
  } catch (error) {
    console.error('Error loading editor sessions:', error);
  }
}

// Create new editor session
async function createEditorSession() {
  try {
    const sessionName = prompt('Введите название новой сессии:', `Сессия ${new Date().toLocaleString('ru-RU')}`);
    if (!sessionName) return;
    
    const response = await fetch('./api/editor-sessions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${userToken}`
      },
      body: JSON.stringify({ name: sessionName })
    });
    
    const result = await response.json();
    
    if (response.ok) {
      loadEditorSessions(); // Refresh the sessions list
    } else {
      openModal(`
        <h3>Ошибка</h3>
        <p>${result.message || 'Ошибка при создании сессии.'}</p>
        <button id="close-modal" class="btn primary">OK</button>
      `);
      document.getElementById('close-modal').addEventListener('click', closeModal);
    }
  } catch (error) {
    openModal(`
      <h3>Ошибка</h3>
      <p>Ошибка при создании сессии.</p>
      <button id="close-modal" class="btn primary">OK</button>
    `);
    document.getElementById('close-modal').addEventListener('click', closeModal);
  }
}

// Restore editor session
async function restoreEditorSession(sessionId) {
  try {
    const response = await fetch(`./api/editor-sessions/${sessionId}/restore`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${userToken}`
      }
    });
    
    const result = await response.json();
    
    if (response.ok) {
      openModal(`
        <h3>Сессия восстановлена</h3>
        <p>Сессия "${result.session.name}" готова к работе.</p>
        <button id="close-modal" class="btn primary">OK</button>
      `);
      document.getElementById('close-modal').addEventListener('click', closeModal);
    } else {
      openModal(`
        <h3>Ошибка</h3>
        <p>${result.message || 'Ошибка при восстановлении сессии.'}</p>
        <button id="close-modal" class="btn primary">OK</button>
      `);
      document.getElementById('close-modal').addEventListener('click', closeModal);
    }
  } catch (error) {
    openModal(`
      <h3>Ошибка</h3>
      <p>Ошибка при восстановлении сессии.</p>
      <button id="close-modal" class="btn primary">OK</button>
    `);
    document.getElementById('close-modal').addEventListener('click', closeModal);
  }
}

// Rename editor session
async function renameEditorSession(sessionId) {
  try {
    const newName = prompt('Введите новое название сессии:');
    if (!newName) return;
    
    const response = await fetch(`./api/editor-sessions/${sessionId}`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${userToken}`
      },
      body: JSON.stringify({ name: newName })
    });
    
    const result = await response.json();
    
    if (response.ok) {
      loadEditorSessions(); // Refresh the sessions list
    } else {
      openModal(`
        <h3>Ошибка</h3>
        <p>${result.message || 'Ошибка при переименовании сессии.'}</p>
        <button id="close-modal" class="btn primary">OK</button>
      `);
      document.getElementById('close-modal').addEventListener('click', closeModal);
    }
  } catch (error) {
    openModal(`
      <h3>Ошибка</h3>
      <p>Ошибка при переименовании сессии.</p>
      <button id="close-modal" class="btn primary">OK</button>
    `);
    document.getElementById('close-modal').addEventListener('click', closeModal);
  }
}

// Delete editor session
async function deleteEditorSession(sessionId) {
  if (!confirm('Вы уверены, что хотите удалить эту сессию? Это действие нельзя отменить.')) {
    return;
  }
  
  try {
    const response = await fetch(`./api/editor-sessions/${sessionId}`, {
      method: 'DELETE',
      headers: {
        'Authorization': `Bearer ${userToken}`
      }
    });
    
    if (response.ok) {
      loadEditorSessions(); // Refresh the sessions list
    } else {
      const result = await response.json();
      openModal(`
        <h3>Ошибка</h3>
        <p>${result.message || 'Ошибка при удалении сессии.'}</p>
        <button id="close-modal" class="btn primary">OK</button>
      `);
      document.getElementById('close-modal').addEventListener('click', closeModal);
    }
  } catch (error) {
    openModal(`
      <h3>Ошибка</h3>
      <p>Ошибка при удалении сессии.</p>
      <button id="close-modal" class="btn primary">OK</button>
    `);
    document.getElementById('close-modal').addEventListener('click', closeModal);
  }
}

// Load admin subscriptions (admin only)
async function loadAdminSubscriptions() {
  // Only load for admin users
  if (!isAdmin) return;
  
  try {
    const response = await fetch('./api/admin/subscriptions', {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${userToken}`
      }
    });
    
    if (response.ok) {
      const subscriptions = await response.json();
      const subscriptionsListBody = document.getElementById('subscriptions-list-body');
      
      subscriptionsListBody.innerHTML = '';
      
      subscriptions.forEach(sub => {
        const row = document.createElement('tr');
        row.innerHTML = `
          <td>${sub.user}</td>
          <td>${sub.email}</td>
          <td>${getPlanName(sub.plan)}</td>
          <td>${getStatusName(sub.status)}</td>
          <td>${sub.maxEditorSessions === Infinity ? 'Без ограничений' : sub.maxEditorSessions}</td>
          <td>
            <button class="btn small secondary edit-subscription" data-email="${sub.email}">Изменить</button>
          </td>
        `;
        subscriptionsListBody.appendChild(row);
      });
      
      // Add event listeners
      document.querySelectorAll('.edit-subscription').forEach(button => {
        button.addEventListener('click', async (e) => {
          const email = e.target.getAttribute('data-email');
          const subscription = subscriptions.find(s => s.email === email);
          await editSubscription(email, subscription);
        });
      });
    } else {
      // If unauthorized, redirect to login
      if (response.status === 401 || response.status === 403) {
        localStorage.removeItem('color360_token');
        localStorage.removeItem('color360_user');
        // Remove any existing error messages
        const existingError = document.querySelector('.error-message');
        if (existingError) {
          existingError.remove();
        }
        // Add new error message
        const errorMessage = document.createElement('div');
        errorMessage.className = 'error-message';
        errorMessage.textContent = 'Доступ запрещен. Только для администраторов.';
        document.body.appendChild(errorMessage);
        setTimeout(() => {
          window.location.href = './';
        }, 3000);
      }
    }
  } catch (error) {
    console.error('Error loading subscriptions:', error);
  }
}

// Edit subscription
async function editSubscription(email, subscription) {
  // Only allow for admin users
  if (!isAdmin) return;
  
  openModal(`
    <h3>Изменить подписку</h3>
    <form id="edit-subscription-form">
      <input type="hidden" name="email" value="${email}" />
      <label>План</label>
      <select name="plan" required>
        <option value="free" ${subscription.plan === 'free' ? 'selected' : ''}>Бесплатный</option>
        <option value="professional" ${subscription.plan === 'professional' ? 'selected' : ''}>Профессионал</option>
        <option value="business" ${subscription.plan === 'business' ? 'selected' : ''}>Бизнес</option>
      </select>
      <label>Статус</label>
      <select name="status" required>
        <option value="active" ${subscription.status === 'active' ? 'selected' : ''}>Активна</option>
        <option value="inactive" ${subscription.status === 'inactive' ? 'selected' : ''}>Неактивна</option>
        <option value="expired" ${subscription.status === 'expired' ? 'selected' : ''}>Истекла</option>
      </select>
      <label>Максимум сессий редактора</label>
      <input name="maxEditorSessions" type="number" min="1" value="${subscription.maxEditorSessions === Infinity ? 100 : subscription.maxEditorSessions}" required />
      <button class="btn primary edit-subscription-submit-btn" type="submit">Сохранить</button>
      <div class="message" id="edit-subscription-msg"></div>
    </form>
  `);
  
  // Add the margin-top style via JavaScript to avoid CSP issues
  const editSubscriptionSubmitBtn = document.querySelector('.edit-subscription-submit-btn');
  if (editSubscriptionSubmitBtn) {
    editSubscriptionSubmitBtn.style.marginTop = '12px';
  }
  
  document.getElementById('edit-subscription-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const formData = new FormData(e.target);
    const data = Object.fromEntries(formData);
    
    // Convert maxEditorSessions to Infinity if business plan
    if (data.plan === 'business') {
      data.maxEditorSessions = 100; // Will be converted to Infinity on server
    } else {
      data.maxEditorSessions = parseInt(data.maxEditorSessions);
    }
    
    try {
      const response = await fetch('./api/admin/subscriptions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${userToken}`
        },
        body: JSON.stringify(data)
      });
      
      const result = await response.json();
      
      if (response.ok) {
        document.getElementById('edit-subscription-msg').textContent = 'Подписка обновлена';
        setTimeout(() => {
          closeModal();
          loadAdminSubscriptions(); // Refresh the subscriptions list
          // Also refresh user profile if this is the current user
          if (email === localStorage.getItem('color360_user')?.email) {
            loadUserProfile();
          }
        }, 1000);
      } else {
        document.getElementById('edit-subscription-msg').textContent = result.message || 'Ошибка при обновлении подписки';
      }
    } catch (error) {
      document.getElementById('edit-subscription-msg').textContent = 'Ошибка при обновлении подписки';
    }
  });
}

// Event listener for refresh button (only for admin users)
if (isAdmin && refreshUsersBtn) {
  refreshUsersBtn.addEventListener('click', () => {
    loadUsersList();
    loadAdminStats();
  });
}

// Event listener for refresh subscriptions button (only for admin users)
const refreshSubscriptionsBtn = document.getElementById('refresh-subscriptions');
if (isAdmin && refreshSubscriptionsBtn) {
  refreshSubscriptionsBtn.addEventListener('click', loadAdminSubscriptions);
}

// Event listener for add news button (only for admin users)
if (isAdmin && addNewsBtn) {
  addNewsBtn.addEventListener('click', openAddNewsModal);
}

// Event listener for refresh news button
if (refreshNewsBtn) {
  refreshNewsBtn.addEventListener('click', loadNewsList);
}

// Add event listener for create session button
document.getElementById('create-session').addEventListener('click', createEditorSession);

// Load data when page loads
document.addEventListener('DOMContentLoaded', () => {
  // Load user dashboard data
  loadUserProfile();
  loadActiveSessions();
  loadEditorSessions(); // Load editor sessions
  
  // Load admin panel data (will be hidden for non-admin users)
  loadAdminStats();
  loadUsersList();
  loadNewsList();
  loadAdminSubscriptions(); // Load subscriptions
});