# OpenShift AI - Chatbot UI Evaluation

## Project Overview

This project evaluates open-source chatbot UI options for deployment on **Red Hat OpenShift AI (RHOAI)**. The goal is to identify the best UI frontend that can connect to model serving endpoints (KServe / vLLM / TGI) and support multiple HuggingFace models.

## Key Context

- **Platform**: Red Hat OpenShift AI (RHOAI)
- **Model Serving**: KServe, vLLM, TGI (OpenAI-compatible API endpoints)
- **GCP Project**: `itpc-gcp-global-revenue-claude`
- **Focus**: Enterprise-ready, open-source chatbot UIs with Helm/K8s support

## Top Candidates

1. **Open WebUI** — Most mature, explicit OpenShift Helm support
2. **LibreChat** — Best enterprise auth (SSO, RBAC, audit), MIT license
3. **HF Chat UI** — Apache 2.0, auto-discovers models from endpoints

## Key Evaluation Criteria

- License compatibility (MIT / Apache 2.0 preferred)
- Helm chart / Kubernetes-native deployment
- OpenAI-compatible API support (for vLLM/TGI)
- Multi-model selection
- Enterprise features (SSO, RBAC, audit)
- HuggingFace integration
