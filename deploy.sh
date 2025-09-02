#!/bin/bash

# Color360 Deployment Script for VPS

set -e  # Exit on any error

echo "Starting Color360 deployment..."

# Check if docker and docker-compose are installed
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Create necessary directories
echo "Creating directories..."
mkdir -p data
mkdir -p ssl
mkdir -p logs

# Build and start services
echo "Building and starting services..."
docker-compose up -d --build

# Wait for services to start
echo "Waiting for services to start..."
sleep 10

# Check if services are running
echo "Checking service status..."
if docker-compose ps | grep -q "Up"; then
    echo "Services are running successfully!"
else
    echo "Some services failed to start. Check logs with 'docker-compose logs'"
    exit 1
fi

# Show running containers
echo "Running containers:"
docker-compose ps

echo "Deployment completed successfully!"
echo "Access your application at http://your-server-ip"