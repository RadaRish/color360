#!/bin/bash

# Deployment script for Color360 on VPS TimeWeb
# Run this script on your VPS as root or with sudo

set -e

# Configuration
APP_NAME="color360"
APP_USER="www-data"
APP_DIR="/var/www/color360"
NGINX_SITE="color360.ru"
NODE_VERSION="18"

echo "🚀 Starting deployment of Color360..."

# Update system
echo "📦 Updating system packages..."
apt update && apt upgrade -y

# Install Node.js
echo "📦 Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo -E bash -
apt install -y nodejs

# Install PM2 globally
echo "📦 Installing PM2..."
npm install -g pm2

# Install Nginx
echo "📦 Installing Nginx..."
apt install -y nginx

# Create application directory
echo "📁 Creating application directory..."
mkdir -p $APP_DIR
chown $APP_USER:$APP_USER $APP_DIR

# Install dependencies
echo "📦 Installing dependencies..."
cd $APP_DIR
npm install --production

# Install SSL certificate (Let's Encrypt)
echo "🔒 Setting up SSL certificate..."
apt install -y certbot python3-certbot-nginx
certbot --nginx -d $NGINX_SITE -d www.$NGINX_SITE --non-interactive --agree-tos --email admin@color360.ru

# Setup PM2
echo "⚙️ Setting up PM2..."
pm2 start ecosystem.config.json
pm2 save
pm2 startup
env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u $APP_USER --hp /home/$APP_USER

# Configure Nginx
echo "⚙️ Configuring Nginx..."
cp nginx.conf /etc/nginx/sites-available/$NGINX_SITE
ln -sf /etc/nginx/sites-available/$NGINX_SITE /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# Create log directories
echo "📁 Creating log directories..."
mkdir -p /var/log/pm2
chown $APP_USER:$APP_USER /var/log/pm2

# Setup firewall
echo "🔥 Configuring firewall..."
ufw allow 'Nginx Full'
ufw allow ssh
ufw --force enable

# Create backup script
echo "💾 Creating backup script..."
cat > /usr/local/bin/color360-backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/color360"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR
tar -czf $BACKUP_DIR/color360_backup_$DATE.tar.gz -C /var/www color360
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete
EOF
chmod +x /usr/local/bin/color360-backup.sh

# Setup cron for backups
echo "⏰ Setting up automated backups..."
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/color360-backup.sh") | crontab -

echo "✅ Deployment completed successfully!"
echo "🌐 Your site should be available at: https://$NGINX_SITE"
echo "🔧 PM2 status: pm2 status"
echo "📊 Nginx status: systemctl status nginx"
echo "💾 Backups are stored in: /var/backups/color360"