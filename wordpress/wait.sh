#!/bin/bash
set -e

echo "🚀 Starting automated WordPress installation..."

# Extract host and port
DB_HOST=$(echo "$WORDPRESS_DB_HOST" | cut -d: -f1)
DB_PORT=$(echo "$WORDPRESS_DB_HOST" | cut -d: -f2)

echo "⏳ Waiting for $DB_HOST:$DB_PORT to be ready..."

# Wait for database port
for i in $(seq 1 60); do
    if timeout 1 bash -c "</dev/tcp/$DB_HOST/$DB_PORT" 2>/dev/null; then
        echo "✅ Database port $DB_HOST:$DB_PORT is open!"
        break
    fi
    echo "Attempt $i/60 - waiting for $DB_HOST:$DB_PORT..."
    sleep 2
done

# Additional wait for MySQL to be fully ready
echo "⏳ Waiting extra 10 seconds for MySQL initialization..."
sleep 10

cd /var/www/html

# Only install if WordPress is not already configured
if [ ! -f wp-config.php ]; then
    echo "📦 Installing WP-CLI..."
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar 2>/dev/null
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp
    
    echo "📥 Downloading WordPress..."
    wp core download --allow-root
    
    echo "🔧 Creating wp-config.php..."
    wp config create \
        --dbname="$WORDPRESS_DB_NAME" \
        --dbuser="$WORDPRESS_DB_USER" \
        --dbpass="$WORDPRESS_DB_PASSWORD" \
        --dbhost="$WORDPRESS_DB_HOST" \
        --allow-root
    
    # Get Node IP for site URL
    NODE_IP="${KUBERNETES_NODE_IP:-localhost}"
    SITE_URL="http://$NODE_IP:30080"
    
    echo "🏗️ Installing WordPress automatically..."
    wp core install \
        --url="$SITE_URL" \
        --title="Cloud-Native Demo Platform" \
        --admin_user="admin" \
        --admin_password="admin123" \
        --admin_email="admin@example.com" \
        --skip-email \
        --allow-root
    
    echo "🎨 Setting up theme and basic content..."
    wp theme install twentytwentyfour --activate --allow-root
    
    echo "📄 Creating homepage with integrated applications..."
    wp post create \
        --post_type=page \
        --post_title="Welcome to Cloud Platform" \
        --post_status=publish \
        --post_content="
        <div style='background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px; border-radius: 8px; margin-bottom: 30px; text-align: center;'>
            <h1>🚀 Cloud-Native Demo Platform</h1>
            <p style='font-size: 1.2em; margin: 0;'>Complete Kubernetes deployment with WordPress, Chat, and AI applications</p>
        </div>
        
        <div style='display: grid; grid-template-columns: 1fr 1fr; gap: 30px; margin: 30px 0;'>
            <div style='border: 2px solid #4caf50; padding: 25px; border-radius: 12px; text-align: center; background: #f8fff8;'>
                <h2 style='color: #4caf50; margin-top: 0;'>💬 Real-time Chat</h2>
                <p>WebSocket-powered chat application with MongoDB persistence and Redis pub/sub</p>
                <p><strong>Backend:</strong> Python + Nginx (2 replicas)<br>
                <strong>Frontend:</strong> React (1 replica)</p>
                <a href='/chat' style='background: #4caf50; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; display: inline-block; margin-top: 10px;'>Launch Chat →</a>
            </div>
            
            <div style='border: 2px solid #2196f3; padding: 25px; border-radius: 12px; text-align: center; background: #f8f9ff;'>
                <h2 style='color: #2196f3; margin-top: 0;'>🤖 AI Image Analysis</h2>
                <p>Azure Computer Vision integration with Blob Storage and SQL Database</p>
                <p><strong>Features:</strong> Image upload, OCR, sentiment analysis<br>
                <strong>Storage:</strong> Azure Blob + SQL</p>
                <a href='/ai' style='background: #2196f3; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; display: inline-block; margin-top: 10px;'>Launch AI →</a>
            </div>
        </div>
        
        <div style='background: #f5f5f5; padding: 25px; border-radius: 8px; margin-top: 30px;'>
            <h2>🏗️ Technical Architecture</h2>
            <div style='display: grid; grid-template-columns: 1fr 1fr; gap: 20px;'>
                <div>
                    <h3>💾 Backend Services</h3>
                    <ul>
                        <li><strong>WordPress CMS:</strong> 4 replicas with MySQL</li>
                        <li><strong>Chat Backend:</strong> Python+Nginx, 2 replicas</li>
                        <li><strong>MongoDB:</strong> Chat message persistence</li>
                        <li><strong>Redis:</strong> WebSocket state sharing</li>
                        <li><strong>AI Backend:</strong> Azure integration</li>
                    </ul>
                </div>
                <div>
                    <h3>🌐 Frontend Applications</h3>
                    <ul>
                        <li><strong>WordPress:</strong> Port 30080 (this site)</li>
                        <li><strong>Chat Frontend:</strong> React app on port 30090</li>
                        <li><strong>AI Frontend:</strong> React app on port 30092</li>
                        <li><strong>All integrated</strong> via iframe embedding</li>
                    </ul>
                </div>
            </div>
        </div>
        
        <div style='text-align: center; margin-top: 30px; padding: 20px; background: #e8f5e8; border-radius: 8px;'>
            <h3>📊 System Information</h3>
            <p><strong>Node IP:</strong> $NODE_IP</p>
            <p><strong>Admin Panel:</strong> <a href='/wp-admin'>WordPress Admin</a> (admin / admin123)</p>
            <p><strong>Deployment:</strong> Fully automated Kubernetes with zero manual configuration</p>
        </div>
        " \
        --allow-root
    
    echo "📝 Creating Chat application page..."
    wp post create \
        --post_type=page \
        --post_title="Chat Application" \
        --post_name=chat \
        --post_status=publish \
        --post_content="
        <div style='background: linear-gradient(135deg, #a8e6cf 0%, #dcedc8 100%); padding: 30px; border-radius: 8px; margin-bottom: 20px; text-align: center;'>
            <h1>💬 Real-time Chat Application</h1>
            <p>Connect with other users using WebSocket technology. Messages are stored in MongoDB with Redis pub/sub for real-time delivery.</p>
        </div>
        
        <div style='border: 2px solid #4caf50; border-radius: 8px; overflow: hidden; height: 600px; margin: 20px 0;'>
            <iframe src='http://$NODE_IP:30090' width='100%' height='100%' frameborder='0' style='border: none;'></iframe>
        </div>
        
        <div style='background: #f8fff8; padding: 20px; border-radius: 8px; margin-top: 20px;'>
            <h3>Technical Details</h3>
            <ul>
                <li><strong>Backend:</strong> Python with WebSocket support (2 replicas)</li>
                <li><strong>Frontend:</strong> React application with real-time messaging</li>
                <li><strong>Database:</strong> MongoDB for message persistence</li>
                <li><strong>Pub/Sub:</strong> Redis for scaling WebSocket connections</li>
                <li><strong>Load Balancing:</strong> Kubernetes service with session affinity</li>
            </ul>
        </div>
        " \
        --allow-root
    
    echo "🤖 Creating AI application page..."
    wp post create \
        --post_type=page \
        --post_title="AI Image Analysis" \
        --post_name=ai \
        --post_status=publish \
        --post_content="
        <div style='background: linear-gradient(135deg, #bbdefb 0%, #e3f2fd 100%); padding: 30px; border-radius: 8px; margin-bottom: 20px; text-align: center;'>
            <h1>🤖 AI Image Analysis & OCR</h1>
            <p>Upload images and extract text using Azure Computer Vision. Files are stored in Azure Blob Storage with metadata in SQL Database.</p>
        </div>
        
        <div style='border: 2px solid #2196f3; border-radius: 8px; overflow: hidden; height: 700px; margin: 20px 0;'>
            <iframe src='http://$NODE_IP:30092' width='100%' height='100%' frameborder='0' style='border: none;'></iframe>
        </div>
        
        <div style='background: #f8f9ff; padding: 20px; border-radius: 8px; margin-top: 20px;'>
            <h3>Azure Integration</h3>
            <ul>
                <li><strong>Computer Vision:</strong> OCR and image description services</li>
                <li><strong>Blob Storage:</strong> Secure file storage with SAS tokens</li>
                <li><strong>SQL Database:</strong> Metadata and results persistence</li>
                <li><strong>Authentication:</strong> Azure service principals</li>
                <li><strong>Processing:</strong> Async image analysis pipeline</li>
            </ul>
        </div>
        " \
        --allow-root
    
    echo "🔗 Setting up navigation menu..."
    wp menu create "Main Menu" --allow-root
    HOMEPAGE_ID=$(wp post list --post_type=page --title="Welcome to Cloud Platform" --format=ids --allow-root)
    CHAT_ID=$(wp post list --post_type=page --name=chat --format=ids --allow-root)
    AI_ID=$(wp post list --post_type=page --name=ai --format=ids --allow-root)
    
    wp menu item add-post main-menu $HOMEPAGE_ID --title="Home" --allow-root
    wp menu item add-post main-menu $CHAT_ID --title="Chat App" --allow-root
    wp menu item add-post main-menu $AI_ID --title="AI App" --allow-root
    
    # Try to assign menu to primary location
    wp menu location assign main-menu primary --allow-root 2>/dev/null || echo "Menu location assignment skipped"
    
    echo "🏠 Setting homepage..."
    wp option update show_on_front page --allow-root
    wp option update page_on_front $HOMEPAGE_ID --allow-root
    
    # Update site URL options
    wp option update home "$SITE_URL" --allow-root
    wp option update siteurl "$SITE_URL" --allow-root
    
    echo "🔐 WordPress Admin Credentials:"
    echo "   URL: $SITE_URL/wp-admin"
    echo "   Username: admin"
    echo "   Password: admin123"
    
    echo "✅ WordPress fully configured and ready!"
else
    echo "ℹ️ WordPress already configured, skipping installation"
fi

# Fix permissions
chown -R www-data:www-data /var/www/html

echo "🎉 Automated installation complete!"