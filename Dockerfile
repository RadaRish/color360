# Multi-stage build for Color360 main site
FROM node:18-alpine AS build

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source files
COPY . .

# Production stage with Node.js
FROM node:18-alpine

WORKDIR /app

# Copy built application and dependencies
COPY --from=build /app .

# Expose port
EXPOSE 3000

# Start the application
CMD ["node", "server.js"]