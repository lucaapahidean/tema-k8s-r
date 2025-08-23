#!/bin/bash
set -e

echo "Starting WordPress container..."
echo "Pod hostname: $(hostname)"
echo "Node IP: ${KUBERNETES_NODE_IP:-unknown}"

# Wait for database to be ready
echo "Waiting for database connection..."
ATTEMPT=0
MAX_ATTEMPTS=30

while ! mysqladmin ping -h"$WORDPRESS_DB_HOST" -u"$WORDPRESS_DB_USER" -p"$WORDPRESS_DB_PASSWORD" --silent 2>/dev/null; do
    ATTEMPT=$((ATTEMPT + 1))
    echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Waiting for database..."
    
    if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
        echo "Failed to connect to database after $MAX_ATTEMPTS attempts"
        echo "Trying to start Apache anyway..."
        break
    fi
    
    sleep 2
done

if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
    echo "Database connection established"
fi

# Run WordPress setup
echo "Running WordPress setup..."
/usr/local/bin/setup-wordpress.sh || {
    echo "WordPress setup failed, continuing with Apache..."
}

# Start Apache
echo "Starting Apache server..."
exec docker-entrypoint.sh "$@"