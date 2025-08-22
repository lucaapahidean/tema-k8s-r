#!/bin/sh

echo "Starting Chat Backend..."

# Start FastAPI server in background
cd /app && python3 server.py &
PYTHON_PID=$!

# Wait briefly for Python server to start
sleep 3

# Check if Python process is running
if ! kill -0 $PYTHON_PID 2>/dev/null; then
    echo "ERROR: Python server failed to start!"
    exit 1
fi

# Start Nginx in foreground
exec nginx -g 'daemon off;'