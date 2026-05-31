# Operations Runbooks

This document provides step-by-step procedures for common operational tasks on the AI Platform.

## Table of Contents

1. [Deploy a New Model](#deploy-a-new-model)
2. [Rollback a Model Version](#rollback-a-model-version)
3. [Scale GPU Node Pool](#scale-gpu-node-pool)
4. [Handle Node Failure](#handle-node-failure)
5. [Certificate Renewal](#certificate-renewal)
6. [Backup and Restore](#backup-and-restore)
7. [Cost Investigation](#cost-investigation)

---

## Deploy a New Model

**Goal**: Deploy a new HuggingFace model (e.g., Llama 3.1 8B) to the inference platform.

### Steps

1. Update the config file:
```bash
# Edit config/demo.yaml — add model section under inference.models
vim config/demo.yaml
```

2. Validate the config:
```bash
python3 terraform/scripts/validate-config.py config/demo.yaml
```

3. Generate the configs:
```bash
python3 terraform/scripts/generate-config.py config/demo.yaml --env dev
```

4. Commit and push (ArgoCD auto-syncs) or sync manually:
```bash
argocd app sync ai-models
```

5. Verify the model is serving:
```bash
kubectl get inferenceservices -n ai
kubectl get pods -n ai -l model=llama-3.1-8b
```

6. Smoke test:
```bash
curl -X POST http://llama-3.1-8b-ai.ai.svc.cluster.local:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"llama-3.1-8b","messages":[{"role":"user","content":"Hello"}]}'
```

---

## Rollback a Model Version

**Goal**: Revert a model to a previous revision.

### Steps

1. Identify the previous revision:
```bash
kubectl get inferenceservice -n ai <model-name> -o yaml | grep revision
```

2. Edit the InferenceService:
```bash
kubectl edit inferenceservice -n ai <model-name>
# Change spec.predictor.model.revision to previous value
```

3. ArgoCD will detect drift. To prevent reversion:
```bash
argocd app set ai-models --sync-policy none
# After rollback completes, re-enable:
argocd app set ai-models --sync-policy automated
```

4. Verify rollback:
```bash
kubectl get pods -n ai -l model=<model-name> --watch
```

---

## Scale GPU Node Pool

**Goal**: Manually adjust GPU node pool size for planned load.

### Steps

1. Update the Terraform variable:
```bash
# Edit terraform/envs/dev/terraform.tfvars
gpu_max_size = 10
```

2. Apply:
```bash
cd terraform/envs/dev
terraform apply -target=module.eks
```

3. Verify:
```bash
kubectl get nodes -l node-type=gpu
```

For Karpenter-managed scaling (preferred), adjust provisioner:
```bash
kubectl edit provisioner gpu
# Update spec.limits.resources.cpu or spec.specifications[].max
```

---

## Handle Node Failure

**Goal**: Respond to an unhealthy GPU node.

### Steps

1. Identify the node:
```bash
kubectl get nodes
kubectl describe node <node-name> | grep -A5 Conditions
```

2. Cord and drain:
```bash
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

3. If using Karpenter, it will automatically replace. If using MNG:
```bash
aws eks update-nodegroup-config --cluster-name <cluster> --nodegroup-name <ng> --scaling-config desiredSize=0
```

4. Terminate the instance:
```bash
aws ec2 terminate-instances --instance-ids <instance-id>
```

5. Verify replacement:
```bash
kubectl get nodes -l node-type=gpu --watch
```

---

## Certificate Renewal

**Goal**: Renew expiring TLS certificates.

### Steps

1. Check certificate expiry:
```bash
kubectl get certificate --all-namespaces
kubectl describe certificate -n <namespace> <name> | grep -E "(Not After|Renewal)"
```

2. cert-manager auto-renews 30 days before expiry. To force renewal:
```bash
kubectl delete certificate -n <namespace> <name>
# ArgoCD recreates it
```

3. Verify new certificate:
```bash
kubectl get secret -n <namespace> <name>-tls -o json | jq -r '.data["tls.crt"]' | base64 -d | openssl x509 -noout -enddate
```

---

## Backup and Restore

**Goal**: Backup and restore Kubernetes resources and data.

### Backup

```bash
# Manual backup
velero backup create daily-$(date +%Y%m%d) --include-namespaces ai,monitoring,platform

# Verify
velero backup describe daily-$(date +%Y%m%d)
```

### Restore

```bash
# List available backups
velero backup get

# Restore a namespace
velero restore create --from-backup daily-20260530 --include-namespaces ai

# Restore a specific resource
velero restore create --from-backup daily-20260530 --include-resources inferenceservice

# Verify
kubectl get inferenceservices -n ai
```

---

## Cost Investigation

**Goal**: Identify cost anomalies.

### Steps

1. Check the Cost Monitoring dashboard in Grafana (dashboards/cost-monitoring.json).

2. Identify top spenders:
```bash
# Query OpenCost API
kubectl port-forward -n monitoring service/opencost 9001:9001
curl http://localhost:9001/allocation/compute?window=24h | jq '.data[0:10]'
```

3. Check idle resources:
```bash
kubectl top nodes
kubectl describe nodes | grep -A3 "Allocated resources"
```

4. For GPU cost optimization:
```bash
# Check GPU utilization
kubectl exec -n ai <vllm-pod> -- nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv
```

5. Adjust KEDA scaling thresholds:
```bash
kubectl edit scaledobject -n ai vllm-scaler
# Reduce minReplicas or adjust triggers
```
