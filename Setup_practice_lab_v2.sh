#!/bin/bash
# =================================================================
# CKAD LAB SETUP SCRIPT (Definitive Final Version)
# =================================================================

# --- Cleanup function (in case of a previous run) ---
cleanup_lab() {
  echo "Cleaning up previous lab resources..."
  kubectl delete ns tiger ckad-netpol external dev pod-resources quetzal cobra kdpd00202 neptune pluto mercury earth mars rbac-test-lab periodic-jobs dev-db some-random-ns --ignore-not-found=true
  echo "Cleanup complete."
}
cleanup_lab

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
kubectl -n ckad-netpol run web-app --image=nginx --labels="app=web-app"
kubectl -n ckad-netpol run mysql-db --image=nginx --labels="app=mysql-db"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: mysql-db
  namespace: ckad-netpol
spec:
  selector:
    app: mysql-db
  ports:
  - protocol: TCP
    port: 3306
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: ckad-netpol
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-db-access
  namespace: ckad-netpol
spec:
  podSelector:
    matchLabels:
      app: mysql-db
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: mysql-client
EOF

# Q3: Ingress Troubleshooting
echo "Creating resources for Q3: Ingress Troubleshooting..."
kubectl create namespace external
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
            name: webapp-svc
            port:
              number: 8080
EOF

# Q4: ServiceAccount Permissions
echo "Creating resources for Q4: ServiceAccount Permissions..."
kubectl create namespace dev
kubectl create serviceaccount log-reader-sa -n dev
kubectl create -f - <<EOF
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
        image: ubuntu
        command: ["/bin/bash", "-c", "sleep 3600"]
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
kubectl run probe-pod --image=busybox --command -- /bin/sh -c "touch /tmp/healthy; sleep 3600"

# Q7: Edit ResourceQuota and Create Pod
echo "Creating resources for Q7: Edit ResourceQuota..."
kubectl create namespace pod-resources
kubectl apply -f - <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: pod-resources-quota
  namespace: pod-resources
spec:
  hard:
    requests.cpu: "100m"
    limits.memory: "128Mi"
    pods: "3"
EOF

# Q8: Security Contexts
echo "Creating resources for Q8: Security Contexts..."
kubectl create namespace quetzal
kubectl create deployment broker-deployment --image=nginx:1.7.9 --replicas=3 -n quetzal

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
echo "Creating resources for Q10: Rolling Updates..."
kubectl create namespace kdpd00202
# Create multiple revisions by updating the image
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
kubectl create namespace some-random-ns
kubectl run log-finder-pod-any-ns --image=nginx -n some-random-ns --labels=app_name=log-pod-123

# Q15: Sidecar
echo "Creating resources for Q15: Sidecar..."
kubectl create namespace mercury
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy-app
  namespace: mercury
spec:
  replicas: 1
  selector:
    matchLabels:
      app: legacy-app
  template:
    metadata:
      labels:
        app: legacy-app
    spec:
      containers:
      - name: app1
        image: busybox
        command: ["/bin/sh", "-c", "while true; do echo 'App1 log entry' >> /log/logs1.txt; sleep 2; done"]
      - name: app2
        image: busybox
        command: ["/bin/sh", "-c", "while true; do echo 'App2 log entry' >> /log/logs2.txt; sleep 3; done"]
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
# Create a pod with multiple hardcoded credentials to be fixed
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

# --- LAB CLEANUP SCRIPT ---
echo "--- Lab setup complete. Here is the cleanup script. ---"
cat << 'EOF'
#!/bin/bash
kubectl delete ns tiger ckad-netpol external dev pod-resources quetzal cobra kdpd00202 neptune pluto mercury earth mars rbac-test-lab periodic-jobs dev-db some-random-ns --ignore-not-found=true
echo "Lab environment has been cleaned up."
EOF