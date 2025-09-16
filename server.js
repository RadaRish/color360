// Simple Node.js + Express backend for demo site
const express = require('express');
const path = require('path');
const fs = require('fs');
const bodyParser = require('body-parser');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');
const compression = require('compression');
const cookieParser = require('cookie-parser');
const { body, validationResult } = require('express-validator');
const multer = require('multer');
const axios = require('axios');
const { spawn } = require('child_process');
const app = express();
const PORT = process.env.PORT || 3000;

// JWT Secret Key - in production this should be set as an environment variable
const JWT_SECRET = process.env.JWT_SECRET || 'color360-super-secure-jwt-secret-key-2025';

// Environment check
const isProduction = process.env.NODE_ENV === 'production';

// LaMa Service Management
const LAMA_PORT = process.env.LAMA_PORT || 5000;
const LAMA_HOST = process.env.LAMA_HOST || '127.0.0.1';
const LAMA_URL = `http://${LAMA_HOST}:${LAMA_PORT}`;

let lamaProcess = null;
let lamaServiceReady = false;

// Function to start LaMa service
function startLamaService() {
  if (lamaProcess) {
    console.error('❌ LaMa процесс уже запущен');
    return;
  }

  try {
    const lamaDir = path.join(__dirname, 'lama');
    const pythonCmd = process.platform === 'win32' ? 'python' : 'python3';
    
    console.error('🐍 Запуск LaMa сервиса...');
    
    lamaProcess = spawn(pythonCmd, ['app.py'], {
      cwd: lamaDir,
      env: { ...process.env, PORT: LAMA_PORT, HOST: LAMA_HOST },
      stdio: ['pipe', 'pipe', 'pipe']
    });

    lamaProcess.stdout.on('data', (data) => {
      const output = data.toString();
      if (output.includes('started server process') || output.includes('Application startup complete')) {
        lamaServiceReady = true;
        console.error('✅ LaMa сервис готов к работе');
      }
      console.error(`[LaMa] ${output.trim()}`);
    });

    lamaProcess.stderr.on('data', (data) => {
      console.error(`[LaMa Error] ${data.toString().trim()}`);
    });

    lamaProcess.on('close', (code) => {
      console.error(`🔄 LaMa процесс завершен с кодом ${code}`);
      lamaProcess = null;
      lamaServiceReady = false;
      
      // Автоматический перезапуск в продакшене
      if (isProduction && code !== 0) {
        console.error('🔄 Перезапуск LaMa сервиса через 5 секунд...');
        setTimeout(startLamaService, 5000);
      }
    });

    lamaProcess.on('error', (err) => {
      console.error('❌ Ошибка запуска LaMa сервиса:', err.message);
      lamaProcess = null;
      lamaServiceReady = false;
    });

  } catch (error) {
    console.error('❌ Критическая ошибка запуска LaMa:', error.message);
  }
}

// Function to stop LaMa service
function stopLamaService() {
  if (lamaProcess) {
    console.error('⏹️ Остановка LaMa сервиса...');
    lamaProcess.kill('SIGTERM');
    lamaProcess = null;
    lamaServiceReady = false;
  }
}

// Start LaMa service on server startup
startLamaService();

// Graceful shutdown
process.on('SIGINT', () => {
  console.error('\n🛑 Получен сигнал SIGINT, завершение работы...');
  stopLamaService();
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.error('\n🛑 Получен сигнал SIGTERM, завершение работы...');
  stopLamaService();
  process.exit(0);
});

// Security headers with production configuration
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", ...(isProduction ? [] : ["'unsafe-inline'", "'unsafe-eval'"]), "https://aframe.io", "https://cdnjs.cloudflare.com"],
      styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"],
      fontSrc: ["'self'", "https://fonts.gstatic.com"],
      imgSrc: ["'self'", "https://images.unsplash.com", "data:", "https:", ...(isProduction ? [] : ["http:"])],
      mediaSrc: ["'self'"],
      connectSrc: ["'self'", ...(isProduction ? [] : ["ws:", "wss:"])]
    }
  },
  hsts: isProduction ? { maxAge: 31536000, includeSubDomains: true, preload: true } : false
}));

// Parse cookies
app.use(cookieParser());

// Enable gzip compression
app.use(compression());

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
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://aframe.io https://cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' https://images.unsplash.com data: https: http: blob:; media-src 'self';");
    
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
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://aframe.io https://cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' https://images.unsplash.com data: https: http: blob:; media-src 'self';");
  }
}));

// For API routes under /pano subpath, we need to handle that as well
// But for the main site, we serve from root
app.use(bodyParser.json({ limit: '10kb' })); // Limit payload size

// Serve uploaded avatars from /avatars
const avatarsDir = path.join(__dirname, 'avatars');
if (!fs.existsSync(avatarsDir)) {
  try { fs.mkdirSync(avatarsDir); } catch (e) { console.error('Could not create avatars dir', e); }
}
// Max avatar upload size (200 KB)
const MAX_AVATAR_BYTES = parseInt(process.env.MAX_AVATAR_BYTES) || 200 * 1024;
app.use('/avatars', express.static(avatarsDir, {
  setHeaders: (res, filePath) => {
    const ext = path.extname(filePath).toLowerCase();
    if (ext === '.jpg' || ext === '.jpeg') res.setHeader('Content-Type', 'image/jpeg');
    else res.setHeader('Content-Type', 'image/png');
    res.setHeader('Cache-Control', 'public, max-age=31536000');
  }
}));

// Directory for news images
const newsImagesDir = path.join(__dirname, 'news_images');
if (!fs.existsSync(newsImagesDir)) {
  try { fs.mkdirSync(newsImagesDir); } catch (e) { console.error('Could not create news_images dir', e); }
}
app.use('/news_images', express.static(newsImagesDir, {
  setHeaders: (res, filePath) => {
    const ext = path.extname(filePath).toLowerCase();
    if (ext === '.jpg' || ext === '.jpeg') res.setHeader('Content-Type', 'image/jpeg');
    else res.setHeader('Content-Type', 'image/png');
    res.setHeader('Cache-Control', 'public, max-age=31536000');
  }
}));

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
  body('name').trim().notEmpty().withMessage('Имя обязательно'),
  body('privacyConsent').equals('on').withMessage('Необходимо согласие на обработку персональных данных')
], async (req, res) => {
  // Check validation errors
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ errors: errors.array() });
  }
  
  const {name, email, password, privacyConsent} = req.body || {};
  
  try {
    // Additional check for privacy consent
    if (!privacyConsent) {
      return res.status(400).json({message:'Необходимо согласие на обработку персональных данных'});
    }
    
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
      isAdmin: false,
      privacyConsentDate: new Date().toISOString() // Сохраняем дату согласия
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
        isAdmin: user.isAdmin || false,
        avatar: users[email].avatar || null
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

// Setup multer for file uploads (in-memory storage for retouch API)
const upload = multer({ 
  storage: multer.memoryStorage(),
  limits: { 
    fileSize: 50 * 1024 * 1024, // 50MB max file size
    fields: 2, // image and mask
    files: 2
  }
});

// LaMa AI Inpainting API endpoint
app.post('/api/retouch', upload.fields([{ name: 'image' }, { name: 'mask' }]), async (req, res) => {
  try {
    const imageFile = req.files?.image?.[0];
    const maskFile = req.files?.mask?.[0];
    
    if (!imageFile || !maskFile) {
      return res.status(400).json({ error: 'Требуются файлы изображения и маски' });
    }

    console.error(`🎨 Запрос на удаление объектов: изображение ${imageFile.size} байт, маска ${maskFile.size} байт`);
    
    // Check if LaMa service is ready
    if (!lamaServiceReady) {
      console.error('⚠️ LaMa сервис еще не готов, используем fallback');
      
      // Fallback: return original image
      res.setHeader('Content-Type', imageFile.mimetype);
      res.setHeader('Content-Length', imageFile.buffer.length);
      res.setHeader('X-Retouch-Status', 'fallback-service-not-ready');
      return res.send(imageFile.buffer);
    }
    
    try {
      // Create FormData for local LaMa service
      const FormData = require('form-data');
      const formData = new FormData();
      formData.append('image', imageFile.buffer, { 
        filename: 'image.png',
        contentType: imageFile.mimetype 
      });
      formData.append('mask', maskFile.buffer, { 
        filename: 'mask.png',
        contentType: maskFile.mimetype 
      });

      console.error(`🚀 Отправляем запрос в LaMa сервис: ${LAMA_URL}/inpaint`);

      // Send request to local LaMa service
      const response = await axios.post(`${LAMA_URL}/inpaint`, formData, {
        headers: { ...formData.getHeaders() },
        responseType: 'arraybuffer',
        timeout: 60000 // 60 seconds timeout for AI processing
      });

      console.error('✅ LaMa обработка завершена успешно');

      // Return the processed image
      res.setHeader('Content-Type', 'image/png');
      res.setHeader('Content-Length', response.data.length);
      res.setHeader('X-Retouch-Status', 'success');
      res.setHeader('X-Retouch-Method', 'lama-ai');
      return res.send(response.data);
      
    } catch (lamaError) {
      const errorMsg = lamaError?.response?.data?.toString() || lamaError?.message || 'Unknown error';
      console.error('❌ LaMa service error:', errorMsg);
      
      // Fallback: return original image if LaMa service fails
      console.error('🔄 Fallback: возвращаем оригинальное изображение');
      res.setHeader('Content-Type', imageFile.mimetype);
      res.setHeader('Content-Length', imageFile.buffer.length);
      res.setHeader('X-Retouch-Status', 'fallback-lama-error');
      res.setHeader('X-Retouch-Error', errorMsg.substring(0, 200)); // Limit error message length
      return res.send(imageFile.buffer);
    }
    
  } catch (error) {
    console.error('❌ Retouch API error:', error);
    return res.status(500).json({ 
      error: 'Ошибка обработки изображения', 
      details: error.message 
    });
  }
});

// Upload or update user avatar (expects JSON { dataUrl: 'data:image/png;base64,...' })
app.post('/api/user/avatar', authenticateToken, async (req, res) => {
  try {
    const { dataUrl } = req.body || {};
    if (!dataUrl || typeof dataUrl !== 'string' || !dataUrl.startsWith('data:')) {
      return res.status(400).json({ message: 'Неверный формат данных аватара' });
    }

    // Parse data URL
  const matches = dataUrl.match(/^data:(image\/(png|jpeg|jpg));base64,(.+)$/);
    if (!matches) return res.status(400).json({ message: 'Unsupported image format' });

    const mime = matches[1];
    const ext = matches[2] === 'jpeg' || matches[2] === 'jpg' ? 'jpg' : 'png';
    const b64 = matches[3];
    const buffer = Buffer.from(b64, 'base64');

    // Validate size (limit to 200 KB)
    const MAX_AVATAR_BYTES = 200 * 1024;
    if (buffer.length > MAX_AVATAR_BYTES) {
      return res.status(413).json({ message: 'Файл слишком большой. Максимум 200KB' });
    }

    const filename = `${encodeURIComponent(req.user.email)}.${ext}`;
    const filepath = path.join(avatarsDir, filename);

    await fs.promises.writeFile(filepath, buffer);

    const url = `/avatars/${filename}`;

    // Optionally store avatar URL in user profile (in-memory)
    users[req.user.email] = users[req.user.email] || {};
    users[req.user.email].avatar = url;

    return res.json({ message: 'ok', url });
  } catch (error) {
    console.error('Avatar upload error:', error);
    return res.status(500).json({ message: 'Ошибка сохранения аватара' });
  }
});

// Get current authenticated user profile
app.get('/api/user/profile', authenticateToken, (req, res) => {
  try {
    const email = req.user.email;
    const user = users[email];
    if (!user) return res.status(404).json({ message: 'Пользователь не найден' });

    return res.json({
      name: user.name,
      email: user.email,
      isAdmin: !!user.isAdmin,
      avatar: user.avatar || null
    });
  } catch (err) {
    console.error('Profile error:', err);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
});

// Get all news
app.get('/api/news', (req, res) => {
  return res.json(newsItems);
});

// Add news (admin only)
app.post('/api/admin/news', authenticateAdmin, (req, res) => {
  const { title, date, text, imageDataUrl } = req.body;
  
  if (!title || !date || !text) {
    return res.status(400).json({ message: 'Заголовок, дата и текст обязательны' });
  }
  
  const newNews = {
    id: newsItems.length > 0 ? Math.max(...newsItems.map(n => n.id)) + 1 : 1,
    title,
    date,
    text
  };

  // If image data provided, save it
  if (imageDataUrl && typeof imageDataUrl === 'string' && imageDataUrl.startsWith('data:')) {
    const m = imageDataUrl.match(/^data:(image\/(png|jpeg|jpg));base64,(.+)$/);
    if (m) {
      const ext = m[2] === 'jpeg' || m[2] === 'jpg' ? 'jpg' : 'png';
      const buffer = Buffer.from(m[3], 'base64');
      // Simple size limit: 500KB
      if (buffer.length <= (500 * 1024)) {
        const fname = `news-${Date.now()}-${Math.random().toString(36).slice(2,8)}.${ext}`;
        const fpath = path.join(newsImagesDir, fname);
        try {
          fs.writeFileSync(fpath, buffer);
          newNews.image = `/news_images/${fname}`;
        } catch (e) {

        }
      }
    }
  }
  
  newsItems.push(newNews);
  
  return res.status(201).json({ message: 'Новость добавлена', news: newNews });
});

// Update news (admin only)
app.put('/api/admin/news/:id', authenticateAdmin, (req, res) => {
  const id = parseInt(req.params.id);
  const { title, date, text, imageDataUrl, removeImage } = req.body;
  
  if (!title || !date || !text) {
    return res.status(400).json({ message: 'Заголовок, дата и текст обязательны' });
  }
  
  const newsIndex = newsItems.findIndex(n => n.id === id);
  
  if (newsIndex === -1) {
    return res.status(404).json({ message: 'Новость не найдена' });
  }
  
  // preserve previous image unless changed
  const prev = newsItems[newsIndex];
  const updated = { id, title, date, text };

  // Handle image removal
  if (removeImage && prev && prev.image) {
    try { fs.unlinkSync(path.join(__dirname, prev.image.replace(/^\//, ''))); } catch (e) {}
    // ensure removed
  }

  // If new image provided, save it
  if (imageDataUrl && typeof imageDataUrl === 'string' && imageDataUrl.startsWith('data:')) {
    const m = imageDataUrl.match(/^data:(image\/(png|jpeg|jpg));base64,(.+)$/);
    if (m) {
      const ext = m[2] === 'jpeg' || m[2] === 'jpg' ? 'jpg' : 'png';
      const buffer = Buffer.from(m[3], 'base64');
      if (buffer.length <= (500 * 1024)) {
        const fname = `news-${Date.now()}-${Math.random().toString(36).slice(2,8)}.${ext}`;
        const fpath = path.join(newsImagesDir, fname);
        try {
          fs.writeFileSync(fpath, buffer);
          updated.image = `/news_images/${fname}`;
        } catch (e) {

        }
      }
    }
  } else if (!removeImage && prev && prev.image) {
    updated.image = prev.image;
  }

  newsItems[newsIndex] = updated;
  
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
  // Also remove image file if exists
  if (news && news.image) {
    try { fs.unlinkSync(path.join(__dirname, news.image.replace(/^\//, ''))); } catch (e) {}
  }
  
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

// New: projects API (alias for editor-sessions) - list projects
app.get('/api/projects', authenticateToken, (req, res) => {
  const userProjects = editorSessions[req.user.email] || [];
  return res.json(userProjects);
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

// New: create project (alias) with limit enforcement
app.post('/api/projects', authenticateToken, (req, res) => {
  const userEmail = req.user.email;
  const subscription = userSubscriptions[userEmail] || { maxEditorSessions: 3 };

  const userProjects = editorSessions[userEmail] || [];
  const maxProjects = subscription.maxEditorSessions || 3;
  if (userProjects.length >= maxProjects) {
    return res.status(400).json({ message: `Достигнут лимит сохранённых проектов (${maxProjects})` });
  }

  const newProject = {
    id: Date.now().toString(),
    name: req.body.name || `Проект ${userProjects.length + 1}`,
    created: new Date().toISOString(),
    lastAccessed: new Date().toISOString(),
    data: req.body.data || {}
  };

  if (!editorSessions[userEmail]) editorSessions[userEmail] = [];
  editorSessions[userEmail].push(newProject);

  return res.status(201).json({ message: 'Проект создан', project: newProject });
});

// New: delete project alias
app.delete('/api/projects/:id', authenticateToken, (req, res) => {
  const userEmail = req.user.email;
  const projectId = req.params.id;
  const userProjects = editorSessions[userEmail] || [];
  const idx = userProjects.findIndex(p => p.id === projectId);
  if (idx === -1) return res.status(404).json({ message: 'Проект не найден' });
  userProjects.splice(idx, 1);
  return res.json({ message: 'Проект удалён' });
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
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' https://images.unsplash.com data: https: http: blob:; media-src 'self';");
  res.sendFile(path.join(__dirname, 'main.html'));
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
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' https://images.unsplash.com data: https: http: blob:; media-src 'self';");
  res.sendFile(path.join(__dirname, 'admin-dashboard.html'));
});

// For serving the admin dashboard page (protected)
app.get('/admin', requireAdmin, (req, res) => {
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' https://images.unsplash.com data: https: http:; media-src 'self';");
  res.sendFile(path.join(__dirname, 'admin-dashboard.html'));
});

// Serve the pano application
app.get('/pano', (req, res) => {
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://aframe.io https://cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' https://images.unsplash.com data: https: http: blob:; media-src 'self';");
  res.sendFile(path.join(__dirname, 'pano', 'index.html'));
});

// Serve the pano application for any sub-routes
app.get('/pano/*', (req, res) => {
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://aframe.io https://cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' https://images.unsplash.com data: https: http: blob:; media-src 'self';");
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
  console.log(`Сервер запущен на порту ${PORT}`);
  if (process.env.NODE_ENV !== 'production') {
    console.log(`Доступен по адресу: http://localhost:${PORT}`);
  }
});