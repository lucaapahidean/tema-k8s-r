apiVersion: v1
kind: ConfigMap
metadata:
  name: wordpress-config
data:
  init-wordpress.sh: |
    #!/bin/bash
    set -e
    
    echo "🚀 Starting WordPress initialization..."
    
    # Wait for database
    while ! mysqladmin ping -h"$WORDPRESS_DB_HOST" -u"$WORDPRESS_DB_USER" -p"$WORDPRESS_DB_PASSWORD" --silent; do
        echo "⏳ Waiting for database connection..."
        sleep 2
    done
    
    echo "✅ Database connection established"
    
    # Get public IP for configuration
    NODE_IP=""
    
    # Try Azure metadata service
    PUBLIC_IP=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text" 2>/dev/null || echo "")
    
    if [ ! -z "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "null" ] && echo "$PUBLIC_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        NODE_IP="$PUBLIC_IP"
        echo "📍 Using Azure public IP: $NODE_IP"
    else
        # Try external services
        for service in "ifconfig.me" "ipecho.net/plain" "icanhazip.com"; do
            EXTERNAL_IP=$(curl -s --connect-timeout 10 "http://$service" 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
            if [ ! -z "$EXTERNAL_IP" ]; then
                NODE_IP="$EXTERNAL_IP"
                echo "📍 Using external service IP: $NODE_IP"
                break
            fi
        done
    fi
    
    # Fallback
    if [ -z "$NODE_IP" ]; then
        NODE_IP="localhost"
        echo "⚠️  Using fallback IP: $NODE_IP"
    fi
    
    echo "🎯 Final IP: $NODE_IP"
    
    # Install WordPress CLI
    if [ ! -f /usr/local/bin/wp ]; then
        echo "📥 Installing WP-CLI..."
        curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        mv wp-cli.phar /usr/local/bin/wp
    fi
    
    cd /var/www/html
    
    # Download WordPress if not exists
    if [ ! -f wp-config.php ]; then
        echo "📦 Downloading WordPress..."
        wp core download --allow-root
        
        echo "🔧 Creating wp-config.php..."
        wp config create --dbname="$WORDPRESS_DB_NAME" --dbuser="$WORDPRESS_DB_USER" --dbpass="$WORDPRESS_DB_PASSWORD" --dbhost="$WORDPRESS_DB_HOST" --allow-root
        
        echo "🏗️ Installing WordPress..."
        wp core install --url="http://$NODE_IP:30080" --title="Cloud-Native Demo Platform" --admin_user=admin --admin_password=admin123 --admin_email=admin@example.com --allow-root
        
        echo "🎨 Installing and activating theme..."
        wp theme install twentytwentyfour --activate --allow-root
        
        echo "🔌 Installing plugins..."
        wp plugin install classic-editor --activate --allow-root
        
        echo "📄 Creating homepage..."
        wp post create --post_type=page --post_title="Welcome to Cloud-Native Platform" --post_status=publish --post_content="
        <div style='background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px; border-radius: 8px; margin-bottom: 30px;'>
            <h1>🚀 Cloud-Native Demo Platform</h1>
            <p style='font-size: 1.2em;'>Complete demonstration of modern cloud-native technologies on Kubernetes</p>
        </div>
        
        <h2>🌟 Live Applications</h2>
        <div style='display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 20px 0;'>
            <div style='border: 2px solid #4caf50; padding: 20px; border-radius: 8px; text-align: center;'>
                <h3>💬 Real-time Chat</h3>
                <p>WebSocket-powered chat application with MongoDB persistence</p>
                <a href='/chat' style='background: #4caf50; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;'>Launch Chat →</a>
            </div>
            <div style='border: 2px solid #2196f3; padding: 20px; border-radius: 8px; text-align: center;'>
                <h3>🤖 AI Image Recognition</h3>
                <p>Azure Computer Vision OCR with Blob Storage</p>
                <a href='/ai-ocr' style='background: #2196f3; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;'>Launch OCR →</a>
            </div>
        </div>
        
        <h2>🏗️ Architecture</h2>
        <ul>
            <li><strong>WordPress CMS:</strong> 4 replicas with MySQL backend</li>
            <li><strong>Chat System:</strong> Python+Nginx backend (2 replicas), React frontend</li>
            <li><strong>AI Integration:</strong> Azure Computer Vision, Blob Storage, SQL Database</li>
            <li><strong>Infrastructure:</strong> Kubernetes with persistent storage</li>
        </ul>
        
        <div style='background: #f5f5f5; padding: 20px; border-radius: 8px; margin-top: 30px;'>
            <h3>📊 System Information</h3>
            <p><strong>Public IP:</strong> $NODE_IP</p>
            <p><strong>WordPress:</strong> http://$NODE_IP:30080</p>
            <p><strong>Chat:</strong> http://$NODE_IP:30090</p>
            <p><strong>AI OCR:</strong> http://$NODE_IP:30180</p>
        </div>
        " --allow-root
        
        echo "📝 Creating Chat page..."
        wp post create --post_type=page --post_title="Chat Application" --post_name=chat --post_status=publish --post_content="
        <div style='background: linear-gradient(135deg, #a8e6cf 0%, #dcedc8 100%); padding: 30px; border-radius: 8px; margin-bottom: 20px;'>
            <h1>💬 Real-time Chat Application</h1>
            <p>Connect with other users using WebSocket technology</p>
        </div>
        
        <div style='border: 2px solid #4caf50; border-radius: 8px; overflow: hidden; height: 600px;'>
            <iframe src='http://$NODE_IP:30090' width='100%' height='100%' frameborder='0'></iframe>
        </div>
        " --allow-root
        
        echo "🤖 Creating AI OCR page..."
        wp post create --post_type=page --post_title="AI Image Recognition" --post_name=ai-ocr --post_status=publish --post_content="
        <div style='background: linear-gradient(135deg, #bbdefb 0%, #e3f2fd 100%); padding: 30px; border-radius: 8px; margin-bottom: 20px;'>
            <h1>🤖 AI Image Recognition & OCR</h1>
            <p>Upload images and extract text using Azure Computer Vision</p>
        </div>
        
        <div style='border: 2px solid #2196f3; border-radius: 8px; overflow: hidden; height: 700px;'>
            <iframe src='http://$NODE_IP:30180' width='100%' height='100%' frameborder='0'></iframe>
        </div>
        " --allow-root
        
        echo "🔗 Setting up navigation menu..."
        wp menu create "Main Menu" --allow-root
        wp menu item add-post main-menu 2 --allow-root  # Chat page
        wp menu item add-post main-menu 3 --allow-root  # AI page
        wp menu location assign main-menu primary --allow-root
        
        echo "🏠 Setting homepage..."
        wp option update show_on_front page --allow-root
        wp option update page_on_front 1 --allow-root
        
        # Create installation marker
        echo "Installation completed at: $(date)" > /var/www/html/wp-content/.wordpress_installed
        echo "Public IP: $NODE_IP" >> /var/www/html/wp-content/.wordpress_installed
        
        echo "✅ WordPress setup completed!"
        echo "🔐 Admin credentials: admin / admin123"
        echo "🌐 Site URL: http://$NODE_IP:30080"
    else
        echo "ℹ️  WordPress already configured"
    fi
    
    # Ensure correct permissions
    chown -R www-data:www-data /var/www/html
    
    echo "🎉 WordPress initialization finished!"