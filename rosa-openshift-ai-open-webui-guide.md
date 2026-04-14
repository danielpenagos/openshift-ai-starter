# Deploy OpenShift AI + Open WebUI on ROSA

End-to-end guide to deploy a production-ready AI chatbot on an **existing ROSA cluster**, using **OpenShift AI** for model serving (vLLM) and **Open WebUI** as the frontend.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Create a GPU Machine Pool](#2-create-a-gpu-machine-pool)
3. [Install the Node Feature Discovery (NFD) Operator](#3-install-the-node-feature-discovery-nfd-operator)
4. [Install the NVIDIA GPU Operator](#4-install-the-nvidia-gpu-operator)
5. [Install the OpenShift Serverless Operator](#5-install-the-openshift-serverless-operator)
6. [Install the OpenShift Service Mesh Operator](#6-install-the-openshift-service-mesh-operator)
7. [Install the OpenShift AI Operator](#7-install-the-openshift-ai-operator)
8. [Create the DataScienceCluster](#8-create-the-datasciencecluster)
9. [Deploy MinIO for Model Storage](#9-deploy-minio-for-model-storage)
10. [Deploy a Model with vLLM](#10-deploy-a-model-with-vllm)
11. [Install Open WebUI](#11-install-open-webui)
12. [Using Open WebUI](#12-using-open-webui)

---

## 1. Prerequisites

- A running **ROSA** cluster (HCP or Classic)
- `rosa`, `oc`, and `helm` CLIs installed and authenticated
- `cluster-admin` privileges
- **AWS GPU quota** — request "Running On-Demand G and VT instances" in your region (minimum 4 vCPUs for `g4dn.xlarge`)

---

## 2. Create a GPU Machine Pool

The cheapest GPU instance on AWS is **g4dn.xlarge**:

| Spec | Value |
|---|---|
| GPU | 1x NVIDIA T4 (16 GB VRAM) |
| vCPUs | 4 |
| RAM | 16 GiB |
| On-Demand Price | ~$0.526/hour (~$378/month) |

> **Note:** For better inference performance (24 GB VRAM), consider `g5.xlarge` at ~$1.006/hour.

### Create the machine pool

```bash
rosa create machinepool --cluster=$ROSA_CLUSTER_NAME \
  --name=gpu-pool \
  --replicas=1 \
  --instance-type=g4dn.xlarge \
  --labels='nvidia.com/gpu=true' \
  --taints='nvidia.com/gpu=:NoSchedule'
```

The taint ensures only GPU workloads (which tolerate this taint) are scheduled on these expensive nodes.

### Verify the node joins the cluster

```bash
oc get nodes -l nvidia.com/gpu=true
```

Wait until the node shows `Ready`.

> **Autoscaling alternative:** If you want the GPU node to scale down when idle:
> ```bash
> rosa create machinepool --cluster=<CLUSTER_NAME> \
>   --name=gpu-pool \
>   --instance-type=g4dn.xlarge \
>   --enable-autoscaling \
>   --min-replicas=0 \
>   --max-replicas=2 \
>   --labels='nvidia.com/gpu=true' \
>   --taints='nvidia.com/gpu=:NoSchedule'
> ```

---

## 3. Install the Node Feature Discovery (NFD) Operator

NFD detects hardware features (GPUs) on nodes and labels them accordingly.

### 3.1. Create the namespace, OperatorGroup, and Subscription

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-nfd
  labels:
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: nfd
  namespace: openshift-nfd
spec:
  targetNamespaces:
    - openshift-nfd
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: nfd
  namespace: openshift-nfd
spec:
  channel: stable
  installPlanApproval: Automatic
  name: nfd
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

### 3.2. Wait for the operator to be ready

```bash
oc get csv -n openshift-nfd -w
```

Wait until `PHASE` shows `Succeeded`.

### 3.3. Create the NodeFeatureDiscovery instance

```bash
cat <<'EOF' | oc apply -f -
apiVersion: nfd.openshift.io/v1
kind: NodeFeatureDiscovery
metadata:
  name: nfd-instance
  namespace: openshift-nfd
spec:
  operand:
    servicePort: 12000
  workerConfig:
    configData: |
      sources:
        pci:
          deviceClassWhitelist:
            - "0300"
            - "0302"
          deviceLabelFields:
            - vendor
EOF
```

### 3.4. Verify GPU detection

After a few minutes, your GPU node should have PCI labels:

```bash
oc get node -l nvidia.com/gpu=true -o json | jq '.items[].metadata.labels | with_entries(select(.key | startswith("feature.node.kubernetes.io/pci-10de")))'
```

You should see `feature.node.kubernetes.io/pci-10de.present: "true"` (10de = NVIDIA vendor ID).

---

## 4. Install the NVIDIA GPU Operator

The GPU Operator installs GPU drivers, the device plugin, and monitoring on labeled nodes.

### 4.1. Create the namespace, OperatorGroup, and Subscription

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: nvidia-gpu-operator
  labels:
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: gpu-operator-certified
  namespace: nvidia-gpu-operator
spec:
  targetNamespaces:
    - nvidia-gpu-operator
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: gpu-operator-certified
  namespace: nvidia-gpu-operator
spec:
  channel: stable
  installPlanApproval: Automatic
  name: gpu-operator-certified
  source: certified-operators
  sourceNamespace: openshift-marketplace
EOF
```

### 4.2. Wait for the operator to be ready

```bash
oc get csv -n nvidia-gpu-operator -w
```

### 4.3. Create the ClusterPolicy

```bash
cat <<'EOF' | oc apply -f -
apiVersion: nvidia.com/v1
kind: ClusterPolicy
metadata:
  name: gpu-cluster-policy
spec:
  operator:
    runtimeClass: nvidia
    initContainer: {}
    use_ocp_driver_toolkit: true
  daemonsets: {}
  driver:
    enabled: true
    useNvidiaDriverCRD: false
    upgradePolicy:
      autoUpgrade: true
      drain:
        deleteEmptyDir: false
        enable: false
        force: false
        timeoutSeconds: 300
      maxParallelUpgrades: 1
      podDeletion:
        deleteEmptyDir: false
        force: false
        timeoutSeconds: 300
      waitForCompletion:
        timeoutSeconds: 0
    manager: {}
    rdma:
      enabled: false
    repoConfig:
      configMapName: ""
    certConfig:
      name: ""
    licensingConfig:
      secretName: ""
      nlsEnabled: true
    virtualTopology:
      config: ""
    kernelModuleConfig:
      name: ""
  toolkit:
    enabled: true
  devicePlugin:
    enabled: true
    config:
      name: ""
      default: ""
  dcgm:
    enabled: true
  dcgmExporter:
    enabled: true
    config:
      name: ""
  gfd:
    enabled: true
  migManager:
    enabled: true
    config:
      name: ""
    gpuClientsConfig:
      name: ""
  nodeStatusExporter:
    enabled: false
  validator:
    plugin: {}
  sandboxWorkloads:
    enabled: false
    defaultWorkload: container
  mig:
    strategy: single
  gds:
    enabled: false
  vgpuManager:
    enabled: false
    kernelModuleConfig:
      name: ""
  vgpuDeviceManager:
    enabled: true
    config:
      name: ""
      default: default
  vfioManager:
    enabled: true
  sandboxDevicePlugin:
    enabled: true
  kataManager:
    enabled: false
    config: {}
  psp:
    enabled: false
  cdi: {}
EOF
```

### 4.4. Verify the GPU is allocatable

Wait a few minutes for the driver and device plugin pods to come up:

```bash
oc get pods -n nvidia-gpu-operator -w
```

Then confirm the GPU appears as an allocatable resource on the node:

```bash
oc describe node -l nvidia.com/gpu=true | grep -A7 "Allocatable:" | grep nvidia
```

Expected output: `nvidia.com/gpu: 1`

---

## 5. Install the OpenShift Serverless Operator

KServe requires Knative Serving for serverless model inference (scale-to-zero, autoscaling). The OpenShift Serverless operator provides this.

### 5.1. Create the Subscription

The Serverless operator installs into `openshift-serverless` and is AllNamespaces-scoped, so no custom OperatorGroup is needed.

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-serverless
  labels:
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: serverless-operator-group
  namespace: openshift-serverless
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: serverless-operator
  namespace: openshift-serverless
spec:
  channel: stable
  installPlanApproval: Automatic
  name: serverless-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

### 5.2. Wait for the operator to be ready

```bash
oc get csv -n openshift-serverless -w
```

Wait until `PHASE` shows `Succeeded`.

### 5.3. Create the KnativeServing instance

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: knative-serving
---
apiVersion: operator.knative.dev/v1beta1
kind: KnativeServing
metadata:
  name: knative-serving
  namespace: knative-serving
spec:
  workloadOverrides:
    - name: net-istio-controller
      env:
        - container: controller
          envVars:
            - name: ENABLE_SECRET_INFORMER_FILTERING_BY_CERT_UID
              value: "true"
    - name: net-istio-webhook
      env:
        - container: webhook
          envVars:
            - name: ENABLE_SECRET_INFORMER_FILTERING_BY_CERT_UID
              value: "true"
EOF
```

### 5.4. Verify Knative Serving is ready

```bash
oc get pods -n knative-serving
oc get knativeserving knative-serving -n knative-serving
```

Wait until all pods are `Running` and the KnativeServing resource shows `Ready`.

---

## 6. Install the OpenShift Service Mesh Operator

KServe requires OpenShift Service Mesh (Istio) to manage ingress and networking for model serving endpoints.

### 6.1. Install the operator

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-operators
  labels:
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: servicemeshoperator
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: servicemeshoperator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

> **Note:** The Service Mesh operator installs into `openshift-operators` which already has an AllNamespaces OperatorGroup, so no custom OperatorGroup is needed.

### 6.2. Wait for the operator to be ready

```bash
oc get csv -n openshift-operators -w | grep servicemesh
```

Wait until `PHASE` shows `Succeeded`.

> **Note:** You do **not** need to create a ServiceMeshControlPlane manually — OpenShift AI manages the mesh configuration automatically when the DataScienceCluster is created.

---

## 7. Install the OpenShift AI Operator

### 7.1. Create the namespace, OperatorGroup, and Subscription

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: redhat-ods-operator
  labels:
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: rhods-operator-group
  namespace: redhat-ods-operator
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  channel: fast
  installPlanApproval: Automatic
  name: rhods-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

> **Note:** The OperatorGroup has no `targetNamespaces`, making it AllNamespaces-scoped (required for OpenShift AI). Use channel `stable-2.25` instead of `fast` if you need a pinned version.

### 7.2. Wait for the operator to be ready

```bash
oc get csv -n redhat-ods-operator -w
```

Wait until `PHASE` shows `Succeeded`.

---

## 8. Create the DataScienceCluster

This enables KServe (for vLLM model serving), the dashboard, and other components:

```bash
cat <<'EOF' | oc apply -f -
apiVersion: datasciencecluster.opendatahub.io/v1
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    dashboard:
      managementState: Managed
    workbenches:
      managementState: Managed
    modelmeshserving:
      managementState: Managed
    datasciencepipelines:
      managementState: Managed
    kserve:
      managementState: Managed
      serving:
        ingressGateway:
          certificate:
            type: SelfSigned
        managementState: Managed
        name: knative-serving
    ray:
      managementState: Managed
    trustyai:
      managementState: Removed
    kueue:
      managementState: Removed
    modelregistry:
      managementState: Managed
      registriesNamespace: odh-model-registries
EOF
```

### Verify

```bash
oc get datasciencecluster default-dsc
oc get pods -n redhat-ods-applications
oc get pods -n knative-serving
```

All pods should reach `Running` state.

---

## 9. Deploy MinIO for Model Storage

MinIO provides S3-compatible object storage running inside the cluster, used to store model weights for vLLM.

> **Alternative: AWS S3** — If you prefer to use an external S3 bucket instead of MinIO, skip this section and go directly to [Section 10](#10-deploy-a-model-with-vllm). When configuring the storage credentials in step 10.2, use the [AWS S3 alternative](#alternative-aws-s3-credentials) instead.

### 9.1. Create the MinIO namespace

```bash
oc new-project minio
```

### 9.2. Deploy MinIO

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-storage
  namespace: minio
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
---
apiVersion: v1
kind: Secret
metadata:
  name: minio-credentials
  namespace: minio
type: Opaque
stringData:
  MINIO_ROOT_USER: minioadmin
  MINIO_ROOT_PASSWORD: minioadmin123
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: minio
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
        - name: minio
          image: quay.io/minio/minio:latest
          args:
            - server
            - /data
            - --console-address
            - ":9001"
          envFrom:
            - secretRef:
                name: minio-credentials
          ports:
            - containerPort: 9000
              name: api
            - containerPort: 9001
              name: console
          volumeMounts:
            - name: data
              mountPath: /data
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: "1"
              memory: 1Gi
          readinessProbe:
            httpGet:
              path: /minio/health/ready
              port: 9000
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /minio/health/live
              port: 9000
            initialDelaySeconds: 10
            periodSeconds: 10
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: minio-storage
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: minio
spec:
  selector:
    app: minio
  ports:
    - name: api
      port: 9000
      targetPort: 9000
    - name: console
      port: 9001
      targetPort: 9001
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: minio-console
  namespace: minio
spec:
  to:
    kind: Service
    name: minio
    weight: 100
  port:
    targetPort: console
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF
```

### 9.3. Wait for MinIO to be ready

```bash
oc get pods -n minio -w
```

Wait until the pod shows `Running` and `1/1` ready.

### 9.4. Create the models bucket and upload model weights

This step downloads the model from HuggingFace and uploads it to MinIO. The recommended approach runs everything inside the cluster, avoiding large downloads to your laptop.

#### Create the models bucket

First, create the bucket using a one-off MinIO Client pod:

```bash
oc run mc-create-bucket --rm -it --restart=Never -n minio \
  --image=quay.io/minio/mc:latest \
  --command -- mc mb minio/models \
  --insecure \
  && mc alias set minio http://minio.minio.svc.cluster.local:9000 minioadmin minioadmin123
```

Or more reliably, run it in two steps:

```bash
oc run mc-setup --rm -it --restart=Never -n minio \
  --image=quay.io/minio/mc:latest \
  -- /bin/sh -c '
    mc alias set minio http://minio.minio.svc.cluster.local:9000 minioadmin minioadmin123 &&
    mc mb --ignore-existing minio/models &&
    echo "Bucket created successfully" &&
    mc ls minio/
  '
```

#### Download model and upload to MinIO from within the cluster

Deploy a pod that downloads the model from HuggingFace and copies it directly to MinIO, keeping all traffic inside the cluster:

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-download
  namespace: minio
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: model-uploader
  namespace: minio
spec:
  restartPolicy: Never
  securityContext:
    fsGroup: 0
  containers:
    - name: uploader
      image: python:3.11-slim
      env:
        - name: HOME
          value: /tmp
        - name: HF_HOME
          value: /tmp/.cache/huggingface
      command:
        - /bin/bash
        - -c
        - |
          set -e
          echo "=== Installing dependencies ==="
          pip install --no-cache-dir huggingface_hub[hf_xet] -t /tmp/pip-packages
          export PYTHONPATH=/tmp/pip-packages:$PYTHONPATH
          export PATH=/tmp/pip-packages/bin:$PATH

          echo "=== Installing MinIO client ==="
          python -c "import urllib.request; urllib.request.urlretrieve('https://dl.min.io/client/mc/release/linux-amd64/mc', '/tmp/mc')"
          chmod +x /tmp/mc

          echo "=== Downloading model from HuggingFace ==="
          hf download TheBloke/Mistral-7B-Instruct-v0.2-AWQ --local-dir /models/mistral-7b-awq

          echo "=== Configuring MinIO client ==="
          /tmp/mc alias set minio http://minio.minio.svc.cluster.local:9000 minioadmin minioadmin123

          echo "=== Uploading model to MinIO ==="
          /tmp/mc cp --recursive /models/mistral-7b-awq/ minio/models/mistral-7b-instruct-awq/

          echo "=== Verifying upload ==="
          /tmp/mc ls minio/models/mistral-7b-instruct-awq/

          echo "=== Done! ==="
      volumeMounts:
        - name: model-storage
          mountPath: /models
      resources:
        requests:
          cpu: "1"
          memory: 2Gi
        limits:
          cpu: "2"
          memory: 4Gi
  volumes:
    - name: model-storage
      persistentVolumeClaim:
        claimName: model-download
EOF
```

Follow the progress:

```bash
oc logs -f model-uploader -n minio
```

Wait until you see `=== Done! ===`. Then clean up the pod and PVC:

```bash
oc delete pod model-uploader -n minio
oc delete pvc model-download -n minio
```

> **Note:** The AWQ-quantized model uses ~4GB VRAM, fitting easily on the T4's 16GB with room for large context lengths. For full-precision (float16) models, use a `g5.xlarge` instance (24GB VRAM).

#### Alternative: Upload from your laptop

If you prefer to download to your local machine and upload from there:

```bash
# Install mc if you don't have it
# macOS:  brew install minio/stable/mc
# Linux:  curl -O https://dl.min.io/client/mc/release/linux-amd64/mc && chmod +x mc && sudo mv mc /usr/local/bin/

# Port-forward the MinIO API
oc port-forward svc/minio 9000:9000 -n minio &

# Configure mc to connect to MinIO
mc alias set minio-local http://localhost:9000 minioadmin minioadmin123

# Create the models bucket
mc mb minio-local/models

# Download the model from HuggingFace
pip install huggingface_hub[cli]
hf download TheBloke/Mistral-7B-Instruct-v0.2-AWQ --local-dir ./mistral-7b-awq

# Upload model weights to MinIO
mc cp --recursive ./mistral-7b-awq minio-local/models/mistral-7b-instruct-awq/
```

### 9.5. Verify the upload

Use the MinIO Console (see [step 9.6](#96-verify-the-upload-via-the-minio-console)) or verify via CLI:

```bash
# From within the cluster
oc run mc-verify --rm -it --restart=Never -n minio \
  --image=quay.io/minio/mc:latest \
  -- /bin/sh -c '
    mc alias set minio http://minio.minio.svc.cluster.local:9000 minioadmin minioadmin123 &&
    mc ls minio/models/mistral-7b-instruct-awq/
  '

# Or from your laptop (requires port-forward)
mc ls minio-local/models/mistral-7b-instruct-awq/
```

### 9.6. Verify the upload via the MinIO Console

MinIO includes a built-in web console for browsing buckets, uploading/downloading files, and managing storage.

1. Get the console URL:

   ```bash
   oc get route minio-console -n minio -o jsonpath='https://{.spec.host}{"\n"}'
   ```

2. Open the URL in your browser.

3. Log in with:
   - **Username:** `minioadmin`
   - **Password:** `minioadmin123`

4. In the left sidebar, click **Object Browser**.

5. Click the **models** bucket to browse its contents.

6. Navigate into `mistral-7b-instruct-awq/` to verify all model files were uploaded (you should see files like `config.json`, `tokenizer.json`, and the `.safetensors` weight files).

> **Tip:** You can also use the console to upload additional files, create new buckets, or delete objects without needing the `mc` CLI.

---

## 10. Deploy a Model with vLLM

### 10.1. Create a project for model serving

```bash
oc new-project llm-serving
```

### 10.2. Create storage credentials and ServiceAccount

These credentials point to the **in-cluster MinIO** deployed in [Section 9](#9-deploy-minio-for-model-storage):

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: models-bucket-secret
  namespace: llm-serving
  annotations:
    serving.kserve.io/s3-endpoint: minio.minio.svc.cluster.local:9000
    serving.kserve.io/s3-usehttps: "0"
    serving.kserve.io/s3-region: us-east-1
    serving.kserve.io/s3-verifyssl: "0"
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: minioadmin
  AWS_SECRET_ACCESS_KEY: minioadmin123
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: models-bucket-sa
  namespace: llm-serving
secrets:
  - name: models-bucket-secret
EOF
```

#### Alternative: AWS S3 credentials

If you are using an AWS S3 bucket instead of MinIO, use this secret instead:

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: models-bucket-secret
  namespace: llm-serving
  annotations:
    serving.kserve.io/s3-endpoint: s3.amazonaws.com
    serving.kserve.io/s3-usehttps: "1"
    serving.kserve.io/s3-region: <YOUR_REGION>
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "<YOUR_ACCESS_KEY>"
  AWS_SECRET_ACCESS_KEY: "<YOUR_SECRET_KEY>"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: models-bucket-sa
  namespace: llm-serving
secrets:
  - name: models-bucket-secret
EOF
```

Then upload your model to S3 before proceeding:

```bash
aws s3 sync ./mistral-7b-awq s3://<YOUR_BUCKET>/mistral-7b-instruct-awq/
```

### 10.3. Create the vLLM ServingRuntime

```bash
cat <<'EOF' | oc apply -f -
apiVersion: serving.kserve.io/v1alpha1
kind: ServingRuntime
metadata:
  name: vllm-runtime
  namespace: llm-serving
  labels:
    opendatahub.io/dashboard: "true"
  annotations:
    openshift.io/display-name: "vLLM ServingRuntime for KServe"
spec:
  builtInAdapter:
    modelLoadingTimeoutMillis: 90000
  containers:
    - name: kserve-container
      image: docker.io/vllm/vllm-openai:v0.8.5.post1
      command:
        - python3
        - -m
        - vllm.entrypoints.openai.api_server
      args:
        - --model
        - /mnt/models/
        - --served-model-name
        - mistral-7b-instruct
        - --port
        - "8080"
        - --max-model-len
        - "8192"
        - --dtype
        - half
        - --quantization
        - awq
        - --trust-remote-code
        - --gpu-memory-utilization
        - "0.9"
      env:
        - name: HOME
          value: /tmp
      ports:
        - containerPort: 8080
          name: http1
          protocol: TCP
      resources:
        limits:
          nvidia.com/gpu: "1"
        requests:
          cpu: "2"
          memory: 8Gi
          nvidia.com/gpu: "1"
  multiModel: false
  supportedModelFormats:
    - autoSelect: true
      name: pytorch
EOF
```

### 10.4. Create the InferenceService

The `storageUri` below points to the MinIO bucket. If using AWS S3, replace it with `s3://<YOUR_BUCKET>/mistral-7b-instruct-awq`.

```bash
cat <<'EOF' | oc apply -f -
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: mistral-7b-instruct
  namespace: llm-serving
  annotations:
    serving.knative.openshift.io/enablePassthrough: "true"
    sidecar.istio.io/inject: "true"
    serving.kserve.io/deploymentMode: RawDeployment
  labels:
    opendatahub.io/dashboard: "true"
spec:
  predictor:
    tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
    model:
      modelFormat:
        name: pytorch
      runtime: vllm-runtime
      storageUri: s3://models/mistral-7b-instruct-awq
      resources:
        limits:
          nvidia.com/gpu: "1"
        requests:
          cpu: "2"
          memory: 8Gi
          nvidia.com/gpu: "1"
    serviceAccountName: models-bucket-sa
    minReplicas: 1
    maxReplicas: 1
EOF
```

### 10.5. Wait for the model to be ready

```bash
oc get inferenceservice mistral-7b-instruct -n llm-serving -w
```

Wait until `READY` shows `True`. This can take several minutes as the model weights are downloaded from MinIO.

### 10.6. Get the model endpoint URL

```bash
# External URL (via Route/Knative)
export MODEL_ENDPOINT=$(oc get inferenceservice mistral-7b-instruct -n llm-serving \
  -o jsonpath='{.status.url}')
echo $MODEL_ENDPOINT

# Internal URL (for cluster-internal access from Open WebUI)
# Format: http://<service-name>.<namespace>.svc.cluster.local:8080
```

### 10.7. Test the endpoint

Run a curl pod inside the cluster to test the internal service URL:

```bash
oc run curl-test --rm -it --restart=Never -n llm-serving \
  --image=curlimages/curl -- \
  curl -s http://mistral-7b-instruct-predictor.llm-serving.svc.cluster.local:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-7b-instruct",
    "messages": [
      {"role": "user", "content": "What is OpenShift in 2 sentences?"}
    ],
    "max_tokens": 256,
    "temperature": 0.7
  }'
```

> **Note:** The model name in the request must match the `--model` argument from the ServingRuntime (`/mnt/models/`). You can also check which models are available:
> ```bash
oc run curl-models --rm -it --restart=Never -n llm-serving \
  --image=curlimages/curl -- \
  curl -s http://mistral-7b-instruct-predictor.llm-serving.svc.cluster.local:8080/v1/models
> ```

---

## 11. Install Open WebUI

Open WebUI is the most mature open-source chat frontend, with explicit OpenShift Helm support, RAG, RBAC, and multi-model conversations.

### 11.1. Add the Helm repository

```bash
helm repo add open-webui https://helm.openwebui.com/
helm repo update
```

### 11.2. Create the values file

Create a file named `open-webui-values.yaml`:

```yaml
cat > open-webui-values.yaml<< EOF
replicaCount: 1

# -- Disable bundled Ollama (we use vLLM instead) --
ollama:
  enabled: false

# -- Disable bundled Pipelines (optional) --
pipelines:
  enabled: false

# -- OpenAI-compatible API (pointing to vLLM / KServe) --
openaiBaseApiUrl: "http://mistral-7b-instruct-predictor.llm-serving.svc.cluster.local:8080/v1"
openaiApiKey: "none"

# -- Service --
service:
  type: ClusterIP
  port: 80
  containerPort: 8080

# -- Ingress: disabled — we use an OpenShift Route --
ingress:
  enabled: false

# -- Security Contexts (compatible with OpenShift restricted-v2 SCC) --
podSecurityContext: {}
containerSecurityContext:
  allowPrivilegeEscalation: false
  runAsNonRoot: true
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault

# -- Persistence --
persistence:
  enabled: true
  size: 5Gi
  accessModes:
    - ReadWriteOnce
  storageClass: ""   # leave empty for cluster default (e.g., gp3-csi on ROSA)

# -- Disable Redis (not needed for single-replica, avoids permission issues on OpenShift) --
websocket:
  enabled: false
redis:
  enabled: false

# -- Extra environment variables --
extraEnvVars:
  - name: WEBUI_SECRET_KEY
    value: "change-me-to-a-random-string"
  - name: WEBUI_NAME
    value: "AI Chat"
  - name: ENABLE_RAG_HYBRID_SEARCH
    value: "true"

# -- Resources --
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: "2"
    memory: 2Gi
EOF
```

> **Important:** The `openaiBaseApiUrl` uses the **cluster-internal** service URL. Adjust it to match your InferenceService name and namespace. If you have multiple model endpoints, use `openaiBaseApiUrls` (list) instead.

### 11.3. Install the chart

```bash
oc new-project open-webui

helm install open-webui open-webui/open-webui \
  --namespace open-webui \
  -f open-webui-values.yaml
```

### 11.4. Wait for pods to be ready

```bash
oc get pods -n open-webui -w
```

### 11.5. Create an OpenShift Route

```bash
cat <<'EOF' | oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: open-webui
  namespace: open-webui
spec:
  to:
    kind: Service
    name: open-webui
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
EOF
```

### 11.6. Get the URL

```bash
oc get route open-webui -n open-webui -o jsonpath='https://{.spec.host}{"\n"}'
```

---

## 12. Using Open WebUI

### 12.1. First Login (Admin Setup)

1. Open the Route URL in your browser.
2. Click **Sign Up** to create the first account.
3. **The first user automatically becomes the admin.** Choose a strong password.
4. To disable public registration after your team is set up: go to **Admin Settings > General** and toggle off user sign-up.

### 12.2. Verify Model Connection

1. After logging in, look at the **model selector dropdown** at the top of the chat screen.
2. Your vLLM model(s) should appear automatically (discovered via `/v1/models`).
3. If no models appear:
   - Go to **Admin Settings** (gear icon) > **Connections** > **OpenAI**.
   - Click **Manage** and verify the API URL and key.
   - Click **Refresh** to re-discover models.

### 12.3. Starting a Conversation

1. Select a model from the dropdown.
2. Type your message in the input field and press **Enter**.
3. You can **switch models mid-conversation** without losing context.
4. Use the sidebar to browse and search previous conversations.

### 12.4. Using RAG (Upload Documents)

Open WebUI supports document-based Q&A out of the box:

1. **Upload a file in chat:** Click the **paperclip icon** in the chat input bar. Upload PDFs, text files, spreadsheets, or code. The content is chunked, embedded, and used as context for the conversation.
2. **Create a Knowledge Base:**
   - Go to **Workspace > Knowledge**.
   - Click **+ New Knowledge** and give it a name.
   - Upload documents to the knowledge base.
3. **Reference knowledge in chat:** Type `#` in the chat input to see available knowledge bases, then select one to attach as context.
4. **Bind knowledge to a model:** Go to **Workspace > Models > Edit** and attach a knowledge base so it is always available to that model.

### 12.5. Admin Features

As admin, you have access to:

| Feature | Where |
|---|---|
| Manage users and roles | Admin Settings > Users |
| Add more model endpoints | Admin Settings > Connections > OpenAI > Manage |
| Configure web search | Admin Settings > Web Search |
| View analytics | Admin Settings > Dashboard |
| Set default model | Admin Settings > Interface |
| Rate limiting / moderation | Admin Settings > General |

### 12.6. Adding More Models

To serve additional models, create new InferenceService resources in the `llm-serving` namespace (repeat [Section 10](#10-deploy-a-model-with-vllm) with a different model). Upload the new model weights to MinIO (or S3) and create a new InferenceService. Open WebUI will auto-discover them.

Alternatively, add additional OpenAI-compatible endpoints in **Admin Settings > Connections > OpenAI > Manage > + Add New Connection**.

---

## Quick Reference

| Component | Namespace | Key Resource |
|---|---|---|
| NFD Operator | `openshift-nfd` | `NodeFeatureDiscovery/nfd-instance` |
| GPU Operator | `nvidia-gpu-operator` | `ClusterPolicy/gpu-cluster-policy` |
| Serverless Operator | `openshift-serverless` | `KnativeServing/knative-serving` |
| Service Mesh Operator | `openshift-operators` | `Subscription/servicemeshoperator` |
| OpenShift AI Operator | `redhat-ods-operator` | `Subscription/rhods-operator` |
| DataScienceCluster | (cluster-scoped) | `DataScienceCluster/default-dsc` |
| MinIO | `minio` | `Deployment/minio`, `Route/minio-console` |
| Model Serving | `llm-serving` | `InferenceService/mistral-7b-instruct` |
| Open WebUI | `open-webui` | `Route/open-webui` |
| GPU Machine Pool | (ROSA) | `gpu-pool` (`g4dn.xlarge`) |
