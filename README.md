# Site Web cu Chat și IA peste Kubernetes

## 🎯 Descriere

Proiect academic care implementează un site web complet, conform specificațiilor temei. Acesta include:
- **🌐 CMS Wordpress** cu MySQL (4 replici).
- **💬 Sistem de chat** în timp real (WebSocket, Python + Nginx, React, MongoDB).
- **🤖 Aplicație AI Image Description** (Azure Computer Vision, Azure Blob Storage, Azure SQL).

Infrastructura este gestionată complet prin **Kubernetes** cu imagini Docker custom și deployment automatizat.

## 🏗️ Arhitectura sistemului

### Stack software
- **Backend**: Python, WebSocket, Nginx
- **Frontend**: React, Axios
- **CMS**: Wordpress 10 cu MySQL 8.0
- **Baze de date**: MySQL, MongoDB, Azure SQL
- **Cloud**: Azure Blob Storage, Computer Vision (Image Description)
- **Containerizare**: Docker multi-stage builds
- **Orchestrare**: Kubernetes (MicroK8s)
- **Messaging / Pub-Sub**: Redis (fan-out pentru WebSockets)

### 🗺️ Maparea serviciilor

| Componentă | Replici | Port intern | NodePort | URL extern |
|---|---|---|---|---|
| **Wordpress CMS** | 4 | 80 | 30080 | `http://NODE_IP:30080` |
| **Wordpress Database** | 1 | 3306 | - | Intern |
| **Chat Backend** | 2 | 80 | 30088 | `ws://NODE_IP:30088` |
| **Chat Frontend** | 1 | 80 | 30090 | `http://NODE_IP:30090` |
| **Chat Database** | 1 | 27017 | - | Intern |
| **Redis (Chat bus)** | 1 | 6379 | - | Intern |
| **AI Backend** | 1 | 3001 | 30101 | `http://NODE_IP:30101` |
| **AI Frontend** | 1 | 80 | 30180 | `http://NODE_IP:30180` |

## 📋 Cerințe și dependențe

### Kubernetes (MicroK8s)
```bash
# Instalare MicroK8s (Ubuntu/Linux)
sudo snap install microk8s --classic --channel=1.33
sudo usermod -a -G microk8s $USER
mkdir -p ~/.kube
chmod 0700 ~/.kube
su - $USER

# Pornire și configurare addon-uri
sudo microk8s start
sudo microk8s enable registry dns hostpath-storage

# Alias pentru kubectl (opțional)
sudo microk8s config > ~/.kube/config
```

### Azure Services necesare

1.  **📦 Storage Account** cu un container pentru imagini (Blob Storage).
2.  **👁️ Computer Vision** pentru **Image Description**.
3.  **🗄️ SQL Database** cu SQL Authentication activat.

### 🔑 Configurare secrete Azure

Editează `secrets/azure-secrets.yaml` cu credențialele tale.

### ☁️ Configurare pentru Azure Cloud

**Important:** Când rulezi pe Azure Cloud, trebuie să modifici `wordpress/wordpress-deployment.yaml` pentru a seta IP-ul extern al cluster-ului:

```yaml
# Înlocuiește această secțiune:
- name: KUBERNETES_NODE_IP
  valueFrom:
    fieldRef:
      fieldPath: status.hostIP

# Cu:
- name: KUBERNETES_NODE_IP
  value: "4.211.207.105"  # Înlocuiește cu IP-ul real al VM-ului Azure
```

## 🚀 Instalare și deployment

### 1. 🔧 Configurare secrete Azure
```bash
# Editează secrets/azure-secrets.yaml cu credențialele tale
nano secrets/azure-secrets.yaml
```

### 2. 🏗️ Build și push imagini
```bash
# Chat Backend
docker build -t localhost:32000/chat-backend:latest ./chat/backend
docker push localhost:32000/chat-backend:latest

# Chat Frontend
docker build -t localhost:32000/chat-frontend:latest ./chat/frontend  
docker push localhost:32000/chat-frontend:latest

# AI Backend
docker build -t localhost:32000/ai-backend:latest ./ai/backend
docker push localhost:32000/ai-backend:latest

# AI Frontend
docker build -t localhost:32000/ai-frontend:latest ./ai/frontend
docker push localhost:32000/ai-frontend:latest

# Wordpress
docker build -t localhost:32000/custom-wordpress:latest ./wordpress
docker push localhost:32000/custom-wordpress:latest
```

### 3. 🎯 Deploy complet (o singură comandă)
```bash
microk8s kubectl apply -k .
```

### 4. 📊 Monitoring și tracking deployment

#### Tracking log-uri Wordpress în timpul deploy-ului
```bash
# Urmărește log-urile pentru toate pod-urile Wordpress în timp real
microk8s kubectl logs -l app=wordpress -f
```

#### Verificare status pod-uri și servicii
```bash
# Verifică statusul tuturor pod-urilor
microk8s kubectl get pods

# Verifică statusul serviciilor
microk8s kubectl get services

# Urmărește progresul deployment-urilor
microk8s kubectl get deployments -w
```

## 🧹 Ștergerea resurselor

### Ștergere completă automată
```bash
# Șterge toate resursele create de acest proiect
microk8s kubectl delete -k .
sudo rm -rf /var/wordpress/* || true
```

### 🐳 Curățare imagini Docker
```bash
# Șterge imaginile custom din registry local
docker rmi localhost:32000/chat-backend:latest
docker rmi localhost:32000/chat-frontend:latest  
docker rmi localhost:32000/ai-backend:latest
docker rmi localhost:32000/ai-frontend:latest
docker rmi localhost:32000/custom-wordpress:latest

# Curățare completă imagini nefolosite
docker system prune -a
```

## ✅ Conformitate cerințe temă

  - ✅ **Wordpress CMS**: **4 replici**, expus pe portul 80 (NodePort 30080).
  - ✅ **Chat Backend**: **Python + Nginx**, **2 replici**, expus pe portul 88 (NodePort 30088).
  - ✅ **Chat Frontend**: **React**, **1 replică**, expus pe portul 90 (NodePort 30090).
  - ✅ **AI Application**: Upload imagini, Azure **Image Description**, istoric rezultate.
  - ✅ **Azure Integration**: Blob Storage, Computer Vision, SQL Database.
  - ✅ **Kubernetes**: Toate resursele (Deployments, Services, PVCs, Secrets) sunt definite în fișiere YAML.
  - ✅ **Registry privat**: MicroK8s registry `localhost:32000` este utilizat pentru imaginile custom.
  - ✅ **Single apply**: Deployment complet cu `kubectl apply -k .`.
  - ✅ **Zero configurare manuală post-deploy**: Aplicația este complet funcțională după `apply`, fără intervenții manuale.
