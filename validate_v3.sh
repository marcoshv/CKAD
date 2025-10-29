#!/bin/bash
# =================================================================
# CKAD LAB VALIDATION SCRIPT (Verbose Error Version)
# =================================================================

echo "--- Validating Answers ---"
echo ""

# --- Q1: Validating Canary Deployment ---
echo "--- Q1: Validating Canary Deployment ---"
BLUE_REPLICAS=$(kubectl get deployment blue -n tiger -o jsonpath='{.spec.replicas}' 2>/dev/null)
CANARY_REPLICAS=$(kubectl get deployment canary-v2 -n tiger -o jsonpath='{.spec.replicas}' 2>/dev/null)
CANARY_IMAGE=$(kubectl get deployment canary-v2 -n tiger -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
SERVICE_SELECTOR=$(kubectl get service web-srv -n tiger -o jsonpath='{.spec.selector.tier}' 2>/dev/null)
SERVICE_ENDPOINTS=$(kubectl get endpointslice -n tiger -l kubernetes.io/service-name=web-srv -o json | jq '.items[].endpoints | length' | paste -sd+ | bc)
CANARY_APP_LABEL=$(kubectl get deployment canary-v2 -n tiger -o jsonpath='{.spec.template.metadata.labels.app}' 2>/dev/null)

if [ "$BLUE_REPLICAS" -eq 8 ] && [ "$CANARY_REPLICAS" -eq 2 ] && [ "$CANARY_IMAGE" = "nginx:1.27.0" ] && [ "$SERVICE_SELECTOR" = "web" ] && [ "$SERVICE_ENDPOINTS" -eq 10 ] && [ "$CANARY_APP_LABEL" = "canary-v2" ]; then
    echo "✅ Success: Canary deployment is correctly configured."
else
    # ENHANCED: More detailed error messages for Q1
    echo "❌ Failure: Validation failed. Check the following:"
    if [ "$BLUE_REPLICAS" -ne 8 ]; then echo "  - Replica count for 'blue' is not 8 (Found: $BLUE_REPLICAS)."; fi
    if [ "$CANARY_REPLICAS" -ne 2 ]; then echo "  - Replica count for 'canary-v2' is not 2 (Found: $CANARY_REPLICAS)."; fi
    if [ "$CANARY_IMAGE" != "nginx:1.27.0" ]; then echo "  - Image for 'canary-v2' is incorrect (Found: $CANARY_IMAGE)."; fi
    if [ "$SERVICE_SELECTOR" != "web" ]; then echo "  - Service selector is incorrect. It should be 'tier=web'."; fi
    if [ "$CANARY_APP_LABEL" != "canary-v2" ]; then echo "  - The 'canary-v2' deployment pods are missing the unique 'app=canary-v2' label (Found: app=$CANARY_APP_LABEL)."; fi
    if [ "$SERVICE_ENDPOINTS" -ne 10 ]; then echo "  - Service is not targeting all 10 pods (Found: $SERVICE_ENDPOINTS endpoints)."; fi
fi
echo "-------------------------------------"
echo ""

# --- Q2: NetworkPolicy ---
echo "--- Q2: Validating Network Policy ---"
TIER_LABEL=$(kubectl get pod frontend -n ckad-netpol -o jsonpath='{.metadata.labels.tier}')
ROLE_LABEL=$(kubectl get pod frontend -n ckad-netpol -o jsonpath='{.metadata.labels.role}')
ACCESS_LABEL=$(kubectl get pod frontend -n ckad-netpol -o jsonpath='{.metadata.labels.access}')
ACCESS_TO_BACKEND=false
ACCESS_TO_CACHE=false
ACCESS_TO_DB_BLOCKED=false
echo "Running connectivity tests for Q2..."
BACKEND_IP=$(kubectl get pod backend -n ckad-netpol -o jsonpath='{.status.podIP}')
if kubectl exec frontend -n ckad-netpol -- curl -s --connect-timeout 2 $BACKEND_IP >/dev/null; then ACCESS_TO_BACKEND=true; fi
CACHE_IP=$(kubectl get pod cache -n ckad-netpol -o jsonpath='{.status.podIP}')
if kubectl exec frontend -n ckad-netpol -- curl -s --connect-timeout 2 $CACHE_IP >/dev/null; then ACCESS_TO_CACHE=true; fi
DB_IP=$(kubectl get pod database -n ckad-netpol -o jsonpath='{.status.podIP}')
if ! kubectl exec frontend -n ckad-netpol -- curl -s --connect-timeout 2 $DB_IP >/dev/null; then ACCESS_TO_DB_BLOCKED=true; fi
if [ "$TIER_LABEL" = "frontend" ] && [ "$ROLE_LABEL" = "api-client" ] && [ "$ACCESS_LABEL" = "cache" ] && [ "$ACCESS_TO_BACKEND" = true ] && [ "$ACCESS_TO_CACHE" = true ] && [ "$ACCESS_TO_DB_BLOCKED" = true ]; then
    echo "✅ Success: The 'frontend' pod has all correct labels and network access is configured as required."
else
    echo "❌ Failure: Validation failed. Check that the 'frontend' pod has all three required labels and that it can reach 'backend' and 'cache' but not 'database'."
fi
echo "-------------------------------------"
echo ""

# --- Q3: Validating Ingress Troubleshooting ---
echo "--- Q3: Validating Ingress Troubleshooting ---"
# Check rule 1 (/app) details
APP_BACKEND_SERVICE=$(kubectl get ingress webapp-ingress -n external -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}' 2>/dev/null)
APP_BACKEND_PORT=$(kubectl get ingress webapp-ingress -n external -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port.number}' 2>/dev/null)
INGRESS_CLASS=$(kubectl get ingress webapp-ingress -n external -o jsonpath='{.spec.ingressClassName}' 2>/dev/null)
REWRITE_ANNOTATION=$(kubectl get ingress webapp-ingress -n external -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/rewrite-target}' 2>/dev/null)

# ADDED: Check rule 2 (/status) details
STATUS_PATH=$(kubectl get ingress webapp-ingress -n external -o jsonpath='{.spec.rules[0].http.paths[1].path}' 2>/dev/null)
STATUS_BACKEND_SERVICE=$(kubectl get ingress webapp-ingress -n external -o jsonpath='{.spec.rules[0].http.paths[1].backend.service.name}' 2>/dev/null)
STATUS_BACKEND_PORT=$(kubectl get ingress webapp-ingress -n external -o jsonpath='{.spec.rules[0].http.paths[1].backend.service.port.number}' 2>/dev/null)


APP_CURL_SUCCESS=false
STATUS_CURL_SUCCESS=false # ADDED: Variable for the second test

echo "Running pre-flight checks for Ingress..."
kubectl wait --for=condition=Available deployment/ingress-nginx-controller -n ingress-nginx --timeout=120s >/dev/null 2>&1
# ADDED: Also wait for the health-check deployment to be ready
kubectl wait --for=condition=Available deployment/health-check -n external --timeout=60s >/dev/null 2>&1

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')

# Test 1: Connectivity for /app
echo "Testing Ingress connectivity on http://$NODE_IP:$NODE_PORT/app"
if [ -n "$NODE_IP" ] && [ -n "$NODE_PORT" ]; then
    for i in {1..10}; do
        if curl -s -m 5 --resolve ckad.local:$NODE_PORT:$NODE_IP http://ckad.local:$NODE_PORT/app | grep -q "Welcome to nginx"; then
            APP_CURL_SUCCESS=true
            break
        fi
        [[ "$i" -ne 10 ]] && echo "Attempt $i failed for /app. Retrying in 2 seconds..." && sleep 2
    done
fi

# ADDED: Test 2: Connectivity for /status
echo "Testing Ingress connectivity on http://$NODE_IP:$NODE_PORT/status"
if [ -n "$NODE_IP" ] && [ -n "$NODE_PORT" ]; then
    for i in {1..10}; do
        # Note: /status doesn't get rewritten, so Nginx will return its default page
        if curl -s -m 5 --resolve ckad.local:$NODE_PORT:$NODE_IP http://ckad.local:$NODE_PORT/status | grep -q "Welcome to nginx"; then
            STATUS_CURL_SUCCESS=true
            break
        fi
        [[ "$i" -ne 10 ]] && echo "Attempt $i failed for /status. Retrying in 2 seconds..." && sleep 2
    done
fi


# Final check includes all conditions
if [ "$APP_BACKEND_SERVICE" = "webapp" ] && \
   [ "$APP_BACKEND_PORT" -eq 8080 ] && \
   [ "$INGRESS_CLASS" = "nginx" ] && \
   [ "$REWRITE_ANNOTATION" = "/" ] && \
   [ "$STATUS_PATH" = "/status" ] && \
   [ "$STATUS_BACKEND_SERVICE" = "health-check-srv" ] && \
   [ "$STATUS_BACKEND_PORT" -eq 8081 ] && \
   [ "$APP_CURL_SUCCESS" = true ] && \
   [ "$STATUS_CURL_SUCCESS" = true ]; then
    echo "✅ Success: Ingress is correctly configured and routing traffic for both /app and /status."
else
    echo "❌ Failure: Validation failed. Check the following:"
    if [ "$APP_BACKEND_SERVICE" != "webapp" ]; then echo "  - /app rule: Backend service name is incorrect."; fi
    if [ "$APP_BACKEND_PORT" != "8080" ]; then echo "  - /app rule: Backend service port is incorrect."; fi
    if [ "$INGRESS_CLASS" != "nginx" ]; then echo "  - 'ingressClassName' is not set to 'nginx'."; fi
    if [ "$REWRITE_ANNOTATION" != "/" ]; then echo "  - 'rewrite-target' annotation is missing or incorrect for /app."; fi
    if [ "$STATUS_PATH" != "/status" ]; then echo "  - /status rule: Path is incorrect."; fi
    if [ "$STATUS_BACKEND_SERVICE" != "health-check-srv" ]; then echo "  - /status rule: Backend service name is incorrect."; fi
    if [ "$STATUS_BACKEND_PORT" != "8081" ]; then echo "  - /status rule: Backend service port is incorrect."; fi
    if [ "$APP_CURL_SUCCESS" = false ]; then echo "  - Connectivity test failed for /app."; fi
    if [ "$STATUS_CURL_SUCCESS" = false ]; then echo "  - Connectivity test failed for /status."; fi
fi
echo "-------------------------------------"
echo ""

# --- Q4: Validating ServiceAccount Permissions ---
echo "--- Q4: Validating ServiceAccount Permissions ---"

# --- Validation for Part 1 ---
PART1_LOG_SUCCESS=false
PART1_RBAC_SUCCESS=false
echo "Validating Part 1: Log file creation and 'log-reader-sa' permissions..."
# ADDED: Check if the log file exists
if [ -f "/opt/course/4/failing-pod.log" ]; then
    PART1_LOG_SUCCESS=true
fi
# Check RBAC permissions (as before)
if kubectl auth can-i get pods --as=system:serviceaccount:dev:log-reader-sa -n dev | grep -q "yes"; then
    if kubectl auth can-i list pods --as=system:serviceaccount:dev:log-reader-sa -n dev | grep -q "yes"; then
        PART1_RBAC_SUCCESS=true
    fi
fi

# --- Validation for Part 2 ---
PART2_SUCCESS=false
echo "Validating Part 2: 'metrics-scraper-deploy' configuration..."
# Check if the deployment was patched to use the correct ServiceAccount
CORRECT_SA=$(kubectl get deployment metrics-scraper-deploy -n dev -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>/dev/null)
if [ "$CORRECT_SA" = "pod-viewer-sa" ]; then
    # If so, check if that ServiceAccount actually has the correct permissions
    if kubectl auth can-i get pods --as=system:serviceaccount:dev:pod-viewer-sa -n dev | grep -q "yes"; then
        if kubectl auth can-i list pods --as=system:serviceaccount:dev:pod-viewer-sa -n dev | grep -q "yes"; then
            PART2_SUCCESS=true
        fi
    fi
fi

# --- Final Result ---
if [ "$PART1_LOG_SUCCESS" = true ] && [ "$PART1_RBAC_SUCCESS" = true ] && [ "$PART2_SUCCESS" = true ]; then
    echo "✅ Success: Log file created and both parts of the RBAC configuration are correct."
else
    echo "❌ Failure: Validation failed. Check the following:"
    if [ "$PART1_LOG_SUCCESS" = false ]; then
        echo "  - Part 1: Log file '/opt/course/4/failing-pod.log' was not created."
    fi
    if [ "$PART1_RBAC_SUCCESS" = false ]; then
        echo "  - Part 1: 'log-reader-sa' does not have 'get' and 'list' permissions on pods."
    fi
    if [ "$PART2_SUCCESS" = false ]; then
        echo "  - Part 2: 'metrics-scraper-deploy' is not using the correct 'pod-viewer-sa' ServiceAccount, or the SA lacks permissions."
    fi
fi
echo "-------------------------------------"
echo ""

# --- Q5: Docker Build ---
echo "--- Q5: Validating Docker Build ---"
IMAGE_CORRECT=false
if [ -f "/opt/course/5/ckad.tar" ]; then
    echo "Found ckad.tar, attempting to load and inspect..."
    docker load -q -i /opt/course/5/ckad.tar
    if docker inspect ckad:0.0.1 >/dev/null 2>&1; then
        IMAGE_CORRECT=true
    fi
    docker rmi ckad:0.0.1 >/dev/null 2>&1
fi
if [ "$IMAGE_CORRECT" = true ]; then
    echo "✅ Success: The archive /opt/course/5/ckad.tar was created and contains the correctly named image 'ckad:0.0.1'."
else
    echo "❌ Failure: The file /opt/course/5/ckad.tar was not found or does not contain the correct image and tag."
fi
echo "-------------------------------------"
echo ""

# --- Q6: Validating Probes ---
echo "--- Q6: Validating Probes ---"
LIVENESS_DELAY=$(kubectl get pod probe-pod -o jsonpath='{.spec.containers[0].livenessProbe.initialDelaySeconds}' 2>/dev/null)
LIVENESS_PERIOD=$(kubectl get pod probe-pod -o jsonpath='{.spec.containers[0].livenessProbe.periodSeconds}' 2>/dev/null)
READINESS_DELAY=$(kubectl get pod probe-pod -o jsonpath='{.spec.containers[0].readinessProbe.initialDelaySeconds}' 2>/dev/null)
READINESS_PERIOD=$(kubectl get pod probe-pod -o jsonpath='{.spec.containers[0].readinessProbe.periodSeconds}' 2>/dev/null)
POD_READY=false
METRICS_FILE_EXISTS=false # Variable for file check

# Check pod readiness (as before)
if kubectl wait --for=condition=ready pod/probe-pod --timeout=60s >/dev/null 2>&1; then
    POD_READY=true
fi

# Check if the metrics file exists
if [ -f "/opt/course/6/pod_metrics.txt" ]; then
    METRICS_FILE_EXISTS=true
fi

# Final check includes all conditions
if [ "$LIVENESS_DELAY" -eq 10 ] && \
   [ "$LIVENESS_PERIOD" -eq 60 ] && \
   [ "$READINESS_DELAY" -eq 10 ] && \
   [ "$READINESS_PERIOD" -eq 60 ] && \
   [ "$POD_READY" = true ] && \
   [ "$METRICS_FILE_EXISTS" = true ]; then
    echo "✅ Success: Probes configured, pod is Ready, and metrics file created."
else
    echo "❌ Failure: Validation failed. Check the following:"
    if [ -z "$LIVENESS_DELAY" ]; then echo "  - Liveness probe is missing."; fi
    if [ "$LIVENESS_DELAY" -ne 10 ]; then echo "  - Liveness probe initialDelaySeconds is not 10."; fi
    if [ "$LIVENESS_PERIOD" -ne 60 ]; then echo "  - Liveness probe periodSeconds is not 60."; fi
    if [ -z "$READINESS_DELAY" ]; then echo "  - Readiness probe is missing."; fi
    if [ "$READINESS_DELAY" -ne 10 ]; then echo "  - Readiness probe initialDelaySeconds is not 10."; fi
    if [ "$READINESS_PERIOD" -ne 60 ]; then echo "  - Readiness probe periodSeconds is not 60."; fi
    if [ "$POD_READY" = false ]; then echo "  - Pod did not become Ready."; fi
    if [ "$METRICS_FILE_EXISTS" = false ]; then echo "  - Metrics file '/opt/course/6/pod_metrics.txt' was not created."; fi
fi
echo "-------------------------------------"
echo ""

# --- Q7: Edit ResourceQuota and Create Pod ---
echo "--- Q7: Validating ResourceQuota and LimitRange ---"
PART1_QUOTA_OK=false
PART1_POD_OK=false
PART2_POD_OK=false
PART3_LR_OK=false
PART3_VERIFY_OK=false
QUOTA_CPU_REQ=$(kubectl get resourcequota pod-resources-quota -n pod-resources -o jsonpath='{.spec.hard.requests\.cpu}')
QUOTA_MEM_LIM=$(kubectl get resourcequota pod-resources-quota -n pod-resources -o jsonpath='{.spec.hard.limits\.memory}')
if [ "$QUOTA_CPU_REQ" = "1" ] && [ "$QUOTA_MEM_LIM" = "1Gi" ]; then PART1_QUOTA_OK=true; fi
POD_CPU_REQ=$(kubectl get pod nginx-resources -n pod-resources -o jsonpath='{.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
POD_MEM_REQ=$(kubectl get pod nginx-resources -n pod-resources -o jsonpath='{.spec.containers[0].resources.requests.memory}' 2>/dev/null)
POD_CPU_LIM=$(kubectl get pod nginx-resources -n pod-resources -o jsonpath='{.spec.containers[0].resources.limits.cpu}' 2>/dev/null)
POD_MEM_LIM=$(kubectl get pod nginx-resources -n pod-resources -o jsonpath='{.spec.containers[0].resources.limits.memory}' 2>/dev/null)
if [ "$POD_CPU_REQ" = "200m" ] && [ "$POD_MEM_REQ" = "256Mi" ] && [ "$POD_CPU_LIM" = "400m" ] && [ "$POD_MEM_LIM" = "512Mi" ]; then PART1_POD_OK=true; fi
DEFAULT_POD_EXISTS=$(kubectl get pod nginx-defaults -n pod-resources --ignore-not-found)
DEFAULTED_MEM_REQ=$(kubectl get pod nginx-defaults -n pod-resources -o jsonpath='{.spec.containers[0].resources.requests.memory}' 2>/dev/null)
if [ -n "$DEFAULT_POD_EXISTS" ] && [ "$DEFAULTED_MEM_REQ" = "64Mi" ]; then PART2_POD_OK=true; fi
# FIX: Corrected typo in limitrange name from pod--resources-lr to pod-resources-lr
LR_MAX_CPU=$(kubectl get limitrange pod-resources-lr -n pod-resources -o jsonpath='{.spec.limits[0].max.cpu}' 2>/dev/null)
LR_MAX_MEM=$(kubectl get limitrange pod-resources-lr -n pod-resources -o jsonpath='{.spec.limits[0].max.memory}' 2>/dev/null)
if [ "$LR_MAX_CPU" = "400m" ] && [ "$LR_MAX_MEM" = "512Mi" ]; then PART3_LR_OK=true; fi
BIG_POD_EXISTS=$(kubectl get pod nginx-too-big -n pod-resources --ignore-not-found)
if [ -z "$BIG_POD_EXISTS" ]; then PART3_VERIFY_OK=true; fi
if [ "$PART1_QUOTA_OK" = true ] && [ "$PART1_POD_OK" = true ] && [ "$PART2_POD_OK" = true ] && [ "$PART3_LR_OK" = true ] && [ "$PART3_VERIFY_OK" = true ]; then
    echo "✅ Success: ResourceQuota, LimitRange, and all Pods were correctly configured."
else
    echo "❌ Failure: Validation failed. Check the following:"
    if [ "$PART1_QUOTA_OK" = false ]; then echo "  - The ResourceQuota was not updated correctly."; fi
    if [ "$PART1_POD_OK" = false ]; then echo "  - The 'nginx-resources' pod's resource requests/limits are incorrect."; fi
    if [ "$PART2_POD_OK" = false ]; then echo "  - The 'nginx-defaults' pod was not created or did not receive the default memory request."; fi
    if [ "$PART3_LR_OK" = false ]; then echo "  - The LimitRange was not edited with the correct max values."; fi
    if [ "$PART3_VERIFY_OK" = false ]; then echo "  - The 'nginx-too-big' pod was created, but it should have been blocked by the LimitRange."; fi
fi
echo "-------------------------------------"
echo ""

# --- Q8: Validating Security Context and Sidecar ---
echo "--- Q8: Validating Security Context and Sidecar ---"
CONFIG_OK=false
FUNCTIONAL_OK=false

echo "Checking deployment 'broker-deployment' spec..."
# Check pod-level security context
RUNASUSER_SETTING=$(kubectl get deploy broker-deployment -n quetzal -o jsonpath='{.spec.template.spec.securityContext.runAsUser}' 2>/dev/null)
# Check container-level security context
ALLOWPRIV_SETTING=$(kubectl get deploy broker-deployment -n quetzal -o jsonpath='{.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation}' 2>/dev/null)
CAP_DROP=$(kubectl get deploy broker-deployment -n quetzal -o jsonpath='{.spec.template.spec.containers[0].securityContext.capabilities.drop[0]}' 2>/dev/null)
CAP_ADD=$(kubectl get deploy broker-deployment -n quetzal -o jsonpath='{.spec.template.spec.containers[0].securityContext.capabilities.add[0]}' 2>/dev/null)
# Check for the modern sidecar configuration
SIDECAR_POLICY=$(kubectl get deploy broker-deployment -n quetzal -o jsonpath='{.spec.template.spec.initContainers[?(@.name=="log-shipper")].restartPolicy}' 2>/dev/null)

if [ "$RUNASUSER_SETTING" = "5000" ] && \
   [ "$ALLOWPRIV_SETTING" = "false" ] && \
   [ "$CAP_DROP" = "ALL" ] && \
   [ "$CAP_ADD" = "NET_BIND_SERVICE" ] && \
   [ "$SIDECAR_POLICY" = "Always" ]; then
    CONFIG_OK=true
fi

# Functional check for readiness and logging
echo "Waiting for pod to become Ready..."
if kubectl wait --for=condition=ready pod -l app=broker-deployment -n quetzal --timeout=90s >/dev/null 2>&1; then
    echo "Performing functional test on log sharing..."
    POD_NAME=$(kubectl get pods -n quetzal -l app=broker-deployment -o jsonpath='{.items[0].metadata.name}')
    # Give the main container a moment to write a log entry
    sleep 6
    LOG_CONTENT=$(kubectl exec "${POD_NAME}" -c log-shipper -n quetzal -- cat /var/log/redis.log 2>/dev/null)
    if [ -n "$LOG_CONTENT" ]; then
        FUNCTIONAL_OK=true
    fi
fi

if [ "$CONFIG_OK" = true ] && [ "$FUNCTIONAL_OK" = true ]; then
    echo "✅ Success: Security context and modern sidecar are correctly configured and functional."
else
    echo "❌ Failure: Validation failed. Check the following:"
    if [ "$CONFIG_OK" = false ]; then echo "  - One or more fields in the deployment's spec is incorrect. Check runAsUser, capabilities, and the sidecar's restartPolicy."; fi
    if [ "$FUNCTIONAL_OK" = false ]; then echo "  - The pod did not become Ready or the sidecar could not read the log file."; fi
fi
echo "-------------------------------------"
echo ""

# --- Q9: Validating Deprecated APIs and Kustomize ---
echo "--- Q9: Validating Deprecated APIs and Kustomize ---"
DEPLOYMENT_EXISTS=$(kubectl get deploy www -n cobra --ignore-not-found=true)
KUSTOMIZATION_FILE_EXISTS=false
PATCH_FILE_EXISTS=false
FINAL_REPLICAS=0

# Check if kustomization.yaml exists
if [ -f "/opt/course/9/kustomization.yaml" ]; then
    KUSTOMIZATION_FILE_EXISTS=true
fi

# Check if replica-patch.yaml exists
if [ -f "/opt/course/9/replica-patch.yaml" ]; then
    PATCH_FILE_EXISTS=true
fi

# Get the final replica count from the deployed object
if [ -n "$DEPLOYMENT_EXISTS" ]; then
    FINAL_REPLICAS=$(kubectl get deploy www -n cobra -o jsonpath='{.spec.replicas}' 2>/dev/null)
fi

# Final check includes all conditions
if [ -n "$DEPLOYMENT_EXISTS" ] && \
   [ "$KUSTOMIZATION_FILE_EXISTS" = true ] && \
   [ "$PATCH_FILE_EXISTS" = true ] && \
   [ "$FINAL_REPLICAS" -eq 3 ]; then
    echo "✅ Success: Deployment 'www' exists, kustomize files created, and replicas scaled to 3."
else
    echo "❌ Failure: Validation failed. Check the following:"
    if [ -z "$DEPLOYMENT_EXISTS" ]; then echo "  - The 'www' deployment was not found. Check initial fix and apply."; fi
    if [ "$KUSTOMIZATION_FILE_EXISTS" = false ]; then echo "  - The 'kustomization.yaml' file was not found in /opt/course/9/."; fi
    if [ "$PATCH_FILE_EXISTS" = false ]; then echo "  - The 'replica-patch.yaml' file was not found in /opt/course/9/."; fi
    if [ "$FINAL_REPLICAS" -ne 3 ]; then echo "  - The final deployment replica count is not 3 (Found: $FINAL_REPLICAS). Ensure kustomize build was applied."; fi
fi
echo "-------------------------------------"
echo ""

# --- Q10: Validating Rolling Updates, HPA, Helm ---
echo "--- Q10: Validating Rolling Updates, HPA, Helm ---"
ROLLOUT_OK=false
HPA_OK=false
HELM_OK=false

# --- Check 1: Deployment Rollout/Rollback/Scale ---
echo "Checking deployment state..."
STRATEGY_MAX_UNAVAILABLE=$(kubectl get deployment app-deployment -n kdpd00202 -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}' 2>/dev/null)
STRATEGY_MAX_SURGE=$(kubectl get deployment app-deployment -n kdpd00202 -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge}' 2>/dev/null)
CURRENT_IMAGE=$(kubectl get deployment app-deployment -n kdpd00202 -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
REPLICAS=$(kubectl get deployment app-deployment -n kdpd00202 -o jsonpath='{.spec.replicas}' 2>/dev/null)

if [ "$STRATEGY_MAX_UNAVAILABLE" = "30%" ] && \
   [ "$STRATEGY_MAX_SURGE" = "30%" ] && \
   [ "$CURRENT_IMAGE" = "nginx:1.11" ] && \
   [ "$REPLICAS" -eq 3 ]; then
    ROLLOUT_OK=true
fi

# --- Check 2: HPA Configuration ---
echo "Checking HPA configuration..."
HPA_MIN=$(kubectl get hpa app-hpa -n kdpd00202 -o jsonpath='{.spec.minReplicas}' 2>/dev/null)
HPA_MAX=$(kubectl get hpa app-hpa -n kdpd00202 -o jsonpath='{.spec.maxReplicas}' 2>/dev/null)
HPA_CPU=$(kubectl get hpa app-hpa -n kdpd00202 -o jsonpath='{.spec.metrics[?(@.type=="Resource")].resource.target.averageUtilization}' 2>/dev/null)
HPA_TARGET_NAME=$(kubectl get hpa app-hpa -n kdpd00202 -o jsonpath='{.spec.scaleTargetRef.name}' 2>/dev/null)

if [ "$HPA_MIN" -eq 2 ] && \
   [ "$HPA_MAX" -eq 5 ] && \
   [ "$HPA_CPU" -eq 75 ] && \
   [ "$HPA_TARGET_NAME" = "app-deployment" ]; then
    HPA_OK=true
fi

# --- Check 3: Helm Release ---
echo "Checking Helm release status..."
# Check if the release exists, is deployed, and in the correct namespace
if helm status redis-cache -n kdpd00202 -o json | grep -q '"status":"deployed"'; then
    # Additionally, check if the running statefulset (or deployment) has 1 replica
    # Note: Chart details might change, this assumes a StatefulSet named redis-cache-master
    REDIS_REPLICAS=$(kubectl get statefulset redis-cache-master -n kdpd00202 -o jsonpath='{.spec.replicas}' 2>/dev/null || kubectl get deployment redis-cache-master -n kdpd00202 -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [ "$REDIS_REPLICAS" -eq 1 ]; then
        HELM_OK=true
    fi
fi


# --- Final Result ---
if [ "$ROLLOUT_OK" = true ] && [ "$HPA_OK" = true ] && [ "$HELM_OK" = true ]; then
    echo "✅ Success: Deployment, HPA, and Helm release are all configured correctly."
else
    echo "❌ Failure: Validation failed. Check the following:"
    if [ "$ROLLOUT_OK" = false ]; then echo "  - Deployment state (strategy, image, replicas) is incorrect."; fi
    if [ "$HPA_OK" = false ]; then echo "  - HPA 'app-hpa' configuration (min/max replicas, CPU target) is incorrect."; fi
    if [ "$HELM_OK" = false ]; then echo "  - Helm release 'redis-cache' not found, not deployed, or Redis replica count is not 1."; fi
fi
echo "-------------------------------------"
echo ""

# --- Q11: Validating CronJob ---
echo "--- Q11: Validating CronJob ---"
CRONJOB_OK=false
MANUAL_JOB_OK=false

# Get all the required spec values from the CronJob
SCHEDULE=$(kubectl get cj my-cronjob -n periodic-jobs -o jsonpath='{.spec.schedule}' 2>/dev/null)
START_DEADLINE=$(kubectl get cj my-cronjob -n periodic-jobs -o jsonpath='{.spec.startingDeadlineSeconds}' 2>/dev/null)
SUCCESS_LIMIT=$(kubectl get cj my-cronjob -n periodic-jobs -o jsonpath='{.spec.successfulJobsHistoryLimit}' 2>/dev/null)
FAIL_LIMIT=$(kubectl get cj my-cronjob -n periodic-jobs -o jsonpath='{.spec.failedJobsHistoryLimit}' 2>/dev/null)
CONCURRENCY_POLICY=$(kubectl get cj my-cronjob -n periodic-jobs -o jsonpath='{.spec.concurrencyPolicy}' 2>/dev/null)
BACKOFF_LIMIT=$(kubectl get cj my-cronjob -n periodic-jobs -o jsonpath='{.spec.jobTemplate.spec.backoffLimit}' 2>/dev/null)
RESTART_POLICY=$(kubectl get cj my-cronjob -n periodic-jobs -o jsonpath='{.spec.jobTemplate.spec.template.spec.restartPolicy}' 2>/dev/null)
# ADDED: Check for the container command
COMMAND=$(kubectl get cj my-cronjob -n periodic-jobs -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].command[2]}' 2>/dev/null)
EXPECTED_COMMAND="echo 'Daily cleanup task complete' && date"


# Check if all values match the requirements
if [ "$SCHEDULE" = "*/30 * * * *" ] && \
   [ "$START_DEADLINE" -eq 200 ] && \
   [ "$SUCCESS_LIMIT" -eq 10 ] && \
   [ "$FAIL_LIMIT" -eq 5 ] && \
   [ "$CONCURRENCY_POLICY" = "Forbid" ] && \
   [ "$BACKOFF_LIMIT" -eq 2 ] && \
   [ "$RESTART_POLICY" = "OnFailure" ] && \
   [ "$COMMAND" = "$EXPECTED_COMMAND" ]; then
    CRONJOB_OK=true
fi

# Check if the manual job was created
MANUAL_JOB_EXISTS=$(kubectl get job my-cronjob-manual -n periodic-jobs --ignore-not-found)
if [ -n "$MANUAL_JOB_EXISTS" ]; then
    MANUAL_JOB_OK=true
fi

# Report final status
if [ "$CRONJOB_OK" = true ] && [ "$MANUAL_JOB_OK" = true ]; then
    echo "✅ Success: CronJob is correctly configured and the manual job was created."
else
    echo "❌ Failure: Validation failed. Check the following:"
    if [ "$CRONJOB_OK" = false ]; then echo "  - One or more CronJob spec fields are incorrect. Verify all settings including schedule, limits, policy, command, and restartPolicy."; fi
    if [ "$MANUAL_JOB_OK" = false ]; then echo "  - The manual job 'my-cronjob-manual' was not created."; fi
fi
echo "-------------------------------------"
echo ""

# --- Q12: Job ---
echo "--- Q12: Validating Job ---"
JOB_COMPLETED=false
echo "Waiting for Job 'neb-new-job' to complete..."
if kubectl wait --for=condition=complete job/neb-new-job -n neptune --timeout=60s >/dev/null 2>&1; then
    JOB_COMPLETED=true
fi
COMPLETIONS=$(kubectl get job neb-new-job -n neptune -o jsonpath='{.spec.completions}' 2>/dev/null)
PARALLELISM=$(kubectl get job neb-new-job -n neptune -o jsonpath='{.spec.parallelism}' 2>/dev/null)
if [ "$JOB_COMPLETED" = true ] && [ "$COMPLETIONS" -eq 3 ] && [ "$PARALLELISM" -eq 2 ]; then
    echo "✅ Success: Job is correctly configured and ran to completion."
else
    echo "❌ Failure: Check that completions=3 and parallelism=2, and that the job can run successfully."
fi
echo "-------------------------------------"
echo ""

# --- Q13: Pod to Deployment ---
echo "--- Q13: Validating Pod to Deployment ---"
DEPLOYMENT_EXISTS=$(kubectl get deployment deployment-app-y -n pluto --ignore-not-found)
REPLICAS=$(kubectl get deployment deployment-app-y -n pluto -o jsonpath='{.spec.replicas}' 2>/dev/null)
ENV_VAR=$(kubectl get deployment deployment-app-y -n pluto -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="SERVER_NAME")].value}' 2>/dev/null)
ALLOW_PRIV=$(kubectl get deployment deployment-app-y -n pluto -o jsonpath='{.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation}' 2>/dev/null)
PRIVILEGED=$(kubectl get deployment deployment-app-y -n pluto -o jsonpath='{.spec.template.spec.containers[0].securityContext.privileged}' 2>/dev/null)
POD_EXISTS=$(kubectl get pod holy-api -n pluto --ignore-not-found)
if [ -n "$DEPLOYMENT_EXISTS" ] && [ "$REPLICAS" -eq 1 ] && [ "$ENV_VAR" = "app-y" ] && [ "$ALLOW_PRIV" = "false" ] && [ "$PRIVILEGED" = "false" ] && [ -z "$POD_EXISTS" ]; then
    echo "✅ Success: Pod was successfully converted to a Deployment with all correct settings."
else
    # ENHANCED: More detailed error messages for Q13
    echo "❌ Failure: Validation failed. Check the following:"
    if [ -z "$DEPLOYMENT_EXISTS" ]; then echo "  - The 'deployment-app-y' deployment does not exist."; fi
    if [ "$REPLICAS" -ne 1 ]; then echo "  - The deployment does not have 1 replica (Found: $REPLICAS)."; fi
    if [ "$ENV_VAR" != "app-y" ]; then echo "  - The SERVER_NAME environment variable is incorrect or missing (Found: $ENV_VAR)."; fi
    if [ "$ALLOW_PRIV" != "false" ] || [ "$PRIVILEGED" != "false" ]; then echo "  - The securityContext settings (allowPrivilegeEscalation/privileged) are incorrect."; fi
    if [ -n "$POD_EXISTS" ]; then echo "  - The original 'holy-api' pod was not deleted."; fi
fi
echo "-------------------------------------"
echo ""

# --- Q14: Validating NodePort Service, Logs, and ExternalName ---
echo "--- Q14: Validating NodePort Service, Logs, and ExternalName ---"
NODEPORT_SVC_OK=false
FILES_OK=false
EXTNAME_SVC_OK=false # ADDED: Variable for the new check

# --- Check 1: NodePort Service ---
echo "Checking NodePort service 'service-14'..."
SVC_TYPE=$(kubectl get service service-14 -n pluto -o jsonpath='{.spec.type}' 2>/dev/null)
SVC_PORT=$(kubectl get service service-14 -n pluto -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
SVC_TARGET_PORT=$(kubectl get service service-14 -n pluto -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)

if [ "$SVC_TYPE" = "NodePort" ] && [ "$SVC_PORT" -eq 8080 ] && [ "$SVC_TARGET_PORT" -eq 80 ]; then
    NODEPORT_SVC_OK=true
fi

# --- Check 2: Output Files ---
echo "Checking output files..."
if [ -f "/opt/course/14/service.html" ] && [ -f "/opt/course/14/pod.log" ]; then
    FILES_OK=true
fi

# --- ADDED: Check 3: ExternalName Service ---
echo "Checking ExternalName service 'external-api'..."
EXTNAME_SVC_TYPE=$(kubectl get service external-api -n pluto -o jsonpath='{.spec.type}' 2>/dev/null)
EXTNAME_VALUE=$(kubectl get service external-api -n pluto -o jsonpath='{.spec.externalName}' 2>/dev/null)

if [ "$EXTNAME_SVC_TYPE" = "ExternalName" ] && [ "$EXTNAME_VALUE" = "api.externalservice.io" ]; then
    EXTNAME_SVC_OK=true
fi

# --- Final Result ---
if [ "$NODEPORT_SVC_OK" = true ] && [ "$FILES_OK" = true ] && [ "$EXTNAME_SVC_OK" = true ]; then
    echo "✅ Success: NodePort Service, output files, and ExternalName Service are all correct."
else
    echo "❌ Failure: Validation failed. Check the following:"
    if [ "$NODEPORT_SVC_OK" = false ]; then echo "  - NodePort Service 'service-14' configuration is incorrect (type, port, or targetPort)."; fi
    if [ "$FILES_OK" = false ]; then echo "  - One or both output files (/opt/course/14/service.html, /opt/course/14/pod.log) are missing."; fi
    if [ "$EXTNAME_SVC_OK" = false ]; then echo "  - ExternalName Service 'external-api' configuration is incorrect (type or externalName value)."; fi
fi
echo "-------------------------------------"
echo ""

# --- Q15: Sidecar ---
echo "--- Q15: Validating Sidecar ---"
SIDECAR_IS_WORKING=false
CONFIGMAP_MOUNTED=false
if kubectl wait --for=condition=ready pod/log-pod -n mercury --timeout=60s >/dev/null 2>&1; then
    LOG_CONTENT=$(kubectl exec log-pod -n mercury -c log-server -- cat /usr/share/nginx/html/log.txt 2>/dev/null)
    if [ -n "$LOG_CONTENT" ]; then SIDECAR_IS_WORKING=true; fi
    INDEX_CONTENT=$(kubectl exec log-pod -n mercury -c log-server -- cat /usr/share/nginx/html/index.html 2>/dev/null)
    if echo "$INDEX_CONTENT" | grep -q "ConfigMap"; then CONFIGMAP_MOUNTED=true; fi
fi
if [ "$SIDECAR_IS_WORKING" = true ] && [ "$CONFIGMAP_MOUNTED" = true ]; then
    echo "✅ Success: The nginx sidecar is correctly serving both the log file and the index.html."
else
    echo "❌ Failure: The sidecar is not serving the log file or index.html. Check volume mounts and commands."
fi
echo "-------------------------------------"
echo ""

# --- Q16: Storage ---
echo "--- Q16: Validating Storage ---"
PVC_IS_BOUND=$(kubectl get pvc pvc-analytics -n earth -o jsonpath='{.status.phase}')
INIT_FILE_EXISTS=false
if kubectl exec analytics -n earth -- test -f /data/init.txt 2>/dev/null; then INIT_FILE_EXISTS=true; fi
if [ "$PVC_IS_BOUND" = "Bound" ] && [ "$INIT_FILE_EXISTS" = true ]; then
    echo "✅ Success: The PVC is bound and the init container ran successfully."
else
    echo "❌ Failure: Check PVC 'pvc-analytics' status and init container file '/data/init.txt'."
fi
echo "-------------------------------------"
echo ""

# --- Q17: Validating Service Troubleshooting ---

## ------------------------------------------------------------------
## Configuration Variables
## ------------------------------------------------------------------
NAMESPACE="mars"
SERVICE_NAME="manager-api-svc"
DEPLOYMENT_APP_LABEL="manager-api-deployment"
SERVICE_PORT="8080"
EXPECTED_CONTENT="Welcome to nginx"

# --- Derived Variables ---
SERVICE_DNS_NAME="${SERVICE_NAME}.${NAMESPACE}"
SERVICE_URL="http://${SERVICE_DNS_NAME}:${SERVICE_PORT}"

## ------------------------------------------------------------------
## Validation Logic
## ------------------------------------------------------------------
echo "--- Q17: Validating Service Troubleshooting ---"
SERVICE_WORKS=false
echo "Running functional test for service '${SERVICE_NAME}' in namespace '${NAMESPACE}'..."

#
# This test uses the direct in-cluster curl command that you verified works.
#
if kubectl run internal-tester --image=curlimages/curl:8.2.1 --restart=Never -n "${NAMESPACE}" --rm -i --quiet --tty -- \
    curl -s --connect-timeout 15 "${SERVICE_URL}" | grep -q "${EXPECTED_CONTENT}"; then
    SERVICE_WORKS=true
fi

# Report the final result.
if [ "$SERVICE_WORKS" = true ]; then
    echo "✅ Success: Service was corrected and is reachable within the cluster."
else
    echo "❌ Failure: The service is not reachable at '${SERVICE_URL}'. Dumping diagnostics..."
    echo "--- Service YAML ---"
    kubectl get service "${SERVICE_NAME}" -n "${NAMESPACE}" -o yaml
    echo "--- Deployment Pod Labels ---"
    kubectl get pods -n "${NAMESPACE}" -l "app=${DEPLOY_APP_LABEL}" --show-labels
    echo "--- Service Endpoints ---"
    kubectl get endpointslice -l "kubernetes.io/service-name=${SERVICE_NAME}" -n "${NAMESPACE}"
fi
echo "-------------------------------------"
echo ""----------------------------""

# --- Q18: Validating Secrets ---
echo "--- Q18: Validating Secrets ---"

# --- Configuration ---
POD_NAME="secret-pod"
NAMESPACE="dev-db"
SECRET_NAME="db-credentials"
EXPECTED_PASS="supersecret123"
MOUNT_PATH="/etc/mysql/password.txt"

# --- Validation Logic ---
SOURCED_CORRECTLY=false
VALUES_CORRECT=false
VOLUME_MOUNT_CORRECT=false

echo "Validating pod '${POD_NAME}' in namespace '${NAMESPACE}'..."

# 1. Check if env vars are sourced from the Secret
echo "Checking if env variables are sourced from Secret '${SECRET_NAME}'..."
USER_SOURCE=$(kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[0].env[?(@.name=="DB_USER")].valueFrom.secretKeyRef.name}' 2>/dev/null)
PASS_SOURCE=$(kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[0].env[?(@.name=="MYSQL_ROOT_PASSWORD")].valueFrom.secretKeyRef.name}' 2>/dev/null)
DB_SOURCE=$(kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[0].env[?(@.name=="DB_NAME")].valueFrom.secretKeyRef.name}' 2>/dev/null)

if [ "$USER_SOURCE" = "$SECRET_NAME" ] && [ "$PASS_SOURCE" = "$SECRET_NAME" ] && [ "$DB_SOURCE" = "$SECRET_NAME" ]; then
    SOURCED_CORRECTLY=true
fi

# 2. Check the resolved values and the mounted file content inside the running Pod.
if [ "$SOURCED_CORRECTLY" = true ]; then
    echo "Source check passed. Checking resolved values and mounted file..."
    if kubectl wait --for=condition=ready pod/"${POD_NAME}" -n "${NAMESPACE}" --timeout=120s >/dev/null 2>&1; then
        # Check env var values
        USER_VALUE=$(kubectl exec "${POD_NAME}" -n "${NAMESPACE}" -- printenv DB_USER | tr -d '\r')
        PASS_VALUE=$(kubectl exec "${POD_NAME}" -n "${NAMESPACE}" -- printenv MYSQL_ROOT_PASSWORD | tr -d '\r')
        DB_VALUE=$(kubectl exec "${POD_NAME}" -n "${NAMESPACE}" -- printenv DB_NAME | tr -d '\r')
        if [ "$USER_VALUE" = "admin" ] && [ "$PASS_VALUE" = "$EXPECTED_PASS" ] && [ "$DB_VALUE" = "prod-db" ]; then
            VALUES_CORRECT=true
        fi

        # Check mounted file content
        FILE_CONTENT=$(kubectl exec "${POD_NAME}" -n "${NAMESPACE}" -- cat "${MOUNT_PATH}" 2>/dev/null | tr -d '\r')
        if [ "$FILE_CONTENT" = "$EXPECTED_PASS" ]; then
            VOLUME_MOUNT_CORRECT=true
        fi
    fi
fi

# --- Final Result ---
if [ "$SOURCED_CORRECTLY" = true ] && [ "$VALUES_CORRECT" = true ] && [ "$VOLUME_MOUNT_CORRECT" = true ]; then
    echo "✅ Success: Pod correctly consumes the Secret as both environment variables and a mounted file."
else
    echo "❌ Failure: Validation failed. Check the following:"
    if [ "$SOURCED_CORRECTLY" = false ]; then echo "  - The pod's env vars are not correctly sourced from the Secret '${SECRET_NAME}'."; fi
    if [ "$VALUES_CORRECT" = false ]; then echo "  - The env var values inside the pod are incorrect."; fi
    if [ "$VOLUME_MOUNT_CORRECT" = false ]; then echo "  - The file at '${MOUNT_PATH}' was not mounted or does not contain the correct password."; fi
fi
echo "-------------------------------------"
echo ""


# --- Q19: RBAC ---
echo "--- Q19: Validating RBAC ---"
PERMISSIONS_WORK=false
if kubectl auth can-i get pods --as=system:serviceaccount:rbac-test-lab:pod-sa -n rbac-test-lab | grep -q "yes"; then
    if kubectl auth can-i list pods --as=system:serviceaccount:rbac-test-lab:pod-sa -n rbac-test-lab | grep -q "yes"; then
        PERMISSIONS_WORK=true
    fi
fi
SA_ASSIGNED=$(kubectl get pod rbac-test-pod -n rbac-test-lab -o jsonpath='{.spec.serviceAccountName}' 2>/dev/null)
if [ "$PERMISSIONS_WORK" = true ] && [ "$SA_ASSIGNED" = "pod-sa" ]; then
    echo "✅ Success: SA is assigned, and Role/RoleBinding grant the correct permissions."
else
    echo "❌ Failure: Check SA assignment on pod, Role permissions (get/list pods), and RoleBinding linkage."
fi
echo "-------------------------------------"
echo ""

# --- Q20: ConfigMap from File ---
echo "--- Q20: Validating ConfigMap from File ---"
FILE_CONTENT=$(kubectl exec -n config-test $(kubectl get pods -n config-test -l app=app-z -o name | head -n1) -- cat /appConfig/ingress_nginx_conf.yaml 2>/dev/null)
EXPECTED_CONTENT=$(cat /opt/course/20/ingress_nginx_conf.yaml 2>/dev/null)
if [ "$FILE_CONTENT" = "$EXPECTED_CONTENT" ]; then
    echo "✅ Success: The ConfigMap was created from the file and correctly mounted."
else
    echo "❌ Failure: The content of the mounted file does not match the source file."
fi
echo "-------------------------------------"
echo ""