# ARO GPU Node Pool

This is a manual step — node pools cannot be managed via Kustomize/ArgoCD.

Run this command before applying the GitOps manifests:

```bash
az aro update --resource-group <RESOURCE_GROUP> --name <CLUSTER_NAME> # ARO doesn't support adding machinepools via CLI directly

# Use the OpenShift MachineSet approach instead:
# 1. Create a MachineSet with a GPU instance type (e.g., Standard_NC4as_T4_v3)
# 2. Add labels and taints for GPU isolation
```

## Recommended GPU VM sizes for ARO

| VM Size | GPU | VRAM | vCPUs | Cost |
|---|---|---|---|---|
| Standard_NC4as_T4_v3 | 1x T4 | 16 GB | 4 | ~$0.526/hr |
| Standard_NC8as_T4_v3 | 1x T4 | 16 GB | 8 | ~$0.752/hr |
| Standard_NC16as_T4_v3 | 1x T4 | 16 GB | 16 | ~$1.204/hr |
