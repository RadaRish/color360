# Multi-stage build for panorama tour editor
FROM node:18-alpine AS build

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source files
COPY . .

# Build and optimize
RUN npm run build

# Production stage with Nginx
FROM nginx:alpine

# Copy custom nginx config
COPY nginx.conf /etc/nginx/nginx.conf

# Copy built application
COPY --from=build /app /usr/share/nginx/html

# Remove development files
RUN rm -rf /usr/share/nginx/html/node_modules \
    /usr/share/nginx/html/package*.json \
    /usr/share/nginx/html/scripts \
    /usr/share/nginx/html/*.md

# Expose port
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]