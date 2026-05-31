# AI Platform Engineering

A production-grade AI platform for deploying and serving Large Language Models (LLMs) on Kubernetes with distributed inference techniques. Demonstrates Platform Engineering, DevOps, MLOps, IaC, GitOps, CI/CD, Security, Observability, and Cloud Architecture.

## Architecture

```
L6: AI Applications       Chat API · RAG Service · Batch Inference
L5: Model Serving          KServe · vLLM · llm-d · Envoy AI Gateway
L4: AI Infrastructure      GPU Operator · Kueue · KEDA
L3: Platform Services      Cilium · ArgoCD · Kyverno · Prometheus · Loki
L2: Kubernetes             EKS / GKE · Karpenter · GPU Node Groups
L1: Infrastructure         Terraform · Multi-account · Multi-cloud
L0: CI/CD                  GitHub Actions · Cosign · Trivy · Renovate
```

## Quick Start

### Prerequisites

- Terraform >= 1.9.0, kubectl, helm, python3, aws-cli
- AWS credentials with sufficient permissions
- HuggingFace token for model access

### One-Command Deploy

```bash
# 1. Copy and edit the demo config
cp config/demo.yaml config/demo.yaml  # Edit with your AWS account ID

# 2. Set required environment variables
export HF_TOKEN="your-huggingface-token"
export AWS_PROFILE="your-aws-profile"

# 3. Deploy everything (Terraform → Helm)
make bootstrap CONFIG=config/demo.yaml
```

Or step by step:

```bash
# 1. Bootstrap Terraform backend
make backend-init

# 2. Validate and generate config + Helm values
make validate
make config-generate

# 3. Provision infrastructure
make apply-all

# 4. Build and install Helm charts
make helm-deps
make helm-install

# 5. Configure kubectl
aws eks update-kubeconfig --name ai-platform-dev --region us-west-2

# 6. Verify inference endpoint
curl http://llm-inference.ai-platform.svc/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "google/gemma-2-2b-it", "messages": [{"role": "user", "content": "Hello"}]}'
```

## Configuration

The platform is entirely config-driven. Edit `config/demo.yaml` to change:

| Section | What It Controls |
|---------|-----------------|
| `providers` | Cloud provider, accounts, multi-cloud toggle |
| `networking` | Topology (single, hub-spoke), cross-account, cross-cloud |
| `kubernetes` | Cluster type, version, GPU node groups, Karpenter |
| `inference` | Model name, serving config, autoscaling metrics |
| `components` | Which platform components to deploy |
| `observability` | Metrics, logging, tracing, alerting |
| `security` | Policies, secrets, signing, scanning |

### Config Examples

| File | Description |
|------|-------------|
| `config/demo.yaml` | Single AWS account, minimal platform |
| `config/multi-account.yaml` | AWS hub-spoke with 4 accounts |
| `config/multi-cloud.yaml` | AWS + GCP with cross-cloud VPN |
| `config/production.yaml` | Full production with all features |

## Repository Structure

```
ai-platform/
├── config/              # Platform configuration YAML files
├── terraform/           # Infrastructure as Code (Terraform)
│   ├── modules/         # Multi-cloud, cross-account modules
│   ├── envs/            # Environment configurations
│   ├── bootstrap/       # S3 + DynamoDB backend setup
│   └── scripts/         # Config generation, apply-all
├── platform/            # Platform services (ArgoCD-managed)
│   ├── gitops/          # ArgoCD configuration
│   ├── networking/      # Cilium, cert-manager, Gateway API
│   ├── security/        # Kyverno, External Secrets, Vault
│   ├── observability/   # Prometheus, Grafana, Loki, Tempo
│   ├── storage/         # CloudNativePG, Valkey, Velero
│   └── cost/            # OpenCost for GPU cost attribution
├── ai/                  # AI-specific infrastructure
│   ├── gpu-operator/    # NVIDIA GPU Operator
│   ├── kserve/          # Model serving framework
│   ├── keda/            # Event-driven autoscaling
│   ├── kueue/           # GPU batch scheduling
│   ├── llm-d/           # Distributed inference (optional)
│   └── gateway/         # Inference Gateway + Envoy AI Gateway
├── apps/                # Sample AI applications
│   ├── chat/            # OpenAI-compatible chat demo
│   └── rag/             # RAG service (WIP)
├── scripts/             # Bootstrap, validation utilities
├── docs/                # Architecture documentation (source of truth)
│   ├── ADR/             # Architecture Decision Records
│   └── TRACKING.md      # Progress tracking
├── clusters/            # Base cluster configuration
└── .github/             # CI/CD workflows
```

## Helm Chart Architecture

Each platform component is a modular Helm chart with config-driven enable/disable toggles:

```
charts/
  ai-platform/           ⬅ Umbrella chart (helm install this)
  ├── Chart.yaml         # 22 dependency conditions
  ├── values.yaml        # All component toggles + overrides
  └── templates/         # Namespaces, platform resources
  gateway-api/           # Gateway API CRDs
  grafana/               # Dashboards + datasources
  llm-d/                 # Distributed inference
  ai-gateway/            # InferenceModel, HTTPRoute, HPA
```

**Toggle any component** in `charts/ai-platform/values.yaml`:
```yaml
vault:
  enabled: false         # Skip Vault entirely
kyverno:
  enabled: true          # Enable Kyverno
  mode: audit            # Start in audit mode
```

Generate from config: `make config-generate ENV=prod` produces `charts/ai-platform/values-generated.yaml`

## Key Technologies

| Category | Tools |
|----------|-------|
| **Inference Engine** | vLLM (PagedAttention, 100+ model architectures) |
| **Model Serving** | KServe v0.17+ (LLMInferenceService CRD) |
| **Distributed Inference** | llm-d (CNCF Sandbox, disaggregated prefill/decode) |
| **GitOps** | ArgoCD |
| **Infrastructure** | Terraform (multi-cloud, cross-account) |
| **GPU Management** | NVIDIA GPU Operator, Kueue |
| **Autoscaling** | KEDA (vLLM metric-based) |
| **CNI** | Cilium (eBPF, Hubble, Gateway API) |
| **Security** | Kyverno, External Secrets, HashiCorp Vault, Cosign, Trivy |
| **Observability** | Prometheus, Grafana, Loki, Tempo, OpenCost |
| **Storage** | CloudNativePG, Valkey, Velero |

## Distributed Inference Architecture

The platform supports 4 progressive deployment patterns:

1. **Single-Node** — 1 GPU, 1 replica (Gemma 2B)
2. **Multi-Replica DP** — N GPUs, N replicas with load balancing
3. **Multi-Node TP** — Split model across GPUs/nodes via tensor parallelism
4. **Disaggregated Prefill/Decode** — Separate compute-heavy prefill from memory-bound decode (llm-d)

## Phases

| Phase | Status | Description |
|:-----:|:------:|-------------|
| 1 | ✅ Complete | Architecture documentation, config schema, ADRs |
| 2 | 🔲 Pending | Terraform modules (all clouds/accounts) |
| 3 | 🔲 Pending | Platform core (ArgoCD, Cilium, Kyverno) |
| 4 | 🔲 Pending | Observability (Prometheus, Grafana, Loki) |
| 5 | 🔲 Pending | AI infrastructure (GPU, KServe, KEDA) |
| 6 | 🔲 Pending | Model serving with autoscaling |
| 7 | 🔲 Pending | Polish, dashboards, runbooks, demo |

See [docs/11-phase-plan.md](docs/11-phase-plan.md) for details.

## Documentation

All documentation is in `docs/` and serves as the source of truth:

| Doc | Description |
|-----|-------------|
| [Architecture](docs/01-architecture.md) | Layered architecture, component map |
| [Config Design](docs/02-config-driven-design.md) | Config schema, processing pipeline |
| [Terraform Modules](docs/03-terraform-modules.md) | Multi-cloud TF design |
| [Networking](docs/04-networking-topology.md) | Cross-account/cloud networking |
| [Platform Components](docs/05-platform-components.md) | Service configurations |
| [AI Serving](docs/06-ai-serving.md) | Distributed inference patterns |
| [Security](docs/07-security.md) | Zero-trust architecture |
| [Observability](docs/08-observability.md) | Metrics, logs, traces |
| [CI/CD](docs/09-cicd.md) | Pipeline design |
| [Bootstrap](docs/10-bootstrap.md) | One-command deploy |
| [Phase Plan](docs/11-phase-plan.md) | Execution roadmap |
| [TRACKING](docs/TRACKING.md) | Progress tracking |

## License

Apache 2.0
