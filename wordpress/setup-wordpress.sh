#!/bin/bash
set -e

cd /var/www/html

# Coordination files for multi-replica setup
LOCK_FILE="/var/www/html/.setup-lock"
COMPLETE_FILE="/var/www/html/.setup-complete"

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

define( 'AUTH_KEY',         'your-auth-key-here' );
define( 'SECURE_AUTH_KEY',  'your-secure-auth-key-here' );
define( 'LOGGED_IN_KEY',    'your-logged-in-key-here' );
define( 'NONCE_KEY',        'your-nonce-key-here' );
define( 'AUTH_SALT',        'your-auth-salt-here' );
define( 'SECURE_AUTH_SALT', 'your-secure-auth-salt-here' );
define( 'LOGGED_IN_SALT',   'your-logged-in-salt-here' );
define( 'NONCE_SALT',       'your-nonce-salt-here' );

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
    echo "✅ WordPress already configured"
    exit 0
fi

# Try to acquire setup lock
if mkdir "$LOCK_FILE" 2>/dev/null; then
    echo "🔒 Acquired setup lock - $(hostname) will configure WordPress"
    
    # Cleanup on exit
    trap 'rm -rf "$LOCK_FILE"' EXIT
    
    # Get Node IP for URLs
    NODE_IP="${KUBERNETES_NODE_IP:-localhost}"
    SITE_URL="http://$NODE_IP:30080"
    
    if [ ! -f wp-config.php ]; then
        echo "📥 Downloading WordPress core..."
        wp core download --allow-root --force
        
        echo "🔧 Creating wp-config.php..."
        create_wp_config
    fi
    
    # Install WordPress if not already installed
    if ! wp core is-installed --allow-root 2>/dev/null; then
        echo "🗄️ Installing WordPress..."
        wp core install \
            --url="$SITE_URL" \
            --title="Cloud-Native Demo Platform" \
            --admin_user="admin" \
            --admin_password="admin123" \
            --admin_email="admin@example.com" \
            --skip-email \
            --allow-root
    fi
    
    # Update URLs
    wp option update home "$SITE_URL" --allow-root
    wp option update siteurl "$SITE_URL" --allow-root
    
    # Install and activate theme
    echo "🎨 Setting up theme..."
    wp theme install twentytwentyfour --activate --allow-root 2>/dev/null || true
    
    # Create integration page
    echo "📄 Creating integration page..."
    PAGE_EXISTS=$(wp post list --post_type=page --title="Integrated Platform" --format=count --allow-root 2>/dev/null || echo "0")
    
    if [ "$PAGE_EXISTS" = "0" ]; then
        # Create page with integration content
        HOMEPAGE_ID=$(wp post create /tmp/integration-page.html \
            --post_type=page \
            --post_title="Integrated Platform" \
            --post_status=publish \
            --format=ids \
            --allow-root)
        
        # Set as homepage
        wp option update show_on_front page --allow-root
        wp option update page_on_front "$HOMEPAGE_ID" --allow-root
        
        echo "✅ Integration page created and set as homepage (ID: $HOMEPAGE_ID)"
    fi
    
    # Mark setup as complete
    touch "$COMPLETE_FILE"
    echo "✅ WordPress setup complete!"
    
    echo "🔐 Admin Credentials:"
    echo "   URL: $SITE_URL/wp-admin"
    echo "   Username: admin"
    echo "   Password: admin123"
    
else
    echo "⏳ Another replica is setting up WordPress, waiting..."
    # Wait for setup to complete
    while [ ! -f "$COMPLETE_FILE" ]; do
        sleep 5
    done
    echo "✅ Setup completed by primary replica"
fi

# Fix permissions
chown -R www-data:www-data /var/www/html 2>/dev/null || true