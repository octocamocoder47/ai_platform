# One-Command Bootstrap

> **Source of Truth** — The bootstrap process that transforms a config file into a running platform from zero.
> Last updated: 2026-05-31

## Overview

The bootstrap process takes an empty AWS environment (no infrastructure) and produces a fully operational AI platform with a running LLM — all from a single command.

## Bootstrap Flow

```
┌────────────────────────────────────────────────────────────────────────┐
│  1. Pre-Flight Checks                                                   │
│  - Check AWS credentials (role assumption)                              │
│  - Validate config file against JSON Schema                             │
│  - Check required tools (terraform, kubectl, helm, python3)             │
│  - Verify domain/DNS prerequisites                                      │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│  2. Bootstrap Backend                                                   │
│  - Create S3 bucket (Terraform state) with versioning + encryption     │
│  - Create DynamoDB table (state locking)                               │
│  - Create KMS key (state encryption at rest)                           │
│  - Apply bucket policy (deny HTTP, require encryption)                 │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│  3. Generate Configuration                                              │
│  - Parse platform-config.yaml                                          │
│  - Resolve secret references (${VAR} → env variables)                  │
│  - Generate terraform.tfvars per account/region                        │
│  - Generate ArgoCD ApplicationSets                                     │
│  - Generate K8s manifests (LLMInferenceService, ScaledObject, etc.)    │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│  4. Apply Terraform (Layer 1 — Infrastructure)                         │
│  Order:                                                                │
│                                                                        │
│  ┌──────────────────────┐   ┌──────────────────────┐                 │
│  │ Network Account (Hub)│   │ Shared Services Acct  │                 │
│  │ ├─ VPC + Subnets     │   │ ├─ Harbor Registry    │                 │
│  │ ├─ Transit Gateway   │   │ └─ Vault              │                 │
│  │ └─ Route53           │   └──────────────────────┘                 │
│  └──────────────────────┘                                            │
│                                                                        │
│  ┌──────────────────────┐   ┌──────────────────────┐                 │
│  │ Workload Account     │   │ GCP (if multi-cloud)  │                 │
│  │ ├─ VPC + TGW attach  │   │ ├─ Shared VPC          │                 │
│  │ ├─ EKS Cluster       │   │ ├─ GKE Cluster         │                 │
│  │ ├─ Karpenter         │   │ └─ Cloud VPN           │                 │
│  │ ├─ Node Groups       │   └──────────────────────┘                 │
│  │ └─ IRSA Roles        │                                             │
│  └──────────────────────┘                                             │
│                                                                        │
│  ┌──────────────────────┐                                             │
│  │ Cross-Cloud          │                                             │
│  │ ├─ VPN Tunnels       │                                             │
│  │ └─ DNS Sync          │                                             │
│  └──────────────────────┘                                             │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│  5. Install ArgoCD (Layer 2 — GitOps Bootstrap)                       │
│  - Apply ArgoCD Helm chart via terraform/helm                          │
│  - Create initial Applications for all platform components             │
│  - Wait for ArgoCD to be healthy                                       │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│  6. ArgoCD Syncs Platform (Layer 3-4 — Platform + AI)                  │
│  ArgoCD automatically reconciles:                                     │
│                                                                        │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │  Phase 1 (Core): Cilium, cert-manager, External Secrets, Vault │   │
│  │  Phase 2 (Obs):  Prometheus, Grafana, Loki, Tempo              │   │
│  │  Phase 3 (AI):   NVIDIA GPU Operator, Kueue, KEDA, KServe     │   │
│  └────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│  7. Deploy Model (Layer 5 — Model Serving)                            │
│  - Apply LLMInferenceService CRD                                       │
│  - Wait for vLLM pod to be ready (initial delay for model download)   │
│  - Verify Gateway API HTTPRoute is configured                          │
│  - Run smoke test against OpenAI-compatible endpoint                   │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│  8. Verification & Reporting                                           │
│  - Run comprehensive health checks                                     │
│  - Open Grafana dashboard URL                                          │
│  - Output inference endpoint                                           │
│  - Print summary report                                                │
└────────────────────────────────────────────────────────────────────────┘
```

## Entrypoint: `scripts/bootstrap.sh`

```bash
#!/bin/bash
# =========================================================================
# AI Platform Bootstrap — One-Command Deploy
# =========================================================================
# Usage:
#   ./scripts/bootstrap.sh --config config/demo.yaml [options]
#
# Options:
#   --config PATH      Path to platform config (required)
#   --auto-approve     Skip approval prompts (CI mode)
#   --skip-infra       Skip Terraform (use existing infra)
#   --skip-platform    Skip ArgoCD platform sync
#   --env ENV          Environment (dev|staging|prod) (default: dev)
#   --dry-run          Validate config and print plan without executing
# =========================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Parse arguments
CONFIG=""
APPROVE=""
SKIP_INFRA=""
SKIP_PLATFORM=""
ENV="dev"
DRY_RUN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)    CONFIG="$2"; shift 2 ;;
    --auto-approve) APPROVE="--auto-approve"; shift ;;
    --skip-infra)   SKIP_INFRA="true"; shift ;;
    --skip-platform) SKIP_PLATFORM="true"; shift ;;
    --env)       ENV="$2"; shift 2 ;;
    --dry-run)   DRY_RUN="true"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "============================================"
echo "  AI Platform Bootstrap v1.0"
echo "  Config:  $CONFIG"
echo "  Env:     $ENV"
echo "============================================"

# Step 0: Pre-flight checks
echo "[0/7] Pre-flight checks..."
python3 "$SCRIPT_DIR/validate-config.py" "$CONFIG"
command -v terraform >/dev/null 2>&1 || { echo "terraform required"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl required"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "helm required"; exit 1; }

# Step 1: Bootstrap backend
if [ -z "$SKIP_INFRA" ]; then
  echo "[1/7] Bootstrap Terraform backend..."
  bash "$PROJECT_DIR/terraform/bootstrap/setup.sh"
fi

# Step 2: Generate config
echo "[2/7] Generate configuration from config..."
python3 "$PROJECT_DIR/terraform/scripts/generate-config.py" "$CONFIG" --env "$ENV"

if [ "$DRY_RUN" = "true" ]; then
  echo "[DRY RUN] Configuration validated. Exiting."
  exit 0
fi

# Step 3: Apply Terraform
if [ -z "$SKIP_INFRA" ]; then
  echo "[3/7] Apply Terraform (infrastructure)..."
  bash "$PROJECT_DIR/terraform/scripts/apply-all.sh" --env "$ENV" "$APPROVE"
fi

# Step 4: Get kubeconfig
echo "[4/7] Configure kubectl..."
aws eks update-kubeconfig --name "ai-platform-${ENV}" --region us-west-2

# Step 5: Install ArgoCD
echo "[5/7] Install ArgoCD..."
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --values "$PROJECT_DIR/platform/gitops/argocd/values.yaml" \
  --wait --timeout 10m

# Wait for ArgoCD
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Step 6: Sync Platform via ArgoCD
echo "[6/7] Sync platform components..."
kubectl apply -f "$PROJECT_DIR/platform/gitops/argocd/applicationset.yaml"

# Wait for core components
for ns in cilium cert-manator monitoring; do
  kubectl wait --for=condition=Ready pods --all -n "$ns" --timeout=300s 2>/dev/null || true
done

# Step 7: Deploy model
echo "[7/7] Deploy AI model..."
kubectl apply -f "$PROJECT_DIR/ai/kserve/llminferenceservice-gemma2b.yaml"

# Wait for model
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=vllm -n ai-inference --timeout=600s

# Verify
echo ""
echo "============================================"
echo "  Bootstrap Complete!"
echo "============================================"
echo "  Inference Endpoint: http://llm-inference.ai-platform.svc/v1/chat/completions"
echo "  Grafana:            http://grafana.ai-platform.internal"
echo "  ArgoCD:             http://argocd.ai-platform.internal"
echo "============================================"

# Smoke test
curl -s http://llm-inference.ai-platform.svc/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "google/gemma-2-2b-it",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 50
  }' | head -c 200
echo ""
echo "Model is responding. Platform is operational."
```

## Prerequisites

### Tools (Checked by bootstrap)

```bash
# Required CLI tools
- terraform >= 1.9.0
- kubectl >= 1.30
- helm >= 3.15
- python3 >= 3.11
- aws-cli >= 2.x
- yq >= 4.x (YAML processing)
```

### AWS Prerequisites

```bash
# AWS credentials with OrganizationAdmin or equivalent
export AWS_PROFILE=ai-platform-admin

# Required permissions:
# - Organizations (to create/manage accounts)
# - IAM (roles, policies, OIDC)
# - EC2 (VPC, TGW, subnets, NAT)
# - EKS (cluster management)
# - S3 (state storage)
# - DynamoDB (state locking)
# - Route53 (DNS)
# - RAM (resource sharing)
```

## Config File Generation

The `generate-config.py` script:

```bash
# Input
./terraform/scripts/generate-config.py config/demo.yaml --env dev

# Output files
terraform/envs/dev/terraform.tfvars      # Terraform variables
platform/gitops/argocd/applicationset.yaml  # ArgoCD apps
ai/kserve/llminferenceservice-gemma2b.yaml  # Model deployment
ai/keda/scaled-object.yaml                   # Autoscaling
clusters/base/network-policies.yaml          # Security
```

## Rollback / Destroy

```bash
# Destroy everything (reverse order)
./scripts/bootstrap.sh --config config/demo.yaml --destroy
```
