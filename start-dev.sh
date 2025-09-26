#!/bin/bash
echo "🚀 Starting Color360 Development Server..."
echo ""
echo "📍 Main page: http://localhost:5500"
echo "🎨 Pano editor: http://localhost:5500/pano/"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

# Check if live-server is installed
if command -v live-server &> /dev/null; then
    live-server --port=5500 --open=/ --no-browser
elif [ -f "./node_modules/.bin/live-server" ]; then
    ./node_modules/.bin/live-server --port=5500 --open=/ --no-browser
else
    echo "Installing live-server..."
    npm install -g live-server
    live-server --port=5500 --open=/ --no-browser
fi