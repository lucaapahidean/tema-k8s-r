#!/bin/bash

echo "🚀 Starting build and deploy process for Chat Application..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if MicroK8s is running
if ! microk8s status --wait-ready > /dev/null 2>&1; then
    print_error "MicroK8s is not running or not ready. Please start it first."
    exit 1
fi

print_status "MicroK8s is running and ready"

# Check if registry is available
if ! curl -s http://localhost:32000/v2/ > /dev/null; then
    print_error "MicroK8s registry is not available. Please enable it with: microk8s enable registry"
    exit 1
fi

print_status "MicroK8s registry is available"

# Build and push Chat Backend (Python)
print_status "Building Chat Backend (Python + Nginx)..."
if docker build -t localhost:32000/chat-backend:latest ./chat/backend; then
    print_status "Chat Backend build successful"
    if docker push localhost:32000/chat-backend:latest; then
        print_status "Chat Backend pushed to registry"
    else
        print_error "Failed to push Chat Backend to registry"
        exit 1
    fi
else
    print_error "Failed to build Chat Backend"
    exit 1
fi

# Build and push Chat Frontend (React)
print_status "Building Chat Frontend (React)..."
if docker build -t localhost:32000/chat-frontend:latest ./chat/frontend; then
    print_status "Chat Frontend build successful"
    if docker push localhost:32000/chat-frontend:latest; then
        print_status "Chat Frontend pushed to registry"
    else
        print_error "Failed to push Chat Frontend to registry"
        exit 1
    fi
else
    print_error "Failed to build Chat Frontend"
    exit 1
fi

# Deploy to Kubernetes
print_status "Deploying to Kubernetes..."

# Cleanup existing deployment to force restart with new image
print_status "Cleaning up existing deployments..."
microk8s kubectl delete deployment chat-backend --ignore-not-found=true
microk8s kubectl delete deployment chat-frontend --ignore-not-found=true

# Wait a bit for cleanup
sleep 5

# Deploy to Kubernetes
print_status "Deploying to Kubernetes..."

# Apply all chat-related Kubernetes resources (only YAML files)
print_status "Deploying MongoDB..."
if microk8s kubectl apply -f chat/db/; then
    print_status "MongoDB deployed"
else
    print_error "Failed to deploy MongoDB"
    exit 1
fi

print_status "Deploying Redis..."
if microk8s kubectl apply -f chat/redis/; then
    print_status "Redis deployed"
else
    print_error "Failed to deploy Redis"
    exit 1
fi

print_status "Deploying Chat Backend..."
if microk8s kubectl apply -f chat/backend/chat-backend-deployment.yaml -f chat/backend/chat-backend-service.yaml; then
    print_status "Chat Backend deployed"
else
    print_error "Failed to deploy Chat Backend"
    exit 1
fi

print_status "Deploying Chat Frontend..."
if microk8s kubectl apply -f chat/frontend/chat-frontend-deployment.yaml -f chat/frontend/chat-frontend-service.yaml; then
    print_status "Chat Frontend deployed"
    print_status "Chat application deployed successfully!"
else
    print_error "Failed to deploy Chat Frontend"
    exit 1
fi

# Wait for deployments to be ready
print_status "Waiting for deployments to be ready..."

# Wait for chat backend
print_status "Waiting for chat-backend deployment..."
microk8s kubectl rollout status deployment/chat-backend --timeout=300s

# Wait for chat frontend
print_status "Waiting for chat-frontend deployment..."
microk8s kubectl rollout status deployment/chat-frontend --timeout=300s

# Wait for MongoDB
print_status "Waiting for chat-db deployment..."
microk8s kubectl rollout status deployment/chat-db --timeout=300s

# Wait for Redis
print_status "Waiting for redis deployment..."
microk8s kubectl rollout status deployment/redis --timeout=300s

print_status "All deployments are ready!"

# Get node IP
NODE_IP=$(microk8s kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
if [ -z "$NODE_IP" ]; then
    NODE_IP="localhost"
fi

# Display access information
echo ""
echo "🎉 Chat Application deployed successfully!"
echo ""
echo "📋 Access Information:"
echo "─────────────────────────────────────────"
echo "🌐 Chat Frontend (React):  http://${NODE_IP}:30090"
echo "🔧 Chat Backend (Python):  ws://${NODE_IP}:30088"
echo ""
echo "📊 Service Status:"
echo "─────────────────────────────────────────"
microk8s kubectl get services -l app=chat-backend -o wide
microk8s kubectl get services -l app=chat-frontend -o wide
echo ""
echo "🔍 Pod Status:"
echo "─────────────────────────────────────────"
microk8s kubectl get pods -l app=chat-backend
microk8s kubectl get pods -l app=chat-frontend
microk8s kubectl get pods -l app=chat-db
microk8s kubectl get pods -l app=redis
echo ""

print_status "Deployment completed! You can now access the chat application."
print_warning "Note: Make sure the frontend can connect to the backend WebSocket."
print_warning "If deploying on Azure/cloud, update the IP address in the React frontend."

echo ""
echo "🔧 Useful commands:"
echo "─────────────────────────────────────────"
echo "View logs: microk8s kubectl logs -l app=chat-backend"
echo "View pods: microk8s kubectl get pods"
echo "Delete app: microk8s kubectl delete -f chat/"