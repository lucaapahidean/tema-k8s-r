# Production stage cu Python și Nginx
FROM python:3.11-alpine

# Install Nginx, wget pentru verificări și dependințe pentru build
RUN apk add --no-cache nginx gcc musl-dev libffi-dev wget

# Creează directorul pentru aplicație
WORKDIR /app

# Copiază fișierele Python
COPY requirements.txt .
COPY server.py .

# Instalează dependințele Python
RUN pip install --no-cache-dir -r requirements.txt

# Configurează Nginx - șterge configurația default și adaugă a noastră
RUN rm -f /etc/nginx/conf.d/default.conf /etc/nginx/http.d/default.conf
COPY nginx.conf /etc/nginx/http.d/chat.conf

# Copiază și face executabil script-ul de start
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Creează directoarele necesare pentru Nginx
RUN mkdir -p /var/log/nginx /var/lib/nginx/tmp /run/nginx

# Expune portul 80
EXPOSE 80

# Pornește aplicația
CMD ["/start.sh"]