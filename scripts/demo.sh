#!/usr/bin/env bash
set -euo pipefail

# AI Platform Demo Script
# This script demonstrates the platform's capabilities for interviews.
# Assumes: cluster is running, ArgoCD synced, model deployed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="ai"
MODEL_HOST=""
TOKEN=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
info()  { echo -e "${CYAN}[i]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; }

usage() {
  cat <<EOF
AI Platform Demo Script

Usage: $0 [options]

Options:
  --model-host HOST   Model inference endpoint (required)
  --token TOKEN       Auth token (optional)
  -h, --help           Show this help

Examples:
  $0 --model-host gemma-2b-ai.ai.svc.cluster.local:8000
  $0 --model-host https://ai.example.com/v1
EOF
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --model-host) MODEL_HOST="$2"; shift 2 ;;
      --token)      TOKEN="$2"; shift 2 ;;
      -h|--help)    usage ;;
      *) error "Unknown option: $1"; usage ;;
    esac
  done
  if [[ -z "$MODEL_HOST" ]]; then
    error "Missing --model-host"
    usage
  fi
}

header() {
  local title="$1"
  echo ""
  echo "========================================"
  echo "  $title"
  echo "========================================"
}

# ───── Demo Steps ─────

demo_01_infrastructure() {
  header "1. Platform Infrastructure"
  info "Showing the platform stack..."
  echo ""

  echo ">>> Namespaces:"
  kubectl get ns --show-labels | head -20

  echo ""
  echo ">>> Platform components:"
  kubectl get pods -n platform -l app.kubernetes.io/component

  echo ""
  echo ">>> AI namespace:"
  kubectl get all -n "$NAMESPACE"
}

demo_02_model_deployed() {
  header "2. Model Serving"
  info "Verifying model is deployed and serving..."

  kubectl get inferenceservice -n "$NAMESPACE"
  echo ""
  kubectl get pods -n "$NAMESPACE" -l model=gemma-2b -o wide
}

demo_03_basic_chat() {
  header "3. Basic Chat Completion"
  info "Sending chat completion request..."

  local payload='{
    "model": "gemma-2b",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Explain Kubernetes in one sentence."}
    ],
    "max_tokens": 100,
    "temperature": 0.7
  }'

  local curl_args=(-s -X POST "$MODEL_HOST/v1/chat/completions" \
    -H "Content-Type: application/json")

  if [[ -n "$TOKEN" ]]; then
    curl_args+=(-H "Authorization: Bearer $TOKEN")
  fi

  echo ">>> Request:"
  echo "$payload" | jq .
  echo ""
  echo ">>> Response:"
  curl "${curl_args[@]}" -d "$payload" | jq '.choices[0].message.content'
}

demo_04_streaming() {
  header "4. Streaming Chat Completion"
  info "Demonstrating streaming response..."

  local payload='{
    "model": "gemma-2b",
    "messages": [
      {"role": "user", "content": "Count from 1 to 5."}
    ],
    "max_tokens": 50,
    "stream": true,
    "temperature": 0.7
  }'

  local curl_args=(-s -N -X POST "$MODEL_HOST/v1/chat/completions" \
    -H "Content-Type: application/json")

  if [[ -n "$TOKEN" ]]; then
    curl_args+=(-H "Authorization: Bearer $TOKEN")
  fi

  echo ">>> Streaming response:"
  curl "${curl_args[@]}" -d "$payload" | while IFS= read -r line; do
    if [[ "$line" =~ ^data:\  ]]; then
      content=$(echo "$line" | sed 's/^data: //' | jq -r '.choices[0].delta.content // empty' 2>/dev/null)
      if [[ -n "$content" ]]; then
        echo -n "$content"
      fi
    fi
  done
  echo ""
}

demo_05_autoscaling() {
  header "5. Autoscaling Demo"
  info "Generating load to trigger KEDA autoscaling..."

  # Send concurrent requests to trigger scale-up
  local payload='{
    "model": "gemma-2b",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 10
  }'

  echo ">>> Current replicas:"
  kubectl get pods -n "$NAMESPACE" -l model=gemma-2b --no-headers | wc -l

  echo ""
  echo ">>> Generating load (20 concurrent requests)..."
  for i in $(seq 1 20); do
    curl -s -X POST "$MODEL_HOST/v1/chat/completions" \
      -H "Content-Type: application/json" \
      ${TOKEN:+-H "Authorization: Bearer $TOKEN"} \
      -d "$payload" > /dev/null 2>&1 &
  done
  wait

  echo ""
  echo ">>> Waiting 30s for KEDA to react..."
  sleep 30

  echo ">>> Replicas after load:"
  kubectl get pods -n "$NAMESPACE" -l model=gemma-2b --no-headers | wc -l

  echo ""
  echo ">>> KEDA ScaledObject status:"
  kubectl get scaledobject -n "$NAMESPACE" -o yaml | grep -A5 "readyReplicaCount\|currentReplicaCount\|desiredReplicaCount"
}

demo_06_observability() {
  header "6. Observability"
  info "Showing monitoring stack..."

  echo ">>> Prometheus targets:"
  kubectl get servicemonitors --all-namespaces | head -10

  echo ""
  echo ">>> Grafana dashboards:"
  kubectl get configmap -n monitoring grafana-dashboards -o yaml | grep -c "json:"

  echo ""
  echo ">>> Recent inference metrics:"
  kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
  PF_PID=$!
  sleep 2
  curl -s "http://localhost:9090/api/v1/query?query=sum(rate(vllm:requests_total[5m]))" | jq '.data.result[]'
  kill $PF_PID 2>/dev/null || true
}

demo_07_gitops() {
  header "7. GitOps (ArgoCD)"
  info "Showing ArgoCD application status..."

  echo ">>> ArgoCD apps:"
  kubectl get applications -n argocd -o wide | head -15

  echo ""
  echo ">>> Sync status:"
  for app in $(kubectl get applications -n argocd --no-headers -o name); do
    echo "  $app: $(kubectl get $app -n argocd -o jsonpath='{.status.sync.status}')"
  done
}

demo_08_cleanup() {
  header "8. Cleanup"
  info "Resources created during demo can be cleaned up..."
  echo ">>> To tear down:"
  echo "  make destroy CONFIG=config/demo.yaml ENV=dev"
  echo ""
  echo ">>> Or destroy specific resources:"
  echo "  kubectl delete inferenceservice -n $NAMESPACE --all"
  echo "  kubectl delete pods -n $NAMESPACE \$(kubectl get pods -n $NAMESPACE -o name | head -5)"
}

# ───── Main ─────

main() {
  parse_args "$@"

  echo ""
  echo "╔══════════════════════════════════════════╗"
  echo "║   AI Platform — Live Demo                ║"
  echo "║   ${MODEL_HOST}         ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""

  demo_01_infrastructure
  demo_02_model_deployed
  demo_03_basic_chat
  demo_04_streaming
  demo_05_autoscaling
  demo_06_observability
  demo_07_gitops
  demo_08_cleanup

  echo ""
  echo "╔══════════════════════════════════════════╗"
  echo "║   Demo Complete                          ║"
  echo "╚══════════════════════════════════════════╝"
}

main "$@"
