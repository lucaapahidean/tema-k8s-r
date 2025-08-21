#!/bin/bash
set -e

echo "🚀 Starting Kubernetes deployment process..."

# Culori pentru output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funcții helper
print_step() {
    echo -e "${BLUE}📋 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Verifică dacă MicroK8s este pornit
print_step "Checking MicroK8s status..."
if ! microk8s status --wait-ready; then
    print_error "MicroK8s is not running. Please start it first with: microk8s start"
    exit 1
fi
print_success "MicroK8s is running"

# Verifică addon-urile necesare
print_step "Checking required addons..."
REQUIRED_ADDONS=("registry" "dns" "hostpath-storage")
for addon in "${REQUIRED_ADDONS[@]}"; do
    if ! microk8s status | grep -q "^$addon: enabled"; then
        print_warning "Enabling $addon addon..."
        microk8s enable $addon
    fi
done
print_success "All required addons are enabled"

# Build și push imagini custom
print_step "Building and pushing custom Docker images..."

# 1. Chat Backend
print_step "Building chat-backend..."
cd chat/backend
docker build -t localhost:32000/chat-backend:latest .
docker push localhost:32000/chat-backend:latest
cd ../..
print_success "chat-backend built and pushed"

# 2. Chat Frontend  
print_step "Building chat-frontend..."
cd chat/frontend
docker build -t localhost:32000/chat-frontend:latest .
docker push localhost:32000/chat-frontend:latest
cd ../..
print_success "chat-frontend built and pushed"

# 3. AI Backend
print_step "Building ai-backend..."
cd ai/backend
docker build -t localhost:32000/ai-backend:latest .
docker push localhost:32000/ai-backend:latest
cd ../..
print_success "ai-backend built and pushed"

# 4. AI Frontend
print_step "Building ai-frontend..."
cd ai/frontend
docker build -t localhost:32000/ai-frontend:latest .
docker push localhost:32000/ai-frontend:latest
cd ../..
print_success "ai-frontend built and pushed"

# 5. Drupal Custom
print_step "Building custom-drupal..."
cd drupal
docker build -t localhost:32000/custom-drupal:latest .
docker push localhost:32000/custom-drupal:latest
cd ..
print_success "custom-drupal built and pushed"

# Verifică secretele Azure
print_step "Checking Azure secrets configuration..."
if [ ! -f "secrets/azure-secrets.yaml" ]; then
    print_error "Azure secrets file not found. Please create secrets/azure-secrets.yaml with your Azure credentials."
    exit 1
fi

# Verifică dacă secretele sunt base64 encoded
if grep -q "your_.*_connection_string\|your_.*_api_key" secrets/azure-secrets.yaml; then
    print_error "Please update secrets/azure-secrets.yaml with your actual Azure credentials (base64 encoded)."
    print_warning "Use: echo -n 'your_connection_string' | base64"
    exit 1
fi
print_success "Azure secrets are configured"

# Deploy la Kubernetes
print_step "Deploying to Kubernetes cluster..."
microk8s kubectl apply -k .
print_success "All resources deployed to Kubernetes"

# Așteaptă ca baza de date să fie ready
print_step "Waiting for databases to be ready..."
microk8s kubectl wait --for=condition=ready pod -l app=drupal-db --timeout=180s
microk8s kubectl wait --for=condition=ready pod -l app=chat-db --timeout=180s
microk8s kubectl wait --for=condition=ready pod -l app=redis --timeout=120s
print_success "Databases and Redis are ready"

# Așteaptă ca job-ul de instalare Drupal să se termine
print_step "Waiting for Drupal installation job to complete..."
if microk8s kubectl wait --for=condition=complete job/drupal-install --timeout=600s; then
    print_success "Drupal installation job completed successfully!"
    
    # Arată log-urile job-ului
    echo ""
    echo "📋 Installation job logs:"
    microk8s kubectl logs job/drupal-install || true
else
    print_error "Drupal installation job failed or timed out"
    echo ""
    echo "📋 Job status:"
    microk8s kubectl describe job drupal-install
    echo ""
    echo "📋 Job logs:"
    microk8s kubectl logs job/drupal-install || true
    exit 1
fi

# Așteaptă ca toate pod-urile să fie ready
print_step "Waiting for all pods to be ready..."
microk8s kubectl wait --for=condition=ready pod -l app=drupal --timeout=300s
print_success "All Drupal pods are ready"

# Verifică status-ul serviciilor
print_step "Checking services status..."
echo ""
echo "📊 Services Status:"
microk8s kubectl get services --field-selector spec.type=NodePort -o wide

echo ""
echo "🔍 Pods Status:"
microk8s kubectl get pods -o wide

echo ""
echo "🔍 Job Status:"
microk8s kubectl get jobs

# Obține IP-ul nodului
NODE_IP=$(microk8s kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo ""
echo "🌐 Access URLs:"
echo "  Drupal CMS:     http://$NODE_IP:30080"
echo "  Chat Frontend:  http://$NODE_IP:30090"  
echo "  AI Frontend:    http://$NODE_IP:30180"
echo "  Chat Backend:   ws://$NODE_IP:30088"
echo "  AI Backend:     http://$NODE_IP:30101"

echo ""
print_success "Deployment completed successfully!"
print_success "Drupal is pre-configured with admin/admin123"
print_warning "Drupal pages include Chat and AI OCR applications via iframes"

echo ""
echo "🔧 Useful commands:"
echo "  Check pods:        microk8s kubectl get pods"
echo "  Check services:    microk8s kubectl get services"
echo "  Check jobs:        microk8s kubectl get jobs"
echo "  View Drupal logs:  microk8s kubectl logs -l app=drupal"
echo "  View job logs:     microk8s kubectl logs job/drupal-install"
echo "  Delete all:        microk8s kubectl delete -k ."
echo "  Delete job only:   microk8s kubectl delete job drupal-install"