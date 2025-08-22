#!/bin/bash
set -e

echo "Starting WordPress container..."
echo "Pod hostname: $(hostname)"

# Debug environment variables
echo "DB Host: $WORDPRESS_DB_HOST"
echo "DB User: $WORDPRESS_DB_USER" 
echo "DB Name: $WORDPRESS_DB_NAME"

# Wait for database to be ready
echo "Waiting for database connection..."
ATTEMPT=0
while ! mariadb -h"$WORDPRESS_DB_HOST" -u"$WORDPRESS_DB_USER" -p"$WORDPRESS_DB_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; do
    ATTEMPT=$((ATTEMPT + 1))
    echo "Attempt $ATTEMPT: Waiting for database... (Host: $WORDPRESS_DB_HOST, User: $WORDPRESS_DB_USER)"
    
    # Add detailed error on every 10th attempt
    if [ $((ATTEMPT % 10)) -eq 0 ]; then
        echo "Detailed connection test:"
        mariadb -h"$WORDPRESS_DB_HOST" -u"$WORDPRESS_DB_USER" -p"$WORDPRESS_DB_PASSWORD" -e "SELECT 1" 2>&1 || true
        echo "Testing basic connectivity:"
        nc -zv "$WORDPRESS_DB_HOST" 3306 2>&1 || true
    fi
    
    sleep 2
done
echo "Database connection established"

# Run WordPress setup only once across all replicas
/usr/local/bin/setup-wordpress.sh

# Continue with original WordPress entrypoint
exec docker-entrypoint.sh "$@"