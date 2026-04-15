#!/bin/bash
set -euo pipefail

# Bootstrap script for OpenShift AI Starter
# This installs the Red Hat OpenShift GitOps operator (ArgoCD) and then
# deploys the app-of-apps to manage everything else via GitOps.
#
# Usage:
#   ./scripts/bootstrap.sh [REPO_URL]
#
# Example:
#   ./scripts/bootstrap.sh https://github.com/myorg/openshift-ai-starter.git

REPO_URL="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

echo "============================================"
echo "  OpenShift AI Starter - Bootstrap"
echo "============================================"
echo ""

# Step 1: Install the GitOps operator
echo "==> Step 1: Installing Red Hat OpenShift GitOps operator..."
oc apply -k "${PROJECT_DIR}/gitops/bootstrap"

echo "==> Waiting for the GitOps operator to be ready..."
echo "    (this may take a few minutes)"

# Wait for the operator CSV to succeed
until oc get csv -n openshift-operators 2>/dev/null | grep -q "openshift-gitops-operator.*Succeeded"; do
  sleep 10
  echo "    still waiting..."
done
echo "==> GitOps operator installed."

# Wait for ArgoCD to be ready
echo "==> Waiting for ArgoCD pods to be ready..."
until oc get pods -n openshift-gitops 2>/dev/null | grep -q "openshift-gitops-server.*Running"; do
  sleep 10
  echo "    still waiting..."
done
echo "==> ArgoCD is ready."

# Step 2: Get ArgoCD URL
ARGOCD_URL=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='https://{.spec.host}' 2>/dev/null || echo "not-available-yet")
echo ""
echo "==> ArgoCD console: ${ARGOCD_URL}"
echo "    (log in with your OpenShift credentials)"
echo ""

# Step 3: Deploy app-of-apps (if repo URL provided)
if [[ -n "${REPO_URL}" ]]; then
  echo "==> Step 2: Deploying app-of-apps from ${REPO_URL}..."

  # Update repo URLs in ArgoCD applications
  TEMP_DIR=$(mktemp -d)
  cp "${PROJECT_DIR}"/gitops/argocd/*.yaml "${TEMP_DIR}/"
  sed -i.bak "s|https://github.com/<YOUR_ORG>/openshift-ai-starter.git|${REPO_URL}|g" "${TEMP_DIR}"/*.yaml
  rm -f "${TEMP_DIR}"/*.bak

  oc apply -f "${TEMP_DIR}/app-of-apps.yaml"
  rm -rf "${TEMP_DIR}"

  echo "==> App-of-apps deployed. ArgoCD will now sync all components."
else
  echo "==> Step 2: Skipped (no REPO_URL provided)."
  echo "    To deploy via GitOps, run:"
  echo "    ./scripts/bootstrap.sh https://github.com/<YOUR_ORG>/openshift-ai-starter.git"
  echo ""
  echo "    Or deploy manually with Kustomize:"
  echo "    oc apply -k gitops/overlays/rosa/"
fi

echo ""
echo "============================================"
echo "  Bootstrap complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Create a GPU machine pool (see gitops/overlays/rosa/gpu-machinepool.md)"
echo "  2. Upload a model: ./scripts/upload-model.sh TheBloke/Mistral-7B-Instruct-v0.2-AWQ mistral-7b-instruct-awq"
echo "  3. Install Open WebUI via Helm: helm install open-webui open-webui/open-webui -n open-webui -f gitops/base/open-webui/open-webui-values.yaml"
