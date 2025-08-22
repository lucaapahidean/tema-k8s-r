# Build stage
FROM node:18-alpine AS build

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Production stage
FROM node:18-alpine

# Create app directory
WORKDIR /app

# Copy built application
COPY --from=build /app/node_modules ./node_modules
COPY . .
RUN mkdir -p uploads && chmod 777 uploads

# Expose port 3001
EXPOSE 3001

# Start the application
CMD ["node", "server.js"]