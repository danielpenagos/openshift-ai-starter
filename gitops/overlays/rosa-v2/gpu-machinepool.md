# ROSA GPU Machine Pool

This is a manual step — machine pools cannot be managed via Kustomize/ArgoCD.

Run this command before applying the GitOps manifests:

```bash
rosa create machinepool --cluster=<CLUSTER_NAME> \
  --name=gpu-pool \
  --replicas=1 \
  --instance-type=g4dn.xlarge \
  --labels='nvidia.com/gpu=true' \
  --taints='nvidia.com/gpu=:NoSchedule'
```

## Autoscaling alternative

```bash
rosa create machinepool --cluster=<CLUSTER_NAME> \
  --name=gpu-pool \
  --instance-type=g4dn.xlarge \
  --enable-autoscaling \
  --min-replicas=0 \
  --max-replicas=2 \
  --labels='nvidia.com/gpu=true' \
  --taints='nvidia.com/gpu=:NoSchedule'
```
