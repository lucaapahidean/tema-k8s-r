FROM drupal:11

# Install required tools
RUN apt-get update && apt-get install -y wait-for-it default-mysql-client && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Drush and Mahi theme
RUN composer require drush/drush && \
    composer require 'drupal/mahi:^1.1' && \
    composer require 'drupal/pathauto:^1.11' && \
    composer require 'drupal/admin_toolbar:^3.4'

# Copy our custom scripts
COPY settings.php /tmp/settings.php
COPY drupal-install-job.sh /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/

# Make scripts executable and set permissions
RUN chmod +x /usr/local/bin/drupal-install-job.sh && \
    chmod +x /usr/local/bin/entrypoint.sh && \
    mkdir -p /var/www/html/sites/default/files && \
    chmod 777 /var/www/html/sites/default && \
    chmod 777 /var/www/html/sites/default/files

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["apache2-foreground"]