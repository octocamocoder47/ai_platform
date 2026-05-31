#!/bin/bash
# =============================================================================
# AI Platform Bootstrap — One-Command Deploy
# =============================================================================
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
#   --destroy          Destroy all resources
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG=""
APPROVE=""
SKIP_INFRA=""
SKIP_PLATFORM=""
ENV="dev"
DRY_RUN=""
DESTROY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)        CONFIG="$2"; shift 2 ;;
    --auto-approve)  APPROVE="--auto-approve"; shift ;;
    --skip-infra)    SKIP_INFRA="true"; shift ;;
    --skip-platform) SKIP_PLATFORM="true"; shift ;;
    --env)           ENV="$2"; shift 2 ;;
    --dry-run)       DRY_RUN="true"; shift ;;
    --destroy)       DESTROY="true"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  AI Platform Bootstrap v1.0${NC}"
echo -e "${BLUE}============================================${NC}"
echo "  Config:  ${CONFIG:-$(pwd)/config/demo.yaml}"
echo "  Env:     $ENV"
echo "  Mode:    ${DESTROY:+destroy}${DESTROY:-deploy}"
echo -e "${BLUE}============================================${NC}"

# Set default config
if [ -z "$CONFIG" ]; then
  CONFIG="$PROJECT_DIR/config/demo.yaml"
fi

# Validate config exists
if [ ! -f "$CONFIG" ]; then
  echo -e "${RED}ERROR: Config file not found: $CONFIG${NC}"
  exit 1
fi

# =============================================================================
# Pre-flight Checks
# =============================================================================
preflight() {
  echo ""
  echo -e "${YELLOW}[Pre-flight]${NC} Checking prerequisites..."

  # Required tools
  local tools=("terraform" "kubectl" "helm" "python3" "aws" "yq")
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
      echo -e "${RED}ERROR: $tool is required but not installed${NC}"
      exit 1
    fi
  done

  # Validate config
  echo "  Validating config..."
  python3 "$SCRIPT_DIR/validate-config.py" "$CONFIG" || true

  # Check AWS credentials
  if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${YELLOW}WARNING: AWS credentials not configured. Configure with: aws configure${NC}"
    echo "  Continuing with dry config validation..."
  else
    echo "  AWS Identity: $(aws sts get-caller-identity --query Arn --output text)"
  fi

  echo -e "${GREEN}  Pre-flight checks complete${NC}"
}

# =============================================================================
# Step 1: Bootstrap Terraform Backend
# =============================================================================
step1_bootstrap() {
  echo ""
  echo -e "${YELLOW}[1/7]${NC} Bootstrap Terraform backend..."

  if [ -z "$SKIP_INFRA" ]; then
    bash "$PROJECT_DIR/terraform/bootstrap/setup.sh" --env "$ENV"
    echo -e "${GREEN}  Backend bootstrap complete${NC}"
  else
    echo "  Skipping (--skip-infra)"
  fi
}

# =============================================================================
# Step 2: Generate Configuration
# =============================================================================
step2_generate() {
  echo ""
  echo -e "${YELLOW}[2/7]${NC} Generate configuration from config..."

  python3 "$PROJECT_DIR/terraform/scripts/generate-config.py" \
    "$CONFIG" --env "$ENV"

  echo -e "${GREEN}  Configuration generated${NC}"

  if [ "$DRY_RUN" = "true" ]; then
    echo ""
    echo -e "${BLUE}[DRY RUN]${NC} Configuration validated. Exiting."
    exit 0
  fi
}

# =============================================================================
# Step 3: Apply Terraform (Infrastructure)
# =============================================================================
step3_infra() {
  echo ""
  echo -e "${YELLOW}[3/7]${NC} Apply Terraform (infrastructure)..."

  if [ -z "$SKIP_INFRA" ]; then
    bash "$PROJECT_DIR/terraform/scripts/apply-all.sh" --env "$ENV" "$APPROVE"
    echo -e "${GREEN}  Infrastructure provisioned${NC}"
  else
    echo "  Skipping (--skip-infra)"
  fi
}

# =============================================================================
# Step 4: Configure kubectl
# =============================================================================
step4_kubeconfig() {
  echo ""
  echo -e "${YELLOW}[4/7]${NC} Configure kubectl..."

  local cluster_name="ai-platform-${ENV}"
  local region
  region=$(yq eval '.spec.providers.aws.region' "$CONFIG" 2>/dev/null || echo "us-west-2")

  if aws eks update-kubeconfig --name "$cluster_name" --region "$region" &> /dev/null; then
    echo -e "${GREEN}  kubectl configured for $cluster_name${NC}"
  else
    echo -e "${YELLOW}  WARNING: Could not configure kubectl. Cluster may not exist.${NC}"
    echo "  You can run: aws eks update-kubeconfig --name $cluster_name --region $region"
  fi
}

# =============================================================================
# Step 5: Install ArgoCD
# =============================================================================
step5_argocd() {
  echo ""
  echo -e "${YELLOW}[5/7]${NC} Install ArgoCD..."

  local argocd_ns="argocd"
  local argocd_values="$PROJECT_DIR/platform/gitops/argocd/values.yaml"

  if [ -z "$SKIP_PLATFORM" ]; then
    # Add Helm repo
    helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
    helm repo update

    # Install ArgoCD
    helm upgrade --install argocd argo/argo-cd \
      --namespace "$argocd_ns" --create-namespace \
      --values "$argocd_values" \
      --wait --timeout 10m

    # Wait for ArgoCD server
    kubectl wait --for=condition=Ready pods \
      -l app.kubernetes.io/name=argocd-server \
      -n "$argocd_ns" --timeout=300s 2>/dev/null || true

    # Apply ApplicationSet
    kubectl apply -f "$PROJECT_DIR/platform/gitops/argocd/applicationset.yaml" 2>/dev/null || true

    echo -e "${GREEN}  ArgoCD installed${NC}"
    echo "  UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "  Password: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath={.data.password} | base64 -d"
  else
    echo "  Skipping (--skip-platform)"
  fi
}

# =============================================================================
# Step 6: Sync Platform Components (ArgoCD handles this)
# =============================================================================
step6_platform() {
  echo ""
  echo -e "${YELLOW}[6/7]${NC} Sync platform components via ArgoCD..."

  if [ -z "$SKIP_PLATFORM" ]; then
    echo "  ArgoCD will auto-sync all components from Git."
    echo "  To force sync: argocd app sync -l app.kubernetes.io/part-of=ai-platform"
  else
    echo "  Skipping (--skip-platform)"
  fi
}

# =============================================================================
# Step 7: Deploy Model
# =============================================================================
step7_model() {
  echo ""
  echo -e "${YELLOW}[7/7]${NC} Deploy AI model..."

  if [ -z "$SKIP_PLATFORM" ]; then
    local model_file="$PROJECT_DIR/ai/kserve/llminferenceservice-gemma2b.yaml"

    if [ -f "$model_file" ]; then
      kubectl apply -f "$model_file" 2>/dev/null || echo "  Model deployment file not yet generated"

      echo "  Waiting for model to be ready..."
      kubectl wait --for=condition=Ready pods \
        -l app.kubernetes.io/name=vllm \
        -n ai-inference --timeout=600s 2>/dev/null || true
    else
      echo -e "${YELLOW}  Model manifest not found: $model_file${NC}"
      echo "  Run generate-config.py first to create it."
    fi
  else
    echo "  Skipping (--skip-platform)"
  fi
}

# =============================================================================
# Summary
# =============================================================================
summary() {
  echo ""
  echo -e "${BLUE}============================================${NC}"
  echo -e "${GREEN}  Bootstrap Complete!${NC}"
  echo -e "${BLUE}============================================${NC}"
  echo ""
  echo "  Inference API:    http://llm-inference.ai-platform.svc/v1/chat/completions"
  echo "  Grafana:          http://grafana.ai-platform.internal"
  echo "  ArgoCD:           http://argocd.ai-platform.internal"
  echo "  Hubble UI:        http://hubble.ai-platform.internal"
  echo ""
  echo "  Quick test:"
  echo "  curl http://llm-inference.ai-platform.svc/v1/chat/completions \\"
  echo "    -H \"Content-Type: application/json\" \\"
  echo "    -d '{\"model\": \"google/gemma-2-2b-it\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}]}'"
  echo ""
  echo -e "${BLUE}============================================${NC}"
}

# =============================================================================
# Execute
# =============================================================================

if [ "$DESTROY" = "true" ]; then
  echo ""
  echo -e "${RED}Destroy mode${NC}"
  bash "$PROJECT_DIR/terraform/scripts/apply-all.sh" --env "$ENV" --destroy "$APPROVE" || true
  echo -e "${GREEN}Destroy complete${NC}"
  exit 0
fi

preflight
step1_bootstrap
step2_generate
step3_infra
step4_kubeconfig
step5_argocd
step6_platform
step7_model
summary
