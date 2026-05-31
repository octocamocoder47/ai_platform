#!/usr/bin/env bash
set -euo pipefail

# Build Helm Dependencies
# This script runs 'helm dependency update' for all charts that need it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHARTS_DIR="$SCRIPT_DIR/../charts"

echo "=== Building Helm Dependencies ==="

# Umbrella chart
echo ">>> ai-platform (umbrella)"
helm dependency update "$CHARTS_DIR/ai-platform"

# Local subcharts with upstream dependencies
LOCAL_CHARTS_WITH_DEPS=(
  "grafana"
)

for chart in "${LOCAL_CHARTS_WITH_DEPS[@]}"; do
  if [[ -f "$CHARTS_DIR/$chart/Chart.yaml" ]]; then
    echo ">>> $chart"
    helm dependency update "$CHARTS_DIR/$chart"
  fi
done

echo ""
echo "=== Done ==="
echo ""
echo "To install: helm install ai-platform $CHARTS_DIR/ai-platform --values $CHARTS_DIR/ai-platform/values.yaml"
