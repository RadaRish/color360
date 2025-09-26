@echo off
echo Starting Color360 Development Server...
echo.
echo Opening main page: http://localhost:5500
echo Opening pano editor: http://localhost:5500/pano/
echo.
echo Press Ctrl+C to stop the server
echo.

REM Start live server if available
if exist "%CD%\node_modules\.bin\live-server.cmd" (
    "%CD%\node_modules\.bin\live-server.cmd" --port=5500 --open=/ --no-browser
) else (
    echo Live Server not found. Installing...
    npm install -g live-server
    live-server --port=5500 --open=/ --no-browser
)

pause