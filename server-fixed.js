const express = require('express');
const helmet = require('helmet');
const bcrypt = require('bcryptjs');
const session = require('express-session');
const FileStore = require('session-file-store')(session);
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const sharp = require('sharp');
const { spawn } = require('child_process');
const axios = require('axios');

const app = express();
const port = process.env.PORT || 3000;
const isProduction = process.env.NODE_ENV === 'production';

console.log(`Starting Color360 server in ${isProduction ? 'production' : 'development'} mode`);

// Ensure required directories exist
const requiredDirs = [
  'uploads/panoramas',
  'uploads/temp',
  'sessions',
  'avatars',
  'news_images'
];

requiredDirs.forEach(dir => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
    console.log(`Created directory: ${dir}`);
  }
});

// User data file
const usersFile = 'users.json';

// Initialize users file if it doesn't exist
if (!fs.existsSync(usersFile)) {
  fs.writeFileSync(usersFile, JSON.stringify([]));
  console.log('Created users.json file');
}

// Helper function to read users
function readUsers() {
  try {
    const data = fs.readFileSync(usersFile, 'utf8');
    return JSON.parse(data);
  } catch (error) {
    console.error('Error reading users file:', error);
    return [];
  }
}

// Helper function to write users
function writeUsers(users) {
  try {
    fs.writeFileSync(usersFile, JSON.stringify(users, null, 2));
    return true;
  } catch (error) {
    console.error('Error writing users file:', error);
    return false;
  }
}

// Session configuration
app.use(session({
  store: new FileStore({
    path: './sessions',
    retries: 3,
    ttl: 86400,
    reapInterval: 3600
  }),
  secret: process.env.SESSION_SECRET || 'color360-secret-key-change-in-production',
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: isProduction,
    httpOnly: true,
    maxAge: 24 * 60 * 60 * 1000 // 24 hours
  }
}));

// Security middleware with CSP for A-Frame
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", "'unsafe-eval'", ...(isProduction ? [] : ["'unsafe-inline'"]), "https://aframe.io", "https://cdnjs.cloudflare.com"],
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
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Static files
app.use('/assets', express.static('assets'));
app.use('/avatars', express.static('avatars'));
app.use('/news_images', express.static('news_images'));

// Authentication middleware
function requireAuth(req, res, next) {
  if (!req.session.user) {
    return res.status(401).json({ error: 'Authentication required' });
  }
  next();
}

// Multer configuration for file uploads
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    const uploadPath = 'uploads/temp';
    cb(null, uploadPath);
  },
  filename: function (req, file, cb) {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, uniqueSuffix + path.extname(file.originalname));
  }
});

const upload = multer({ 
  storage: storage,
  limits: {
    fileSize: 50 * 1024 * 1024 // 50MB limit
  },
  fileFilter: (req, file, cb) => {
    if (file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new Error('Only image files are allowed'), false);
    }
  }
});

// Avatar upload configuration
const avatarStorage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, 'avatars');
  },
  filename: function (req, file, cb) {
    const email = req.session.user.email;
    const ext = path.extname(file.originalname);
    cb(null, `${email}${ext}`);
  }
});

const avatarUpload = multer({ 
  storage: avatarStorage,
  limits: {
    fileSize: 5 * 1024 * 1024 // 5MB limit for avatars
  },
  fileFilter: (req, file, cb) => {
    if (file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new Error('Only image files are allowed'), false);
    }
  }
});

// Routes

// Main page
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

// Main app page
app.get('/main.html', requireAuth, (req, res) => {
  res.sendFile(path.join(__dirname, 'main.html'));
});

// Profile page
app.get('/profile.html', requireAuth, (req, res) => {
  res.sendFile(path.join(__dirname, 'profile.html'));
});

// Admin dashboard
app.get('/admin-dashboard.html', requireAuth, (req, res) => {
  const user = req.session.user;
  if (user.role !== 'admin') {
    return res.status(403).send('Access denied');
  }
  res.sendFile(path.join(__dirname, 'admin-dashboard.html'));
});

// Privacy page
app.get('/privacy.html', (req, res) => {
  res.sendFile(path.join(__dirname, 'privacy.html'));
});

// Test registration page
app.get('/test-registration.html', (req, res) => {
  res.sendFile(path.join(__dirname, 'test-registration.html'));
});

// Panoramic editor
app.get('/pano/', (req, res) => {
  res.sendFile(path.join(__dirname, 'pano/index.html'));
});

app.get('/pano/index.html', (req, res) => {
  res.sendFile(path.join(__dirname, 'pano/index.html'));
});

// Serve pano static files
app.use('/pano', express.static('pano'));

// API Routes

// Register
app.post('/api/register', async (req, res) => {
  try {
    const { email, password, name } = req.body;
    
    if (!email || !password || !name) {
      return res.status(400).json({ error: 'All fields are required' });
    }

    const users = readUsers();
    
    if (users.find(user => user.email === email)) {
      return res.status(400).json({ error: 'User already exists' });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    const newUser = {
      id: Date.now().toString(),
      email,
      password: hashedPassword,
      name,
      role: users.length === 0 ? 'admin' : 'user',
      createdAt: new Date().toISOString()
    };

    users.push(newUser);
    
    if (writeUsers(users)) {
      req.session.user = { id: newUser.id, email: newUser.email, name: newUser.name, role: newUser.role };
      res.json({ success: true, message: 'Registration successful' });
    } else {
      res.status(500).json({ error: 'Failed to save user data' });
    }
  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Login
app.post('/api/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    
    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }

    const users = readUsers();
    const user = users.find(u => u.email === email);
    
    if (!user) {
      return res.status(400).json({ error: 'Invalid credentials' });
    }

    const validPassword = await bcrypt.compare(password, user.password);
    
    if (!validPassword) {
      return res.status(400).json({ error: 'Invalid credentials' });
    }

    req.session.user = { id: user.id, email: user.email, name: user.name, role: user.role };
    res.json({ success: true, message: 'Login successful' });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Logout
app.post('/api/logout', (req, res) => {
  req.session.destroy((err) => {
    if (err) {
      return res.status(500).json({ error: 'Failed to logout' });
    }
    res.json({ success: true, message: 'Logout successful' });
  });
});

// Get current user
app.get('/api/user', (req, res) => {
  if (req.session.user) {
    res.json({ user: req.session.user });
  } else {
    res.status(401).json({ error: 'Not authenticated' });
  }
});

// Upload avatar
app.post('/api/upload-avatar', requireAuth, avatarUpload.single('avatar'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }

    const avatarPath = `/avatars/${req.file.filename}`;
    res.json({ success: true, avatarPath });
  } catch (error) {
    console.error('Avatar upload error:', error);
    res.status(500).json({ error: 'Failed to upload avatar' });
  }
});

// Upload panorama
app.post('/api/upload', requireAuth, upload.single('panorama'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }

    const tempPath = req.file.path;
    const finalDir = 'uploads/panoramas';
    const finalPath = path.join(finalDir, req.file.filename);

    // Ensure final directory exists
    if (!fs.existsSync(finalDir)) {
      fs.mkdirSync(finalDir, { recursive: true });
    }

    // Process image with Sharp for optimization
    await sharp(tempPath)
      .jpeg({ quality: 85, progressive: true })
      .resize({ width: 4096, height: 2048, fit: 'inside', withoutEnlargement: true })
      .toFile(finalPath);

    // Remove temp file
    fs.unlinkSync(tempPath);

    const imageUrl = `/uploads/panoramas/${req.file.filename}`;
    res.json({ success: true, imageUrl });
  } catch (error) {
    console.error('Upload error:', error);
    if (req.file && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    res.status(500).json({ error: 'Failed to process image' });
  }
});

// Serve uploaded files
app.use('/uploads', express.static('uploads'));

// Update user profile
app.post('/api/update-profile', requireAuth, async (req, res) => {
  try {
    const { name, currentPassword, newPassword } = req.body;
    const userId = req.session.user.id;
    
    const users = readUsers();
    const userIndex = users.findIndex(u => u.id === userId);
    
    if (userIndex === -1) {
      return res.status(404).json({ error: 'User not found' });
    }

    const user = users[userIndex];

    // Update name if provided
    if (name) {
      user.name = name;
      req.session.user.name = name;
    }

    // Update password if provided
    if (newPassword) {
      if (!currentPassword) {
        return res.status(400).json({ error: 'Current password is required' });
      }

      const validPassword = await bcrypt.compare(currentPassword, user.password);
      if (!validPassword) {
        return res.status(400).json({ error: 'Current password is incorrect' });
      }

      user.password = await bcrypt.hash(newPassword, 10);
    }

    user.updatedAt = new Date().toISOString();
    users[userIndex] = user;

    if (writeUsers(users)) {
      res.json({ success: true, message: 'Profile updated successfully' });
    } else {
      res.status(500).json({ error: 'Failed to update profile' });
    }
  } catch (error) {
    console.error('Profile update error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Admin routes
app.get('/api/admin/users', requireAuth, (req, res) => {
  if (req.session.user.role !== 'admin') {
    return res.status(403).json({ error: 'Access denied' });
  }
  
  const users = readUsers();
  const sanitizedUsers = users.map(user => ({
    id: user.id,
    email: user.email,
    name: user.name,
    role: user.role,
    createdAt: user.createdAt,
    updatedAt: user.updatedAt
  }));
  
  res.json({ users: sanitizedUsers });
});

app.post('/api/admin/users/:id/role', requireAuth, (req, res) => {
  if (req.session.user.role !== 'admin') {
    return res.status(403).json({ error: 'Access denied' });
  }
  
  const { role } = req.body;
  const userId = req.params.id;
  
  if (!['user', 'admin'].includes(role)) {
    return res.status(400).json({ error: 'Invalid role' });
  }
  
  const users = readUsers();
  const userIndex = users.findIndex(u => u.id === userId);
  
  if (userIndex === -1) {
    return res.status(404).json({ error: 'User not found' });
  }
  
  users[userIndex].role = role;
  users[userIndex].updatedAt = new Date().toISOString();
  
  if (writeUsers(users)) {
    res.json({ success: true, message: 'User role updated' });
  } else {
    res.status(500).json({ error: 'Failed to update user role' });
  }
});

app.delete('/api/admin/users/:id', requireAuth, (req, res) => {
  if (req.session.user.role !== 'admin') {
    return res.status(403).json({ error: 'Access denied' });
  }
  
  const userId = req.params.id;
  
  // Prevent admin from deleting themselves
  if (userId === req.session.user.id) {
    return res.status(400).json({ error: 'Cannot delete your own account' });
  }
  
  const users = readUsers();
  const filteredUsers = users.filter(u => u.id !== userId);
  
  if (filteredUsers.length === users.length) {
    return res.status(404).json({ error: 'User not found' });
  }
  
  if (writeUsers(filteredUsers)) {
    res.json({ success: true, message: 'User deleted' });
  } else {
    res.status(500).json({ error: 'Failed to delete user' });
  }
});

// LaMa AI inpainting endpoint
app.post('/api/retouch', requireAuth, upload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No image uploaded' });
    }

    const { mask } = req.body;
    if (!mask) {
      return res.status(400).json({ error: 'Mask data is required' });
    }

    console.log('Processing retouch request:', {
      imageFile: req.file.filename,
      maskLength: mask.length
    });

    // Check if LaMa service is available (removed blocking check)
    const lamaUrl = 'http://localhost:5000/inpaint';
    
    // Prepare form data for LaMa service
    const FormData = require('form-data');
    const form = new FormData();
    
    // Add image file
    form.append('image', fs.createReadStream(req.file.path));
    
    // Add mask as base64 string
    form.append('mask', mask);

    try {
      const response = await axios.post(lamaUrl, form, {
        headers: {
          ...form.getHeaders(),
        },
        responseType: 'arraybuffer',
        timeout: 30000 // 30 second timeout
      });

      // Save the result
      const resultPath = path.join('uploads/temp', `result_${Date.now()}.jpg`);
      fs.writeFileSync(resultPath, response.data);

      // Clean up original upload
      fs.unlinkSync(req.file.path);

      res.json({
        success: true,
        resultUrl: `/${resultPath}`
      });

    } catch (lamaError) {
      console.error('LaMa service error:', lamaError.message);
      
      // Clean up uploaded file
      if (fs.existsSync(req.file.path)) {
        fs.unlinkSync(req.file.path);
      }
      
      res.status(503).json({ 
        error: 'AI service temporarily unavailable. Please try again later.',
        details: lamaError.message 
      });
    }

  } catch (error) {
    console.error('Retouch endpoint error:', error);
    
    // Clean up uploaded file
    if (req.file && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    timestamp: new Date().toISOString(),
    env: process.env.NODE_ENV || 'development'
  });
});

// Error handling middleware
app.use((error, req, res, next) => {
  console.error('Express error:', error);
  
  if (error instanceof multer.MulterError) {
    if (error.code === 'LIMIT_FILE_SIZE') {
      return res.status(413).json({ error: 'File too large' });
    }
  }
  
  res.status(500).json({ error: 'Internal server error' });
});

// 404 handler
app.use((req, res) => {
  res.status(404).send('Page not found');
});

// Start server
app.listen(port, () => {
  console.log(`Color360 server running on port ${port}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`Time: ${new Date().toISOString()}`);
});