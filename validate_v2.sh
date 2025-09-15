#!/bin/bash
# =================================================================
# CKAD LAB VALIDATION SCRIPT (Definitive Final Version)
# =================================================================

echo "--- Validating Answers ---"
echo ""

# --- Q1: Canary Deployment ---
echo "--- Q1: Validating Canary Deployment ---"
BLUE_REPLICAS=$(kubectl get deployment blue -n tiger -o jsonpath='{.spec.replicas}')
GREEN_REPLICAS=$(kubectl get deployment main-app-v2 -n tiger -o jsonpath='{.spec.replicas}')
SERVICE_ENDPOINTS=$(kubectl get endpoints web-srv -n tiger -o jsonpath='{range .subsets[*]}{.addresses[*].ip}{"\n"}{end}' | wc -l)
if [ "$BLUE_REPLICAS" -eq 7 ] && [ "$GREEN_REPLICAS" -eq 3 ] && [ "$SERVICE_ENDPOINTS" -eq 10 ]; then
    echo "✅ Success: Canary deployment is correctly configured."
else
    echo "❌ Failure: Check replica counts (7/3) and service endpoints (10)."
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
# Test 1: Frontend to Backend (should succeed)
BACKEND_IP=$(kubectl get pod backend -n ckad-netpol -o jsonpath='{.status.podIP}')
if kubectl exec frontend -n ckad-netpol -- curl -s --connect-timeout 2 $BACKEND_IP >/dev/null; then
    ACCESS_TO_BACKEND=true
fi

# Test 2: Frontend to Cache (should succeed)
CACHE_IP=$(kubectl get pod cache -n ckad-netpol -o jsonpath='{.status.podIP}')
if kubectl exec frontend -n ckad-netpol -- curl -s --connect-timeout 2 $CACHE_IP >/dev/null; then
    ACCESS_TO_CACHE=true
fi

# Test 3: Frontend to Database (should fail/timeout)
DB_IP=$(kubectl get pod database -n ckad-netpol -o jsonpath='{.status.podIP}')
if ! kubectl exec frontend -n ckad-netpol -- curl -s --connect-timeout 2 $DB_IP >/dev/null; then
    ACCESS_TO_DB_BLOCKED=true
fi

if [ "$TIER_LABEL" = "frontend" ] && [ "$ROLE_LABEL" = "api-client" ] && [ "$ACCESS_LABEL" = "cache" ] && [ "$ACCESS_TO_BACKEND" = true ] && [ "$ACCESS_TO_CACHE" = true ] && [ "$ACCESS_TO_DB_BLOCKED" = true ]; then
    echo "✅ Success: The 'frontend' pod has all correct labels and network access is configured as required."
else
    echo "❌ Failure: Validation failed. Check that the 'frontend' pod has all three required labels and that it can reach 'backend' and 'cache' but not 'database'."
fi
echo "-------------------------------------"
echo ""

# --- Q3: Ingress Troubleshooting ---
echo "--- Q3: Validating Ingress Troubleshooting ---"
CONFIG_CORRECT=false
CONNECTION_WORKS=false

# Part 1: Check that the ingress is pointing to the correct service backend
BACKEND_SERVICE_NAME=$(kubectl get ingress webapp-ingress -n external -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}')
if [ "$BACKEND_SERVICE_NAME" = "webapp" ]; then
    CONFIG_CORRECT=true
fi

# Part 2: Functionally test the connection through the ingress
echo "Testing Ingress connectivity..."
# Find the Ingress controller's NodePort
NODE_PORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null)
if [ -z "$NODE_PORT" ]; then
  # Fallback for different ingress controller names/configs
  NODE_PORT=$(kubectl get svc -n ingress-nginx -o jsonpath='{.items[0].spec.ports[?(@.nodePort)].nodePort}')
fi

if [ -n "$NODE_PORT" ]; then
    # Use a temporary pod to curl the ingress, passing the correct Host header
    HTTP_STATUS=$(kubectl run tmp-curl --image=busybox --rm -i --restart=Never -- \
      sh -c "wget --spider --timeout=5 -S -O /dev/null http://127.0.0.1:$NODE_PORT/app --header 'Host: ckad.local' 2>&1 | grep 'HTTP/' | awk '{print \$2}'")
    
    if [ "$HTTP_STATUS" = "200" ]; then
        CONNECTION_WORKS=true
    fi
fi

# Final combined validation
if [ "$CONFIG_CORRECT" = true ] && [ "$CONNECTION_WORKS" = true ]; then
    echo "✅ Success: Ingress is correctly configured and the application is reachable."
else
    echo "❌ Failure: Validation failed. Check the following:"
    if [ "$CONFIG_CORRECT" = false ]; then
        echo "  - The Ingress is not pointing to the correct 'webapp' service."
    fi
    if [ "$CONNECTION_WORKS" = false ]; then
        echo "  - The application is not reachable via 'curl http://ckad.local:<nodeport>/app'."
    fi
fi
echo "-------------------------------------"
echo ""

# --- Q4: ServiceAccount Permissions ---
echo "--- Q4: Validating ServiceAccount Permissions ---"
ROLE_EXISTS=$(kubectl get role pod-reader-role -n dev --ignore-not-found=true)
ROLEBINDING_EXISTS=$(kubectl get rolebinding log-reader-binding -n dev --ignore-not-found=true)
if [ -n "$ROLE_EXISTS" ] && [ -n "$ROLEBINDING_EXISTS" ]; then
    echo "✅ Success: Role and RoleBinding were created."
else
    echo "❌ Failure: Role or RoleBinding not found."
fi
echo "-------------------------------------"
echo ""

# --- Q5: Docker Build ---
echo "--- Q5: Validating Docker Build (Simulated) ---"
if [ -f "/opt/course/5/ckad.tar" ]; then
    echo "✅ Success: The file /opt/course/5/ckad.tar was found."
else
    echo "❌ Failure: The file /opt/course/5/ckad.tar was not found."
fi
echo "-------------------------------------"
echo ""

# --- Q6: Probes ---
echo "--- Q6: Validating Probes ---"
LIVENESS_PROBE=$(kubectl get pod probe-pod -o jsonpath='{.spec.containers[0].livenessProbe.exec.command}')
READINESS_PROBE=$(kubectl get pod probe-pod -o jsonpath='{.spec.containers[0].readinessProbe.exec.command}')
if [ -n "$LIVENESS_PROBE" ] && [ -n "$READINESS_PROBE" ]; then
    echo "✅ Success: Both liveness and readiness probes are configured."
else
    echo "❌ Failure: One or both probes are missing from the pod manifest."
fi
echo "-------------------------------------"
echo ""

# --- Q7: Edit ResourceQuota and Create Pod ---
echo "--- Q7: Validating ResourceQuota and Pod ---"
QUOTA_CORRECT=false
POD_CORRECT=false
QUOTA_CPU_REQ=$(kubectl get resourcequota pod-resources-quota -n pod-resources -o jsonpath='{.spec.hard.requests\.cpu}')
QUOTA_MEM_LIM=$(kubectl get resourcequota pod-resources-quota -n pod-resources -o jsonpath='{.spec.hard.limits\.memory}')
if [ "$QUOTA_CPU_REQ" = "1" ] && [ "$QUOTA_MEM_LIM" = "1Gi" ]; then QUOTA_CORRECT=true; fi
POD_CPU_REQ=$(kubectl get pod nginx-resources -n pod-resources -o jsonpath='{.spec.containers[0].resources.requests.cpu}')
POD_MEM_REQ=$(kubectl get pod nginx-resources -n pod-resources -o jsonpath='{.spec.containers[0].resources.requests.memory}')
POD_CPU_LIM=$(kubectl get pod nginx-resources -n pod-resources -o jsonpath='{.spec.containers[0].resources.limits.cpu}')
POD_MEM_LIM=$(kubectl get pod nginx-resources -n pod-resources -o jsonpath='{.spec.containers[0].resources.limits.memory}')
if [ "$POD_CPU_REQ" = "200m" ] && [ "$POD_MEM_REQ" = "256Mi" ] && [ "$POD_CPU_LIM" = "400m" ] && [ "$POD_MEM_LIM" = "512Mi" ]; then POD_CORRECT=true; fi

if [ "$QUOTA_CORRECT" = true ] && [ "$POD_CORRECT" = true ]; then
    echo "✅ Success: ResourceQuota was edited and the Pod was created correctly."
else
    echo "❌ Failure: Check both the ResourceQuota and the Pod's resource spec."
fi
echo "-------------------------------------"
echo ""

# --- Q8: Security Contexts ---
echo "--- Q8: Validating Security Contexts ---"
RUNASUSER=$(kubectl get deploy broker-deployment -n quetzal -o jsonpath='{.spec.template.spec.securityContext.runAsUser}')
ALLOWPRIV=$(kubectl get deploy broker-deployment -n quetzal -o jsonpath='{.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation}')
if [ "$RUNASUSER" = "5000" ] && [ "$ALLOWPRIV" = "false" ]; then
    echo "✅ Success: Security context is correctly configured."
else
    echo "❌ Failure: Check runAsUser and allowPrivilegeEscalation."
fi
echo "-------------------------------------"
echo ""

# --- Q9: Deprecated APIs ---
echo "--- Q9: Validating Deprecated APIs ---"
API_VERSION=$(kubectl get deploy www -n cobra -o jsonpath='{.apiVersion}')
if [ "$API_VERSION" = "apps/v1" ]; then
    echo "✅ Success: API version is correctly updated to 'apps/v1'."
else
    echo "❌ Failure: Expected apiVersion 'apps/v1', but found '$API_VERSION'."
fi
echo "-------------------------------------"
echo ""

# --- Q10: Rolling Updates ---
echo "--- Q10: Validating Rolling Updates ---"
REVISION=$(kubectl rollout history deployment/app-deployment -n kdpd00202 --revision=1 2>/dev/null)
REPLICAS=$(kubectl get deployment app-deployment -n kdpd00202 -o jsonpath='{.spec.replicas}')
if [ -n "$REVISION" ] && [ "$REPLICAS" -eq 3 ]; then
    echo "✅ Success: Deployment was rolled back and scaled correctly."
else
    echo "❌ Failure: Check the rollback revision and final replica count."
fi
echo "-------------------------------------"
echo ""

# --- Q11: CronJob ---
echo "--- Q11: Validating CronJob ---"
CRONJOB_SPEC_CORRECT=false
SCHEDULE=$(kubectl get cj cron-job1 -n periodic-jobs -o jsonpath='{.spec.schedule}')
CONCURRENCY=$(kubectl get cj cron-job1 -n periodic-jobs -o jsonpath='{.spec.concurrencyPolicy}')
SUCCESS_LIMIT=$(kubectl get cj cron-job1 -n periodic-jobs -o jsonpath='{.spec.successfulJobsHistoryLimit}')
FAIL_LIMIT=$(kubectl get cj cron-job1 -n periodic-jobs -o jsonpath='{.spec.failedJobsHistoryLimit}')
COMPLETIONS=$(kubectl get cj cron-job1 -n periodic-jobs -o jsonpath='{.spec.jobTemplate.spec.completions}')
BACKOFF=$(kubectl get cj cron-job1 -n periodic-jobs -o jsonpath='{.spec.jobTemplate.spec.backoffLimit}')
ACTIVE_DEADLINE=$(kubectl get cj cron-job1 -n periodic-jobs -o jsonpath='{.spec.jobTemplate.spec.activeDeadlineSeconds}')
PULL_POLICY=$(kubectl get cj cron-job1 -n periodic-jobs -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].imagePullPolicy}')
RESTART_POLICY=$(kubectl get cj cron-job1 -n periodic-jobs -o jsonpath='{.spec.jobTemplate.spec.template.spec.restartPolicy}')

if [ "$SCHEDULE" = "*/15 * * * *" ] && \
   [ "$CONCURRENCY" = "Forbid" ] && \
   [ "$SUCCESS_LIMIT" -eq 5 ] && \
   [ "$FAIL_LIMIT" -eq 7 ] && \
   [ "$COMPLETIONS" -eq 3 ] && \
   [ "$BACKOFF" -eq 4 ] && \
   [ "$ACTIVE_DEADLINE" -eq 10 ] && \
   [ "$PULL_POLICY" = "IfNotPresent" ] && \
   [ "$RESTART_POLICY" = "OnFailure" ]; then
    CRONJOB_SPEC_CORRECT=true
fi

MANUAL_JOB_EXISTS=$(kubectl get job manual-job-1 -n periodic-jobs --ignore-not-found=true)

if [ "$CRONJOB_SPEC_CORRECT" = true ] && [ -n "$MANUAL_JOB_EXISTS" ]; then
    echo "✅ Success: CronJob is correctly configured and the manual Job was created."
else
    echo "❌ Failure: Validation failed. Check all CronJob spec fields and ensure the manual job was created."
fi
echo "-------------------------------------"
echo ""

# --- Q12: Job ---
echo "--- Q12: Validating Job ---"
COMPLETIONS=$(kubectl get job neb-new-job -n neptune -o jsonpath='{.spec.completions}')
PARALLELISM=$(kubectl get job neb-new-job -n neptune -o jsonpath='{.spec.parallelism}')
if [ -n "$COMPLETIONS" ] && [ "$COMPLETIONS" -eq 3 ] && [ "$PARALLELISM" -eq 2 ]; then
    echo "✅ Success: Job is correctly configured."
else
    echo "❌ Failure: Job spec is incorrect."
fi
echo "-------------------------------------"
echo ""

# --- Q13: Pod to Deployment ---
echo "--- Q13: Validating Pod to Deployment ---"
DEPLOYMENT_EXISTS=$(kubectl get deployment deployment-app-y -n pluto --ignore-not-found=true)
POD_EXISTS=$(kubectl get pod holy-api -n pluto --ignore-not-found=true)
if [ -n "$DEPLOYMENT_EXISTS" ] && [ -z "$POD_EXISTS" ]; then
    echo "✅ Success: Pod was successfully converted to a Deployment."
else
    echo "❌ Failure: Deployment not found or original pod still exists."
fi
echo "-------------------------------------"
echo ""

# --- Q14: NodePort Service and Logs ---
echo "--- Q14: Validating NodePort Service and Logs ---"
SERVICE_CORRECT=false
FILES_EXIST=false

# Part 1: Check if the service is a correctly configured NodePort
SVC_TYPE=$(kubectl get service service-14 -n pluto -o jsonpath='{.spec.type}')
PORT=$(kubectl get service service-14 -n pluto -o jsonpath='{.spec.ports[0].port}')
TARGET_PORT=$(kubectl get service service-14 -n pluto -o jsonpath='{.spec.ports[0].targetPort}')
if [ "$SVC_TYPE" = "NodePort" ] && [ "$PORT" -eq 8080 ] && [ "$TARGET_PORT" -eq 80 ]; then
    SERVICE_CORRECT=true
fi

# Part 2: Check for the existence of the created files
if [ -f "/opt/course/14/service.html" ] && [ -f "/opt/course/14/pod.log" ]; then
    FILES_EXIST=true
fi

# Final combined validation
if [ "$SERVICE_CORRECT" = true ] && [ "$FILES_EXIST" = true ]; then
    echo "✅ Success: NodePort Service is correctly configured and both required files were created."
else
    echo "❌ Failure: Validation failed. Check the Service type/ports and that both files exist."
fi
echo "-------------------------------------"
echo ""

# --- Q15: Sidecar ---
echo "--- Q15: Validating Sidecar ---"
LOGS_WORKING=false
echo "Waiting for 'legacy-app' pod to be ready..."
if kubectl wait --for=condition=ready deployment/legacy-app -n mercury --timeout=60s >/dev/null 2>&1; then
    POD_NAME=$(kubectl get pods -n mercury -l app=legacy-app -o jsonpath='{.items[0].metadata.name}')
    sleep 5
    LOGS=$(kubectl logs $POD_NAME -n mercury -c log-aggregator)
    if echo "$LOGS" | grep -q "App1 log entry" && echo "$LOGS" | grep -q "App2 log entry"; then
        LOGS_WORKING=true
    fi
fi
if [ "$LOGS_WORKING" = true ]; then
    echo "✅ Success: The sidecar is aggregating logs from both containers."
else
    echo "❌ Failure: The sidecar is not streaming logs correctly."
fi
echo "-------------------------------------"
echo ""

# --- Q16: Storage ---
echo "--- Q16: Validating Storage ---"
PVC_IS_BOUND=$(kubectl get pvc pvc-analytics -n earth -o jsonpath='{.status.phase}')
POD_IS_CORRECT=false
INIT_FILE_EXISTS=false
MOUNTED_PVC_NAME=$(kubectl get pod analytics -n earth -o jsonpath='{.spec.volumes[?(@.persistentVolumeClaim.claimName=="pvc-analytics")].name}')
NODE_SELECTOR_CORRECT=$(kubectl get pod analytics -n earth -o jsonpath='{.spec.nodeSelector.disk}')
if [ -n "$MOUNTED_PVC_NAME" ] && [ "$NODE_SELECTOR_CORRECT" = "ssd" ]; then POD_IS_CORRECT=true; fi
if kubectl exec analytics -n earth -- test -f /pv/analytics/init.txt; then INIT_FILE_EXISTS=true; fi

if [ "$PVC_IS_BOUND" = "Bound" ] && [ "$POD_IS_CORRECT" = true ] && [ "$INIT_FILE_EXISTS" = true ]; then
    echo "✅ Success: The PVC is bound, the pod is mounting it on the correct node, and the init container ran."
else
    echo "❌ Failure: Check PVC binding, pod spec (volume mount, nodeSelector), and initContainer."
fi
echo "-------------------------------------"
echo ""

# --- Q1t: Service Troubleshooting ---
echo "--- Q17: Validating Service Troubleshooting ---"
ENDPOINTS_EXIST=false
PORT_CORRECT=false
ENDPOINTS=$(kubectl get endpoints manager-api-svc -n mars -o jsonpath='{.subsets[?(@.addresses)].addresses}')
if [ -n "$ENDPOINTS" ]; then ENDPOINTS_EXIST=true; fi
TARGET_PORT=$(kubectl get service manager-api-svc -n mars -o jsonpath='{.spec.ports[0].targetPort}')
if [ "$TARGET_PORT" -eq 80 ]; then PORT_CORRECT=true; fi

if [ "$ENDPOINTS_EXIST" = true ] && [ "$PORT_CORRECT" = true ]; then
    echo "✅ Success: Service selector and targetPort were both corrected."
else
    echo "❌ Failure: Check both the service selector and the targetPort."
fi
echo "-------------------------------------"
echo ""

# --- Q18: Secrets ---
echo "--- Q18: Validating Secrets ---"
USER_CORRECT=false
PASS_CORRECT=false
DB_CORRECT=false

echo "Waiting for 'secret-pod' pod to be ready..."
if kubectl wait --for=condition=ready pod/secret-pod -n dev-db --timeout=120s >/dev/null 2>&1; then
    # Check the DB_USER environment variable
    USER_VALUE=$(kubectl exec secret-pod -n dev-db -- printenv DB_USER | tr -d '\r')
    if [ "$USER_VALUE" = "admin" ]; then
        USER_CORRECT=true
    fi
    
    # Check the MYSQL_ROOT_PASSWORD environment variable
    PASS_VALUE=$(kubectl exec secret-pod -n dev-db -- printenv MYSQL_ROOT_PASSWORD | tr -d '\r')
    if [ "$PASS_VALUE" = "supersecret123" ]; then
        PASS_CORRECT=true
    fi

    # Check the DB_NAME environment variable
    DB_VALUE=$(kubectl exec secret-pod -n dev-db -- printenv DB_NAME | tr -d '\r')
    if [ "$DB_VALUE" = "prod-db" ]; then
        DB_CORRECT=true
    fi
fi

if [ "$USER_CORRECT" = true ] && [ "$PASS_CORRECT" = true ] && [ "$DB_CORRECT" = true ]; then
    echo "✅ Success: Pod is correctly consuming all 3 keys from the Secret as environment variables."
else
    echo "❌ Failure: Validation failed. Check that DB_USER, MYSQL_ROOT_PASSWORD, and DB_NAME env variables are correctly sourced from the 'db-credentials' secret."
fi
echo "-------------------------------------"
echo ""

# --- Q19: RBAC ---
echo "--- Q19: Validating RBAC ---"
SA_ASSIGNED=$(kubectl get pod rbac-test-pod -n rbac-test-lab -o jsonpath='{.spec.serviceAccountName}')
ROLE_EXISTS=$(kubectl get role pod-sa-role -n rbac-test-lab --ignore-not-found=true)
ROLEBINDING_EXISTS=$(kubectl get rolebinding pod-sa-roleBinding -n rbac-test-lab --ignore-not-found=true)
if [ "$SA_ASSIGNED" = "pod-sa" ] && [ -n "$ROLE_EXISTS" ] && [ -n "$ROLEBINDING_EXISTS" ]; then
    echo "✅ Success: ServiceAccount is assigned and Role/RoleBinding exist."
else
    echo "❌ Failure: Check that the SA is assigned and the Role/RoleBinding are created."
fi
echo "-------------------------------------"
echo ""

# --- Q20: ConfigMap from File ---
echo "--- Q20: Validating ConfigMap from File ---"
FILE_CONTENT=$(kubectl exec -n config-test $(kubectl get pods -n config-test -l app=app-z -o name) -- cat /appConfig/ingress_nginx_conf.yaml)
EXPECTED_CONTENT=$(cat /opt/course/20/ingress_nginx_conf.yaml)
if [ "$FILE_CONTENT" = "$EXPECTED_CONTENT" ]; then
    echo "✅ Success: The ConfigMap was created from the file and correctly mounted as a volume."
else
    echo "❌ Failure: The content of the mounted file does not match the source file."
fi
echo "-------------------------------------"
echo ""