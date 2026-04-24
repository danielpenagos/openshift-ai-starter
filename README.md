# OpenShift AI Starter

Deploy a production-ready AI chatbot on managed OpenShift clusters (ROSA / ARO) using **OpenShift AI** for model serving and **Open WebUI** as the frontend. Fully GitOps-ready with Kustomize and ArgoCD.

## What You Get

- **5 operators** installed and configured (NFD, NVIDIA GPU, Serverless, Service Mesh, OpenShift AI)
- **MinIO** for in-cluster model storage
- **vLLM** serving a quantized Mistral 7B model on a single T4 GPU
- **Open WebUI** as a ChatGPT-like frontend with RAG support
- **ArgoCD** managing everything via GitOps (app-of-apps pattern)

## Prerequisites

- A running **ROSA** or **ARO** cluster
- `oc`, `helm`, and `rosa` (or `az`) CLIs installed and authenticated
- `cluster-admin` privileges
- **GPU quota** in your cloud provider region
- Worker nodes meeting the **minimum compute requirements** below

### Minimum Compute Requirements

The full stack (RHOAI + ArgoCD + MinIO + vLLM + Open WebUI) requires significant compute resources. The RHOAI dashboard alone requests **2.5 CPU + 5Gi** per replica (x2 replicas by default).

#### Resource requests by component

| Component | Namespace | CPU request | Memory request | Notes |
|---|---|---|---|---|
| **RHOAI Dashboard** (x2) | `redhat-ods-applications` | 5000m | 10Gi | Largest consumer — 5 containers per pod |
| **RHOAI Controllers** | `redhat-ods-applications` | 1520m | 2Gi | KServe, notebooks, pipelines, etc. |
| **ArgoCD** | `openshift-gitops` | 1875m | 2.4Gi | |
| **NVIDIA GPU Operator** | `nvidia-gpu-operator` | 200m | 200Mi | Runs on GPU node |
| **MinIO** | `minio` | 250m | 512Mi | |
| **vLLM (model serving)** | `llm-serving` | 2000m | 8Gi | Runs on GPU node |
| **Open WebUI** | `open-webui` | 500m | 512Mi | |
| **Total** | | **~11.3 CPU** | **~23.6Gi** | |

#### RHOAI Dashboard breakdown (per replica)

| Container | CPU request | Memory request |
|---|---|---|
| rhods-dashboard | 500m | 1Gi |
| kube-rbac-proxy | 500m | 1Gi |
| model-registry-ui | 500m | 1Gi |
| gen-ai-ui | 500m | 1Gi |
| maas-ui | 500m | 1Gi |
| **Total per pod** | **2500m** | **5Gi** |

#### Recommended cluster sizing

| Config | Worker nodes | GPU node | Total CPU | Total MEM | Works? |
|---|---|---|---|---|---|
| **Minimum** | 2x `m5.2xlarge` (8 CPU, 32Gi) | 1x `g4dn.xlarge` | 19.5 CPU | 78Gi | Fits all components with little headroom |
| **Recommended** | 3x `m5.2xlarge` (8 CPU, 32Gi) | 1x `g4dn.xlarge` | 27.5 CPU | 110Gi | Comfortable — room for additional models |
| **Comfortable** | 3x `m5.4xlarge` (16 CPU, 64Gi) | 1x `g5.xlarge` | 51.5 CPU | 206Gi | Production-grade with multiple models |

> **Warning:** 3x `m5.xlarge` (3.5 CPU, 14Gi each) is **not enough**. The RHOAI dashboard alone requires 5 CPU / 10Gi (2 replicas), which leaves insufficient capacity for ArgoCD, MinIO, and system pods on small instances.

> **Note:** OpenShift system components (monitoring, ingress, DNS, etc.) consume ~2-3 CPU and ~4Gi per node before any workloads are deployed. Factor this into your sizing.

---

## Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/<YOUR_ORG>/openshift-ai-starter.git
cd openshift-ai-starter
```

### 2. Create a GPU machine pool

This step is platform-specific and must be done before deploying.

**ROSA:**

```bash
export CLUSTER_NAME=dpenagos-hcp
rosa create machinepool --cluster=$CLUSTER_NAME \
  --name=gpu-pool \
  --replicas=1 \
  --instance-type=g4dn.xlarge \
  --labels='nvidia.com/gpu=true' \
  --taints='nvidia.com/gpu=:NoSchedule'
```

**ARO:** See [gitops/overlays/aro/gpu-nodepool.md](gitops/overlays/aro/gpu-nodepool.md) for Azure GPU VM options.

Verify the GPU node is ready:

```bash
oc get nodes -l nvidia.com/gpu=true
```

### 3. Bootstrap ArgoCD and deploy everything

```bash
./scripts/bootstrap.sh https://github.com/danielpenagos/openshift-ai-starter.git
```

This script:
1. Installs the **Red Hat OpenShift GitOps** operator (ArgoCD)
2. Waits for ArgoCD to be ready
3. Deploys the **app-of-apps**, which syncs all components in order:
   - Operators (NFD, GPU, Serverless, Service Mesh, OpenShift AI)
   - DataScienceCluster
   - MinIO
   - Model serving (vLLM + InferenceService)
   - Open WebUI

> **Note:** Operators take several minutes to install. Monitor progress in the ArgoCD console (URL is printed by the script) or with:
> ```bash
> oc get csv -A | grep -E "nfd|gpu|serverless|servicemesh|rhods"
> ```

### 4. Upload a model to MinIO

> **Important:** After ArgoCD finishes deploying, the model-serving component will be in error state (`CrashLoopBackOff`). This is expected — the InferenceService tries to download the model from MinIO, but the bucket is empty. Once you upload the model (this step), the pod will automatically recover and start serving.

Once MinIO is running, upload the quantized Mistral model:

```bash
./scripts/upload-model.sh TheBloke/Mistral-7B-Instruct-v0.2-AWQ mistral-7b-instruct-awq
```

This creates a pod inside the cluster that downloads the model from HuggingFace and copies it to MinIO. Follow the logs until you see `=== Done! ===`.

After the upload completes, the InferenceService pod will restart automatically and load the model. This can take a few minutes. Monitor with:

```bash
oc get pods -n llm-serving -w
```

Wait until the pod shows `1/1 Running`.

To upload a different model:

```bash
./scripts/upload-model.sh <HUGGINGFACE_MODEL_ID> <MINIO_FOLDER_NAME>
```

### Alternative: Install Open WebUI via Helm instead of using GitOps

If you want to install open web ui by yourself, you can execute this helm installation.


```bash
helm repo add open-webui https://helm.openwebui.com/
helm repo update

helm install open-webui open-webui/open-webui \
  --namespace open-webui \
  --create-namespace \
  -f gitops/base/open-webui/open-webui-values.yaml
```

Create the Route:

```bash
oc apply -f gitops/base/open-webui/route.yaml
```

Get the URL:

```bash
oc get route open-webui -n open-webui -o jsonpath='https://{.spec.host}{"\n"}'
```

### 5. Access Open WebUI

1. Open the URL from step 5 in your browser.
2. **Sign up** — the first user becomes the admin.
3. Select **mistral-7b-instruct** from the model dropdown.
4. Start chatting.

If no models appear, go to **Admin Settings > Connections > OpenAI > Manage** and verify the API URL is:
```
http://mistral-7b-instruct-predictor.llm-serving.svc.cluster.local:8080/v1
```

---

## Alternative: Deploy Without ArgoCD

If you prefer not to use ArgoCD, deploy everything with Kustomize:

```bash
# Install all operators + components at once
oc apply -k gitops/overlays/rosa/

# Then upload the model and install Open WebUI (steps 4-5 above)
```

Or deploy component by component:

```bash
oc apply -k gitops/base/operators/nfd
oc apply -k gitops/base/operators/gpu-operator
oc apply -k gitops/base/operators/serverless
oc apply -k gitops/base/operators/servicemesh
oc apply -k gitops/base/operators/openshift-ai
# Wait for operators to be ready...
oc apply -k gitops/base/datasciencecluster
oc apply -k gitops/base/minio
oc apply -k gitops/base/model-serving
oc apply -k gitops/base/open-webui
```

---

## Verification Commands

```bash
# Check all operators are installed
oc get csv -A | grep -E "nfd|gpu|serverless|servicemesh|rhods"

# Check GPU is allocatable
oc describe node -l nvidia.com/gpu=true | grep -A7 "Allocatable:" | grep nvidia

# Check DataScienceCluster is ready
oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# Check MinIO is running
oc get pods -n minio

# Check the model is serving
oc get inferenceservice -n llm-serving

# Test the model endpoint from inside the cluster
oc run curl-test --rm -it --restart=Never -n llm-serving \
  --image=curlimages/curl -- \
  curl -s http://mistral-7b-instruct-predictor.llm-serving.svc.cluster.local:8080/v1/models

# Check Open WebUI
oc get route open-webui -n open-webui
```

---

## Useful Scripts

| Script | Description | Usage |
|---|---|---|
| `scripts/bootstrap.sh` | Install GitOps operator + deploy app-of-apps | `./scripts/bootstrap.sh <REPO_URL>` |
| `scripts/upload-model.sh` | Upload a HuggingFace model to MinIO | `./scripts/upload-model.sh <HF_MODEL> <MINIO_PATH>` |

---

## Project Structure

```
openshift-ai-starter/
├── docs/                          # Detailed step-by-step guides
│   ├── rosa-guide.md              # ROSA deployment guide
│   ├── migration-v2-to-v3.md     # RHOAI v2 → v3 migration guide
│   └── chatbot-ui-options.md      # Chatbot UI evaluation
├── gitops/
│   ├── bootstrap/                 # GitOps operator (one-time install)
│   ├── argocd/                    # ArgoCD app-of-apps definitions
│   ├── base/                      # Shared Kustomize base
│   │   ├── operators/             # NFD, GPU, Serverless, ServiceMesh, OpenShift AI
│   │   ├── datasciencecluster/    # DataScienceCluster CR
│   │   ├── minio/                 # In-cluster S3 storage
│   │   ├── model-serving/         # vLLM ServingRuntime + InferenceService
│   │   └── open-webui/            # Helm values + Route
│   └── overlays/
│       ├── rosa/                  # ROSA + RHOAI 3.x (default)
│       ├── rosa-v2/              # ROSA + RHOAI 2.x (adds Serverless/ServiceMesh)
│       └── aro/                   # ARO-specific config
├── scripts/                       # Automation scripts
├── CLAUDE.md                      # AI assistant context
└── README.md                      # This file
```

---

## OpenShift AI 3.x Support

This project supports both RHOAI 2.x and 3.x. RHOAI 3 simplifies the architecture by removing the need for Serverless and Service Mesh operators (RawDeployment is the default mode).

The base and `rosa/` overlay use RHOAI 3.x by default. To deploy with RHOAI 2.x instead, use the `rosa-v2` overlay:

```bash
# RHOAI 3.x (default)
oc apply -k gitops/overlays/rosa/

# RHOAI 2.x (legacy — adds Serverless + Service Mesh)
oc apply -k gitops/overlays/rosa-v2/
```

For full details on what changed, see [docs/migration-v2-to-v3.md](docs/migration-v2-to-v3.md).

---

## Customization

### Change the model

1. Upload a new model:
   ```bash
   ./scripts/upload-model.sh <HF_MODEL_ID> <MINIO_FOLDER>
   ```

2. Update [gitops/base/model-serving/inference-service.yaml](gitops/base/model-serving/inference-service.yaml):
   ```yaml
   storageUri: s3://models/<MINIO_FOLDER>
   ```

3. Update `--served-model-name` in [gitops/base/model-serving/serving-runtime.yaml](gitops/base/model-serving/serving-runtime.yaml).

4. Apply:
   ```bash
   oc apply -k gitops/base/model-serving
   ```

### Use AWS S3 instead of MinIO

Update [gitops/base/model-serving/s3-secret.yaml](gitops/base/model-serving/s3-secret.yaml) with your AWS credentials and S3 endpoint. See the ROSA guide for details: [docs/rosa-guide.md](docs/rosa-guide.md).

### Add more model endpoints to Open WebUI

In the Open WebUI admin panel: **Admin Settings > Connections > OpenAI > Manage > + Add New Connection**.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| GPU node has `untolerated taint` | Ensure pods have `tolerations` for `nvidia.com/gpu` |
| Open WebUI shows no models | Restart the pod: `oc delete pod -n open-webui -l app.kubernetes.io/name=open-webui` |
| Redis permission errors in Open WebUI | Disable Redis in Helm values (already done in `open-webui-values.yaml`) |
| vLLM OOM on T4 (16GB) | Use AWQ-quantized models or reduce `--max-model-len` |
| `huggingface-cli` deprecated | Use `hf` command instead |
| Pod can't write to PVC | Add `securityContext.fsGroup: 0` to the pod spec |
| DataScienceCluster not ready | Check: `oc get dsc default-dsc -o jsonpath='{.status.conditions}'` |
