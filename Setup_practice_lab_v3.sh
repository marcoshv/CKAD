#!/bin/bash
# =================================================================
# CKAD LAB SETUP SCRIPT (Improved Version)
# =================================================================

# --- Cleanup function (in case of a previous run) ---
cleanup_lab() {
  echo "Cleaning up previous lab resources..."
  kubectl delete ns tiger ckad-netpol external dev pod-resources quetzal cobra kdpd00202 neptune pluto mercury earth mars rbac-test-lab periodic-jobs dev-db some-random-ns config-test --ignore-not-found=true
  
  echo "--- Removing NGINX Ingress Controller ---"
  kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml --ignore-not-found=true
  echo "Cleanup complete."
}

# Run the cleanup function
cleanup_lab

# --- Install Cluster-Wide Infrastructure ---
echo "--- Installing NGINX Ingress Controller ---"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml

# FIX: Wait for the Ingress controller to be fully ready before proceeding
echo "--- Waiting for NGINX Ingress Controller to be ready... ---"
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s
# -----------------------------------------------------------------
# ADDED: Install Helm
echo "Installing Helm..."
if ! command -v helm &> /dev/null; then
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm ./get_helm.sh
else
    echo "Helm already installed."
fi
# ADDED: Add Bitnami Helm repo
echo "Adding Bitnami Helm repository..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# -----------------------------------------------------------------

# --- SECTION 1: CORE APPLICATION CONCEPTS ---
echo "--- Setting up resources for Section 1 ---"

# Q1: Canary Deployment
echo "Creating resources for Q1: Canary Deployment..."
kubectl create namespace tiger
kubectl create -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blue
  namespace: tiger
spec:
  replicas: 10
  selector:
    matchLabels:
      app: blue
  template:
    metadata:
      labels:
        app: blue
        tier: web
    spec:
      containers:
      - image: nginx:1.26.3
        name: nginx
        ports:
        - containerPort: 80
EOF
kubectl expose deployment blue --name=web-srv --port=80 --target-port=80 -n tiger

# Q2: NetworkPolicy
echo "Creating resources for Q2: NetworkPolicy..."
kubectl create namespace ckad-netpol
# Create four pods
kubectl -n ckad-netpol run frontend --image=nginx --labels="app=frontend"
kubectl -n ckad-netpol run backend --image=nginx --labels="app=backend"
kubectl -n ckad-netpol run database --image=nginx --labels="app=database"
kubectl -n ckad-netpol run cache --image=nginx --labels="app=cache"

# Apply the four network policies for the scenario
kubectl apply -f - <<EOF
# Policy 1: Blocks all traffic by default
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: ckad-netpol
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
# Policy 2: The EGRESS policy for the frontend.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-egress-policy
  namespace: ckad-netpol
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes: [Egress]
  egress:
  - to:
    - podSelector: {}
---
# Policy 3: The INGRESS policy for the backend.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-ingress-policy
  namespace: ckad-netpol
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: api-client
---
# Policy 4: The INGRESS policy for the cache.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cache-ingress-policy
  namespace: ckad-netpol
spec:
  podSelector:
    matchLabels:
      app: cache
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          access: cache
EOF

# Q3: Ingress Troubleshooting
echo "Creating resources for Q3: Ingress Troubleshooting..."
kubectl create namespace external
# Copy initial manifests (as before)
mkdir -p /opt/course/3
cat << 'EOF' > /opt/course/3/pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: webapp-pod
  namespace: external
  labels:
    app: webapp
spec:
  containers:
  - name: webapp-container
    image: nginx
    ports:
    - containerPort: 80
EOF
cat << 'EOF' > /opt/course/3/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: webapp
  namespace: external
spec:
  selector:
    app: webapp
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 80
EOF
cat << 'EOF' > /opt/course/3/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: webapp-ingress
  namespace: external
spec:
  rules:
  - host: ckad.local
    http:
      paths:
      - path: /app
        pathType: Prefix
        backend:
          service:
            name: webapp-svc # Incorrect service name
            port:
              number: 8080
EOF

# ADDED: Create the backend and service for the new /status rule
echo "Creating health-check service for Q3 enhancement..."
kubectl create deployment health-check --image=nginx -n external
# Expose on port 8081 targeting container port 80
kubectl expose deployment health-check --name=health-check-srv --port=8081 --target-port=80 -n external

# Q4: ServiceAccount Permissions
echo "Creating resources for Q4: ServiceAccount Permissions..."
kubectl create namespace dev

# --- Resources for Part 1 ---
# Creates the deployment and its unpermissioned ServiceAccount.
# MODIFIED: Changed image and command to make the pod actively fail.
kubectl create serviceaccount log-reader-sa -n dev
# Create the directory for the log file output
mkdir -p /opt/course/4
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: log-reader-deploy
  namespace: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: log-reader-app
  template:
    metadata:
      labels:
        app: log-reader-app
    spec:
      serviceAccountName: log-reader-sa
      containers:
      - name: log-reader-container
        # Using an image with kubectl
        image: bitnami/kubectl:latest
        # This command will fail due to lack of permissions, causing restarts
        command: ["/bin/sh", "-c", "kubectl get pods -n dev && sleep 3600"]
EOF
# Give the pod a moment to start and fail, generating logs for --previous
echo "Waiting for log-reader-deploy pod to start and potentially fail..."
sleep 10


# --- ENHANCEMENT: Resources for Part 2 ---
# (These remain unchanged from our previous version)
echo "Creating additional resources for Q4 Enhancement..."
# --- Decoy Role 1: Incomplete Permissions (list only) ---
kubectl create serviceaccount pod-lister-sa -n dev
kubectl create role pod-lister-role --verb=list --resource=pods -n dev
kubectl create rolebinding pod-lister-binding --role=pod-lister-role --serviceaccount=dev:pod-lister-sa -n dev
# --- Decoy Role 2: Wrong Resource Type (secrets) ---
kubectl create serviceaccount secret-reader-sa -n dev
kubectl create role secret-reader-role --verb=get,list --resource=secrets -n dev
kubectl create rolebinding secret-reader-binding --role=secret-reader-role --serviceaccount=dev:secret-reader-sa -n dev
# --- The CORRECT Pre-existing Role (get/list on pods) ---
kubectl create serviceaccount pod-viewer-sa -n dev
kubectl create role pod-viewer-role --verb=get,list --resource=pods -n dev
kubectl create rolebinding pod-viewer-binding --role=pod-viewer-role --serviceaccount=dev:pod-viewer-sa -n dev
# --- The Second Failing Deployment ---
kubectl create serviceaccount metrics-scraper-sa -n dev
kubectl create -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metrics-scraper-deploy
  namespace: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: metrics-scraper-app
  template:
    metadata:
      labels:
        app: metrics-scraper-app
    spec:
      serviceAccountName: metrics-scraper-sa # This is the "wrong" SA
      containers:
      - name: metrics-container
        # Using an image with curl available
        image: curlimages/curl:latest
        command: ["/bin/sh", "-c", "sleep 3600"]
EOF

# Q5: Dockerfile
echo "Creating resources for Q5: Dockerfile..."
mkdir -p /opt/course/5
cat << 'EOF' > /opt/course/5/Dockerfile
FROM nginx:alpine
LABEL maintainer="CKAD Lab"
EOF

# Q6: Probes
echo "Creating resources for Q6: Probes..."
# Create the directory for the metrics file
mkdir -p /opt/course/6
# Create the initial pod
kubectl run probe-pod --image=busybox --command -- /bin/sh -c "touch /tmp/healthy; sleep 3600"

# ADDED: Install Metrics Server
echo "Installing Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# ADDED: Patch Metrics Server deployment to allow insecure Kubelet TLS
echo "Patching Metrics Server deployment for insecure Kubelet TLS..."
# Use a JSON patch to add the argument if it doesn't exist
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# ADDED: Wait for the (patched) Metrics Server to become ready
echo "Waiting for Metrics Server to become ready..."
# Increase timeout slightly to allow for patching and rollout
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=30s

# ADDED: Small delay after Metrics Server is ready to allow initial scrape
sleep 10

# Q7: Edit ResourceQuota and Create Pod
echo "Creating resources for Q7..."
kubectl create namespace pod-resources

# Create the initial restrictive ResourceQuota
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: pod-resources-quota
  namespace: pod-resources
spec:
  hard:
    requests.cpu: "100m"
    limits.memory: "128Mi"
    pods: "5"
EOF

# Create the initial LimitRange with defaults but no max limits
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: LimitRange
metadata:
  name: pod-resources-lr
  namespace: pod-resources
spec:
  limits:
  - default:
      memory: "128Mi"
    defaultRequest:
      memory: "64Mi"
    type: Container
EOF

# Q8: Security Contexts
echo "Creating resources for Q8: Security Contexts..."
kubectl create namespace quetzal
# FIX: Use an image that supports running as an arbitrary non-root user
kubectl create deployment broker-deployment --image=redis:alpine --replicas=3 -n quetzal

# Q9: Deprecated APIs
echo "Creating resources for Q9: Deprecated APIs..."
kubectl create namespace cobra
mkdir -p /opt/course/9
cat << 'EOF' > /opt/course/9/www.yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: www
  namespace: cobra
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: www
    spec:
      containers:
      - name: nginx
        image: nginx:1.16
        ports:
        - containerPort: 80
EOF

# Q10: Rolling Updates
echo "Creating resources for Q10..."
kubectl create namespace kdpd00202
# Create a deployment and then update it to generate a revision history
kubectl create deployment app-deployment --image=nginx:1.11 -n kdpd00202 --replicas=4
sleep 2
kubectl set image deployment/app-deployment -n kdpd00202 nginx=nginx:1.12

# Q11: CronJob
echo "Creating resources for Q11: CronJob..."
kubectl create namespace periodic-jobs

# Q12: Job
echo "Creating resources for Q12: Job..."
kubectl create namespace neptune

# Q13: Pod to Deployment
echo "Creating resources for Q13: Pod to Deployment..."
kubectl create namespace pluto
kubectl run holy-api --image=viktoruj/ping_pong:alpine -n pluto

# Q14: Service & Logs
echo "Creating resources for Q14: Service & Logs..."
mkdir -p /opt/course/14
kubectl run app-14 --image=nginx -n pluto

# Q15: Sidecar
echo "Creating resources for Q15: Sidecar..."
kubectl create namespace mercury
mkdir -p /opt/course/15
cat << 'EOF' > /opt/course/15/index.html
<h1>Welcome to the Sidecar Logs</h1>
<p>This file is served from a ConfigMap.</p>
EOF

# Q16: Storage
echo "Creating resources for Q16: Storage..."
kubectl create namespace earth
kubectl label node node01 disk=ssd --overwrite=true

# Q17: Service Troubleshooting
echo "Creating resources for Q17: Service Troubleshooting..."
kubectl create namespace mars
kubectl create deployment manager-api-deployment --image=nginx -n mars
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: manager-api-svc
  namespace: mars
spec:
  type: NodePort
  selector:
    app: wrong-selector
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 8081
EOF

# Q18: Secrets
echo "Creating resources for Q18: Secrets..."
kubectl create namespace dev-db
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: secret-pod
  namespace: dev-db
spec:
  containers:
  - name: db-container
    image: mysql:8.0
    command: ["/bin/sh", "-c", "sleep 3600"]
    env:
    - name: "DB_USER"
      value: "admin"
    - name: "MYSQL_ROOT_PASSWORD"
      value: "supersecret123"
    - name: "DB_NAME"
      value: "prod-db"
EOF

# Q19: RBAC
echo "Creating resources for Q19: RBAC..."
kubectl create namespace rbac-test-lab

# Q20: ConfigMap from File
echo "Creating resources for Q20: ConfigMap from File..."
kubectl create namespace config-test
mkdir -p /opt/course/20
echo "nginx-config-data" > /opt/course/20/ingress_nginx_conf.yaml

# --- LAB CLEANUP SCRIPT ---
echo "--- Lab setup complete. Here is the cleanup script. ---"
cat << 'EOF'
#!/bin/bash
kubectl delete ns tiger ckad-netpol external dev pod-resources quetzal cobra kdpd00202 neptune pluto mercury earth mars rbac-test-lab periodic-jobs dev-db some-random-ns config-test --ignore-not-found=true
echo "Lab environment has been cleaned up."
EOF