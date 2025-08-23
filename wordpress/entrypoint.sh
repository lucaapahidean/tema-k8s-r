#!/bin/bash
set -e

echo "Starting WordPress container..."
echo "Pod hostname: $(hostname)"

# Wait for database to be ready
echo "Waiting for database connection..."
ATTEMPT=0
MAX_ATTEMPTS=20

while ! mysql -h"$WORDPRESS_DB_HOST" -u"$WORDPRESS_DB_USER" -p"$WORDPRESS_DB_PASSWORD" --skip-ssl -e "SELECT 1" >/dev/null 2>&1; do
    ATTEMPT=$((ATTEMPT + 1))
    echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Waiting for database..."
    
    if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
        echo "Failed to connect to database, starting Apache anyway..."
        exec docker-entrypoint.sh "$@"
    fi
    
    sleep 3
done
echo "Database connection established"

# Run WordPress setup with timeout protection
echo "Running WordPress setup..."
timeout 120 /usr/local/bin/setup-wordpress.sh || {
    echo "WordPress setup timed out or failed, continuing with Apache..."
}

# Start Apache
echo "Starting Apache server..."
exec docker-entrypoint.sh "$@"