# AI Platform Architecture

> **Source of Truth** — This document defines the overall architecture of the AI Platform.
> Last updated: 2026-05-31

## Table of Contents

1. [Architecture Philosophy](#architecture-philosophy)
2. [Layered Architecture](#layered-architecture)
3. [Component Map](#component-map)
4. [Data Flow](#data-flow)
5. [Config-Driven Design](#config-driven-design)
6. [Multi-Cloud / Cross-Account Strategy](#multi-cloud--cross-account-strategy)
7. [Key Design Decisions](#key-design-decisions)
8. [Related Documents](#related-documents)

---

## Architecture Philosophy

### Principles

| # | Principle | Description |
|---|-----------|-------------|
| 1 | **Everything as Code** | Infrastructure, configuration, policies, and documentation are all defined as code in Git. Zero manual steps. |
| 2 | **Config-Driven** | A single YAML configuration file determines what runs, where it runs, and how it behaves. |
| 3 | **Loose Coupling** | Every component is independently deployable, replaceable, and testable. Components communicate through well-defined APIs. |
| 4 | **Cloud-Agnostic Core** | Platform components are Kubernetes-native Helm charts. Cloud-specific logic is isolated in Terraform modules. |
| 5 | **Default-Deny Security** | Nothing is open by default. Networking, IAM, and policies start from zero and are explicitly allowed. |
| 6 | **Progressive Complexity** | Start simple (single cluster, one model) and scale up (multi-cloud, distributed inference) by changing config. |
| 7 | **GitOps Reconciliation** | ArgoCD owns all Kubernetes resources. The cluster state always matches Git. |

### Target State

```
Single Config File
       │
       │ drives
       ▼
┌─────────────────────────────────────────────────────────────┐
│                  Terraform (Infrastructure)                   │
│  Provisions: VPCs, EKS/GKE, IAM, DNS, VPN, S3, ECR          │
│  Orchestrates: Multi-account, multi-region, multi-cloud      │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            │ kubeconfig
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  ArgoCD (Platform Services)                   │
│  Owns: networking, security, observability, storage, ai      │
│  Syncs: Helm charts from Git → running state on cluster      │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            │ model deployment
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  KServe + vLLM (Model Serving)                │
│  Deploys: Gemma 2B as LLMInferenceService                    │
│  Routes: Gateway API + Inference Extension + Envoy           │
│  Scales: KEDA on vLLM metrics (queue depth, KV cache)        │
└─────────────────────────────────────────────────────────────┘
```

---

## Layered Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│  L6 — AI APPLICATIONS                                                   │
│  ┌────────────┐  ┌────────────┐  ┌──────────────┐                     │
│  │ Chat API   │  │ RAG Service│  │ Batch Inf.   │                     │
│  │ (OpenAI    │  │ (Qdrant +  │  │ (Async Jobs) │                     │
│  │  Compat)   │  │ Embeddings)│  │              │                     │
│  └────────────┘  └────────────┘  └──────────────┘                     │
├────────────────────────────────────────────────────────────────────────┤
│  L5 — MODEL SERVING & ROUTING                                           │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ KServe     │  │ LLMInfSvc    │  │ Gateway API  │  │ Envoy AI     │ │
│  │ (Operator) │  │ (CRD)        │  │ + Inference  │  │ Gateway      │ │
│  │            │  │              │  │   Extension  │  │ (Rate Limit) │ │
│  └────────────┘  └──────────────┘  └──────────────┘  └──────────────┘ │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────┐                    │
│  │ vLLM       │  │ vLLM Router  │  │ llm-d (EPP)  │                    │
│  │ (Engine)   │  │ (KV-Cache    │  │ (Disagg.     │                    │
│  │            │  │  Routing)    │  │  Scheduling) │                    │
│  └────────────┘  └──────────────┘  └──────────────┘                    │
├────────────────────────────────────────────────────────────────────────┤
│  L4 — AI INFRASTRUCTURE & OPERATORS                                     │
│  ┌──────────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ NVIDIA GPU   │  │ Kueue    │  │ KEDA     │  │ Volcano  │          │
│  │ Operator     │  │ (GPU     │  │ (Event-  │  │ (Gang    │          │
│  │ (Driver,MIG) │  │  Batch)  │  │  Driven  │  │  Sched)  │          │
│  └──────────────┘  └──────────┘  └──────────┘  └──────────┘          │
├────────────────────────────────────────────────────────────────────────┤
│  L3 — PLATFORM SERVICES (Managed by ArgoCD)                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │ Cilium   │  │ Gateway  │  │ Kyverno  │  │ External │  │ Vault   │ │
│  │ (CNI +   │  │ API      │  │ (Policy) │  │ Secrets  │  │ (Secrets│ │
│  │ NetPol)  │  │ (Ingress)│  │          │  │          │  │  Store) │ │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └─────────┘ │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │ Prometheus│  │ Grafana  │  │ Loki     │  │ Tempo    │  │ OpenCost│ │
│  │ + Alert  │  │ (Dash)   │  │ (Logs)   │  │(Traces)  │  │ (Cost)  │ │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └─────────┘ │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                              │
│  │ CloudNati│  │ Valkey   │  │ Velero   │                              │
│  │ vePG     │  │ (Redis)  │  │ (Backup) │                              │
│  └──────────┘  └──────────┘  └──────────┘                              │
├────────────────────────────────────────────────────────────────────────┤
│  L2 — KUBERNETES CLUSTER                                                │
│  ┌─────────────────────────────┐  ┌──────────────────────────────┐     │
│  │ EKS Control Plane           │  │ GKE Control Plane (opt)      │     │
│  │ Version: 1.31               │  │ Version: 1.31                │     │
│  └─────────────────────────────┘  └──────────────────────────────┘     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │ System   │  │ GPU-Inf  │  │ GPU-     │  │ Karpenter│              │
│  │ NodeGrp  │  │ erence   │  │ Batch    │  │ (Node    │              │
│  │ (CPU)    │  │ (T4/A10) │  │ (H100)   │  │  Auto)   │              │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘              │
├────────────────────────────────────────────────────────────────────────┤
│  L1 — INFRASTRUCTURE (Terraform)                                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │ VPC +    │  │ Transit  │  │ S3 / GCS │  │ ECR /    │  │ IAM +   │ │
│  │ Subnets  │  │ Gateway  │  │ (State+  │  │ Artifact │  │ OIDC    │ │
│  │ + NAT    │  │ + VPN    │  │  Data)   │  │ Registry │  │ (IRSA)  │ │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └─────────┘ │
├────────────────────────────────────────────────────────────────────────┤
│  L0 — CI/CD & DEVELOPER EXPERIENCE                                      │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐       │
│  │ GitHub     │  │ Trivy +    │  │ Cosign +   │  │ Renovate   │       │
│  │ Actions    │  │ Syft       │  │ SBOM       │  │ (Deps)     │       │
│  └────────────┘  └────────────┘  └────────────┘  └────────────┘       │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Component Map

| Layer | Component | Role | Config-Driven? | Replaceable? |
|-------|-----------|------|:---:|:---:|
| L6 | Chat API | OpenAI-compatible inference endpoint | Y | Y |
| L6 | RAG Service | Retrieval-augmented generation | Y | Y |
| L6 | Batch Inference | Async job-based inference | Y | Y |
| L5 | KServe | K8s-native model serving framework | Y | N (core) |
| L5 | vLLM | High-performance inference engine | Y | Y (SGLang, TGI) |
| L5 | LLMInferenceService (CRD) | GenAI-specific serving API | Y | N (core) |
| L5 | Gateway API + Inference Ext | K8s-native, AI-aware routing | Y | Y (Istio) |
| L5 | Envoy AI Gateway | Token-based rate limiting | Y | Y |
| L5 | llm-d (EPP) | Distributed inference scheduler | Y | Y (Ray Serve) |
| L4 | NVIDIA GPU Operator | GPU driver, runtime, MIG | Y | Y (intel, amd) |
| L4 | Kueue | GPU batch/job scheduling | Y | Y (Volcano) |
| L4 | KEDA | Event-driven autoscaling | Y | Y (HPA) |
| L4 | Volcano | Gang scheduling for training | Y | Y (Kueue) |
| L3 | Cilium | CNI + NetworkPolicies + Hubble | Y | Y (Calico) |
| L3 | ArgoCD | GitOps continuous delivery | Y | Y (Flux) |
| L3 | Kyverno | Policy engine | Y | Y (OPA) |
| L3 | External Secrets | Cloud secret sync | Y | Y (Vault) |
| L3 | HashiCorp Vault | Secrets management | Y | Y (AWS SM) |
| L3 | cert-manager | TLS certificates | Y | Y |
| L3 | Prometheus + Grafana | Metrics + dashboards | Y | Y (Mimir) |
| L3 | Loki | Log aggregation | Y | Y (Elastic) |
| L3 | Tempo | Distributed tracing | Y | Y (Jaeger) |
| L3 | OpenCost | GPU cost attribution | Y | Y (Kubecost) |
| L3 | CloudNativePG | PostgreSQL operator | Y | Y (Crunchy) |
| L3 | Valkey | Redis-compatible cache | Y | Y (Redis) |
| L3 | Velero | Backup/restore | Y | Y |
| L2 | EKS | Managed K8s (primary) | Y | Y (GKE, AKS) |
| L2 | Karpenter | Node autoscaling | Y | Y (CAS) |
| L1 | Terraform | Infrastructure provisioning | Y | Y (Crossplane) |
| L0 | GitHub Actions | CI/CD pipelines | Y | Y (GitLab CI) |
| L0 | Trivy | Vulnerability scanning | Y | Y (Snyk) |
| L0 | Cosign | Container signing | Y | Y (Notation) |

---

## Data Flow

### Request Flow (Runtime)

```
┌──────────┐     ┌──────────────┐     ┌───────────────┐     ┌───────────┐
│ Client   │────▶│ Route53 /    │────▶│ Envoy AI      │────▶│ Gateway   │
│ (curl/   │     │ ALB (L7)     │     │ Gateway       │     │ API HTTP  │
│  app)    │     │              │     │ (Rate Limit)  │     │ Route     │
└──────────┘     └──────────────┘     └───────────────┘     └─────┬─────┘
                                                                    │
                                          ┌─────────────────────────┤
                                          │                         │
                                    ┌─────▼─────┐            ┌──────▼──────┐
                                    │ KServe     │            │ llm-d (EPP) │
                                    │ isvc       │            │ KV-cache    │
                                    │ (basic)    │            │ aware       │
                                    └─────┬─────┘            └──────┬──────┘
                                          │                         │
                                    ┌─────▼─────┐            ┌──────▼──────┐
                                    │ vLLM Pod  │            │ Prefill     │
                                    │ (TP=1)    │            │ Pool (H100) │
                                    └───────────┘            └──────┬──────┘
                                                                    │
                                                              ┌─────▼──────┐
                                                              │ Decode Pool│
                                                              │ (A100)     │
                                                              └────────────┘
```

### Deployment Flow (Build Time)

```
Config Change
    │
    ▼
Git Push → PR → CI Validation → Merge → Git Tag
    │
    ├──▶ Terraform: Plan → Apply (infra changes)
    │
    └──▶ ArgoCD: Detects drift → Syncs Helm charts
         │
         ├──▶ Platform components (Cilium, Prometheus, etc.)
         ├──▶ AI operators (GPU Operator, KServe, KEDA)
         └──▶ Model deployment (LLMInferenceService)
```

---

## Config-Driven Design

See [02-config-driven-design.md](02-config-driven-design.md) for the full specification.

The platform is controlled by a single YAML configuration file. Key sections:

```yaml
spec:
  providers:       # Which clouds, which accounts
  environment:     # dev, staging, prod
  networking:      # Topology, cross-account, cross-cloud
  kubernetes:      # Cluster type, version, node groups
  inference:       # Model, serving config, autoscaling
  components:      # Which platform components to deploy
  observability:   # Metrics, logs, traces, alerting
  security:        # Policies, secrets, signing
  cicd:            # CI/CD provider and settings
```

Multiple config files can exist (e.g., `config/demo.yaml`, `config/production.yaml`).

---

## Multi-Cloud / Cross-Account Strategy

See [04-networking-topology.md](04-networking-topology.md) for detailed networking design.

### Account Structure (AWS)

```
┌──────────────────────────────────────────────────────────────────┐
│ Organization (AWS Organizations)                                  │
│                                                                   │
│  ┌────────────────┐  ┌────────────────┐  ┌──────────────────┐   │
│  │ Network        │  │ Workload (Dev) │  │ Workload (Prod)  │   │
│  │ Account (Hub)  │  │ (Spoke)        │  │ (Spoke)          │   │
│  │                │  │                │  │                  │   │
│  │ • TGW          │◀─│ • VPC          │  │ • VPC            │   │
│  │ • Route53 Zone │  │ • EKS (dev)    │  │ • EKS (prod)     │   │
│  │ • CloudWatch   │  │ • Dev services │  │ • Prod services  │   │
│  │ • VPN Endpoints│  │ • Dev models   │  │ • Prod models    │   │
│  └────────────────┘  └────────────────┘  └──────────────────┘   │
│                                                                   │
│  ┌────────────────┐  ┌────────────────┐                          │
│  │ Shared Svcs    │  │ Security       │                          │
│  │ Account        │  │ Account        │                          │
│  │                │  │                │                          │
│  │ • Harbor       │  │ • CloudTrail   │                          │
│  │ • Vault        │  │ • GuardDuty    │                          │
│  │ • Artifacts    │  │ • Audit Logs   │                          │
│  └────────────────┘  └────────────────┘                          │
└──────────────────────────────────────────────────────────────────┘
```

### Multi-Cloud Extension

```
┌─────────────┐          Site-to-Site VPN          ┌─────────────┐
│  AWS        │◀══════════════════════════════════▶│  GCP        │
│  (us-west-2)│     or Private Interconnect         │  (us-central)│
│             │                                     │             │
│  EKS Cluster│    BGP + Route Propagation          │  GKE Cluster│
│  Pod CIDR   │◀══════════════════════════════════▶│  Pod CIDR   │
└─────────────┘                                     └─────────────┘
```

---

## Key Design Decisions

| ID | Decision | Rationale | ADR |
|:--:|----------|-----------|:---:|
| D01 | Terraform over Crossplane | Broader provider support, remote state, portfolio familiarity | [ADR-001](ADR/001-use-terraform-over-crossplane.md) |
| D02 | vLLM over TGI | 70k+ stars, 100+ model architectures, hardware-agnostic | [ADR-002](ADR/002-vllm-as-inference-engine.md) |
| D03 | KServe over standalone vLLM | GenAI-first CRD (LLMInferenceService), canary, scale-to-zero | [ADR-003](ADR/003-kserve-for-model-serving.md) |
| D04 | llm-d over Ray Serve | Disaggregated prefill/decode, KV-cache-aware routing, CNCF-backed | [ADR-004](ADR/004-llm-d-for-distributed-inference.md) |
| D05 | Cilium over Calico | eBPF-native, Hubble observability, Gateway API support | [ADR-005](ADR/005-cilium-as-cni.md) |
| D06 | Gemma 2B model | Apache 2.0 license, no gated access, small fast iteration | [ADR-006](ADR/006-gemma-2b-model.md) |

---

## Related Documents

| Document | Description |
|----------|-------------|
| [02-config-driven-design.md](02-config-driven-design.md) | Config file specification and all parameters |
| [03-terraform-modules.md](03-terraform-modules.md) | Multi-cloud Terraform module design |
| [04-networking-topology.md](04-networking-topology.md) | Cross-account/cloud networking |
| [05-platform-components.md](05-platform-components.md) | Platform service descriptions |
| [06-ai-serving.md](06-ai-serving.md) | Model serving architecture |
| [07-security.md](07-security.md) | Security architecture |
| [08-observability.md](08-observability.md) | Monitoring, logging, tracing |
| [09-cicd.md](09-cicd.md) | CI/CD pipeline design |
| [10-bootstrap.md](10-bootstrap.md) | One-command deployment |
| [11-phase-plan.md](11-phase-plan.md) | Phased execution roadmap |
| [12-config-examples.md](12-config-examples.md) | Example configurations |
| [TRACKING.md](TRACKING.md) | Progress tracking |
