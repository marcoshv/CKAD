#!/bin/bash
# =================================================================
# CKAD LAB SETUP SCRIPT (Final, with Direct Validation)
# =================================================================

# --- Cleanup function (in case of a previous run) ---
cleanup_lab() {
  echo "Cleaning up previous lab resources..."
  kubectl delete ns tiger ckad-netpol external dev pod-resources quetzal cobra kdpd00202 neptune pluto mercury earth mars rbac-test-lab periodic-jobs --ignore-not-found=true
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
  replicas: 6
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
kubectl -n ckad-netpol run web --image=nginx --labels="run=web"
kubectl -n ckad-netpol run db --image=nginx --labels="run=db"
kubectl -n ckad-netpol run ckad-netpol-newpod --image=nginx --labels="env=newpod"
kubectl -n ckad-netpol create -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: ckad-netpol
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF
kubectl -n ckad-netpol apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all
  namespace: ckad-netpol
spec:
  podSelector: {matchLabels: {env: newpod}}
  policyTypes: [Ingress, Egress]
  ingress:
  - from:
    - podSelector: {}
  egress:
  - to:
    - podSelector: {}
EOF

# Q3: Ingress Troubleshooting
echo "Creating resources for Q3: Ingress Troubleshooting..."
kubectl create namespace external
kubectl run webapp --image=nginx --port=8080 -n external
kubectl expose pod webapp --name=webapp --port=8080 --target-port=8080 -n external
kubectl create -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-name
  namespace: external
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx-example
  rules:
  - host: external.a.local
    http:
      paths:
      - path: /path
        pathType: Prefix
        backend:
          service:
            name: webapp
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
mkdir -p /opt/course/docker-build
cat << 'EOF' > /opt/course/docker-build/Dockerfile
# This is a simple Dockerfile for the CKAD lab
FROM nginx:alpine
LABEL maintainer="CKAD Lab"
EOF
echo "NOTE for Q5: Validation will now directly check the host path /opt/course/docker-build/."

# Q6: Readiness Probe
echo "Creating resources for Q6: Readiness Probe..."
kubectl run probe-pod --image=busybox --command -- sleep 3600

# Q7: Resource Requests
echo "Creating resources for Q7: Resource Requests..."
kubectl create namespace pod-resources

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
kubectl create deployment app-deployment --image=nginx:1.12 -n kdpd00202

# Q11: CronJob
echo "Creating resources for Q11: CronJob..."
kubectl create namespace periodic-jobs

# Q12: Job
echo "Creating resources for Q12: Job..."
kubectl create namespace neptune

# Q13: Pod to Deployment
echo "Creating resources for Q13: Pod to Deployment..."
kubectl create namespace pluto
kubectl run holy-api --image=nginx:1.17.3-alpine -n pluto

# Q14: Service & Logs
echo "Creating resources for Q14: Service & Logs..."
mkdir -p /opt/course/10
echo "NOTE for Q14: Validation will now directly check the host path /opt/course/10/."

# Q15: Sidecar
echo "Creating resources for Q15: Sidecar..."
kubectl create namespace mercury
kubectl create -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cleaner
  namespace: mercury
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cleaner
  template:
    metadata:
      labels:
        app: cleaner
    spec:
      containers:
      - name: cleaner-app
        image: ubuntu
        command: ["/bin/bash", "-c", "sleep 3600"]
EOF

# Q16: PV/PVC
echo "Creating resources for Q16: PV/PVC..."
kubectl create namespace earth

# Q17: Service Troubleshooting
echo "Creating resources for Q17: Service Troubleshooting..."
kubectl create namespace mars
kubectl create -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: manager-api-deployment
  namespace: mars
spec:
  replicas: 3
  selector:
    matchLabels:
      id: manager-api-pod
  template:
    metadata:
      labels:
        id: manager-api-pod
    spec:
      containers:
      - name: nginx
        image: nginx
EOF
kubectl create service clusterip manager-api-svc --tcp=4444:80 -n mars
kubectl patch service manager-api-svc -n mars -p '{"spec": {"selector": {"id": "wrong-selector"}}}'

# Q18: ConfigMap
echo "Creating resources for Q18: ConfigMap..."
kubectl run my-app --image=ubuntu --command -- sh -c "echo DB_HOST=mysql-svc; echo API_KEY=my-secure-key; sleep 3600"

# Q19: ServiceAccount Permissions
echo "Creating resources for Q19: ServiceAccount Permissions..."
kubectl create namespace rbac-test-lab
kubectl create deployment rbac-app-deploy --image=ubuntu -n rbac-test-lab -- /bin/bash -c "sleep 3600"
kubectl create serviceaccount rbac-sa -n rbac-test-lab

# --- LAB CLEANUP SCRIPT ---
echo "--- Lab setup complete. Here is the cleanup script. ---"
cat << 'EOF'
#!/bin/bash
kubectl delete ns tiger ckad-netpol external dev pod-resources quetzal cobra kdpd00202 neptune pluto mercury earth mars rbac-test-lab periodic-jobs --ignore-not-found=true
echo "Lab environment has been cleaned up."
EOF