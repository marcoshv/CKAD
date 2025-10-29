#!/bin/bash
# =================================================================
# CKAD ANSWER SCRIPT (Corrected Final Version)
# =================================================================

echo "--- Applying Solutions for All Questions ---"

# --- Q1: Canary Deployment ---
echo "Solving Q1..."
# FIX: The original answer had incorrect names, replicas, labels, and image.
# This solution scales blue to 8, creates canary-v2 with 2 replicas,
# sets the correct image, and applies the correct labels for the canary pattern.
kubectl scale deployment blue -n tiger --replicas=8
kubectl get svc web-srv -n tiger -o yaml > web-srv.yaml
yq -i '.spec.selector = {"tier": "web"}' web-srv.yaml
kubectl replace -f web-srv.yaml -n tiger --force
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: canary-v2
  namespace: tiger
spec:
  replicas: 2
  selector:
    matchLabels:
      app: canary-v2
  template:
    metadata:
      labels:
        app: canary-v2
        tier: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.27.0
EOF

# --- Q2: NetworkPolicy ---
echo "Solving Q2..."
# FIX: The original answer targeted the wrong pod with the wrong label.
# This applies all three required labels to the correct 'frontend' pod.
kubectl label pod frontend -n ckad-netpol tier=frontend role=api-client access=cache --overwrite

# --- Q3: Ingress Troubleshooting ---
echo "Solving Q3..."

# 1. Apply the primary backend pod and service
kubectl apply -f /opt/course/3/pod.yaml
kubectl apply -f /opt/course/3/service.yaml

# 2. Wait for the primary pod to be ready
echo "Waiting for webapp-pod to become Ready..."
kubectl wait --for=condition=ready pod/webapp-pod -n external --timeout=90s

# 3. Apply the corrected Ingress manifest with BOTH rules
echo "Applying corrected Ingress with /app and /status rules..."
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: webapp-ingress
  namespace: external
  annotations:
    # Annotation to strip /app prefix
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  # Correct Ingress Class
  ingressClassName: nginx
  rules:
  - host: ckad.local
    http:
      paths:
      # Rule 1: Fixed path for /app
      - path: /app
        pathType: Prefix
        backend:
          service:
            # Corrected service name
            name: webapp
            port:
              number: 8080
      # Rule 2: ADDED path for /status
      - path: /status
        pathType: Prefix
        backend:
          service:
            name: health-check-srv # Target the new service
            port:
              number: 8081 # Target the new service's port
EOF

# 4. Give the Ingress Controller time to process rules
sleep 15

# --- Q4: ServiceAccount Permissions ---
echo "Solving Q4..."

# --- Solution for Part 1 ---
echo "Extracting logs from the previously failed pod..."
# ADDED: Get the name of a pod from the deployment
POD_NAME=$(kubectl get pods -n dev -l app=log-reader-app -o jsonpath='{.items[0].metadata.name}')
# ADDED: Run the logs command with --previous
kubectl logs "${POD_NAME}" -n dev --previous > /opt/course/4/failing-pod.log 2>&1 || echo "No previous container logs found, proceeding..."

echo "Creating Role and RoleBinding for log-reader-sa..."
kubectl create role pod-reader-role --verb=get,list --resource=pods -n dev
kubectl create rolebinding log-reader-binding --role=pod-reader-role --serviceaccount=dev:log-reader-sa -n dev
# Optional: Trigger rollout restart so the deployment picks up new permissions immediately
kubectl rollout restart deployment log-reader-deploy -n dev

# --- Solution for Part 2 ---
echo "Patching metrics-scraper-deploy to use correct ServiceAccount..."
# Note: The user would first investigate using commands like:
# kubectl get role,rolebinding -n dev
# kubectl describe rolebinding pod-viewer-binding -n dev
# This would reveal that 'pod-viewer-sa' is the correct ServiceAccount to use.
kubectl patch deployment metrics-scraper-deploy -n dev -p '{"spec":{"template":{"spec":{"serviceAccountName":"pod-viewer-sa"}}}}'
# Optional: Trigger rollout restart
kubectl rollout restart deployment metrics-scraper-deploy -n dev

# --- Q5: Docker Build ---
echo "Solving Q5..."
# FIX: The original just printed the command. This actually runs it.
# Docker build requires a context directory (e.g., the directory containing the Dockerfile).
docker build -t ckad:0.0.1 -f /opt/course/5/Dockerfile /opt/course/5
docker save -o /opt/course/5/ckad.tar ckad:0.0.1

# --- Q6: Probes ---
echo "Solving Q6..."
# Delete the old pod and apply the new manifest with probes
kubectl delete pod probe-pod --force --ignore-not-found=true
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: probe-pod
spec:
  containers:
  - name: probe-pod
    image: busybox
    command:
    - /bin/sh
    - -c
    - touch /tmp/ready && touch /tmp/healthy && sleep 3600
    livenessProbe:
      exec:
        command:
        - ls
        - /tmp/healthy
      initialDelaySeconds: 10
      periodSeconds: 60
    readinessProbe:
      exec:
        command:
        - /bin/sh
        - -c
        - "touch /tmp/ready; cat /tmp/ready"
      initialDelaySeconds: 10
      periodSeconds: 60
EOF

# Wait for the pod to be ready and metrics to potentially become available
echo "Waiting for probe-pod to be ready and metrics collection..."
kubectl wait --for=condition=ready pod/probe-pod --timeout=60s
# Give metrics server a bit more time
sleep 15

# Get pod metrics and append to file
echo "Appending pod metrics to /opt/course/6/pod_metrics.txt..."
# Use --no-headers for cleaner output, redirect errors in case metrics aren't ready yet
kubectl top pod probe-pod --no-headers >> /opt/course/6/pod_metrics.txt 2>/dev/null || echo "Metrics not available yet." >> /opt/course/6/pod_metrics.txt

# --- Q7: Edit ResourceQuota and Create Pod ---
echo "Solving Q7..."
# FIX: The original answer was missing the second and third parts of the question.
# This version patches the quota, creates both required pods, and patches the LimitRange.
kubectl patch resourcequota pod-resources-quota -n pod-resources --type='json' -p='[{"op": "replace", "path": "/spec/hard/requests.cpu", "value":"1"}, {"op": "replace", "path": "/spec/hard/limits.memory", "value":"1Gi"}]'
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nginx-resources
  namespace: pod-resources
spec:
  containers:
  - name: nginx
    image: nginx
    resources:
      requests:
        cpu: "200m"
        memory: "256Mi"
      limits:
        cpu: "400m"
        memory: "512Mi"
EOF
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nginx-defaults
  namespace: pod-resources
spec:
  containers:
  - name: nginx
    image: nginx
    resources:
      requests:
        cpu: "100m"
EOF
kubectl patch limitrange pod-resources-lr -n pod-resources --type='json' -p='[{"op": "add", "path": "/spec/limits/0/max", "value": {"cpu": "400m", "memory": "512Mi"}}]'

# --- Q8: Security Context and Sidecar ---
echo "Solving Q8..."
# Applying a full manifest is the clearest way to add multiple complex fields
# to an existing deployment.
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: broker-deployment
  namespace: quetzal
  labels:
    app: broker-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: broker-deployment
  template:
    metadata:
      labels:
        app: broker-deployment
    spec:
      # Pod-level security context
      securityContext:
        runAsUser: 5000
      # Sidecar is an initContainer with restartPolicy: Always
      initContainers:
      - name: log-shipper
        image: busybox:1.36
        restartPolicy: Always
        command: ["tail", "-F", "/var/log/redis.log"]
        volumeMounts:
        - name: log-volume
          mountPath: /var/log
      # Main application container
      containers:
      - name: redis # Name is derived from the original image
        image: redis:alpine
        # Command is now overridden to generate logs
        command:
          - "/bin/sh"
          - "-c"
          - "while true; do echo \$(date) >> /var/log/redis.log; sleep 5; done"
        # Container-level security context
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
            add: ["NET_BIND_SERVICE"]
        volumeMounts:
        - name: log-volume
          mountPath: /var/log
      # Shared volume
      volumes:
      - name: log-volume
        emptyDir: {}
EOF

# --- Q9: Deprecated APIs and Kustomize ---
echo "Solving Q9..."

# --- Part 1: Fix and Deploy Initial Manifest ---
echo "Fixing deprecated API and deploying initial version..."
# Fix the apiVersion
sed -i 's#extensions/v1beta1#apps/v1#' /opt/course/9/www.yaml
# Add the mandatory selector for apps/v1 Deployment
sed -i '/replicas: 1/a\ \ selector:\n\ \ \ \ matchLabels:\n\ \ \ \ \ \ app: www' /opt/course/9/www.yaml
# Apply the corrected manifest
kubectl apply -f /opt/course/9/www.yaml

# --- Part 2: Implement Kustomize Changes ---
echo "Creating kustomization files..."
# Create kustomization.yaml
cat << EOF > /opt/course/9/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- www.yaml
patches:
- replica-patch.yaml
EOF

# Create replica-patch.yaml
cat << EOF > /opt/course/9/replica-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: www
  namespace: cobra
spec:
  replicas: 3
EOF

# Apply changes using kustomize build
echo "Applying kustomize configuration..."
kubectl kustomize /opt/course/9/ | kubectl apply -f -

# --- Q10: Rolling Updates, HPA, Helm ---
echo "Solving Q10..."

# --- Part 1: Rolling Update, Rollback, Scale ---
echo "Applying deployment strategy, rollout, rollback, and scale..."
kubectl patch deployment app-deployment -n kdpd00202 -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":"30%","maxUnavailable":"30%"}}}}'
kubectl set image deployment/app-deployment -n kdpd00202 nginx=nginx:1.27.0
# Wait for the rollout to finish before rolling back
kubectl rollout status deployment/app-deployment -n kdpd00202 --timeout=120s
kubectl rollout undo deployment/app-deployment --to-revision=1 -n kdpd00202
# Wait for the rollback to finish before scaling
kubectl rollout status deployment/app-deployment -n kdpd00202 --timeout=120s
kubectl scale deployment app-deployment -n kdpd00202 --replicas=3

# --- Part 2: HorizontalPodAutoscaler ---
echo "Creating HorizontalPodAutoscaler..."
# Using kubectl autoscale is the quickest way
kubectl autoscale deployment app-deployment -n kdpd00202 \
  --cpu=75% \
  --min=2 \
  --max=5 \
  --name=app-hpa

# --- Part 3: Helm Install ---
echo "Installing Redis Helm chart..."
# Install redis chart with specified release name, namespace, and replica count
helm install redis-cache bitnami/redis \
  --namespace kdpd00202 \
  --set replica.replicaCount=1 \
  --version 18.15.1 # Pinning version for consistency

# --- Q11: CronJob ---
echo "Solving Q11..."
# This command creates the entire complex CronJob from scratch.
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: my-cronjob
  namespace: periodic-jobs
spec:
  schedule: "*/30 * * * *"
  startingDeadlineSeconds: 200
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 10
  failedJobsHistoryLimit: 5
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          containers:
          - name: cron-job-container
            image: busybox
            command:
              - "/bin/sh"
              - "-c"
              - "echo 'Daily cleanup task complete' && date"
          restartPolicy: OnFailure
EOF
kubectl create job my-cronjob-manual --from=cronjob/my-cronjob -n periodic-jobs

# --- Q12: Job ---
echo "Solving Q12..."
# FIX: The original was missing the backoffLimit.
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: neb-new-job
  namespace: neptune
spec:
  completions: 3
  parallelism: 2
  backoffLimit: 4
  template:
    spec:
      containers:
      - name: neb-new-job-container
        image: busybox:1.31.0
        command: ["sh", "-c", "sleep 2 && echo done"]
      restartPolicy: Never
EOF

# --- Q13: Pod to Deployment ---
echo "Solving Q13..."
# FIX: The original sed command was very complex and hard to verify.
# This is a much clearer and more reliable way to create the correct Deployment.
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: deployment-app-y
  namespace: pluto
spec:
  replicas: 1
  selector:
    matchLabels:
      run: holy-api
  template:
    metadata:
      labels:
        run: holy-api
    spec:
      containers:
      - name: holy-api
        image: viktoruj/ping_pong:alpine
        env:
        - name: SERVER_NAME
          value: app-y
        securityContext:
          allowPrivilegeEscalation: false
          privileged: false
EOF
kubectl delete pod holy-api -n pluto --ignore-not-found=true --force

# --- Q14: Service & Logs & ExternalName ---
echo "Solving Q14..."

# --- Part 1: NodePort Service, Curl, Logs ---
echo "Exposing pod, testing connectivity, and exporting logs..."
kubectl expose pod app-14 -n pluto --name=service-14 --port=8080 --target-port=80 --type=NodePort
# Wait for service endpoint (good practice, though NodePort doesn't strictly need it for DNS)
sleep 5
kubectl run temp-curl --image=curlimages/curl:latest -n pluto --rm -i --quiet --restart=Never -- \
  curl -s --connect-timeout 10 http://service-14.pluto:8080 > /opt/course/14/service.html
kubectl wait --for=condition=ready pod/app-14 -n pluto --timeout=60s
kubectl logs app-14 -n pluto > /opt/course/14/pod.log

# --- Part 2: ExternalName Service ---
echo "Creating ExternalName service..."
# Using kubectl create service externalname is the quickest way
kubectl create service externalname external-api -n pluto \
  --external-name api.externalservice.io

# --- Q15: Sidecar ---
echo "Solving Q15..."
# FIX: The original answer patched a non-existent deployment. This creates the
# required ConfigMap and the correct multi-container Pod from scratch.
kubectl create configmap nginx-config -n mercury --from-file=/opt/course/15/index.html
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: log-pod
  namespace: mercury
spec:
  containers:
  - name: log-writer
    image: busybox
    command: ["/bin/sh", "-c", "while true; do date >> /var/log/app/log.txt; sleep 1; done"]
    volumeMounts:
    - name: log-volume
      mountPath: /var/log/app
  - name: log-server
    image: nginx:alpine
    volumeMounts:
    - name: log-volume
      mountPath: /usr/share/nginx/html
    - name: nginx-config-vol
      mountPath: /usr/share/nginx/html/index.html
      subPath: index.html
  volumes:
  - name: log-volume
    emptyDir: {}
  - name: nginx-config-vol
    configMap:
      name: nginx-config
EOF

# --- Q16: Storage ---
echo "Solving Q16..."
# FIX: Original had incorrect hostPath and command paths.
# This uses the correct '/pv/data' hostPath and writes to '/data/init.txt' in the volume.
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-analytics
spec:
  capacity:
    storage: 100Mi
  accessModes:
  - ReadWriteOnce
  hostPath:
    path: /pv/data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-analytics
  namespace: earth
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: analytics
  namespace: earth
spec:
  nodeSelector:
    disk: ssd
  volumes:
  - name: data-volume
    persistentVolumeClaim:
      claimName: pvc-analytics
  initContainers:
  - name: data-initializer
    image: busybox
    command: ["/bin/sh", "-c", "echo 'Initialized' > /data/init.txt"]
    volumeMounts:
    - name: data-volume
      mountPath: /data
  containers:
  - name: main-app
    image: busybox
    command: ["sleep", "36000"]
    volumeMounts:
    - name: data-volume
      mountPath: /data
EOF

# --- Q17: Service Troubleshooting ---
echo "Solving Q17..."
kubectl patch service manager-api-svc -n mars --type='json' \
-p='[{"op": "replace", "path": "/spec/selector", "value": {"app": "manager-api-deployment"}}, {"op": "replace", "path": "/spec/ports/0/targetPort", "value":80}]'
# FIX: Increased delay to allow endpoints and DNS to update reliably
sleep 15

# --- Q18: Secrets ---
echo "Solving Q18..."
# This version creates the secret, then applies a complete, correct pod manifest
# that uses the secret for both environment variables AND a volume mount.
kubectl delete pod secret-pod -n dev-db --ignore-not-found=true --force
kubectl create secret generic db-credentials -n dev-db \
  --from-literal=user=admin \
  --from-literal=dbname=prod-db \
  --from-literal=pass=supersecret123

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
    - name: DB_USER
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: user
    - name: MYSQL_ROOT_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: pass
    - name: DB_NAME
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: dbname
    volumeMounts:
    - name: secret-vol
      mountPath: /etc/mysql/password.txt
      subPath: password.txt
  volumes:
  - name: secret-vol
    secret:
      secretName: db-credentials
      items:
      - key: pass
        path: password.txt
EOF

# --- Q19: RBAC ---
echo "Solving Q19..."
kubectl create serviceaccount pod-sa -n rbac-test-lab
kubectl create role pod-sa-role --verb=get,list --resource=pods -n rbac-test-lab
kubectl create rolebinding pod-sa-roleBinding --role=pod-sa-role --serviceaccount=rbac-test-lab:pod-sa -n rbac-test-lab
# FIX: The original kubectl run command was missing the serviceAccount flag.
# A manifest is more explicit and reliable.
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: rbac-test-pod
  namespace: rbac-test-lab
spec:
  serviceAccountName: pod-sa
  containers:
  - name: test-container
    image: busybox
    command: ["sleep", "3600"]
EOF

# --- Q20: ConfigMap from File ---
echo "Solving Q20..."
# FIX: Original was missing the environment variable from the ConfigMap.
kubectl create configmap config --from-literal=LOG_LEVEL=INFO -n config-test --from-file=/opt/course/20/ingress_nginx_conf.yaml
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-z
  namespace: config-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-z
  template:
    metadata:
      labels:
        app: app-z
    spec:
      containers:
      - name: main
        image: viktoruj/ping_pong:alpine
        env:
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: config
              key: LOG_LEVEL
        volumeMounts:
        - name: config-vol
          mountPath: /appConfig
      volumes:
      - name: config-vol
        configMap:
          name: config
EOF

echo "--- All Solutions Applied ---"