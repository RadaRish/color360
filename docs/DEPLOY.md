# VPS Deployment Guide for Panorama Tour Editor

## Prerequisites

- Ubuntu 20.04+ or CentOS 8+
- Docker and Docker Compose installed
- Domain name pointing to your VPS
- SSL certificate (Let's Encrypt recommended)

## Quick Deploy

### 1. Clone and build

```bash
git clone <your-repo-url> /opt/panorama-editor
cd /opt/panorama-editor
docker build -t panorama-editor .
```

### 2. Run with Docker

```bash
docker run -d \
  --name panorama-editor \
  -p 80:80 \
  --restart unless-stopped \
  panorama-editor
```

### 3. Or use Docker Compose

```bash
# Create docker-compose.yml
cat > docker-compose.yml << EOF
version: '3.8'
services:
  panorama-editor:
    build: .
    ports:
      - "80:80"
    restart: unless-stopped
    volumes:
      - ./export:/usr/share/nginx/html/export
EOF

# Deploy
docker-compose up -d
```

## SSL Setup with Let's Encrypt

### 1. Install Certbot

```bash
sudo apt update
sudo apt install certbot python3-certbot-nginx
```

### 2. Get certificate

```bash
sudo certbot --nginx -d yourdomain.com
```

### 3. Update nginx config for HTTPS

Add to nginx.conf:

```nginx
server {
    listen 443 ssl http2;
    server_name yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    # Your existing config...
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name yourdomain.com;
    return 301 https://$server_name$request_uri;
}
```

## Production Optimizations

### 1. Enable caching

```nginx
# In nginx.conf
location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
}
```

### 2. Enable compression

```nginx
gzip on;
gzip_types text/plain text/css application/json application/javascript;
```

### 3. Security headers

```nginx
add_header X-Frame-Options "SAMEORIGIN";
add_header X-Content-Type-Options "nosniff";
add_header X-XSS-Protection "1; mode=block";
```

## Backup Strategy

### 1. User data backup

```bash
# Backup user projects
docker exec panorama-editor tar -czf /tmp/projects.tar.gz /usr/share/nginx/html/export
docker cp panorama-editor:/tmp/projects.tar.gz ./backup/
```

### 2. Automated backup script

```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
docker exec panorama-editor tar -czf /tmp/backup_$DATE.tar.gz /usr/share/nginx/html/export
docker cp panorama-editor:/tmp/backup_$DATE.tar.gz /backup/
# Remove backups older than 30 days
find /backup -name "backup_*.tar.gz" -mtime +30 -delete
```

## Monitoring

### 1. Health check

```bash
curl -f http://localhost/index.html || echo "Service down"
```

### 2. Log monitoring

```bash
docker logs panorama-editor --tail 100 -f
```

## Troubleshooting

### Common issues:

1. **Port 80/443 blocked**: Check firewall settings
2. **SSL errors**: Verify domain DNS and certificate paths
3. **Memory issues**: Increase Docker memory limits
4. **File upload issues**: Check nginx client_max_body_size

### Performance tuning:

1. Increase nginx worker processes
2. Enable HTTP/2
3. Use CDN for static assets
4. Implement Redis caching if needed
