# OpenShift AI Starter

## Project Overview

GitOps-ready starter kit for deploying **OpenShift AI** with **Open WebUI** on managed OpenShift clusters (ROSA and ARO). Includes operator subscriptions, MinIO for model storage, vLLM model serving, and Open WebUI as the chat frontend.

## Project Structure

```
openshift-ai-starter/
├── docs/                        # Human-readable guides
│   ├── rosa-guide.md            # Step-by-step ROSA guide (battle-tested)
│   ├── aro-guide.md             # ARO guide (to be created)
│   └── chatbot-ui-options.md    # UI evaluation research
├── gitops/
│   ├── bootstrap/               # GitOps operator install (one-time, manual)
│   ├── argocd/                  # ArgoCD Application definitions (app-of-apps)
│   ├── base/                    # Shared Kustomize base
│   │   ├── operators/           # NFD, GPU, Serverless, ServiceMesh, OpenShift AI
│   │   ├── datasciencecluster/  # DataScienceCluster CR
│   │   ├── minio/               # In-cluster S3-compatible storage
│   │   ├── model-serving/       # vLLM ServingRuntime + InferenceService
│   │   └── open-webui/          # Helm values + Route
│   └── overlays/
│       ├── rosa/                # ROSA-specific (GPU machinepool, gp3-csi)
│       └── aro/                 # ARO-specific (GPU nodepool, managed-premium)
├── scripts/
│   ├── bootstrap.sh             # One-time: install GitOps operator + deploy app-of-apps
│   └── upload-model.sh          # Helper to upload HF models to MinIO
└── CLAUDE.md
```

## Key Technical Decisions

- **Model**: `RedHatAI/Mistral-7B-Instruct-v0.3-quantized.w4a16` (GPTQ w4a16, 4-bit, fits on T4 16GB, supports tool calling)
- **vLLM image**: `docker.io/vllm/vllm-openai:v0.8.5.post1` (upstream, not RHOAI image)
- **GPU instance**: `g4dn.xlarge` on ROSA (cheapest, ~$0.526/hr)
- **Storage**: MinIO in-cluster (with AWS S3 as alternative)
- **GitOps**: Kustomize base/overlay + ArgoCD app-of-apps

## Quick Deploy

```bash
# 1. Bootstrap (one-time): install GitOps operator + ArgoCD
REPO_ORG=danielpenagos
./scripts/bootstrap.sh https://github.com/$REPO_ORG/openshift-ai-starter.git

# Or manually without ArgoCD:
oc apply -k gitops/bootstrap/          # install GitOps operator
oc apply -k gitops/overlays/rosa/      # deploy everything via Kustomize

# 2. Create GPU machine pool (manual, see gitops/overlays/rosa/gpu-machinepool.md)

# 3. Upload a model to MinIO:
./scripts/upload-model.sh TheBloke/Mistral-7B-Instruct-v0.2-AWQ mistral-7b-instruct-awq
```

## OpenShift-Specific Gotchas

- Containers run as random UIDs — use `HOME=/tmp`, `fsGroup: 0`, never `apt-get`
- Redis in Open WebUI fails on OpenShift — disable it for single-replica
- `WEBUI_SECRET_KEY` env var is required by Open WebUI
- GPU nodes need `nvidia.com/gpu=:NoSchedule` taint + matching toleration on pods
- `huggingface-cli` is deprecated — use `hf` instead
