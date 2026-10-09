#!/bin/bash
set -euo pipefail

# Upload a HuggingFace model to MinIO running on the OpenShift cluster.
# This script creates a pod inside the cluster that downloads the model
# from HuggingFace and uploads it directly to MinIO.
#
# Usage:
#   ./scripts/upload-model.sh  <HF_MODEL_ID> <MINIO_PATH> <HF_TOKEN>
#
# Examples:
#   ./scripts/upload-model.sh TheBloke/Mistral-7B-Instruct-v0.2-AWQ mistral-7b-instruct-awq hf_123456
#   ./scripts/upload-model.sh TheBloke/Llama-2-7B-Chat-AWQ llama-2-7b-chat-awq hf_123456

HF_MODEL="${1:?Usage: $0 <HF_MODEL_ID> <MINIO_PATH> <HF_TOKEN>}"
MINIO_PATH="${2:?Usage: $0 <HF_MODEL_ID> <MINIO_PATH> <HF_TOKEN>}"
HF_TOKEN="${3:?Usage: $0 <HF_MODEL_ID> <MINIO_PATH> <HF_TOKEN>}"
NAMESPACE="${MINIO_NAMESPACE:-minio}"
PVC_SIZE="${PVC_SIZE:-30Gi}"

echo "==> Using Token: ${HF_TOKEN}"
echo "==> Uploading model: ${HF_MODEL}"
echo "==> MinIO path: models/${MINIO_PATH}"
echo "==> Namespace: ${NAMESPACE}"

# Clean up any previous run
kubectl delete pod model-uploader -n "${NAMESPACE}" --ignore-not-found
kubectl delete pvc model-download -n "${NAMESPACE}" --ignore-not-found

# Create a ServiceAccount with anyuid SCC for PVC write access
kubectl create serviceaccount model-uploader-sa -n "${NAMESPACE}" 2>/dev/null || true
oc adm policy add-scc-to-user anyuid -z model-uploader-sa -n "${NAMESPACE}" 2>/dev/null || true

# Build and base64-encode the Python upload script (namespace/path substituted here on the host)
UPLOAD_PY_B64=$(cat <<PYEOF | base64 | tr -d '\n'
from pathlib import Path
from minio import Minio

client = Minio(
    "minio.${NAMESPACE}.svc.cluster.local:9000",
    access_key="minioadmin",
    secret_key="minioadmin123",
    secure=False,
)

bucket = "models"
if not client.bucket_exists(bucket):
    client.make_bucket(bucket)
    print("Created bucket: " + bucket)

local_dir = Path("/models/download")
prefix = "${MINIO_PATH}"
files = [p for p in local_dir.rglob("*") if p.is_file()]
total = len(files)
print("Uploading " + str(total) + " files to minio/" + bucket + "/" + prefix + "/")

for i, path in enumerate(files, 1):
    object_name = prefix + "/" + str(path.relative_to(local_dir))
    client.fput_object(bucket, object_name, str(path))
    print("[" + str(i) + "/" + str(total) + "] " + object_name)

objects = list(client.list_objects(bucket, prefix=prefix + "/", recursive=True))
print("Done. Found " + str(len(objects)) + " objects in minio/" + bucket + "/" + prefix + "/")
PYEOF
)

# Create PVC and uploader pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-download
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${PVC_SIZE}
---
apiVersion: v1
kind: Pod
metadata:
  name: model-uploader
  namespace: ${NAMESPACE}
spec:
  serviceAccountName: model-uploader-sa
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
        - name: HF_TOKEN
          value: "${HF_TOKEN}"
      command:
        - /bin/bash
        - -c
        - |
          set -e
          echo "=== Installing dependencies ==="
          pip install --no-cache-dir huggingface_hub[hf_xet] minio -t /tmp/pip-packages
          export PYTHONPATH=/tmp/pip-packages:\$PYTHONPATH
          export PATH=/tmp/pip-packages/bin:\$PATH

          echo "=== Downloading model from HuggingFace ==="
          hf download ${HF_MODEL} --local-dir /models/download

          echo "=== Uploading model to MinIO ==="
          echo "${UPLOAD_PY_B64}" | base64 -d > /tmp/upload.py
          python /tmp/upload.py

          echo "=== Done! ==="
      volumeMounts:
        - name: model-storage
          mountPath: /models
      resources:
        requests:
          cpu: 250m
          memory: 1Gi
        limits:
          cpu: "2"
          memory: 4Gi
  volumes:
    - name: model-storage
      persistentVolumeClaim:
        claimName: model-download
EOF

echo "==> Waiting for pod to start..."
kubectl wait --for=condition=Ready pod/model-uploader -n "${NAMESPACE}" --timeout=300s 2>/dev/null || true

echo "==> Following logs (Ctrl+C to detach, pod will continue)..."
kubectl logs -f model-uploader -n "${NAMESPACE}" || true

echo "==> Waiting for pod to complete..."
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/model-uploader -n "${NAMESPACE}" --timeout=3600s \
  || { echo "ERROR: Pod did not complete successfully."; kubectl logs --tail=30 model-uploader -n "${NAMESPACE}" 2>/dev/null; exit 1; }

echo ""
echo "==> Cleaning up..."
kubectl delete pod model-uploader -n "${NAMESPACE}" --ignore-not-found
kubectl delete pvc model-download -n "${NAMESPACE}" --ignore-not-found
oc adm policy remove-scc-from-user anyuid -z model-uploader-sa -n "${NAMESPACE}" 2>/dev/null || true
kubectl delete serviceaccount model-uploader-sa -n "${NAMESPACE}" --ignore-not-found
echo "==> Done!"
