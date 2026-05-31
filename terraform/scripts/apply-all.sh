#!/bin/bash
# =============================================================================
# Apply Terraform in dependency order across all accounts and clouds.
# =============================================================================
# Usage: ./apply-all.sh --env dev [--auto-approve] [--target TARGET]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$SCRIPT_DIR/../envs"
ENV="dev"
APPROVE=""
TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV="$2"; shift 2 ;;
    --auto-approve) APPROVE="-auto-approve"; shift ;;
    --target) TARGET="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "============================================"
echo "  Terraform Apply All — Environment: $ENV"
echo "============================================"

apply_env() {
  local dir="$1"
  local name="$2"
  echo ""
  echo "──> Applying: $name ($dir)"

  cd "$dir"
  terraform init -upgrade > /dev/null 2>&1
  terraform workspace select "$ENV" 2>/dev/null || terraform workspace new "$ENV"
  terraform apply $APPROVE

  if [ $? -ne 0 ]; then
    echo "ERROR: $name failed!"
    exit 1
  fi
  echo "──> Complete: $name"
}

# Order: Network → Shared Services → Workload → GCP → Cross-Cloud
if [ -z "$TARGET" ] || [ "$TARGET" == "bootstrap" ]; then
  # Bootstrap is run separately via setup.sh
  echo "Skipping bootstrap (run terraform/bootstrap/setup.sh separately)"
fi

if [ -z "$TARGET" ] || [ "$TARGET" == "network" ]; then
  # Network account (hub) runs from the env dir with specific account role
  apply_env "$ENV_DIR/$ENV" "aws-network" "TF_VAR_account_role=hub" \
    || echo "Network account not configured, skipping"
fi

if [ -z "$TARGET" ] || [ "$TARGET" == "workload" ]; then
  apply_env "$ENV_DIR/$ENV" "aws-workload" "TF_VAR_account_role=spoke" \
    || echo "Workload account not configured, skipping"
fi

if [ -z "$TARGET" ] || [ "$TARGET" == "gcp" ]; then
  apply_env "$ENV_DIR/$ENV" "gcp" "TF_VAR_gcp_enabled=true" \
    || echo "GCP not configured, skipping"
fi

echo ""
echo "============================================"
echo "  All Terraform applies complete!"
echo "============================================"
echo ""
echo "To get kubeconfig:"
echo "  aws eks update-kubeconfig --name ai-platform-$ENV --region us-west-2"
