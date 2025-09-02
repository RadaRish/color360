# Color360 Deployment Guide

This guide explains how to deploy the Color360 site and panorama editor application on a VPS for online access.

## Architecture Overview

The deployment consists of three main components:
1. **Main Site** - Express.js application serving the landing page and API
2. **Panorama Editor** - Static HTML/JS application for creating tours
3. **Nginx Proxy** - Reverse proxy routing requests to the appropriate service

## Prerequisites

- Ubuntu 20.04+ or CentOS 8+ VPS
- Docker and Docker Compose installed
- Domain name (optional but recommended)
- Firewall configured to allow ports 80 and 443

## Installation

### 1. Install Docker and Docker Compose

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install docker.io docker-compose -y

# Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker

# Add current user to docker group
sudo usermod -aG docker $USER
```

### 2. Clone the Repository

```bash
git clone <your-repo-url> /opt/color360
cd /opt/color360
```

### 3. Deploy with Docker Compose

```bash
# Make deploy script executable
chmod +x deploy.sh

# Run deployment
./deploy.sh
```

Or manually:

```bash
# Create necessary directories
mkdir -p data ssl logs

# Build and start services
docker-compose up -d --build
```

## Configuration

### Environment Variables

The main site can be configured with these environment variables:
- `PORT` - Port to run the main site on (default: 3000)
- `NODE_ENV` - Environment (production/development)

### SSL Setup with Let's Encrypt

1. Install Certbot:
```bash
sudo apt install certbot python3-certbot-nginx -y
```

2. Obtain certificate:
```bash
sudo certbot --nginx -d yourdomain.com
```

3. Update nginx.conf for HTTPS (replace the server block):
```nginx
server {
    listen 80;
    server_name yourdomain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    # Include the rest of your nginx configuration here
}
```

## Accessing the Application

After deployment, the application will be accessible at:
- Main site: http://your-server-ip
- Panorama editor: http://your-server-ip/pano

With domain and SSL:
- Main site: https://yourdomain.com
- Panorama editor: https://yourdomain.com/pano

## Data Persistence

User data and panorama projects are stored in:
- Main site data: `./data` directory
- Panorama exports: `./pano/export` directory

These directories are mounted as volumes in the Docker containers.

## Monitoring and Maintenance

### Check Service Status
```bash
docker-compose ps
```

### View Logs
```bash
# Main site logs
docker-compose logs color360-main

# Panorama editor logs
docker-compose logs color360-pano

# Nginx logs
docker-compose logs nginx
```

### Update Application
```bash
# Pull latest changes
git pull

# Rebuild and restart services
docker-compose up -d --build
```

## Backup Strategy

### Automated Backup Script
```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/color360_$DATE"

mkdir -p $BACKUP_DIR

# Backup main site data
cp -r /opt/color360/data $BACKUP_DIR/

# Backup panorama exports
cp -r /opt/color360/pano/export $BACKUP_DIR/

# Compress backup
tar -czf "/backup/color360_backup_$DATE.tar.gz" $BACKUP_DIR

# Remove old backups (keep last 30 days)
find /backup -name "color360_backup_*.tar.gz" -mtime +30 -delete
```

## Troubleshooting

### Common Issues

1. **Ports already in use**:
   - Check if other services are using ports 80, 443, or 3000
   - Modify docker-compose.yml to use different ports

2. **Permission denied errors**:
   - Ensure current user is in the docker group
   - Run commands with sudo if necessary

3. **Services not starting**:
   - Check logs with `docker-compose logs`
   - Verify all files have correct permissions

4. **Application not accessible**:
   - Check firewall settings
   - Verify nginx configuration
   - Ensure domain DNS is pointing to the VPS

### Health Check

Access http://your-server-ip/health to verify the application is running.

## Scaling Considerations

For high-traffic deployments:
1. Use a load balancer for multiple instances
2. Implement Redis for session storage
3. Use a database instead of in-memory storage
4. Add CDN for static assets
5. Implement monitoring with Prometheus/Grafana