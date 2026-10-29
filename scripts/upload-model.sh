#!/bin/bash
set -euo pipefail

# Upload a HuggingFace model to MinIO running on the OpenShift cluster.
# This script creates a pod inside the cluster that downloads the model
# from HuggingFace and uploads it directly to MinIO.
#
# Usage:
#   ./scripts/upload-model.sh  <HF_MODEL_ID> <HF_TOKEN> <MINIO_PATH>
#
# Examples:
#   ./scripts/upload-model.sh TheBloke/Mistral-7B-Instruct-v0.2-AWQ mistral-7b-instruct-awq hf_123456 
#   ./scripts/upload-model.sh TheBloke/Llama-2-7B-Chat-AWQ llama-2-7b-chat-awq hf_123456 

HF_MODEL="${1:?Usage: $0 <HF_MODEL_ID> <HF_TOKEN> <MINIO_PATH>}"
MINIO_PATH="${2:?Usage: $0 <HF_MODEL_ID> <HF_TOKEN> <MINIO_PATH>}"
HF_TOKEN="${3:?Usage: $0 <HF_MODEL_ID> <HF_TOKEN> <MINIO_PATH>}"
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

# Encode the upload script as base64 so it can be embedded safely in YAML
UPLOAD_PY_B64=$(base64 -w0 << 'PYEOF'
import os, glob
from minio import Minio

client = Minio(os.environ["MINIO_HOST"], access_key="minioadmin", secret_key="minioadmin123", secure=False)
bucket = "models"
if not client.bucket_exists(bucket):
    client.make_bucket(bucket)
    print("Created bucket:", bucket)

local_dir = "/models/download"
dest = os.environ["MINIO_DEST"]
files = sorted(p for p in glob.glob(local_dir + "/**/*", recursive=True) if os.path.isfile(p))
for local_path in files:
    obj = dest + "/" + os.path.relpath(local_path, local_dir)
    print("  uploading", obj)
    client.fput_object(bucket, obj, local_path)

print("=== Verifying upload ===")
for o in client.list_objects(bucket, prefix=dest + "/", recursive=True):
    print(" ", o.object_name)
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
        - name: MINIO_HOST
          value: "minio.${NAMESPACE}.svc.cluster.local:9000"
        - name: MINIO_DEST
          value: "${MINIO_PATH}"
        - name: UPLOAD_PY_B64
          value: "${UPLOAD_PY_B64}"
      command:
        - /bin/bash
        - -c
        - |
          set -e
          echo "=== Installing dependencies ==="
          pip install --no-cache-dir "huggingface_hub[hf_xet]" minio -t /tmp/pip-packages
          export PYTHONPATH=/tmp/pip-packages:\$PYTHONPATH
          export PATH=/tmp/pip-packages/bin:\$PATH

          echo "=== Downloading model from HuggingFace ==="
          python3 -c "
import os, sys
sys.path.insert(0, '/tmp/pip-packages')
from huggingface_hub import snapshot_download
snapshot_download(repo_id='${HF_MODEL}', local_dir='/models/download', token=os.environ['HF_TOKEN'])
print('Download complete.')
"

          echo "=== Uploading model to MinIO ==="
          echo "\$UPLOAD_PY_B64" | base64 -d > /tmp/upload.py
          python3 /tmp/upload.py

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
