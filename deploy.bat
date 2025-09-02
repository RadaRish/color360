@echo off
REM Color360 Deployment Script for Windows

echo Starting Color360 deployment...

REM Check if docker is installed
docker --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Docker is not installed. Please install Docker Desktop first.
    exit /b 1
)

REM Check if docker-compose is installed
docker-compose --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Docker Compose is not installed. Please install Docker Desktop which includes Docker Compose.
    exit /b 1
)

REM Create necessary directories
echo Creating directories...
mkdir data 2>nul
mkdir ssl 2>nul
mkdir logs 2>nul

REM Build and start services
echo Building and starting services...
docker-compose up -d --build

REM Wait for services to start
echo Waiting for services to start...
timeout /t 10 /nobreak >nul

REM Check if services are running
echo Checking service status...
docker-compose ps | findstr "Up" >nul
if %errorlevel% equ 0 (
    echo Services are running successfully!
) else (
    echo Some services failed to start. Check logs with 'docker-compose logs'
    exit /b 1
)

REM Show running containers
echo Running containers:
docker-compose ps

echo Deployment completed successfully!
echo Access your application at http://localhost
pause