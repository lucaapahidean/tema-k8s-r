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

// Database repair mode (uncomment if needed)
// define( 'WP_ALLOW_REPAIR', true );

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
WPCONFIG
}

# Function to process template and replace placeholders
process_integration_template() {
    local node_ip="$1"
    local template_file="$2"
    local output_file="$3"
    
    if [ ! -f "$template_file" ]; then
        echo "Warning: Template file $template_file not found"
        return 1
    fi
    
    echo "Processing integration template with Node IP: $node_ip"
    
    # Use sed to replace {{NODE_IP}} placeholder with actual node IP
    sed "s/{{NODE_IP}}/$node_ip/g" "$template_file" > "$output_file"
    
    if [ -f "$output_file" ]; then
        echo "Integration page template processed successfully: $output_file"
        chown www-data:www-data "$output_file"
        return 0
    else
        echo "Error: Failed to create processed integration page"
        return 1
    fi
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
    
    # Always reprocess the integration template in case the node IP changed
    NODE_IP="${KUBERNETES_NODE_IP:-localhost}"
    if [ -f "/tmp/integration-page.html" ]; then
        process_integration_template "$NODE_IP" "/tmp/integration-page.html" "/tmp/integration-page-processed.html"
    fi
    
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

    # Process integration template first
    TEMPLATE_PROCESSED=false
    if [ -f "/tmp/integration-page.html" ]; then
        if process_integration_template "$NODE_IP" "/tmp/integration-page.html" "/tmp/integration-page-processed.html"; then
            TEMPLATE_PROCESSED=true
            echo "Integration template processing: SUCCESS"
        else
            echo "Integration template processing: FAILED - will use fallback"
        fi
    else
        echo "Integration template not found: /tmp/integration-page.html"
    fi

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
    
    # Update .htaccess to prevent redirects
    cat > .htaccess << 'HTACCESS'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
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
HTACCESS

    # Use default WordPress theme (no custom theme installation)
    echo "Using default WordPress theme..."

    # Create integration page if it doesn't exist
    echo "Creating integration page..."
    PAGE_EXISTS=$(wp post list --post_type=page --title="Integrated Platform" --format=count --allow-root 2>/dev/null || echo "0")

    if [ "$PAGE_EXISTS" = "0" ]; then
        # Use processed template if available, otherwise use original
        TEMPLATE_TO_USE="/tmp/integration-page.html"
        if [ "$TEMPLATE_PROCESSED" = "true" ] && [ -f "/tmp/integration-page-processed.html" ]; then
            TEMPLATE_TO_USE="/tmp/integration-page-processed.html"
            echo "Using processed integration template"
        else
            echo "Using original integration template (fallback)"
        fi
        
        if [ -f "$TEMPLATE_TO_USE" ]; then
            # Create the page
            HOMEPAGE_ID=$(wp post create "$TEMPLATE_TO_USE" \
                --post_type=page \
                --post_title="Integrated Platform" \
                --post_status=publish \
                --post_name="home" \
                --format=ids \
                --allow-root) || {
                    echo "Failed to create integration page"
                    HOMEPAGE_ID=""
                }
            
            if [ -n "$HOMEPAGE_ID" ]; then
                # Set as homepage
                wp option update show_on_front page --allow-root
                wp option update page_on_front "$HOMEPAGE_ID" --allow-root
                echo "Integration page created and set as homepage (ID: $HOMEPAGE_ID)"
                
                if [ "$TEMPLATE_PROCESSED" = "true" ]; then
                    echo "✓ Integration page includes proper Node IP: $NODE_IP"
                else
                    echo "⚠ Integration page uses fallback template - iframes may need manual configuration"
                fi
            fi
        else
            echo "No integration template found"
        fi
    else
        echo "Integration page already exists"
        
        # Try to update existing page with processed template if available
        if [ "$TEMPLATE_PROCESSED" = "true" ] && [ -f "/tmp/integration-page-processed.html" ]; then
            echo "Updating existing integration page with processed template..."
            EXISTING_PAGE_ID=$(wp post list --post_type=page --title="Integrated Platform" --format=ids --allow-root 2>/dev/null | head -1)
            if [ -n "$EXISTING_PAGE_ID" ]; then
                wp post update "$EXISTING_PAGE_ID" "/tmp/integration-page-processed.html" --allow-root || {
                    echo "Failed to update existing integration page"
                }
            fi
        fi
    fi

    # Create a simple test page
    echo "Creating test page..."
    TEST_PAGE_EXISTS=$(wp post list --post_type=page --title="Test Page" --format=count --allow-root 2>/dev/null || echo "0")

    if [ "$TEST_PAGE_EXISTS" = "0" ]; then
        wp post create \
            --post_type=page \
            --post_title="Test Page" \
            --post_content="<h1>WordPress is running on Kubernetes!</h1><p>Node IP: $NODE_IP</p><p>Chat: http://$NODE_IP:30090</p><p>AI: http://$NODE_IP:30180</p>" \
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
    echo "Admin URL: $SITE_URL/wp-admin"
    echo "Username: admin"
    echo "Password: admin123"
    echo "Node IP: $NODE_IP"
    echo "Chat App: http://$NODE_IP:30090"
    echo "AI App: http://$NODE_IP:30180"
    if [ "$TEMPLATE_PROCESSED" = "true" ]; then
        echo "✓ Integration template processed with correct IPs"
    else
        echo "⚠ Integration template may need manual configuration"
    fi
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
            
            # Always reprocess the integration template in case the node IP changed
            NODE_IP="${KUBERNETES_NODE_IP:-localhost}"
            if [ -f "/tmp/integration-page.html" ]; then
                process_integration_template "$NODE_IP" "/tmp/integration-page.html" "/tmp/integration-page-processed.html"
            fi
            
            exit 0
        fi
        sleep 2
    done
    
    echo "Warning: Setup may not have completed properly"
fi