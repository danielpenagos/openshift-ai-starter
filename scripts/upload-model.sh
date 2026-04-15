#!/bin/bash
set -euo pipefail

# Upload a HuggingFace model to MinIO running on the OpenShift cluster.
# This script creates a pod inside the cluster that downloads the model
# from HuggingFace and uploads it directly to MinIO.
#
# Usage:
#   ./scripts/upload-model.sh <HF_MODEL_ID> <MINIO_PATH>
#
# Examples:
#   ./scripts/upload-model.sh TheBloke/Mistral-7B-Instruct-v0.2-AWQ mistral-7b-instruct-awq
#   ./scripts/upload-model.sh TheBloke/Llama-2-7B-Chat-AWQ llama-2-7b-chat-awq

HF_MODEL="${1:?Usage: $0 <HF_MODEL_ID> <MINIO_PATH>}"
MINIO_PATH="${2:?Usage: $0 <HF_MODEL_ID> <MINIO_PATH>}"
NAMESPACE="${MINIO_NAMESPACE:-minio}"
PVC_SIZE="${PVC_SIZE:-10Gi}"

echo "==> Uploading model: ${HF_MODEL}"
echo "==> MinIO path: models/${MINIO_PATH}"
echo "==> Namespace: ${NAMESPACE}"

# Clean up any previous run
kubectl delete pod model-uploader -n "${NAMESPACE}" --ignore-not-found
kubectl delete pvc model-download -n "${NAMESPACE}" --ignore-not-found

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
          export PYTHONPATH=/tmp/pip-packages:\$PYTHONPATH
          export PATH=/tmp/pip-packages/bin:\$PATH

          echo "=== Installing MinIO client ==="
          python -c "import urllib.request; urllib.request.urlretrieve('https://dl.min.io/client/mc/release/linux-amd64/mc', '/tmp/mc')"
          chmod +x /tmp/mc

          echo "=== Downloading model from HuggingFace ==="
          hf download ${HF_MODEL} --local-dir /models/download

          echo "=== Configuring MinIO client ==="
          /tmp/mc alias set minio http://minio.${NAMESPACE}.svc.cluster.local:9000 minioadmin minioadmin123

          echo "=== Creating bucket (if needed) ==="
          /tmp/mc mb --ignore-existing minio/models

          echo "=== Uploading model to MinIO ==="
          /tmp/mc cp --recursive /models/download/ minio/models/${MINIO_PATH}/

          echo "=== Verifying upload ==="
          /tmp/mc ls minio/models/${MINIO_PATH}/

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

echo "==> Waiting for pod to start..."
kubectl wait --for=condition=Ready pod/model-uploader -n "${NAMESPACE}" --timeout=120s 2>/dev/null || true

echo "==> Following logs (Ctrl+C to detach, pod will continue)..."
kubectl logs -f model-uploader -n "${NAMESPACE}" || true

echo ""
echo "==> Cleaning up..."
kubectl delete pod model-uploader -n "${NAMESPACE}" --ignore-not-found
kubectl delete pvc model-download -n "${NAMESPACE}" --ignore-not-found
echo "==> Done!"
