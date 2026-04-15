# Chatbot UI Options for OpenShift AI

Comparison of open-source chatbot UI projects that can run on **Red Hat OpenShift AI (RHOAI)**, connect to model serving endpoints (KServe / vLLM / TGI), and allow selecting among multiple HuggingFace models.

---

## Quick Comparison

| Project | Stars | License | Multi-Model | HF Integration | OpenAI-Compatible API | K8s / Helm | OpenShift Ready | Status |
|---|---|---|---|---|---|---|---|---|
| [Open WebUI](#1-open-webui) | 124k+ | Open WebUI License | Yes (parallel) | Via vLLM/TGI | Yes | Official Helm | Yes (explicit) | Very Active |
| [LibreChat](#2-librechat) | ~34.8k | MIT | Yes (mid-chat switch) | Via endpoints | Yes | Official Helm + OCP chart | Yes (explicit) | Very Active |
| [HF Chat UI](#3-hugging-face-chat-ui) | ~10.6k | Apache 2.0 | Yes (auto-discover) | Native | Yes (only protocol) | Helm in repo | Yes (generic K8s) | Active |
| [AnythingLLM](#4-anythingllm) | ~54k | MIT | 30+ providers | Via endpoints + HF API | Yes | Docker only | Manual | Very Active |
| [Jan](#5-jan) | ~41.6k | AGPL-3.0 | Local + cloud | Direct download | Yes (serves) | K8s documented | Possible | Active |
| [text-generation-webui](#6-text-generation-webui) | ~46.5k | AGPL-3.0 | One at a time | Direct download | Yes (serves) | Docker only | Limited | Very Active |
| [Chatbot UI](#7-chatbot-ui-mckay-wrigley) | ~33k | MIT | Via env vars | Indirect | Yes | No Helm | Manual | Stagnant |
| [RAG-LLM-GitOps](#8-rag-llm-gitops-validated-pattern) | 18 | Apache 2.0 | Multi-provider | Via vLLM | Yes | GitOps / ArgoCD | Purpose-built | Active |
| [Gradio ChatInterface](#9-gradio-chatinterface) | N/A | Apache 2.0 | Via code | Via endpoints | Yes | Easy to containerize | De facto standard | Very Active |
| [LM Studio](#10-lm-studio) | N/A | Proprietary | Local only | Direct download | Yes (serves) | None | No | Active |

---

## Detailed Analysis

### 1. Open WebUI

| | |
|---|---|
| **GitHub** | [open-webui/open-webui](https://github.com/open-webui/open-webui) |
| **Stars** | 124k+ |
| **License** | Open WebUI License (formerly MIT; now includes branding preservation requirements) |
| **Tech Stack** | Python (FastAPI) + SvelteKit |
| **Container** | Official Helm charts at [helm.openwebui.com](https://helm.openwebui.com/). Docker images with `:ollama` and `:cuda` tags. |

**How it connects to OpenShift AI:** Connects to vLLM / TGI / KServe endpoints as OpenAI-compatible providers. Community guides exist for deploying on OpenShift ([Medium guide](https://gautam75.medium.com/deploy-ollama-and-open-webui-on-openshift-c88610d3b5c7)). Helm charts explicitly list OpenShift as a supported distribution.

**Key Features:**
- Parallel multi-model conversations
- RAG with 9 vector DB backends
- Web search (15+ providers)
- Voice / video calls, image generation (DALL-E, ComfyUI)
- RBAC and multi-user auth
- Model builder and native Python function calling
- PostgreSQL / S3 / Azure Blob support for scaling
- `/ready` endpoint for Kubernetes health checks

**Pros:**
- Most popular and mature option by far
- Explicit OpenShift support in Helm charts
- Connects natively to vLLM/TGI endpoints used by OpenShift AI
- Feature-rich: RAG, web search, voice, RBAC

**Cons:**
- License changed from MIT to a custom license -- review branding requirements before enterprise adoption
- Large feature surface may be more than needed for a simple chatbot

---

### 2. LibreChat

| | |
|---|---|
| **GitHub** | [danny-avila/LibreChat](https://github.com/danny-avila/LibreChat) |
| **Stars** | ~34.8k |
| **License** | MIT |
| **Tech Stack** | TypeScript / Node.js, MongoDB, MeiliSearch, Redis |
| **Container** | Official Helm chart in repo. OCI install: `helm install librechat oci://ghcr.io/danny-avila/librechat-chart/librechat`. OpenShift chart on [Artifact Hub](https://artifacthub.io/packages/helm/librechat-openshift/librechat). |

**How it connects to OpenShift AI:** Custom endpoints configuration for any OpenAI-compatible API (vLLM, TGI). Community-maintained OpenShift-specific Helm chart available on Artifact Hub.

**Key Features:**
- Switch between providers/models mid-conversation
- Fork conversations to explore different responses
- AI Agents and MCP (Model Context Protocol) support
- Artifacts and Code Interpreter
- SAML / OIDC / LDAP SSO, 2FA
- Rate limiting, moderation tools, audit trails
- Presets and custom actions

**Pros:**
- MIT license -- enterprise friendly
- Best-in-class enterprise auth (SSO, RBAC, audit)
- OpenShift Helm chart on Artifact Hub
- Very active development (acquired by ClickHouse, remains MIT)
- 9k+ Discord community

**Cons:**
- Requires MongoDB + MeiliSearch + Redis -- heavier operational footprint
- More complex to deploy than simpler alternatives

---

### 3. Hugging Face Chat UI

| | |
|---|---|
| **GitHub** | [huggingface/chat-ui](https://github.com/huggingface/chat-ui) |
| **Stars** | ~10.6k |
| **License** | Apache 2.0 |
| **Tech Stack** | SvelteKit + TypeScript, MongoDB |
| **Container** | Helm chart in `/chart` directory. Docker image at `ghcr.io/huggingface/chat-ui-db:latest` (bundles MongoDB). |

**How it connects to OpenShift AI:** Speaks only the OpenAI protocol -- auto-discovers models from any OpenAI-compatible endpoint via `/models`. Points directly at vLLM/TGI serving endpoints.

**Key Features:**
- This is the codebase behind HuggingChat
- Auto-discovers available models from endpoints
- Tools / function calling
- Multimodal inputs (images, files)
- Web search integration
- Authentication and theming
- HuggingFace Inference Providers router

**Pros:**
- Apache 2.0 license -- very permissive
- Native HuggingFace ecosystem integration
- Clean, simple UI focused on chat
- Auto-model-discovery from endpoints is elegant for OpenShift AI

**Cons:**
- Smaller community than Open WebUI or LibreChat
- Fewer enterprise features (no SSO, limited RBAC)
- Requires MongoDB

---

### 4. AnythingLLM

| | |
|---|---|
| **GitHub** | [Mintplex-Labs/anything-llm](https://github.com/Mintplex-Labs/anything-llm) |
| **Stars** | ~54k |
| **License** | MIT |
| **Tech Stack** | JavaScript (Node.js), ViteJS + React, Express |
| **Container** | Docker image: `mintplexlabs/anythingllm`. No official Helm chart. |

**How it connects to OpenShift AI:** Connects to vLLM/TGI endpoints as OpenAI-compatible providers. Also supports HuggingFace Inference API directly.

**Key Features:**
- Document RAG (PDF, DOCX, TXT, code, audio)
- Workspace containerization (isolate knowledge per workspace)
- 30+ LLM provider integrations
- Built-in agents with tool use
- Embeddable chat widget for other apps
- White-labeling and RBAC
- No-code workflow builder
- Telegram bot, mobile app

**Pros:**
- MIT license
- Best all-in-one RAG solution
- Excellent document ingestion pipeline
- Embeddable widget useful for integrating into existing apps

**Cons:**
- Docker-only deployment -- no official Helm chart for Kubernetes/OpenShift
- Deploying on OpenShift requires manual manifest creation
- Heavier than needed if you just want a simple chat UI

---

### 5. Jan

| | |
|---|---|
| **GitHub** | [janhq/jan](https://github.com/janhq/jan) |
| **Stars** | ~41.6k |
| **License** | AGPL-3.0 |
| **Tech Stack** | TypeScript / Electron (desktop), Node.js (server), C++ (inference engine) |
| **Container** | Docker Compose for dev, Kubernetes for production. Helm charts with vLLM StatefulSets. |

**How it connects to OpenShift AI:** Jan Server provides an OpenAI-compatible API. Kubernetes deployment is documented with GPU support, OAuth/OIDC via Keycloak, and observability (OpenTelemetry, Prometheus, Grafana).

**Key Features:**
- Offline-first design
- MCP integration
- OpenAI-compatible local API (port 1337)
- VSCode-like extension system
- Multimodal reasoning
- Web search

**Pros:**
- Mature Kubernetes deployment story
- Enterprise features (OAuth, observability)
- Strong extension ecosystem

**Cons:**
- **AGPL-3.0 license** -- requires source disclosure for network-accessible services (enterprise legal review needed)
- Desktop-focused architecture; server mode feels secondary
- Primarily designed to run models locally, not connect to external endpoints

---

### 6. text-generation-webui

| | |
|---|---|
| **GitHub** | [oobabooga/text-generation-webui](https://github.com/oobabooga/text-generation-webui) |
| **Stars** | ~46.5k |
| **License** | AGPL-3.0 |
| **Tech Stack** | Python, Gradio (custom fork), PyTorch |
| **Container** | Docker Compose in repo (NVIDIA/AMD/CPU). Community images: `atinoda/text-generation-webui`. No Helm chart. |

**How it connects to OpenShift AI:** This tool **IS** the serving endpoint -- it loads and runs models locally on GPU. It exposes an OpenAI-compatible API on port 5000 with `--api`. Not designed to connect to external serving endpoints.

**Key Features:**
- Downloads models directly from HuggingFace (GGUF, GPTQ, AWQ, EXL2)
- Multiple backends: ExLlamaV3, Transformers, llama.cpp, TensorRT-LLM
- Training / fine-tuning capabilities
- Vision, tool-calling, TTS extensions
- 100% offline operation

**Pros:**
- Excellent for local model experimentation
- Direct HuggingFace model download
- Active development, funded by a16z

**Cons:**
- **Not the right fit for OpenShift AI** -- designed to load models itself, not to connect to KServe/vLLM endpoints
- AGPL-3.0 license
- Loads one model at a time
- No Helm chart

---

### 7. Chatbot UI (McKay Wrigley)

| | |
|---|---|
| **GitHub** | [mckaywrigley/chatbot-ui](https://github.com/mckaywrigley/chatbot-ui) |
| **Stars** | ~33k |
| **License** | MIT |
| **Tech Stack** | Next.js + TypeScript + Tailwind CSS, Supabase (PostgreSQL) |
| **Container** | Image at `ghcr.io/mckaywrigley/chatbot-ui:main`. No Helm chart. |

**Key Features:**
- Clean ChatGPT-like UI
- Conversation history
- Model switching via `OPENAI_API_HOST`

**Pros:**
- MIT license
- Clean, simple interface

**Cons:**
- **Maintenance appears stagnant** -- no recent commits, community concerns about project status
- Requires Supabase (adds complexity)
- Limited features compared to alternatives
- No Kubernetes/Helm tooling

---

### 8. RAG-LLM-GitOps Validated Pattern

| | |
|---|---|
| **GitHub** | [validatedpatterns/rag-llm-gitops](https://github.com/validatedpatterns/rag-llm-gitops) |
| **Stars** | 18 (109 forks) |
| **License** | Apache 2.0 |
| **Tech Stack** | Gradio UI, LangChain, vLLM, IBM Granite 3.1-8B-Instruct, EDB Postgres / Redis / Elasticsearch |
| **Deployment** | ArgoCD / GitOps, NVIDIA GPU operator, OpenShift AI model serving |

**How it connects to OpenShift AI:** **Purpose-built.** This is an official Red Hat Validated Pattern that deploys a complete RAG chatbot stack on OpenShift AI using GitOps principles.

**Key Features:**
- Full GitOps deployment via ArgoCD
- vLLM inference servers on GPU-enabled nodes
- Multiple LLM provider support (HuggingFace, OpenAI, NVIDIA NIM)
- Vector store options (Postgres, Redis, Elasticsearch)
- Reference architecture for production deployments

**Pros:**
- Official Red Hat reference architecture
- Production-grade GitOps deployment
- Apache 2.0 license
- Purpose-built for OpenShift AI

**Cons:**
- Basic Gradio UI -- functional but not polished
- Primarily a RAG pattern, not a general chat UI
- Small community

**Related OpenShift AI projects:**
- [eartvit/llm-on-ocp](https://github.com/eartvit/llm-on-ocp) -- step-by-step LLM deployment guide with Gradio chatbot
- [rh-mobb/parasol-insurance](https://github.com/rh-mobb/parasol-insurance) -- Red Hat's flagship AI demo (insurance claims chatbot)
- [rh-telco-tigers/flowise-chat-agent-rhoai](https://github.com/rh-telco-tigers/flowise-chat-agent-rhoai) -- Flowise no-code chat agent on RHOAI
- [rhpds/ai-chatbots](https://github.com/rhpds/ai-chatbots) -- demo app with LLM vs RAG side-by-side comparison

---

### 9. Gradio ChatInterface

| | |
|---|---|
| **GitHub** | [gradio-app/gradio](https://github.com/gradio-app/gradio) |
| **License** | Apache 2.0 |
| **Tech Stack** | Python |

**How it connects to OpenShift AI:** `gr.load_chat()` connects to any OpenAI-compatible endpoint in a single line of Python. The de facto UI framework for OpenShift AI demos and prototypes.

**Key Features:**
- `gr.ChatInterface` -- build a chatbot UI in a few lines of Python
- Easy to containerize (expose port 7860)
- Widely used in the OpenShift AI ecosystem
- [Deployment guide for K8s/OpenShift](https://rcarrata.com/ai/gradio-k8s/)

**Pros:**
- Apache 2.0 license
- Fastest path from zero to working chatbot
- Already the standard in OpenShift AI demos

**Cons:**
- Not a full chat platform -- no multi-user auth, no conversation persistence, no RBAC
- Basic UI compared to dedicated chat applications
- Best suited for prototyping, not production multi-user deployments

---

### 10. LM Studio

| | |
|---|---|
| **Website** | [lmstudio.ai](https://lmstudio.ai/) |
| **License** | **Proprietary freeware** (SDKs are MIT) |

**Not recommended.** The core application is not open source. It is a desktop-only tool with no server or Kubernetes deployment capability. Cannot be self-hosted on OpenShift.

---

## Recommendations

### Tier 1 -- Best Options for OpenShift AI

| Rank | Project | Best For | Why |
|---|---|---|---|
| 1 | **Open WebUI** | General-purpose production chatbot | Most mature, most popular, explicit OpenShift Helm support, rich features (RAG, RBAC, web search). Connects natively to vLLM/TGI. |
| 2 | **LibreChat** | Enterprise environments needing SSO/audit | MIT license, SAML/OIDC/LDAP SSO, OpenShift Helm chart on Artifact Hub, multi-provider mid-chat switching. |
| 3 | **HF Chat UI** | HuggingFace-centric workflows | Apache 2.0, auto-discovers models from endpoints, clean focused UI. Ideal if your models are primarily from HuggingFace served via TGI/vLLM. |

### Tier 2 -- Viable with Extra Effort

| Rank | Project | Best For | Caveat |
|---|---|---|---|
| 4 | **AnythingLLM** | Document-heavy RAG use cases | No Helm chart -- requires manual K8s manifest creation |
| 5 | **Jan Server** | Self-contained model serving + UI | AGPL license needs enterprise legal review |

### Tier 3 -- OpenShift-Native (Simpler UIs)

| Rank | Project | Best For | Caveat |
|---|---|---|---|
| 6 | **RAG-LLM-GitOps** | Official Red Hat starting point | Basic Gradio UI, but production-grade GitOps deployment |
| 7 | **Gradio ChatInterface** | Quick prototypes and demos | Not a full chat platform; lacks multi-user features |

### Not Recommended

| Project | Reason |
|---|---|
| **text-generation-webui** | Designed to load models locally, not connect to external endpoints; AGPL |
| **Chatbot UI** | Maintenance appears stagnant; Supabase dependency adds friction |
| **LM Studio** | Proprietary, desktop-only |
