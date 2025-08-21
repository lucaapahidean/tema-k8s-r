#!/bin/bash
set -e

echo "🚀 Starting Drupal container..."

# Ensure directory exists and has correct permissions
mkdir -p /var/www/html/sites/default/files
chmod 777 /var/www/html/sites/default
chmod 777 /var/www/html/sites/default/files

# Copy settings file if it doesn't exist
if [ ! -f /var/www/html/sites/default/settings.php ]; then
    echo "📄 Copying settings.php file..."
    cp /tmp/settings.php /var/www/html/sites/default/settings.php
    chmod 664 /var/www/html/sites/default/settings.php
fi

# Always ensure correct permissions
chown -R www-data:www-data /var/www/html/sites/default

# Wait for installation to be completed by the Job
echo "⏳ Waiting for Drupal installation to be completed by Job..."
INSTALL_MARKER="/var/www/html/sites/default/files/.drupal_installed"
TIMEOUT=600  # 10 minutes timeout
ELAPSED=0

while [ ! -f "$INSTALL_MARKER" ] && [ $ELAPSED -lt $TIMEOUT ]; do
    echo "⏱️  Waiting for installation job to complete... ($ELAPSED/${TIMEOUT}s)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ -f "$INSTALL_MARKER" ]; then
    echo "✅ Installation completed by Job. Starting web server..."
    echo "📋 Installation details:"
    cat "$INSTALL_MARKER" || true
else
    echo "⚠️  Installation job timeout. Starting anyway (Drupal will show installation page)..."
fi

# Start Apache in the foreground
echo "🌐 Starting Apache web server..."
exec "$@"