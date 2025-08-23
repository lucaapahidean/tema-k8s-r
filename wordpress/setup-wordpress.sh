#!/bin/bash
set -e

cd /var/www/html

# Coordination files for multi-replica setup
LOCK_DIR="/var/www/html/.setup-lock"
COMPLETE_FILE="/var/www/html/.setup-complete"
PID_FILE="/var/www/html/.setup-pid"

# Function to cleanup on exit
cleanup() {
    if [ -f "$PID_FILE" ] && [ "$(cat $PID_FILE)" = "$$" ]; then
        echo "Cleaning up setup lock (PID $$)..."
        rm -rf "$LOCK_DIR" "$PID_FILE" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Function to create wp-config.php
create_wp_config() {
    cat > wp-config.php << 'WPCONFIG'
<?php
define( 'DB_NAME', getenv('WORDPRESS_DB_NAME') );
define( 'DB_USER', getenv('WORDPRESS_DB_USER') );
define( 'DB_PASSWORD', getenv('WORDPRESS_DB_PASSWORD') );
define( 'DB_HOST', getenv('WORDPRESS_DB_HOST') );
define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );

define( 'AUTH_KEY',         'put your unique phrase here' );
define( 'SECURE_AUTH_KEY',  'put your unique phrase here' );
define( 'LOGGED_IN_KEY',    'put your unique phrase here' );
define( 'NONCE_KEY',        'put your unique phrase here' );
define( 'AUTH_SALT',        'put your unique phrase here' );
define( 'SECURE_AUTH_SALT', 'put your unique phrase here' );
define( 'LOGGED_IN_SALT',   'put your unique phrase here' );
define( 'NONCE_SALT',       'put your unique phrase here' );

$table_prefix = 'wp_';

define( 'WP_DEBUG', false );
define( 'FS_METHOD', 'direct' );
define( 'WP_MEMORY_LIMIT', '512M' );

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
WPCONFIG
}

# Check if setup is already complete
if [ -f "$COMPLETE_FILE" ] && wp core is-installed --allow-root 2>/dev/null; then
    echo "WordPress already configured"
    exit 0
fi

# Clear any stale locks older than 10 minutes
if [ -d "$LOCK_DIR" ] && [ -f "$PID_FILE" ]; then
    LOCK_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$LOCK_PID" ] && ! kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "Clearing stale setup lock (process $LOCK_PID no longer exists)"
        rm -rf "$LOCK_DIR" "$PID_FILE" 2>/dev/null || true
    fi
fi

# Try to acquire setup lock with shorter timeout
LOCK_TIMEOUT=30  # 30 seconds only
LOCK_ACQUIRED=false

for i in $(seq 1 $LOCK_TIMEOUT); do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo $$ > "$PID_FILE"
        LOCK_ACQUIRED=true
        echo "Acquired setup lock - $(hostname) (PID $$) will configure WordPress"
        break
    else
        if [ $((i % 10)) -eq 0 ]; then
            echo "Waiting for setup lock... ($i/$LOCK_TIMEOUT)"
        fi
        sleep 1
    fi
done

if [ "$LOCK_ACQUIRED" = "true" ]; then
    # We got the lock, do the setup
    echo "Starting WordPress configuration..."
    
    # Get Node IP for URLs
    NODE_IP="${KUBERNETES_NODE_IP:-localhost}"
    SITE_URL="http://$NODE_IP:30080"

    # Force remove existing wp-config to ensure our version is used
    rm -f wp-config.php

    # Create our wp-config.php
    echo "Creating wp-config.php..."
    create_wp_config

    # Install WordPress if not already installed (NO --timeout parameter)
    if ! wp core is-installed --allow-root 2>/dev/null; then
        echo "Installing WordPress..."
        
        wp core install \
            --url="$SITE_URL" \
            --title="Cloud-Native Demo Platform" \
            --admin_user="admin" \
            --admin_password="admin123" \
            --admin_email="admin@example.com" \
            --skip-email \
            --allow-root
        
        echo "WordPress core installed"
    fi

    # Update URLs
    wp option update home "$SITE_URL" --allow-root
    wp option update siteurl "$SITE_URL" --allow-root

    # Install and activate theme (NO --timeout parameter)
    echo "Setting up theme..."
    wp theme install twentytwentyfour --activate --allow-root 2>/dev/null || {
        echo "Theme installation failed, using default theme"
        wp theme activate twentytwentyfour --allow-root 2>/dev/null || true
    }

    # Create integration page
    echo "Creating integration page..."
    PAGE_EXISTS=$(wp post list --post_type=page --title="Integrated Platform" --format=count --allow-root 2>/dev/null || echo "0")

    if [ "$PAGE_EXISTS" = "0" ]; then
        HOMEPAGE_ID=$(wp post create /tmp/integration-page.html \
            --post_type=page \
            --post_title="Integrated Platform" \
            --post_status=publish \
            --format=ids \
            --allow-root)
        
        if [ -n "$HOMEPAGE_ID" ]; then
            # Set as homepage
            wp option update show_on_front page --allow-root
            wp option update page_on_front "$HOMEPAGE_ID" --allow-root
            echo "Integration page created and set as homepage (ID: $HOMEPAGE_ID)"
        fi
    fi

    # Fix permissions
    echo "Fixing permissions..."
    chown -R www-data:www-data /var/www/html 2>/dev/null || true
    chmod -R 755 /var/www/html 2>/dev/null || true

    # Mark setup as complete
    touch "$COMPLETE_FILE"
    echo "WordPress setup complete!"

    echo "Admin Credentials:"
    echo "   URL: $SITE_URL/wp-admin"
    echo "   Username: admin"
    echo "   Password: admin123"
    
else
    echo "Could not acquire setup lock, another replica may be setting up..."
    
    # Wait briefly for setup completion
    for i in {1..30}; do
        if [ -f "$COMPLETE_FILE" ]; then
            echo "Setup completed by another replica"
            break
        fi
        sleep 1
    done
fi