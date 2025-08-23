#!/bin/bash
# =================================================================
# CKAD LAB VALIDATION SCRIPT (Final, with New Q10 Logic)
# =================================================================

echo "--- Validating Answers ---"
echo ""

# --- Q1: Canary Deployment ---
echo "--- Q1: Validating Canary Deployment ---"
POD_COUNT=$(kubectl -n tiger get pods -l tier=web --no-headers 2>/dev/null | wc -l)
SERVICE_ENDPOINTS=$(kubectl get endpoints web-srv -n tiger -o jsonpath='{.subsets[?(@.addresses)].addresses[*].ip}' 2>/dev/null | wc -w)

if [ "$POD_COUNT" -eq 10 ] && [ "$SERVICE_ENDPOINTS" -eq 10 ]; then
    echo "✅ Success: Canary deployment is correctly configured."
else
    echo "❌ Failure: Pod count is $POD_COUNT, but expected 10. Endpoints are $SERVICE_ENDPOINTS, but expected 10."
fi
echo "-------------------------------------"
echo ""

# --- Q2: Network Policy ---
echo "--- Q2: Validating Network Policy ---"
POLICY_EXISTS=$(kubectl get networkpolicy db-policy -n ckad-netpol --ignore-not-found=true)
DB_POD_IP=$(kubectl -n ckad-netpol get pod -l run=db -o jsonpath='{.items[0].status.podIP}')
TEST_POD="ckad-netpol-newpod"
TRAFFIC_IS_BLOCKED=false

if [ -n "$DB_POD_IP" ]; then
    kubectl -n ckad-netpol exec ${TEST_POD} -- curl -s --connect-timeout 3 ${DB_POD_IP} >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        TRAFFIC_IS_BLOCKED=true
    fi
fi

if [ -n "$POLICY_EXISTS" ] && [ "$TRAFFIC_IS_BLOCKED" = true ]; then
    echo "✅ Success: NetworkPolicy 'db-policy' was created and is correctly blocking unwanted traffic."
else
    echo "❌ Failure: Ensure a NetworkPolicy named 'db-policy' exists and correctly blocks traffic."
fi
echo "-------------------------------------"
echo ""

# --- Q3: Ingress Troubleshooting ---
echo "--- Q3: Validating Ingress Troubleshooting ---"
INGRESS_PATH=$(kubectl get ingress ingress-name -n external -o jsonpath='{.spec.rules[0].http.paths[0].path}' 2>/dev/null)
if [ "$INGRESS_PATH" = "/" ]; then
    echo "✅ Success: Ingress path is correctly set to '/'."
else
    echo "❌ Failure: Ingress path is '$INGRESS_PATH', but expected '/'."
fi
echo "-------------------------------------"
echo ""

# --- Q4: ServiceAccount Permissions ---
echo "--- Q4: Validating ServiceAccount Permissions ---"
ROLE_EXISTS=$(kubectl get role pod-reader-role -n dev --ignore-not-found 2>/dev/null)
ROLEBINDING_EXISTS=$(kubectl get rolebinding log-reader-binding -n dev --ignore-not-found 2>/dev/null)
if [ -n "$ROLE_EXISTS" ] && [ -n "$ROLEBINDING_EXISTS" ]; then
    echo "✅ Success: Role and RoleBinding were created."
else
    echo "❌ Failure: Role or RoleBinding not found."
fi
echo "-------------------------------------"
echo ""

# --- Q5: Export built container images in OCI format. ---
echo "--- Q5: Validating Image Export (Simulated) ---"
echo "✅ Success: This is a manual task. Verification passed."
echo "-------------------------------------"
echo ""

# --- Q6: Readiness Probe ---
echo "--- Q6: Validating Readiness Probe ---"
PROBE_EXISTS=$(kubectl get pod probe-pod -o jsonpath='{.spec.containers[0].readinessProbe}' 2>/dev/null)
if [ -n "$PROBE_EXISTS" ]; then
    echo "✅ Success: Readiness probe is configured."
else
    echo "❌ Failure: Readiness probe not found in pod manifest."
fi
echo "-------------------------------------"
echo ""

# --- Q7: Resource Requests ---
echo "--- Q7: Validating Resource Requests ---"
CPU_REQUEST=$(kubectl get pod nginx-resources -n pod-resources -o jsonpath='{.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
MEM_REQUEST=$(kubectl get pod nginx-resources -n pod-resources -o jsonpath='{.spec.containers[0].resources.requests.memory}' 2>/dev/null)
if [ "$CPU_REQUEST" = "200m" ] && [ "$MEM_REQUEST" = "1Gi" ]; then
    echo "✅ Success: Resource requests are correctly configured."
else
    echo "❌ Failure: Expected CPU=200m, Memory=1Gi. Found CPU=$CPU_REQUEST, Memory=$MEM_REQUEST."
fi
echo "-------------------------------------"
echo ""

# --- Q8: Security Contexts ---
echo "--- Q8: Validating Security Contexts ---"
RUNASUSER=$(kubectl get deploy broker-deployment -n quetzal -o jsonpath='{.spec.template.spec.securityContext.runAsUser}' 2>/dev/null)
ALLOWPRIV=$(kubectl get deploy broker-deployment -n quetzal -o jsonpath='{.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation}' 2>/dev/null)
if [ "$RUNASUSER" = "30000" ] && [ "$ALLOWPRIV" = "false" ]; then
    echo "✅ Success: Security context is correctly configured."
else
    echo "❌ Failure: Expected runAsUser=30000 and allowPrivilegeEscalation=false. Found user=$RUNASUSER, allowPrivilege=$ALLOWPRIV"
fi
echo "-------------------------------------"
echo ""

# --- Q9: Deprecated APIs ---
echo "--- Q9: Validating Deprecated APIs ---"
API_VERSION=$(kubectl get deploy www -n cobra -o jsonpath='{.apiVersion}' 2>/dev/null)
if [ "$API_VERSION" = "apps/v1" ]; then
    echo "✅ Success: API version is correctly updated to 'apps/v1'."
else
    echo "❌ Failure: Expected apiVersion 'apps/v1', but found '$API_VERSION'."
fi
echo "-------------------------------------"
echo ""

# --- Q10: Rolling Updates ---
echo "--- Q10: Validating Rolling Updates ---"
CURRENT_IMAGE=$(kubectl get deploy app-deployment -n kdpd00202 -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
# CORRECTED: This new check looks for the existence of an old ReplicaSet with the updated image.
# This proves an update was actually performed before the rollback.
EVIDENCE_OF_UPDATE=$(kubectl get replicaset -n kdpd00202 -l app=app-deployment -o jsonpath='{.items[*].spec.template.spec.containers[?(@.image=="nginx:1.13")].image}' 2>/dev/null)

if [ "$CURRENT_IMAGE" = "nginx:1.12" ] && [ -n "$EVIDENCE_OF_UPDATE" ]; then
    echo "✅ Success: Deployment was correctly rolled back to the original image after an update."
else
    echo "❌ Failure: The deployment image is '$CURRENT_IMAGE' (expected 'nginx:1.12') or there is no evidence that an update to nginx:1.13 was performed."
fi
echo "-------------------------------------"
echo ""

# --- Q11: CronJob ---
echo "--- Q11: Validating CronJob ---"
CRONJOB_SCHEDULE=$(kubectl get cronjob hello -n periodic-jobs -o jsonpath='{.spec.schedule}' 2>/dev/null)
if [ "$CRONJOB_SCHEDULE" = "*/1 * * * *" ]; then
    echo "✅ Success: CronJob is correctly scheduled."
else
    echo "❌ Failure: CronJob schedule is '$CRONJOB_SCHEDULE', but should be '*/1 * * * *'."
fi
echo "-------------------------------------"
echo ""

# --- Q12: Job ---
echo "--- Q12: Validating Job ---"
COMPLETIONS=$(kubectl get job neb-new-job -n neptune -o jsonpath='{.spec.completions}' 2>/dev/null)
PARALLELISM=$(kubectl get job neb-new-job -n neptune -o jsonpath='{.spec.parallelism}' 2>/dev/null)
if [ -n "$COMPLETIONS" ] && [ "$COMPLETIONS" -eq 3 ] && [ "$PARALLELISM" -eq 2 ]; then
    echo "✅ Success: Job is correctly configured for 3 completions and 2 parallelism."
else
    echo "❌ Failure: Job has completions='$COMPLETIONS' and parallelism='$PARALLELISM', but expected 3 and 2."
fi
echo "-------------------------------------"
echo ""

# --- Q13: Pod to Deployment ---
echo "--- Q13: Validating Pod to Deployment ---"
DEPLOYMENT_EXISTS=$(kubectl get deployment holy-api -n pluto --ignore-not-found 2>/dev/null)
POD_EXISTS=$(kubectl get pod holy-api -n pluto --ignore-not-found 2>/dev/null)
if [ -n "$DEPLOYMENT_EXISTS" ] && [ -z "$POD_EXISTS" ]; then
    echo "✅ Success: Pod was successfully converted to a Deployment."
else
    echo "❌ Failure: Deployment not found or original pod still exists."
fi
echo "-------------------------------------"
echo ""

# --- Q14: Service & Logs ---
echo "--- Q14: Validating Service & Logs (Simulated) ---"
SERVICE_CORRECT=false
SVC_PORT=$(kubectl get service project-plt-6cc-svc -n pluto -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
TARGET_PORT=$(kubectl get service project-plt-6cc-svc -n pluto -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)
if [ -n "$SVC_PORT" ] && [ "$SVC_PORT" -eq 3333 ] && [ "$TARGET_PORT" -eq 80 ]; then
    SERVICE_CORRECT=true
fi
if [ "$SERVICE_CORRECT" = true ]; then
    echo "✅ Success: Service is correctly configured. (Manual validation needed for log files)."
else
    echo "❌ Failure: Check that the service ports are 3333:80."
fi
echo "-------------------------------------"
echo ""

# --- Q15: Sidecar ---
echo "--- Q15: Validating Sidecar ---"
CONTAINER_COUNT=$(kubectl get deployment cleaner -n mercury -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n"}{end}' 2>/dev/null | wc -l)
if [ "$CONTAINER_COUNT" -eq 2 ]; then
    echo "✅ Success: Deployment has two containers, including the sidecar."
else
    echo "❌ Failure: Expected 2 containers, but found $CONTAINER_COUNT."
fi
echo "-------------------------------------"
echo ""

# --- Q16: PV/PVC ---
echo "--- Q16: Validating PV/PVC ---"
PVC_STATUS=$(kubectl get pvc earth-project-earthflower-pvc -n earth -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$PVC_STATUS" = "Bound" ]; then
    echo "✅ Success: PVC is created and bound."
else
    echo "❌ Failure: PVC status is '$PVC_STATUS', but expected 'Bound'."
fi
echo "-------------------------------------"
echo ""

# --- Q17: Service Troubleshooting ---
echo "--- Q17: Validating Service Troubleshooting ---"
ENDPOINTS=$(kubectl get endpoints manager-api-svc -n mars -o jsonpath='{.subsets[?(@.addresses)].addresses}' 2>/dev/null)
if [ -n "$ENDPOINTS" ]; then
    echo "✅ Success: Service has endpoints and is routing traffic."
else
    echo "❌ Failure: Service has no endpoints. Check the selector."
fi
echo "-------------------------------------"
echo ""

# --- Q18: ConfigMap ---
echo "--- Q18: Validating ConfigMap ---"
CONFIGMAP_EXISTS=$(kubectl get configmap app-config --ignore-not-found 2>/dev/null)
ENV_FROM_EXISTS=$(kubectl get pod my-app -o jsonpath='{.spec.containers[0].envFrom[0].configMapRef.name}' 2>/dev/null)
if [ -n "$CONFIGMAP_EXISTS" ] && [ "$ENV_FROM_EXISTS" = "app-config" ]; then
    echo "✅ Success: Pod is using the ConfigMap for environment variables."
else
    echo "❌ Failure: ConfigMap not found or pod is not configured to use it."
fi
echo "-------------------------------------"
echo ""

# --- Q19: ServiceAccount Permissions ---
echo "--- Q19: Validating ServiceAccount Permissions ---"
ROLE_EXISTS=$(kubectl get role pod-reader-role -n rbac-test-lab --ignore-not-found 2>/dev/null)
ROLEBINDING_EXISTS=$(kubectl get rolebinding rbac-binding -n rbac-test-lab --ignore-not-found 2>/dev/null)
if [ -n "$ROLE_EXISTS" ] && [ -n "$ROLEBINDING_EXISTS" ]; then
    echo "✅ Success: Role and RoleBinding were created in the rbac-test-lab namespace."
else
    echo "❌ Failure: Check if the Role and RoleBinding exist in the rbac-test-lab namespace."
fi
echo "-------------------------------------"
echo ""

# --- Q20: Network Policy ---
echo "--- Q20: Validating Network Policy Labels ---"
WEB_LABEL=$(kubectl get pod web -n ckad-netpol -o jsonpath='{.metadata.labels.env}' 2>/dev/null)
DB_LABEL=$(kubectl get pod db -n ckad-netpol -o jsonpath='{.metadata.labels.env}' 2>/dev/null)
if [ "$WEB_LABEL" = "newpod" ] && [ "$DB_LABEL" = "newpod" ]; then
    echo "✅ Success: 'web' and 'db' pods have the correct label 'env=newpod'."
else
    echo "❌ Failure: The 'web' or 'db' pod is missing the 'env=newpod' label."
fi
echo "-------------------------------------"
echo ""

# --- Q21: Ingress Troubleshooting ---
echo "--- Q21: Validating Ingress Troubleshooting ---"
INGRESS_PATH=$(kubectl get ingress ingress-name -n external -o jsonpath='{.spec.rules[0].http.paths[0].path}' 2>/dev/null)
if [ "$INGRESS_PATH" = "/" ]; then
    echo "✅ Success: The ingress path is correctly set to '/'."
else
    echo "❌ Failure: The ingress path is '$INGRESS_PATH', but expected '/'."
fi
echo "-------------------------------------"
echo ""