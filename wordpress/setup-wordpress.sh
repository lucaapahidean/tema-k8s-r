#!/bin/bash
set -e

cd /var/www/html

# Coordination files
LOCK_DIR="/var/www/html/.setup-lock"
COMPLETE_FILE="/var/www/html/.setup-complete"
PID_FILE="/var/www/html/.setup-pid"

# Function to cleanup on exit
cleanup() {
    if [ -f "$PID_FILE" ] && [ "$(cat $PID_FILE 2>/dev/null)" = "$$" ]; then
        echo "Cleaning up setup lock (PID $$)..."
        rm -rf "$LOCK_DIR" "$PID_FILE" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Function to create wp-config.php with proper settings
create_wp_config() {
    cat > wp-config.php << 'WPCONFIG'
<?php
define( 'DB_NAME', getenv('WORDPRESS_DB_NAME') );
define( 'DB_USER', getenv('WORDPRESS_DB_USER') );
define( 'DB_PASSWORD', getenv('WORDPRESS_DB_PASSWORD') );
define( 'DB_HOST', getenv('WORDPRESS_DB_HOST') );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

// Authentication Keys
define( 'AUTH_KEY',         'K8s-auth-key-2025-random-string-here' );
define( 'SECURE_AUTH_KEY',  'K8s-secure-auth-key-2025-random' );
define( 'LOGGED_IN_KEY',    'K8s-logged-in-key-2025-random' );
define( 'NONCE_KEY',        'K8s-nonce-key-2025-random-string' );
define( 'AUTH_SALT',        'K8s-auth-salt-2025-random-string' );
define( 'SECURE_AUTH_SALT', 'K8s-secure-auth-salt-2025-random' );
define( 'LOGGED_IN_SALT',   'K8s-logged-in-salt-2025-random' );
define( 'NONCE_SALT',       'K8s-nonce-salt-2025-random-string' );

$table_prefix = 'wp_';

// Important: Disable SSL redirects and force HTTP
define( 'FORCE_SSL_ADMIN', false );
define( 'FORCE_SSL_LOGIN', false );
define( 'WP_HOME', 'http://' . getenv('KUBERNETES_NODE_IP') . ':30080' );
define( 'WP_SITEURL', 'http://' . getenv('KUBERNETES_NODE_IP') . ':30080' );

// Performance and debugging
define( 'WP_DEBUG', false );
define( 'WP_DEBUG_LOG', false );
define( 'WP_DEBUG_DISPLAY', false );
define( 'SCRIPT_DEBUG', false );

// File system
define( 'FS_METHOD', 'direct' );
define( 'WP_MEMORY_LIMIT', '256M' );
define( 'WP_MAX_MEMORY_LIMIT', '512M' );

// Disable automatic updates
define( 'AUTOMATIC_UPDATER_DISABLED', true );
define( 'WP_AUTO_UPDATE_CORE', false );

// Security
define( 'DISALLOW_FILE_EDIT', true );
define( 'DISALLOW_FILE_MODS', false );

// Handle proxy and load balancer headers
if ( isset( $_SERVER['HTTP_X_FORWARDED_HOST'] ) ) {
    $_SERVER['HTTP_HOST'] = $_SERVER['HTTP_X_FORWARDED_HOST'];
}

if ( isset( $_SERVER['HTTP_X_FORWARDED_PROTO'] ) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) {
    $_SERVER['HTTPS'] = 'on';
}

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
WPCONFIG
}

# Function to setup custom PHP template for integration page
setup_integration_template() {
    echo "Setting up integration page template..."
    
    # Get current theme directory
    local theme_dir=$(wp theme path --allow-root 2>/dev/null)
    if [ -z "$theme_dir" ]; then
        # Fallback to default theme directory structure
        theme_dir="/var/www/html/wp-content/themes"
        local active_theme=$(wp option get template --allow-root 2>/dev/null || echo "twentytwentyfour")
        theme_dir="$theme_dir/$active_theme"
    else
        local active_theme=$(wp option get template --allow-root 2>/dev/null || echo "twentytwentyfour")
        theme_dir="$theme_dir/$active_theme"
    fi
    
    echo "Theme directory: $theme_dir"
    
    # Ensure theme directory exists
    if [ ! -d "$theme_dir" ]; then
        echo "Theme directory does not exist, creating fallback..."
        mkdir -p "/var/www/html/wp-content/themes/custom"
        theme_dir="/var/www/html/wp-content/themes/custom"
        
        # Create basic theme files
        cat > "$theme_dir/style.css" << 'EOF'
/*
Theme Name: Custom Integration Theme
Description: Custom theme for Kubernetes integration demo
Version: 1.0
*/
EOF
        
        cat > "$theme_dir/index.php" << 'EOF'
<?php
// Basic theme index
get_header();
if (have_posts()) :
    while (have_posts()) : the_post();
        the_content();
    endwhile;
endif;
get_footer();
?>
EOF
        
        # Activate the custom theme
        wp theme activate custom --allow-root 2>/dev/null || true
    fi
    
    # Copy the integration template
    if [ -f "/tmp/integration-page.php" ]; then
        cp "/tmp/integration-page.php" "$theme_dir/page-integration.php"
        chown www-data:www-data "$theme_dir/page-integration.php"
        echo "✓ Integration template installed: $theme_dir/page-integration.php"
        return 0
    else
        echo "⚠ Integration PHP template not found at /tmp/integration-page.php"
        return 1
    fi
}

# Function to create integration page with custom template
create_integration_page() {
    echo "Creating integration page with custom template..."
    
    # Check if page already exists
    local page_exists=$(wp post list --post_type=page --name="integration" --format=count --allow-root 2>/dev/null || echo "0")
    
    if [ "$page_exists" = "0" ]; then
        # Create the page
        local page_id=$(wp post create \
            --post_type=page \
            --post_title="Integrated Platform" \
            --post_name="integration" \
            --post_status=publish \
            --page_template="page-integration.php" \
            --format=ids \
            --allow-root 2>/dev/null)
        
        if [ -n "$page_id" ]; then
            echo "✓ Integration page created with ID: $page_id"
            
            # Set as homepage
            wp option update show_on_front page --allow-root
            wp option update page_on_front "$page_id" --allow-root
            echo "✓ Integration page set as homepage"
            
            return 0
        else
            echo "✗ Failed to create integration page"
            return 1
        fi
    else
        echo "Integration page already exists"
        
        # Update existing page to use the template
        local page_id=$(wp post list --post_type=page --name="integration" --format=ids --allow-root 2>/dev/null | head -1)
        if [ -n "$page_id" ]; then
            wp post meta update "$page_id" "_wp_page_template" "page-integration.php" --allow-root 2>/dev/null || true
            echo "✓ Updated existing page to use integration template"
        fi
        
        return 0
    fi
}

# Function to create URL rewrite rules for clean integration access
setup_url_rewrites() {
    echo "Setting up URL rewrites..."
    
    # Update .htaccess with custom rules
    cat > .htaccess << 'HTACCESS'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /

# Custom rule for integration page (serve directly)
RewriteRule ^$ /integration/ [R=301,L]
RewriteRule ^integration/?$ /index.php?pagename=integration [QSA,L]

# Standard WordPress rules
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress

# Disable HTTPS redirect
<IfModule mod_rewrite.c>
RewriteCond %{HTTPS} on
RewriteRule ^(.*)$ http://%{HTTP_HOST}/$1 [R=301,L]
</IfModule>

# Security headers
<IfModule mod_headers.c>
Header always set X-Frame-Options SAMEORIGIN
Header always set X-Content-Type-Options nosniff
Header always unset X-Powered-By
</IfModule>
HTACCESS
    
    chown www-data:www-data .htaccess
    echo "✓ URL rewrites configured"
}

# Check if setup is already complete
if [ -f "$COMPLETE_FILE" ]; then
    echo "WordPress already configured (complete file exists)"
    
    # Ensure wp-config.php exists with correct settings
    if [ ! -f "wp-config.php" ]; then
        echo "Recreating wp-config.php..."
        create_wp_config
        chown www-data:www-data wp-config.php
    fi
    
    # Always ensure integration template is up to date
    setup_integration_template
    
    exit 0
fi

# Clear stale locks
if [ -d "$LOCK_DIR" ] && [ -f "$PID_FILE" ]; then
    LOCK_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$LOCK_PID" ] && ! kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "Clearing stale setup lock (process $LOCK_PID no longer exists)"
        rm -rf "$LOCK_DIR" "$PID_FILE" 2>/dev/null || true
    fi
fi

# Try to acquire setup lock
LOCK_TIMEOUT=60
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
    echo "Starting WordPress configuration..."
    
    # Get Node IP for URLs
    NODE_IP="${KUBERNETES_NODE_IP:-localhost}"
    SITE_URL="http://$NODE_IP:30080"
    
    echo "Configuring WordPress for URL: $SITE_URL"
    echo "Node IP: $NODE_IP"

    # Remove any existing wp-config
    rm -f wp-config.php wp-config-sample.php

    # Create our wp-config.php
    echo "Creating wp-config.php..."
    create_wp_config

    # Check if WordPress is installed
    if ! wp core is-installed --allow-root 2>/dev/null; then
        echo "Installing WordPress core..."
        
        # Install WordPress
        wp core install \
            --url="$SITE_URL" \
            --title="Cloud-Native Platform - Kubernetes Demo" \
            --admin_user="admin" \
            --admin_password="admin123" \
            --admin_email="admin@k8s.local" \
            --skip-email \
            --allow-root || {
                echo "WordPress installation failed!"
                exit 1
            }
        
        echo "WordPress core installed successfully"
    else
        echo "WordPress is already installed"
    fi

    # Force update URLs to avoid redirects
    echo "Updating WordPress URLs..."
    wp option update home "$SITE_URL" --allow-root
    wp option update siteurl "$SITE_URL" --allow-root
    
    # Disable HTTPS redirect
    wp option delete force_ssl_admin --allow-root 2>/dev/null || true
    wp option delete force_ssl_login --allow-root 2>/dev/null || true

    # Setup integration template and page
    if setup_integration_template; then
        create_integration_page
        echo "✓ Integration template setup completed"
    else
        echo "⚠ Integration template setup failed - using fallback method"
        
        # Fallback: create simple page with iframe content
        PAGE_EXISTS=$(wp post list --post_type=page --title="Integrated Platform" --format=count --allow-root 2>/dev/null || echo "0")
        if [ "$PAGE_EXISTS" = "0" ]; then
            wp post create \
                --post_type=page \
                --post_title="Integrated Platform" \
                --post_content="<iframe src=\"http://$NODE_IP:30090\" width=\"100%\" height=\"600\" style=\"border:1px solid #ccc; margin-bottom: 20px;\"></iframe><iframe src=\"http://$NODE_IP:30180\" width=\"100%\" height=\"600\" style=\"border:1px solid #ccc;\"></iframe>" \
                --post_status=publish \
                --post_name="integration" \
                --allow-root 2>/dev/null || true
        fi
    fi

    # Setup URL rewrites
    setup_url_rewrites

    # Create a simple test page
    echo "Creating test page..."
    TEST_PAGE_EXISTS=$(wp post list --post_type=page --title="Test Page" --format=count --allow-root 2>/dev/null || echo "0")

    if [ "$TEST_PAGE_EXISTS" = "0" ]; then
        wp post create \
            --post_type=page \
            --post_title="Test Page" \
            --post_content="<h1>WordPress is running on Kubernetes!</h1><p>Node IP: $NODE_IP</p><p>Chat: <a href=\"http://$NODE_IP:30090\" target=\"_blank\">http://$NODE_IP:30090</a></p><p>AI: <a href=\"http://$NODE_IP:30180\" target=\"_blank\">http://$NODE_IP:30180</a></p>" \
            --post_status=publish \
            --allow-root 2>/dev/null || true
        echo "Test page created successfully"
    else
        echo "Test page already exists (count: $TEST_PAGE_EXISTS)"
    fi

    # Disable all plugins that might cause redirects
    wp plugin deactivate --all --allow-root 2>/dev/null || true

    # Fix permissions
    echo "Fixing permissions..."
    chown -R www-data:www-data /var/www/html
    chmod -R 755 /var/www/html
    chmod 644 wp-config.php .htaccess 2>/dev/null || true

    # Mark setup as complete
    touch "$COMPLETE_FILE"
    chown www-data:www-data "$COMPLETE_FILE"
    
    echo "================================"
    echo "WordPress setup complete!"
    echo "================================"
    echo "Site URL: $SITE_URL"
    echo "Integration: $SITE_URL/integration/"
    echo "Admin URL: $SITE_URL/wp-admin"
    echo "Username: admin"
    echo "Password: admin123"
    echo "Node IP: $NODE_IP"
    echo "Chat App: http://$NODE_IP:30090"
    echo "AI App: http://$NODE_IP:30180"
    echo "✓ PHP-based integration template active"
    echo "================================"
    
else
    echo "Could not acquire setup lock after $LOCK_TIMEOUT seconds"
    echo "Another replica may be setting up WordPress..."
    
    # Wait for setup completion
    echo "Waiting for setup to complete..."
    for i in {1..60}; do
        if [ -f "$COMPLETE_FILE" ]; then
            echo "Setup completed by another replica"
            
            # Ensure wp-config exists
            if [ ! -f "wp-config.php" ]; then
                echo "Creating wp-config.php..."
                create_wp_config
                chown www-data:www-data wp-config.php
            fi
            
            # Always ensure integration template is up to date
            setup_integration_template
            
            exit 0
        fi
        sleep 2
    done
    
    echo "Warning: Setup may not have completed properly"
fi