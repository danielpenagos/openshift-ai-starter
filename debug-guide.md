# Debug Guide

Layer-by-layer verification commands for the OpenShift AI Starter deployment. Work through each layer in order — each layer depends on the previous one being healthy.

---

## Layer 0: ArgoCD (GitOps Control Plane)

```bash
# Is the GitOps operator installed?
oc get csv -n openshift-operators | grep gitops

# Are the ArgoCD pods running?
oc get pods -n openshift-gitops

# Get the ArgoCD console URL
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='https://{.spec.host}{"\n"}'

# List all ArgoCD Applications and their sync status
oc get applications -n openshift-gitops

# Check a specific application's health
oc get application <APP_NAME> -n openshift-gitops -o jsonpath='{.status.health.status}{"\n"}'

# Check a specific application's sync status
oc get application <APP_NAME> -n openshift-gitops -o jsonpath='{.status.sync.status}{"\n"}'

# Get detailed conditions for a failing application
oc get application <APP_NAME> -n openshift-gitops -o jsonpath='{.status.conditions}' | jq .

# Force a re-sync
oc patch application <APP_NAME> -n openshift-gitops --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

---

## Layer 1: Operators

### 1.1 Node Feature Discovery (NFD)

```bash
# Is the operator installed?
oc get csv -n openshift-nfd | grep nfd

# Is the NFD instance created?
oc get nodefeaturediscovery -n openshift-nfd

# Are the NFD pods running?
oc get pods -n openshift-nfd

# Does the GPU node have PCI labels? (10de = NVIDIA vendor ID)
oc get node -l nvidia.com/gpu=true -o json | \
  jq '.items[].metadata.labels | with_entries(select(.key | startswith("feature.node.kubernetes.io/pci-10de")))'
```

### 1.2 NVIDIA GPU Operator

```bash
# Is the operator installed?
oc get csv -n nvidia-gpu-operator | grep gpu

# Is the ClusterPolicy created?
oc get clusterpolicy gpu-cluster-policy

# Are all GPU operator pods running?
oc get pods -n nvidia-gpu-operator

# Check for pods that are NOT Running/Completed
oc get pods -n nvidia-gpu-operator --field-selector=status.phase!=Running,status.phase!=Succeeded

# Is the GPU allocatable on the node?
oc describe node -l nvidia.com/gpu=true | grep -A7 "Allocatable:" | grep nvidia

# Check GPU driver pod logs (if driver is loading)
oc logs -n nvidia-gpu-operator -l app=nvidia-driver-daemonset -c nvidia-driver-ctr --tail=20

# Check device plugin is running
oc get pods -n nvidia-gpu-operator -l app=nvidia-device-plugin-daemonset

# Check GPU node labels (driver version, GPU model, memory)
oc get node -l nvidia.com/gpu=true -o json | \
  jq '.items[].metadata.labels | with_entries(select(.key | startswith("nvidia.com/gpu")))'
```

### 1.3 OpenShift Serverless

```bash
# Is the operator installed?
oc get csv -n openshift-serverless | grep serverless

# Is KnativeServing created and ready?
oc get knativeserving -n knative-serving

# Are the Knative pods running?
oc get pods -n knative-serving

# Check for scheduling issues (common: insufficient CPU)
oc get events -n knative-serving --field-selector reason=FailedScheduling --sort-by='.lastTimestamp' | tail -5
```

### 1.4 OpenShift Service Mesh

```bash
# Is the operator installed?
oc get csv -n openshift-operators | grep servicemesh

# Check operator pod
oc get pods -n openshift-operators -l name=istio-operator
```

### 1.5 OpenShift AI (RHOAI)

```bash
# Is the operator installed?
oc get csv -n redhat-ods-operator | grep rhods

# What version?
oc get csv -n redhat-ods-operator -o jsonpath='{.items[0].spec.version}'

# Are the operator pods running?
oc get pods -n redhat-ods-operator

# Check operator logs for errors
oc logs -n redhat-ods-operator deployment/rhods-operator --tail=30
```

### 1.6 All operators at a glance

```bash
# Single command to check all operators
oc get csv -A | grep -E "nfd|gpu|serverless|servicemesh|rhods"

# Expected: all should show "Succeeded" in the PHASE column
```

---

## Layer 2: DataScienceCluster

```bash
# Is the DSC created?
oc get datasciencecluster default-dsc

# Is it ready?
oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# Expected: True

# If not ready, which components are failing?
oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}'

# Check all component conditions
oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions}' | jq '.[] | select(.status != "True" and .reason != "Removed")'

# Check individual component readiness
oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions}' | \
  jq -r '.[] | "\(.type): \(.status) \(.message // "")"'

# Are RHOAI application pods running?
oc get pods -n redhat-ods-applications

# Is KServe controller running?
oc get pods -n redhat-ods-applications | grep kserve
```

**Common issues:**
- `ServiceMesh operator must be installed` → Layer 1.4 failed
- `KserveReady: False` → Check Serverless (1.3) and Service Mesh (1.4)
- `ModelControllerReady: False` → Usually resolves after KServe is ready

---

## Layer 3: MinIO (Model Storage)

```bash
# Is the namespace created?
oc get namespace minio

# Are MinIO pods running?
oc get pods -n minio

# Check MinIO pod logs
oc logs -n minio deployment/minio --tail=20

# Is the PVC bound?
oc get pvc -n minio

# Is the service available?
oc get svc -n minio

# Is the console route available?
oc get route minio-console -n minio -o jsonpath='https://{.spec.host}{"\n"}'

# Test MinIO health from inside the cluster
oc run minio-health --rm -it --restart=Never -n minio \
  --image=curlimages/curl -- \
  curl -s http://minio.minio.svc.cluster.local:9000/minio/health/ready
# Expected: 200 OK

# List buckets
oc run mc-ls --rm -it --restart=Never -n minio \
  --image=quay.io/minio/mc:latest \
  --env="MC_CONFIG_DIR=/tmp/.mc" \
  --command -- /bin/sh -c '
    mc alias set minio http://minio.minio.svc.cluster.local:9000 minioadmin minioadmin123 &&
    mc ls minio/
  '

# List model files
oc run mc-ls-models --rm -it --restart=Never -n minio \
  --image=quay.io/minio/mc:latest \
  --env="MC_CONFIG_DIR=/tmp/.mc" \
  --command -- /bin/sh -c '
    mc alias set minio http://minio.minio.svc.cluster.local:9000 minioadmin minioadmin123 &&
    mc ls minio/models/mistral-7b-instruct-awq/
  '
```

**Common issues:**
- PVC stuck in `Pending` → Check StorageClass: `oc get storageclass`
- Pod `CrashLoopBackOff` → Check logs: `oc logs -n minio deployment/minio`

---

## Layer 4: Model Serving (vLLM)

### 4.1 ServingRuntime

```bash
# Is the ServingRuntime created?
oc get servingruntime -n llm-serving

# Check the image being used
oc get servingruntime vllm-runtime -n llm-serving -o jsonpath='{.spec.containers[0].image}'
```

### 4.2 InferenceService

```bash
# Is the InferenceService created and ready?
oc get inferenceservice -n llm-serving

# Check conditions
oc get inferenceservice mistral-7b-instruct -n llm-serving -o jsonpath='{.status.conditions}' | jq .

# Is the predictor pod running?
oc get pods -n llm-serving

# Check pod events (scheduling, image pull, crashes)
oc describe pod -n llm-serving -l serving.kserve.io/inferenceservice=mistral-7b-instruct | tail -30

# Check storage-initializer logs (model download from MinIO)
oc logs -n llm-serving -l serving.kserve.io/inferenceservice=mistral-7b-instruct -c storage-initializer

# Check vLLM container logs (model loading, CUDA errors)
oc logs -n llm-serving -l serving.kserve.io/inferenceservice=mistral-7b-instruct -c kserve-container

# If the container crashed, check the previous run's logs
oc logs -n llm-serving -l serving.kserve.io/inferenceservice=mistral-7b-instruct -c kserve-container --previous

# Check for OOM kills
oc get pod -n llm-serving -l serving.kserve.io/inferenceservice=mistral-7b-instruct \
  -o jsonpath='{.items[0].status.containerStatuses[?(@.name=="kserve-container")].lastState.terminated}'
```

### 4.3 Endpoint connectivity

```bash
# List available models via the API
oc run curl-models --rm -it --restart=Never -n llm-serving \
  --image=curlimages/curl -- \
  curl -s http://mistral-7b-instruct-predictor.llm-serving.svc.cluster.local:8080/v1/models

# Send a test chat completion
oc run curl-chat --rm -it --restart=Never -n llm-serving \
  --image=curlimages/curl -- \
  curl -s http://mistral-7b-instruct-predictor.llm-serving.svc.cluster.local:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-7b-instruct",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}],
    "max_tokens": 50
  }'

# Check the vLLM health endpoint
oc run curl-health --rm -it --restart=Never -n llm-serving \
  --image=curlimages/curl -- \
  curl -s http://mistral-7b-instruct-predictor.llm-serving.svc.cluster.local:8080/health
```

**Common issues:**
- `Pending` pod → GPU taint not tolerated, or no GPU available. Check: `oc describe pod ... | grep -A5 Events`
- `InvalidImageName` → Image reference is wrong. Check: `oc get servingruntime vllm-runtime -n llm-serving -o jsonpath='{.spec.containers[0].image}'`
- `ImagePullBackOff` → Image tag doesn't exist. Verify the image is pullable.
- `CrashLoopBackOff` → Check vLLM logs for CUDA/memory errors. Try reducing `--max-model-len`.
- Storage-initializer fails → S3 credentials are wrong or MinIO is down. Check Layer 3.

---

## Layer 5: Open WebUI

```bash
# Are Open WebUI pods running?
oc get pods -n open-webui

# Check pod logs
oc logs -n open-webui -l app.kubernetes.io/name=open-webui --tail=30

# Is the route available?
oc get route open-webui -n open-webui -o jsonpath='https://{.spec.host}{"\n"}'

# Test connectivity from Open WebUI pod to vLLM
oc exec -n open-webui $(oc get pod -n open-webui -l app.kubernetes.io/name=open-webui -o name) -- \
  curl -s http://mistral-7b-instruct-predictor.llm-serving.svc.cluster.local:8080/v1/models

# Check if Redis errors are present (should be disabled)
oc logs -n open-webui -l app.kubernetes.io/name=open-webui 2>&1 | grep -i redis

# Restart the pod (forces model re-discovery)
oc delete pod -n open-webui -l app.kubernetes.io/name=open-webui
```

**Common issues:**
- `ValueError: Required environment variable not found` → `WEBUI_SECRET_KEY` is missing from Helm values
- Redis permission errors → Redis should be disabled in `open-webui-values.yaml`
- No models in dropdown → Restart the pod, or check Admin Settings > Connections > OpenAI
- Pod can't reach vLLM → Test cross-namespace connectivity (curl command above)

---

## Layer 6: GPU Node

```bash
# Is the GPU node Ready?
oc get nodes -l nvidia.com/gpu=true

# Node resource usage (actual vs allocatable)
oc adm top nodes
oc describe node -l nvidia.com/gpu=true | grep -A10 "Allocated resources"

# Check GPU details (model, memory, driver)
oc describe node -l nvidia.com/gpu=true | grep -E "nvidia.com/gpu|instance-type"

# Run nvidia-smi on the GPU node
oc debug node/$(oc get node -l nvidia.com/gpu=true -o name | head -1 | cut -d/ -f2) -- chroot /host nvidia-smi

# Check if the GPU is already claimed by another pod
oc get pods -A -o json | jq -r '.items[] | select(.spec.containers[].resources.limits."nvidia.com/gpu" != null) | "\(.metadata.namespace)/\(.metadata.name)"'
```

---

## Full Health Check (all layers)

Run this to get a quick status of every component:

```bash
echo "=== ArgoCD Applications ==="
oc get applications -n openshift-gitops -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status"

echo ""
echo "=== Operators ==="
oc get csv -A 2>/dev/null | grep -E "nfd|gpu|serverless|servicemesh|rhods" | awk '{print $2, $NF}'

echo ""
echo "=== DataScienceCluster ==="
oc get datasciencecluster default-dsc -o jsonpath='Ready: {.status.conditions[?(@.type=="Ready")].status}{"\n"}' 2>/dev/null || echo "Not found"

echo ""
echo "=== MinIO ==="
oc get pods -n minio -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready" 2>/dev/null || echo "Not found"

echo ""
echo "=== Model Serving ==="
oc get inferenceservice -n llm-serving 2>/dev/null || echo "Not found"
oc get pods -n llm-serving -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready" 2>/dev/null || echo "No pods"

echo ""
echo "=== Open WebUI ==="
oc get pods -n open-webui -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready" 2>/dev/null || echo "Not found"
oc get route open-webui -n open-webui -o jsonpath='URL: https://{.spec.host}{"\n"}' 2>/dev/null || echo "No route"

echo ""
echo "=== GPU Node ==="
oc get nodes -l nvidia.com/gpu=true -o custom-columns="NAME:.metadata.name,STATUS:.status.conditions[-1].type,GPU:.status.allocatable.nvidia\.com/gpu" 2>/dev/null || echo "No GPU node"
```

---

## Nuclear Options (use with caution)

```bash
# Force-restart all pods in a namespace
oc delete pods --all -n <NAMESPACE>

# Delete and recreate an InferenceService
oc delete inferenceservice mistral-7b-instruct -n llm-serving
oc apply -k gitops/base/model-serving

# Delete and recreate the DataScienceCluster
oc delete datasciencecluster default-dsc
oc apply -k gitops/base/datasciencecluster

# Force ArgoCD to re-sync an application
oc delete application <APP_NAME> -n openshift-gitops
oc apply -f gitops/argocd/<APP_NAME>.yaml

# Completely remove and redeploy a component
oc delete -k gitops/base/<COMPONENT>
oc apply -k gitops/base/<COMPONENT>
```
