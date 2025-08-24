FROM wordpress:6.7-apache

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    less \
    vim \
    default-mysql-client \
    netcat-openbsd \
    net-tools \
    iputils-ping \
    dnsutils \
    && docker-php-ext-install mysqli pdo pdo_mysql \
    && rm -rf /var/lib/apt/lists/*

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp \
    && wp --info --allow-root

# Configure PHP
RUN { \
    echo 'memory_limit = 512M'; \
    echo 'max_execution_time = 300'; \
    echo 'max_input_vars = 3000'; \
    echo 'upload_max_filesize = 64M'; \
    echo 'post_max_size = 64M'; \
    echo 'max_input_time = 300'; \
    echo 'display_errors = Off'; \
    echo 'log_errors = On'; \
    echo 'error_log = /var/log/apache2/php_errors.log'; \
} > /usr/local/etc/php/conf.d/custom.ini

# Configure Apache
RUN { \
    echo 'ServerName localhost'; \
    echo 'ServerTokens Prod'; \
    echo 'ServerSignature Off'; \
    echo 'TraceEnable Off'; \
    echo 'FileETag None'; \
    echo 'Header always unset X-Powered-By'; \
    echo 'Header unset X-Powered-By'; \
} > /etc/apache2/conf-available/security-custom.conf \
    && a2enconf security-custom \
    && a2enmod rewrite headers expires

# Create necessary directories
RUN mkdir -p /var/www/html /var/log/apache2 \
    && chown -R www-data:www-data /var/www/html /var/log/apache2

# Copy integration page PHP template
COPY integration-page.php /tmp/integration-page.php

# Copy setup script
COPY setup-wordpress.sh /usr/local/bin/setup-wordpress.sh
RUN chmod +x /usr/local/bin/setup-wordpress.sh

# Copy custom entrypoint
COPY entrypoint.sh /usr/local/bin/custom-entrypoint.sh
RUN chmod +x /usr/local/bin/custom-entrypoint.sh

# Set working directory
WORKDIR /var/www/html

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

# Use custom entrypoint
ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
CMD ["apache2-foreground"]