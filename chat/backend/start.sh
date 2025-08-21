#!/bin/sh
# Porneste serverul Node.js si Nginx
cd /app && node server.js &
nginx -g 'daemon off;'