#!/bin/bash
# =============================================================================
# Bootstrap: Create Terraform backend infrastructure (S3 + DynamoDB)
# =============================================================================
# Run this ONCE per environment before any other Terraform operations.
#
# Usage:
#   ./setup.sh [--env dev] [--region us-west-2] [--bucket-name BUCKET]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV="${1:-dev}"
REGION="${AWS_REGION:-us-west-2}"
BUCKET_NAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)         ENV="$2"; shift 2 ;;
    --region)      REGION="$2"; shift 2 ;;
    --bucket-name) BUCKET_NAME="$2"; shift 2 ;;
    *) shift ;;
  esac
done

echo "============================================"
echo "  Bootstrap: Terraform Backend Setup"
echo "  Environment: $ENV"
echo "  Region:      $REGION"
echo "============================================"

# Initialize Terraform
cd "$SCRIPT_DIR"
terraform init

# Apply
terraform apply \
  -var="environment=$ENV" \
  -var="bucket_name=$BUCKET_NAME" \
  -auto-approve

echo ""
echo "Bootstrap complete!"
echo "State Bucket:  $(terraform output -raw state_bucket)"
echo "DynamoDB Lock: $(terraform output -raw dynamodb_table)"
echo "Region:        $REGION"
