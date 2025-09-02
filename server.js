// Simple Node.js + Express backend for demo site
const express = require('express');
const path = require('path');
const bodyParser = require('body-parser');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');
const cookieParser = require('cookie-parser');
const { body, validationResult } = require('express-validator');
const app = express();
const PORT = process.env.PORT || 3000;

// JWT Secret Key - in production this should be set as an environment variable
const JWT_SECRET = process.env.JWT_SECRET || 'color360-super-secure-jwt-secret-key-2025';

// Security headers
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", "'unsafe-inline'", "'unsafe-eval'", "https://aframe.io", "https://cdnjs.cloudflare.com"],
      styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"],
      fontSrc: ["'self'", "https://fonts.gstatic.com"],
      imgSrc: ["'self'", "https://images.unsplash.com", "data:", "https:", "http:"],
      mediaSrc: ["'self'"]
    }
  }
}));

// Parse cookies
app.use(cookieParser());

// Rate limiting
const apiLimiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 15 * 60 * 1000, // 15 minutes
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 100, // Limit each IP to 100 requests per window
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Слишком много запросов, пожалуйста, повторите попытку позже.' }
});

// Apply rate limiting to all API routes
app.use('/api/', apiLimiter);

// More strict rate limiting for authentication routes
const authLimiter = rateLimit({
  windowMs: parseInt(process.env.AUTH_RATE_LIMIT_WINDOW_MS) || 60 * 60 * 1000, // 1 hour window
  max: parseInt(process.env.AUTH_RATE_LIMIT_MAX_ATTEMPTS) || 10, // 10 attempts per hour
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Слишком много попыток входа, пожалуйста, повторите позже.' }
});

// Apply stricter rate limiting to login/register endpoints
app.use('/api/login', authLimiter);
app.use('/api/register', authLimiter);

// Serve static files from the root directory
app.use(express.static(path.join(__dirname), {
  setHeaders: (res, path) => {
    // Set secure headers for static files
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-XSS-Protection', '1; mode=block');
    // More permissive CSP for static files to allow images and videos
    res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://aframe.io https://cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' https://images.unsplash.com data: https: http:; media-src 'self';");
    
    // Set proper MIME type for MP4 files
    if (path.endsWith('.mp4')) {
      res.setHeader('Content-Type', 'video/mp4');
    }
  }
}));

// Serve static files from the pano directory
app.use('/pano', express.static(path.join(__dirname, 'pano'), {
  setHeaders: (res, path) => {
    // Set secure headers for pano static files
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-XSS-Protection', '1; mode=block');
    // More permissive CSP for pano app to allow required external resources
    res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://aframe.io https://cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' https://images.unsplash.com data: https: http:; media-src 'self';");
  }
}));

// For API routes under /pano subpath, we need to handle that as well
// But for the main site, we serve from root
app.use(bodyParser.json({ limit: '10kb' })); // Limit payload size

// In-memory user store (demo only)
// Limit to 100 users as requested
const users = {};
const MAX_USERS = 100;

// In-memory storage for user subscriptions and editor sessions
const userSubscriptions = {};
const editorSessions = {};

// In-memory session store
const sessions = {};

// In-memory news store
let newsItems = [
  {id: 1, title:'Запуск демо-платформы', date:'2025-08-31', text:'Привет! Это демонстрационная новость.'},
  {id: 2, title:'Новый функционал редактора', date:'2025-08-25', text:'Добавлены инструменты для управления сценами и хотспотами.'}
];

// Admin user (for demo purposes)
const ADMIN_EMAIL = 'admin@color360.online';
const ADMIN_PASSWORD = 'admin123';

// Initialize admin user with subscription
// Initialize admin user with hashed password
const adminPasswordHash = bcrypt.hashSync(ADMIN_PASSWORD, 10);
users[ADMIN_EMAIL] = {
  name: 'Администратор',
  email: ADMIN_EMAIL,
  password: adminPasswordHash,
  registered: new Date().toISOString(),
  isAdmin: true
};

// Initialize admin subscription (unlimited)
userSubscriptions[ADMIN_EMAIL] = {
  plan: 'business',
  status: 'active',
  startDate: new Date().toISOString(),
  endDate: null, // No end date for admin
  maxEditorSessions: Infinity
};

// Helper function to create JWT token
function makeToken(email){
  // Create a token with 1 hour expiration
  return jwt.sign({ email }, JWT_SECRET, { expiresIn: '1h' });
}

// Helper function to get plan name
function getPlanName(plan) {
  switch(plan) {
    case 'free': return 'Бесплатный';
    case 'professional': return 'Профессионал';
    case 'business': return 'Бизнес';
    default: return plan;
  }
}

// Helper function to get status name
function getStatusName(status) {
  switch(status) {
    case 'active': return 'Активна';
    case 'inactive': return 'Неактивна';
    case 'expired': return 'Истекла';
    default: return status;
  }
}

// Middleware to authenticate user with JWT
function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN
  
  if (!token) {
    return res.status(401).json({ message: 'Токен не предоставлен' });
  }
  
  jwt.verify(token, JWT_SECRET, (err, decoded) => {
    if (err || !decoded?.email) {
      // Token verification failed
      return res.status(403).json({ message: 'Неверный или просроченный токен' });
    }
    
    // Check if user exists
    const user = users[decoded.email];
    if (!user) {
      return res.status(403).json({ message: 'Пользователь не найден' });
    }
    
    req.user = { email: decoded.email, token };
    next();
  });
}

// Middleware to check if user is admin
function authenticateAdmin(req, res, next) {
  // First authenticate the token
  authenticateToken(req, res, () => {
    // If we reach this point, authentication was successful
    // Now check if user is admin
    const user = users[req.user.email];
    if (!user || !user.isAdmin) {
      return res.status(403).json({ message: 'Доступ запрещен. Только для администраторов.' });
    }
    next();
  });
}

// Register endpoint with user limit and validation
app.post('/api/register', [
  // Input validation
  body('email').isEmail().normalizeEmail().withMessage('Неверный формат email'),
  body('password').isLength({ min: 8 }).withMessage('Пароль должен быть минимум 8 символов'),
  body('name').trim().notEmpty().withMessage('Имя обязательно')
], async (req, res) => {
  // Check validation errors
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ errors: errors.array() });
  }
  
  const {name, email, password} = req.body || {};
  
  try {
    // Check user limit
    if (Object.keys(users).length >= MAX_USERS) {
      return res.status(400).json({message:'Достигнут лимит количества пользователей. Регистрация временно недоступна.'});
    }
    
    if(users[email]) {
      return res.status(400).json({message:'Пользователь уже зарегистрирован'});
    }
    
    // Hash the password before saving
    const hashedPassword = await bcrypt.hash(password, 10);
    
    users[email] = {
      name, 
      email, 
      password: hashedPassword, 
      registered: new Date().toISOString(),
      isAdmin: false
    };
    
    // Create JWT token
    const token = makeToken(email);
    
    // Create initial session
    sessions[email] = sessions[email] || [];
    sessions[email].push({
      id: token,
      loginTime: new Date().toISOString(),
      device: req.headers['user-agent'] || 'Неизвестное устройство'
    });
    
    // Initialize subscription
    userSubscriptions[email] = {
      plan: 'free',
      status: 'active',
      startDate: new Date().toISOString(),
      endDate: null,
      maxEditorSessions: 3
    };
    
    return res.status(201).json({message:'ok', token});
  } catch (error) {
    console.error('Registration error:', error);
    return res.status(500).json({message:'Ошибка регистрации'});
  }
});

// Login endpoint with secure authentication
app.post('/api/login', [
  // Input validation
  body('email').isEmail().normalizeEmail().withMessage('Неверный формат email'),
  body('password').notEmpty().withMessage('Пароль обязателен')
], async (req, res) => {
  // Check validation errors
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ errors: errors.array() });
  }
  
  const {email, password} = req.body || {};
  
  try {
    const user = users[email];
    if (!user) {
      // Use same error message for both email and password errors to prevent user enumeration
      return res.status(401).json({message:'Неверные учетные данные'});
    }
    
    // Compare password with hashed version
    const validPassword = await bcrypt.compare(password, user.password);
    if (!validPassword) {
      // Add delay to prevent timing attacks
      await new Promise(resolve => setTimeout(resolve, 1000));
      return res.status(401).json({message:'Неверные учетные данные'});
    }
    
    // Create JWT token
    const token = makeToken(email);
    
    // Manage sessions - limit to 3 active sessions per user
    sessions[email] = sessions[email] || [];
    if (sessions[email].length >= 3) {
      // Remove oldest session
      sessions[email].shift();
    }
    
    // Add new session
    sessions[email].push({
      id: token,
      loginTime: new Date().toISOString(),
      device: req.headers['user-agent'] || 'Неизвестное устройство',
      ip: req.ip || req.headers['x-forwarded-for'] || 'Неизвестный IP'
    });
    
    // Set HttpOnly cookie for extra security
    res.cookie('auth_token', token, {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'strict',
      maxAge: 3600000 // 1 hour
    });
    
    // Initialize subscription for new users
    if (!userSubscriptions[email]) {
      userSubscriptions[email] = {
        plan: 'free',
        status: 'active',
        startDate: new Date().toISOString(),
        endDate: null,
        maxEditorSessions: 3
      };
    }
    
    return res.json({
      message: 'ok', 
      token,
      user: {
        name: user.name,
        email: user.email,
        isAdmin: user.isAdmin || false
      }
    });
  } catch (error) {
    console.error('Login error:', error);
    return res.status(500).json({message:'Ошибка входа в систему'});
  }
});

app.post('/api/demo', (req, res) => {
  try {
    // Create a demo token with limited permissions
    const token = jwt.sign({ email: 'demo@color360.online', isDemo: true }, JWT_SECRET, { expiresIn: '4h' });
    
    // Demo behaviour: return token and a suggested link to the local pano app
    return res.json({message:'demo issued', token, app:'/pano'});
  } catch (error) {
    console.error('Demo error:', error);
    return res.status(500).json({message:'Ошибка создания демо-доступа'});
  }
});

// Get all news
app.get('/api/news', (req, res) => {
  return res.json(newsItems);
});

// Add news (admin only)
app.post('/api/admin/news', authenticateAdmin, (req, res) => {
  const { title, date, text } = req.body;
  
  if (!title || !date || !text) {
    return res.status(400).json({ message: 'Заголовок, дата и текст обязательны' });
  }
  
  const newNews = {
    id: newsItems.length > 0 ? Math.max(...newsItems.map(n => n.id)) + 1 : 1,
    title,
    date,
    text
  };
  
  newsItems.push(newNews);
  
  return res.status(201).json({ message: 'Новость добавлена', news: newNews });
});

// Update news (admin only)
app.put('/api/admin/news/:id', authenticateAdmin, (req, res) => {
  const id = parseInt(req.params.id);
  const { title, date, text } = req.body;
  
  if (!title || !date || !text) {
    return res.status(400).json({ message: 'Заголовок, дата и текст обязательны' });
  }
  
  const newsIndex = newsItems.findIndex(n => n.id === id);
  
  if (newsIndex === -1) {
    return res.status(404).json({ message: 'Новость не найдена' });
  }
  
  newsItems[newsIndex] = { id, title, date, text };
  
  return res.json({ message: 'Новость обновлена', news: newsItems[newsIndex] });
});

// Delete news (admin only)
app.delete('/api/admin/news/:id', authenticateAdmin, (req, res) => {
  const id = parseInt(req.params.id);
  const newsIndex = newsItems.findIndex(n => n.id === id);
  
  if (newsIndex === -1) {
    return res.status(404).json({ message: 'Новость не найдена' });
  }
  
  newsItems.splice(newsIndex, 1);
  
  return res.json({ message: 'Новость удалена' });
});

// New endpoints for dashboard functionality

// Get user profile with subscription info
app.get('/api/profile', authenticateToken, (req, res) => {
  const user = users[req.user.email];
  if (!user) {
    return res.status(404).json({ message: 'Пользователь не найден' });
  }
  
  const subscription = userSubscriptions[req.user.email] || {
    plan: 'free',
    status: 'active',
    startDate: user.registered,
    endDate: null,
    maxEditorSessions: 3
  };
  
  return res.json({
    name: user.name,
    email: user.email,
    registered: user.registered,
    isAdmin: user.isAdmin || false,
    subscription: subscription
  });
});

// Get user editor sessions
app.get('/api/editor-sessions', authenticateToken, (req, res) => {
  const userSessions = editorSessions[req.user.email] || [];
  
  return res.json(userSessions);
});

// Create new editor session
app.post('/api/editor-sessions', authenticateToken, (req, res) => {
  const userEmail = req.user.email;
  const user = users[userEmail];
  const subscription = userSubscriptions[userEmail] || {
    plan: 'free',
    status: 'active',
    maxEditorSessions: 3
  };
  
  // Check session limit
  const userSessions = editorSessions[userEmail] || [];
  if (userSessions.length >= subscription.maxEditorSessions) {
    return res.status(400).json({ 
      message: `Достигнут лимит сессий редактора (${subscription.maxEditorSessions})` 
    });
  }
  
  // Create new session
  const newSession = {
    id: Date.now().toString(),
    name: req.body.name || `Сессия ${userSessions.length + 1}`,
    created: new Date().toISOString(),
    lastAccessed: new Date().toISOString(),
    data: req.body.data || {}
  };
  
  if (!editorSessions[userEmail]) {
    editorSessions[userEmail] = [];
  }
  
  editorSessions[userEmail].push(newSession);
  
  return res.status(201).json({ 
    message: 'Сессия создана', 
    session: newSession 
  });
});

// Update editor session
app.put('/api/editor-sessions/:id', authenticateToken, (req, res) => {
  const userEmail = req.user.email;
  const sessionId = req.params.id;
  
  const userSessions = editorSessions[userEmail] || [];
  const sessionIndex = userSessions.findIndex(s => s.id === sessionId);
  
  if (sessionIndex === -1) {
    return res.status(404).json({ message: 'Сессия не найдена' });
  }
  
  // Update session
  userSessions[sessionIndex] = {
    ...userSessions[sessionIndex],
    ...req.body,
    lastAccessed: new Date().toISOString()
  };
  
  return res.json({ 
    message: 'Сессия обновлена', 
    session: userSessions[sessionIndex] 
  });
});

// Delete editor session
app.delete('/api/editor-sessions/:id', authenticateToken, (req, res) => {
  const userEmail = req.user.email;
  const sessionId = req.params.id;
  
  const userSessions = editorSessions[userEmail] || [];
  const sessionIndex = userSessions.findIndex(s => s.id === sessionId);
  
  if (sessionIndex === -1) {
    return res.status(404).json({ message: 'Сессия не найдена' });
  }
  
  userSessions.splice(sessionIndex, 1);
  
  return res.json({ message: 'Сессия удалена' });
});

// Restore editor session
app.post('/api/editor-sessions/:id/restore', authenticateToken, (req, res) => {
  const userEmail = req.user.email;
  const sessionId = req.params.id;
  
  const userSessions = editorSessions[userEmail] || [];
  const session = userSessions.find(s => s.id === sessionId);
  
  if (!session) {
    return res.status(404).json({ message: 'Сессия не найдена' });
  }
  
  // Update last accessed time
  session.lastAccessed = new Date().toISOString();
  
  return res.json({ 
    message: 'Сессия восстановлена', 
    session: session 
  });
});

// Get user sessions
app.get('/api/sessions', authenticateToken, (req, res) => {
  const userSessions = sessions[req.user.email] || [];
  
  // Add current session flag
  const sessionsWithCurrent = userSessions.map(session => ({
    ...session,
    current: session.id === req.user.token
  }));
  
  return res.json(sessionsWithCurrent);
});

// Terminate a session
app.post('/api/terminate-session', authenticateToken, (req, res) => {
  const { sessionId } = req.body;
  const userEmail = req.user.email;
  
  if (!sessionId) {
    return res.status(400).json({ message: 'ID сессии обязателен' });
  }
  
  // Cannot terminate current session
  if (sessionId === req.user.token) {
    return res.status(400).json({ message: 'Нельзя завершить текущую сессию' });
  }
  
  // Find and remove session
  if (sessions[userEmail]) {
    sessions[userEmail] = sessions[userEmail].filter(session => session.id !== sessionId);
    return res.json({ message: 'Сессия завершена' });
  }
  
  return res.status(404).json({ message: 'Сессия не найдена' });
});

// Change password endpoint with validation
app.post('/api/change-password', [
  body('currentPassword').notEmpty().withMessage('Текущий пароль обязателен'),
  body('newPassword').isLength({ min: 8 }).withMessage('Новый пароль должен содержать минимум 8 символов')
], authenticateToken, async (req, res) => {
  // Check validation errors
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ errors: errors.array() });
  }
  
  const { currentPassword, newPassword } = req.body;
  const userEmail = req.user.email;
  
  try {
    const user = users[userEmail];
    
    if (!user) {
      return res.status(404).json({ message: 'Пользователь не найден' });
    }
    
    // Verify current password
    const validPassword = await bcrypt.compare(currentPassword, user.password);
    if (!validPassword) {
      return res.status(400).json({ message: 'Неверный текущий пароль' });
    }
    
    // Hash the new password
    const hashedPassword = await bcrypt.hash(newPassword, 10);
    
    // Update password
    users[userEmail].password = hashedPassword;
    
    // Terminate all sessions except current one
    if (sessions[userEmail]) {
      sessions[userEmail] = sessions[userEmail].filter(session => session.id === req.user.token);
    }
    
    return res.json({ message: 'Пароль успешно изменен' });
  } catch (error) {
    console.error('Change password error:', error);
    return res.status(500).json({ message: 'Ошибка при изменении пароля' });
  }
});

// Delete account with additional security
app.post('/api/delete-account', authenticateToken, async (req, res) => {
  const userEmail = req.user.email;
  
  try {
    // Prevent admin deletion via this endpoint
    if (userEmail === ADMIN_EMAIL) {
      return res.status(403).json({ message: 'Нельзя удалить аккаунт администратора' });
    }
    
    // Require confirmation password for account deletion
    const { password } = req.body;
    if (!password) {
      return res.status(400).json({ message: 'Для удаления аккаунта требуется подтверждение пароля' });
    }
    
    const user = users[userEmail];
    if (!user) {
      return res.status(404).json({ message: 'Пользователь не найден' });
    }
    
    // Verify password
    const validPassword = await bcrypt.compare(password, user.password);
    if (!validPassword) {
      return res.status(403).json({ message: 'Неверный пароль' });
    }
    
    // Remove user
    delete users[userEmail];
    
    // Remove all sessions
    delete sessions[userEmail];
    
    return res.json({ message: 'Аккаунт удален' });
  } catch (error) {
    console.error('Delete account error:', error);
    return res.status(500).json({ message: 'Ошибка при удалении аккаунта' });
  }
});

// Get admin stats (admin only)
app.get('/api/admin/stats', authenticateAdmin, (req, res) => {
  try {
    const totalUsers = Object.keys(users).length;
    let activeSessions = 0;
    
    // Count active sessions
    for (const userEmail in sessions) {
      if (sessions[userEmail]) {
        activeSessions += sessions[userEmail].length;
      }
    }
    
    return res.json({
      totalUsers,
      activeSessions,
      userLimit: MAX_USERS
    });
  } catch (error) {
    console.error('Admin stats error:', error);
    return res.status(500).json({ message: 'Ошибка при получении статистики' });
  }
});

// Get all users (admin only)
app.get('/api/admin/users', authenticateAdmin, (req, res) => {
  try {
    const userList = Object.values(users).map(user => ({
      name: user.name,
      email: user.email,
      registered: user.registered,
      sessionCount: sessions[user.email] ? sessions[user.email].length : 0
    }));
    
    return res.json(userList);
  } catch (error) {
    console.error('Get users error:', error);
    return res.status(500).json({ message: 'Ошибка при получении списка пользователей' });
  }
});

// Get subscription info (admin only)
app.get('/api/admin/subscriptions', authenticateAdmin, (req, res) => {
  try {
    const subscriptionList = Object.keys(userSubscriptions).map(email => ({
      email: email,
      user: users[email].name,
      planName: getPlanName(userSubscriptions[email].plan),
      statusName: getStatusName(userSubscriptions[email].status),
      ...userSubscriptions[email]
    }));
    
    return res.json(subscriptionList);
  } catch (error) {
    console.error('Get subscriptions error:', error);
    return res.status(500).json({ message: 'Ошибка при получении информации о подписках' });
  }
});

// Update user subscription (admin only)
app.post('/api/admin/subscriptions', authenticateAdmin, (req, res) => {
  const { email, plan, status, maxEditorSessions } = req.body;
  
  if (!email) {
    return res.status(400).json({ message: 'Email обязателен' });
  }
  
  if (!users[email]) {
    return res.status(404).json({ message: 'Пользователь не найден' });
  }
  
  // Create or update subscription
  userSubscriptions[email] = {
    plan: plan || 'free',
    status: status || 'active',
    startDate: userSubscriptions[email]?.startDate || new Date().toISOString(),
    endDate: null,
    maxEditorSessions: plan === 'business' ? Infinity : (maxEditorSessions || 3)
  };
  
  return res.json({ 
    message: 'Подписка обновлена', 
    subscription: userSubscriptions[email] 
  });
});

// Reset user password (admin only)
app.post('/api/admin/reset-password', authenticateAdmin, async (req, res) => {
  const { email } = req.body;
  
  if (!email) {
    return res.status(400).json({ message: 'Email обязателен' });
  }
  
  try {
    const user = users[email];
    if (!user) {
      return res.status(404).json({ message: 'Пользователь не найден' });
    }
    
    // Generate a random password
    const newPassword = Math.random().toString(36).slice(-8);
    const hashedPassword = await bcrypt.hash(newPassword, 10);
    
    // Update password
    users[email].password = hashedPassword;
    
    // Terminate all sessions for this user
    if (sessions[email]) {
      delete sessions[email];
    }
    
    // In a real application, you would send the new password to the user's email
    // For this demo, we'll just return it in the response
    return res.json({ 
      message: 'Пароль сброшен', 
      newPassword: newPassword,
      note: 'В реальном приложении новый пароль был бы отправлен на email пользователя'
    });
  } catch (error) {
    console.error('Reset password error:', error);
    return res.status(500).json({ message: 'Ошибка при сбросе пароля' });
  }
});

// Delete user (admin only)
app.post('/api/admin/delete-user', authenticateAdmin, async (req, res) => {
  const { email } = req.body;
  
  if (!email) {
    return res.status(400).json({ message: 'Email обязателен' });
  }
  
  try {
    // Prevent admin deletion
    if (email === ADMIN_EMAIL) {
      return res.status(403).json({ message: 'Нельзя удалить аккаунт администратора' });
    }
    
    const user = users[email];
    if (!user) {
      return res.status(404).json({ message: 'Пользователь не найден' });
    }
    
    // Remove user
    delete users[email];
    
    // Remove all sessions
    delete sessions[email];
    
    return res.json({ message: 'Пользователь удален' });
  } catch (error) {
    console.error('Delete user error:', error);
    return res.status(500).json({ message: 'Ошибка при удалении пользователя' });
  }
});

// For serving the main page
app.get('/', (req, res) => {
  // Более гибкая CSP, которая позволяет загружать изображения и видео с внешних источников
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' https://images.unsplash.com data: https: http:; media-src 'self';");
  res.sendFile(path.join(__dirname, 'index.html'));
});

// Middleware for dashboard protection
function requireAuth(req, res, next) {
  const token = req.cookies?.auth_token || req.headers['authorization']?.split(' ')[1];
  
  if (!token) {
    return res.redirect('/');
  }
  
  jwt.verify(token, JWT_SECRET, (err, decoded) => {
    if (err || !decoded?.email) {
      // Удаляем неверную cookie, если она есть
      res.clearCookie('auth_token');
      return res.redirect('/');
    }
    
    const user = users[decoded.email];
    if (!user) {
      // Удаляем неверную cookie, если она есть
      res.clearCookie('auth_token');
      return res.redirect('/');
    }
    
    // Добавляем информацию о пользователе в запрос
    req.user = user;
    req.userEmail = decoded.email;
    next();
  });
}

// Middleware for admin protection
function requireAdmin(req, res, next) {
  const token = req.cookies?.auth_token || req.headers['authorization']?.split(' ')[1];
  
  if (!token) {
    return res.redirect('/');
  }
  
  jwt.verify(token, JWT_SECRET, (err, decoded) => {
    if (err || !decoded?.email) {
      // Удаляем неверную cookie, если она есть
      res.clearCookie('auth_token');
      return res.redirect('/');
    }
    
    const user = users[decoded.email];
    if (!user || !user.isAdmin) {
      return res.redirect('./dashboard');
    }
    
    // Добавляем информацию о пользователе в запрос
    req.user = user;
    req.userEmail = decoded.email;
    next();
  });
}

// For serving the dashboard page (protected)
app.get('/dashboard', requireAuth, (req, res) => {
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' https://images.unsplash.com data: https: http:; media-src 'self';");
  res.sendFile(path.join(__dirname, 'admin-dashboard.html'));
});

// For serving the admin dashboard page (protected)
app.get('/admin', requireAdmin, (req, res) => {
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' https://images.unsplash.com data: https: http:; media-src 'self';");
  res.sendFile(path.join(__dirname, 'admin-dashboard.html'));
});

// Serve the pano application
app.get('/pano', (req, res) => {
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://aframe.io https://cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' https://images.unsplash.com data: https: http:; media-src 'self';");
  res.sendFile(path.join(__dirname, 'pano', 'index.html'));
});

// Serve the pano application for any sub-routes
app.get('/pano/*', (req, res) => {
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://aframe.io https://cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' https://images.unsplash.com data: https: http:; media-src 'self';");
  res.sendFile(path.join(__dirname, 'pano', 'index.html'));
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', timestamp: new Date().toISOString() });
});

// For any other routes, serve the main page (for client-side routing)
app.get('*', (req, res) => {
  res.status(404).send('Страница не найдена');
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Server error:', err.stack);
  res.status(500).json({ message: 'Внутренняя ошибка сервера' });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  if (process.env.NODE_ENV !== 'production') {
    console.log(`Admin credentials: ${ADMIN_EMAIL} / ${ADMIN_PASSWORD}`);
  }
});