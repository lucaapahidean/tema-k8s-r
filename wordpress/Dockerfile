FROM wordpress:6-apache

# Install required PHP extensions and tools
RUN apt-get update && apt-get install -y \
    curl \
    less \
    default-mysql-client \
    netcat-openbsd \
    net-tools \
    dnsutils \
    && docker-php-ext-install mysqli pdo pdo_mysql \
    && rm -rf /var/lib/apt/lists/*

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Set PHP memory limit
RUN echo 'memory_limit = 512M' > /usr/local/etc/php/conf.d/memory.ini \
    && echo 'max_execution_time = 300' >> /usr/local/etc/php/conf.d/memory.ini \
    && echo 'max_input_vars = 3000' >> /usr/local/etc/php/conf.d/memory.ini \
    && echo 'upload_max_filesize = 64M' >> /usr/local/etc/php/conf.d/memory.ini \
    && echo 'post_max_size = 64M' >> /usr/local/etc/php/conf.d/memory.ini

# Copy integration page template
COPY integration-page.html /tmp/integration-page.html

# Copy setup script
COPY setup-wordpress.sh /usr/local/bin/setup-wordpress.sh
RUN chmod +x /usr/local/bin/setup-wordpress.sh

# Set custom entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["apache2-foreground"]