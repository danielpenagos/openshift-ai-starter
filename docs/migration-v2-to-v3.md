# OpenShift AI: Migration from v2 to v3

## Overview

OpenShift AI 3 introduces a major architectural simplification: **RawDeployment is now the default** (and only) mode for model serving. This eliminates the need for Serverless and Service Mesh operators, removing the complexity and conflicts we experienced with KnativeServing and Istio.

> **Note:** There is no supported in-place upgrade from 2.x to 3.x. RHOAI 3 requires a fresh install.

## Requirements

| Requirement | v2 | v3 |
|---|---|---|
| Min OpenShift version | 4.12 | **4.19** |
| Serverless Operator | Required | **Not needed** |
| Service Mesh Operator | Required | **Not needed** |
| cert-manager Operator | Not needed | **Required** |
| KnativeServing instance | Required | **Not needed** |

## Changes Summary

### Operators

| Operator | v2 | v3 |
|---|---|---|
| NFD | Required | Required (no change) |
| NVIDIA GPU | Required | Required (no change) |
| OpenShift Serverless | Required | **Remove** |
| OpenShift Service Mesh | Required | **Remove** |
| cert-manager | Not needed | **Add** |
| OpenShift AI (rhods-operator) | `channel: fast` | `channel: stable-3.x` |

### DataScienceCluster CR

| Field | v2 | v3 |
|---|---|---|
| API version | `datasciencecluster.opendatahub.io/v1` | `datasciencecluster.opendatahub.io/v2` |
| `modelmeshserving` | Managed | **Removed** (component no longer exists) |
| `datasciencepipelines` | Managed | **Renamed** to `aipipelines` |
| `kserve.serving` (Knative) | Managed | **Removed** (RawDeployment is default) |
| `kserve.rawDeploymentServiceConfig` | N/A | **New** — set to `Headless` |
| `modelregistry` | Managed | Managed (no change) |
| `trustyai` | Removed | Managed (now GA) |
| `trainer` | N/A | **New** (replaces `trainingoperator`) |
| `feastoperator` | N/A | **New** |

### Operator Instances

| Instance | v2 | v3 |
|---|---|---|
| KnativeServing | Required | **Remove** |
| ClusterPolicy (GPU) | Required | Required (no change) |
| NodeFeatureDiscovery | Required | Required (no change) |

### Model Serving

| Field | v2 | v3 |
|---|---|---|
| InferenceService API | `serving.kserve.io/v1beta1` | `serving.kserve.io/v1beta1` (no change) |
| ServingRuntime API | `serving.kserve.io/v1alpha1` | `serving.kserve.io/v1alpha1` (no change) |
| Deployment mode annotation | `serving.kserve.io/deploymentMode: RawDeployment` | **Not needed** (RawDeployment is default) |
| Knative annotations | `serving.knative.openshift.io/enablePassthrough: "true"` | **Remove** |
| Istio annotations | `sidecar.istio.io/inject: "true"` | **Remove** |
| vLLM image | `docker.io/vllm/vllm-openai:v0.8.5.post1` | `registry.redhat.io/rhaiis/vllm-cuda-rhel9:3` |
| vLLM command | `python3 -m vllm.entrypoints.openai.api_server` | `vllm serve` |

## File-by-File Changes

### Files to modify

| File | Change |
|---|---|
| `gitops/base/operators/openshift-ai/operator.yaml` | Channel: `fast` → `stable-3.x` |
| `gitops/base/datasciencecluster/datasciencecluster.yaml` | API v1 → v2, remove `modelmeshserving`, rename `datasciencepipelines` → `aipipelines`, remove `kserve.serving` |
| `gitops/base/model-serving/serving-runtime.yaml` | Image and command changes |
| `gitops/base/model-serving/inference-service.yaml` | Remove Knative/Istio annotations |

### Files to remove

| File | Reason |
|---|---|
| `gitops/base/operators/serverless/` | Serverless no longer needed |
| `gitops/base/operators/servicemesh/` | Service Mesh no longer needed |
| `gitops/base/operators-instances/knative-serving.yaml` | KnativeServing no longer needed |

### Files to add

| File | Reason |
|---|---|
| `gitops/base/operators/cert-manager/` | New prerequisite for v3 |

## How to Use

Use the v3 overlay instead of the default base:

```bash
# With Kustomize
oc apply -k gitops/overlays/rosa-v3/

# With ArgoCD — update the app-of-apps source path to use the v3 overlay
```

Or switch the entire project to v3 by updating the base files directly.

## References

- [RHOAI 3.0 Release Notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/release_notes/index)
- [RHOAI 3.3 Installation Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install)
- [Converting to RawDeployment](https://access.redhat.com/articles/7134025)
- [RHOAI Supported Configurations 3.x](https://access.redhat.com/articles/rhoai-supported-configs-3.x)
