FROM python:3.11-alpine

# Install Nginx and build dependencies
RUN apk add --no-cache nginx gcc musl-dev libffi-dev

# Create app directory
WORKDIR /app

# Copy and install Python dependencies
COPY requirements.txt .
COPY server.py .
RUN pip install --no-cache-dir -r requirements.txt

# Configure Nginx
RUN rm -f /etc/nginx/conf.d/default.conf /etc/nginx/http.d/default.conf
COPY nginx.conf /etc/nginx/http.d/chat.conf

# Copy and make start script executable
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Create required directories for Nginx
RUN mkdir -p /var/log/nginx /var/lib/nginx/tmp /run/nginx

# Expose port 80
EXPOSE 80

# Start application
CMD ["/start.sh"]