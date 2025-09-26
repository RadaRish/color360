// Color360 Server with LaMa Inpainting Integration
const express = require('express');
const bcrypt = require('bcryptjs');
const path = require('path');
const fs = require('fs');
const bodyParser = require('body-parser');
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

// JWT Secret Key
const JWT_SECRET = process.env.JWT_SECRET || 'color360-super-secure-jwt-secret-key-2025';

// LaMa Inpainting Service Configuration
const LAMA_PORT = process.env.LAMA_PORT || 5002;
const LAMA_HOST = process.env.LAMA_HOST || '127.0.0.1';
const LAMA_URL = `http://${LAMA_HOST}:${LAMA_PORT}`;
const LAMA_ENABLED = process.env.LAMA_ENABLED !== 'false';
let lamaProcess = null;
let lamaServiceReady = false;

// Backward compatibility
const AI_PORT = LAMA_PORT;
const AI_HOST = LAMA_HOST;
const AI_URL = LAMA_URL;
const SD_PORT = LAMA_PORT;
const SD_HOST = LAMA_HOST; 
const SD_URL = LAMA_URL;
let aiProcess = null;
let aiServiceReady = false;
let sdProcess = null;
let sdServiceReady = false;

// Environment check
const isProduction = process.env.NODE_ENV === 'production';

// Graceful shutdown
process.on('SIGINT', () => {
  console.error('\n🛑 Получен сигнал SIGINT, завершение работы...');
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.error('\n🛑 Получен сигнал SIGTERM, завершение работы...');
  process.exit(0);
});

// Security headers with production configuration
if (isProduction) {
  app.use(helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com", "https://cdn.jsdelivr.net"],
        fontSrc: ["'self'", "https://fonts.gstatic.com", "https://cdn.jsdelivr.net"],
        scriptSrc: ["'self'", "'unsafe-inline'", "'unsafe-eval'", "https://cdn.jsdelivr.net", "https://unpkg.com"],
        imgSrc: ["'self'", "data:", "blob:", "https:", "http:"],
        connectSrc: ["'self'", "ws:", "wss:", "https:", "http:"],
        frameSrc: ["'none'"],
        objectSrc: ["'none'"],
        baseUri: ["'self'"]
      }
    },
    crossOriginEmbedderPolicy: false
  }));
} else {
  app.use(helmet({
    contentSecurityPolicy: false,
    crossOriginEmbedderPolicy: false
  }));
}

// Enable compression
app.use(compression());

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 1000, // Limit each IP to 1000 requests per windowMs
  message: 'Слишком много запросов с этого IP, попробуйте позже.'
});
app.use(limiter);

// Body parser middleware
app.use(bodyParser.json({ limit: '50mb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '50mb' }));
app.use(cookieParser());

// Static files
app.use(express.static(path.join(__dirname)));

// CORS headers
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
  if (req.method === 'OPTIONS') {
    res.sendStatus(200);
  } else {
    next();
  }
});

console.log(`
🚀 Color360 с LaMa AI запускается...
🎯 LaMa Service: ${LAMA_ENABLED ? 'включён' : 'отключён'}  
🌐 Port: ${PORT}
🔧 Mode: ${isProduction ? 'production' : 'development'}
`);

// ==================== LaMa Service Management ====================

/**
 * Запускает LaMa Inpainting сервис
 */
async function startLamaService() {
  return new Promise((resolve, reject) => {
    if (lamaProcess && !lamaProcess.killed) {
      console.log('🎯 LaMa сервис уже запущен');
      return resolve(true);
    }

    console.log('🚀 Запуск LaMa Inpainting сервиса...');
    
    // Используем Python из виртуального окружения
    let pythonExecutable;
    
    const venvPaths = [
      path.join(__dirname, '.venv', process.platform === 'win32' ? 'Scripts/python.exe' : 'bin/python'),
      path.join(__dirname, 'sd_env', process.platform === 'win32' ? 'Scripts/python.exe' : 'bin/python'),
      path.join(__dirname, 'lama_env', process.platform === 'win32' ? 'Scripts/python.exe' : 'bin/python'),
      path.join(__dirname, 'venv', process.platform === 'win32' ? 'Scripts/python.exe' : 'bin/python')
    ];
    
    let venvFound = false;
    for (const venvPath of venvPaths) {
      if (fs.existsSync(venvPath)) {
        pythonExecutable = venvPath;
        venvFound = true;
        console.log('📦 Python из виртуального окружения:', pythonExecutable);
        break;
      }
    }
    
    if (!venvFound) {
      if (process.platform === 'win32') {
        pythonExecutable = 'python';
      } else {
        const pythonCommands = ['python3.11', 'python3.10', 'python3.9', 'python3.8', 'python3', 'python'];
        pythonExecutable = 'python3';
        
        for (const cmd of pythonCommands) {
          try {
            const { execSync } = require('child_process');
            execSync(`which ${cmd}`, { stdio: 'ignore' });
            pythonExecutable = cmd;
            break;
          } catch (e) {
            // Команда не найдена
          }
        }
      }
      console.log('🐍 Системный Python:', pythonExecutable);
    }
    
    const lamaAppPath = path.join(__dirname, 'sd', 'lama_service.py');
    
    if (!fs.existsSync(lamaAppPath)) {
      console.warn('⚠️ Файл LaMa сервиса не найден:', lamaAppPath);
      return resolve(false);
    }

    lamaProcess = spawn(pythonExecutable, [lamaAppPath], {
      cwd: path.join(__dirname, 'sd'),
      env: {
        ...process.env,
        PORT: LAMA_PORT,
        HOST: LAMA_HOST,
        PYTHONUNBUFFERED: '1'
      },
      stdio: ['inherit', 'pipe', 'pipe']
    });

    const startupTimeout = setTimeout(() => {
      console.warn('⚠️ Timeout при запуске LaMa сервиса');
      if (lamaProcess) {
        lamaProcess.kill();
      }
      resolve(false);
    }, 60000);

    lamaProcess.stdout.on('data', (data) => {
      const output = data.toString();
      console.log(`LaMa stdout: ${output.trim()}`);
      
      if (output.includes('Application startup complete') || output.includes('Uvicorn running')) {
        clearTimeout(startupTimeout);
        console.log('✅ LaMa сервис запущен');
        lamaServiceReady = true;
        sdServiceReady = true;
        aiServiceReady = true;
        resolve(true);
      }
    });

    lamaProcess.stderr.on('data', (data) => {
      const output = data.toString();
      console.error(`LaMa stderr: ${output.trim()}`);
      
      if (output.includes('ImportError') || output.includes('ModuleNotFoundError')) {
        clearTimeout(startupTimeout);
        console.warn('⚠️ LaMa зависимости не установлены');
        resolve(false);
      }
    });

    lamaProcess.on('close', (code) => {
      clearTimeout(startupTimeout);
      console.log(`LaMa процесс завершён: ${code}`);
      lamaServiceReady = false;
      sdServiceReady = false;
      aiServiceReady = false;
      resolve(code === 0);
    });

    lamaProcess.on('error', (error) => {
      clearTimeout(startupTimeout);
      console.error('❌ Ошибка LaMa:', error.message);
      resolve(false);
    });
  });
}

/**
 * Проверка здоровья LaMa сервиса
 */
async function checkLamaHealth() {
  try {
    const response = await axios.get(`${LAMA_URL}/health`, {
      timeout: 5000,
      validateStatus: function (status) {
        return status < 500;
      }
    });
    
    if (response.status === 200) {
      lamaServiceReady = true;
      sdServiceReady = true;
      aiServiceReady = true;
      return { healthy: true, data: response.data };
    } else {
      lamaServiceReady = false;
      sdServiceReady = false;
      aiServiceReady = false;
      return { healthy: false, error: `HTTP ${response.status}` };
    }
  } catch (error) {
    lamaServiceReady = false;
    sdServiceReady = false;
    aiServiceReady = false;
    return { healthy: false, error: error.message };
  }
}

// Backward compatibility functions
async function startStableDiffusionService() {
  console.log('🔄 Backward compatibility: запуск LaMa как SD');
  return startLamaService();
}

async function checkStableDiffusionHealth() {
  return checkLamaHealth();
}

// Запуск LaMa сервиса при старте
if (LAMA_ENABLED && process.env.NODE_ENV !== 'production') {
  console.log('🎯 Запуск LaMa сервиса...');
  startLamaService().catch(error => {
    console.error('⚠️ LaMa сервис не запустился:', error.message);
    console.log('🔄 Продолжаем без AI...');
  });
} else if (process.env.NODE_ENV === 'production') {
  console.log('🎯 Production: LaMa через systemctl');
} else {
  console.log('🎯 LaMa отключён');
}

// ==================== File Upload Configuration ====================

const storage = multer.memoryStorage();
const upload = multer({
  storage: storage,
  limits: { 
    fileSize: 50 * 1024 * 1024, // 50MB
    fields: 10,
    files: 2
  }
});

// ==================== Health Endpoints ====================

app.get('/api/lama-health', async (req, res) => {
  try {
    const health = await checkLamaHealth();
    if (health.healthy) {
      res.json({
        status: 'ok',
        service: 'lama-inpainting',
        ...health.data
      });
    } else {
      res.status(503).json({
        status: 'error',
        service: 'lama-inpainting',
        error: health.error
      });
    }
  } catch (error) {
    res.status(503).json({
      status: 'error',
      service: 'lama-inpainting',
      error: error.message
    });
  }
});

app.get('/api/sd-health', async (req, res) => {
  try {
    const health = await checkLamaHealth();
    res.json({
      status: health.healthy ? 'ok' : 'error',
      service: 'lama-inpainting',
      compatibility: 'sd-api',
      error: health.error || null
    });
  } catch (error) {
    res.status(503).json({
      status: 'error',
      service: 'lama-inpainting',
      error: error.message
    });
  }
});

app.get('/api/ai-health', async (req, res) => {
  try {
    const health = await checkLamaHealth();
    res.json({
      status: health.healthy ? 'ok' : 'degraded',
      services: {
        'lama-inpainting': {
          status: health.healthy ? 'ok' : 'error',
          error: health.error || null
        }
      }
    });
  } catch (error) {
    res.status(503).json({
      status: 'error',
      error: error.message
    });
  }
});

// ==================== Inpainting Endpoints ====================

app.post('/api/inpaint', upload.fields([
  { name: 'image', maxCount: 1 },
  { name: 'mask', maxCount: 1 }
]), async (req, res) => {
  try {
    if (!req.files || !req.files.image || !req.files.mask) {
      return res.status(400).json({
        error: 'Требуются файлы image и mask'
      });
    }

    const imageFile = req.files.image[0];
    const maskFile = req.files.mask[0];

    console.log('🎨 Запрос inpainting через LaMa');

    if (!lamaServiceReady) {
      const health = await checkLamaHealth();
      if (!health.healthy) {
        return res.status(503).json({
          error: 'LaMa сервис недоступен',
          details: health.error
        });
      }
    }

    // Создаём FormData для Node.js
    const FormDataNode = require('form-data');
    const formData = new FormDataNode();
    
    formData.append('image', imageFile.buffer, {
      filename: 'image.jpg',
      contentType: imageFile.mimetype
    });
    
    formData.append('mask', maskFile.buffer, {
      filename: 'mask.jpg', 
      contentType: maskFile.mimetype
    });
    
    // Добавляем параметры для лучшего качества
    formData.append('prompt', req.body.prompt || 'remove object completely, natural background');
    formData.append('negative_prompt', req.body.negative_prompt || 'artifacts, blurry, seams');
    formData.append('num_inference_steps', req.body.num_inference_steps || '25');
    formData.append('guidance_scale', req.body.guidance_scale || '7.5');
    formData.append('strength', req.body.strength || '1.0');

    const response = await axios.post(`${LAMA_URL}/inpaint`, formData, {
      headers: {
        ...formData.getHeaders(),
      },
      responseType: 'arraybuffer',
      timeout: 120000, // 2 минуты
    });

    res.set({
      'Content-Type': 'image/jpeg',
      'X-Inpaint-Method': response.headers['x-inpaint-method'] || 'lama',
      'X-Inpaint-Status': response.headers['x-inpaint-status'] || 'success',
      'X-Processing-Time': response.headers['x-processing-time'] || 'unknown'
    });

    res.send(response.data);
    console.log('✅ Inpainting выполнен успешно');

  } catch (error) {
    console.error('❌ Ошибка inpainting:', error.message);
    
    if (error.response) {
      res.status(error.response.status).json({
        error: 'Ошибка AI сервиса',
        details: error.response.data?.detail || error.message
      });
    } else if (error.code === 'ECONNREFUSED') {
      res.status(503).json({
        error: 'AI сервис недоступен',
        details: 'Подключение отклонено'
      });
    } else {
      res.status(500).json({
        error: 'Внутренняя ошибка сервера',
        details: error.message
      });
    }
  }
});

// Backward compatibility endpoint
app.post('/api/sd-inpaint', upload.fields([
  { name: 'image', maxCount: 1 },
  { name: 'mask', maxCount: 1 }
]), async (req, res) => {
  console.log('🔄 SD compatibility redirect to LaMa');
  return app._router.handle(Object.assign(req, { url: '/api/inpaint' }), res);
});

// ==================== User Management (Simplified) ====================

// In-memory user storage (replace with database in production)
const users = new Map();
const sessions = new Map();

// Default admin user
const ADMIN_EMAIL = 'admin@color360.online';
const ADMIN_PASSWORD = 'Color360Admin2025!';
const ADMIN_HASH = bcrypt.hashSync(ADMIN_PASSWORD, 10);

users.set(ADMIN_EMAIL, {
  email: ADMIN_EMAIL,
  password: ADMIN_HASH,
  role: 'admin',
  created: new Date()
});

// Login endpoint
app.post('/api/login', [
  body('email').isEmail().normalizeEmail(),
  body('password').isLength({ min: 6 })
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        error: 'Неверные данные',
        details: errors.array()
      });
    }

    const { email, password } = req.body;
    const user = users.get(email);

    if (!user || !bcrypt.compareSync(password, user.password)) {
      return res.status(401).json({
        error: 'Неверный email или пароль'
      });
    }

    const token = jwt.sign(
      { 
        email: user.email, 
        role: user.role 
      },
      JWT_SECRET,
      { expiresIn: '24h' }
    );

    res.json({
      success: true,
      token: token,
      user: {
        email: user.email,
        role: user.role
      }
    });

  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({
      error: 'Ошибка сервера при входе'
    });
  }
});

// ==================== Static Routes ====================

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'admin-dashboard.html'));
});

app.get('/main', (req, res) => {
  res.sendFile(path.join(__dirname, 'main.html'));
});

app.get('/profile', (req, res) => {
  res.sendFile(path.join(__dirname, 'profile.html'));
});

app.get('/privacy', (req, res) => {
  res.sendFile(path.join(__dirname, 'privacy.html'));
});

// ==================== Server Startup ====================

const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`
🚀 Color360 с LaMa AI запущен!
📍 URL: http://localhost:${PORT}
🎯 LaMa Service: ${LAMA_ENABLED ? `${LAMA_URL}` : 'отключён'}
🔧 Environment: ${process.env.NODE_ENV || 'development'}
📊 Память: ${Math.round(process.memoryUsage().heapUsed / 1024 / 1024)}MB

✨ Готов к профессиональному удалению объектов!
  `);
});

// Graceful shutdown
const gracefulShutdown = (signal) => {
  console.log(`\n🛑 Получен сигнал ${signal}, завершение работы...`);
  
  server.close(() => {
    console.log('🔴 HTTP сервер остановлен');
    
    if (lamaProcess && !lamaProcess.killed) {
      console.log('🛑 Остановка LaMa сервиса...');
      lamaProcess.kill('SIGTERM');
      setTimeout(() => {
        if (!lamaProcess.killed) {
          lamaProcess.kill('SIGKILL');
        }
      }, 5000);
    }
    
    console.log('✅ Завершение работы завершено');
    process.exit(0);
  });
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

module.exports = app;