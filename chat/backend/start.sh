#!/bin/sh
# Start Python FastAPI server and Nginx

echo "Starting Chat Backend with Python + Nginx..."

# Așteaptă serviciile dependencies să fie disponibile
echo "Waiting for dependencies to be ready..."
sleep 10

# Start FastAPI server in background
echo "Starting FastAPI server on port 3000..."
cd /app && python3 server.py &
PYTHON_PID=$!

# Verifică dacă procesul Python a pornit
sleep 2
if ! kill -0 $PYTHON_PID 2>/dev/null; then
    echo "ERROR: Python server failed to start!"
    exit 1
fi

# Așteaptă ca serverul Python să fie gata să primească conexiuni
echo "Waiting for Python server to be ready..."
for i in {1..30}; do
    if wget -q -O /dev/null http://localhost:3000/health 2>/dev/null; then
        echo "Python server is ready!"
        break
    fi
    echo "Waiting for Python server... ($i/30)"
    sleep 2
done

# Verifică din nou dacă procesul Python încă rulează
if ! kill -0 $PYTHON_PID 2>/dev/null; then
    echo "ERROR: Python server died during startup!"
    exit 1
fi

# Start Nginx în foreground
echo "Starting Nginx..."
nginx -g 'daemon off;'