# Phase Execution Plan

> **Source of Truth** — Phased implementation roadmap with milestones, deliverables, and progress.
> Last updated: 2026-05-31

## Phase Overview

```
Phase 1: Foundation     ████████████████░░░░░░  80%  Core structure + docs
Phase 2: Terraform      ░░░░░░░░░░░░░░░░░░░░   0%  Multi-cloud TF modules
Phase 3: Platform Core  ░░░░░░░░░░░░░░░░░░░░   0%  ArgoCD + Cilium + Security
Phase 4: Observability  ░░░░░░░░░░░░░░░░░░░░   0%  Prometheus + Grafana + Loki
Phase 5: AI Infra       ░░░░░░░░░░░░░░░░░░░░   0%  GPU Operator + KServe + KEDA
Phase 6: Model Serving  ░░░░░░░░░░░░░░░░░░░░   0%  Gemma 2B + Distributed Inf.
Phase 7: Polish         ░░░░░░░░░░░░░░░░░░░░   0%  Dashboards + Runbooks + Demo
```

---

## Phase 1: Foundation (Current)

**Goal**: Establish project structure, architecture documentation, and config-driven design.

### Deliverables

| Item | Status | File |
|:----:|:------:|------|
| Directory structure | ✅ Done | Project root |
| Architecture doc | ✅ Done | `docs/01-architecture.md` |
| Config-driven design | ✅ Done | `docs/02-config-driven-design.md` |
| Terraform module design | ✅ Done | `docs/03-terraform-modules.md` |
| Networking topology | ✅ Done | `docs/04-networking-topology.md` |
| Platform components | ✅ Done | `docs/05-platform-components.md` |
| AI serving architecture | ✅ Done | `docs/06-ai-serving.md` |
| Security architecture | ✅ Done | `docs/07-security.md` |
| Observability design | ✅ Done | `docs/08-observability.md` |
| CI/CD pipeline | ✅ Done | `docs/09-cicd.md` |
| Bootstrap design | ✅ Done | `docs/10-bootstrap.md` |
| Phase plan | ✅ Done | `docs/11-phase-plan.md` |
| Config examples | 🔲 Pending | `docs/12-config-examples.md` |
| TRACKING.md | 🔲 Pending | `docs/TRACKING.md` |
| ADR-001: Terraform | 🔲 Pending | `docs/ADR/001-use-terraform-over-crossplane.md` |
| ADR-002: vLLM | 🔲 Pending | `docs/ADR/002-vllm-as-inference-engine.md` |
| ADR-003: KServe | 🔲 Pending | `docs/ADR/003-kserve-for-model-serving.md` |
| ADR-004: llm-d | 🔲 Pending | `docs/ADR/004-llm-d-for-distributed-inference.md` |
| ADR-005: Cilium | 🔲 Pending | `docs/ADR/005-cilium-as-cni.md` |
| ADR-006: Gemma 2B | 🔲 Pending | `docs/ADR/006-gemma-2b-model.md` |

### Completion Criteria

- [x] All directory structure created
- [x] Architecture documented with all 6 layers
- [x] Config schema defined with all sections
- [ ] Config example files created (demo, multi-account, multi-cloud, production)
- [ ] ADRs documented for key decisions
- [ ] TRACKING.md created

---

## Phase 2: Terraform Modules (Weeks 1-2)

**Goal**: Build all Terraform modules for multi-cloud, cross-account infrastructure.

### Deliverables

| Module | File | Priority |
|--------|------|:--------:|
| AWS Network (VPC, TGW, subnets, NAT, endpoints) | `terraform/modules/aws/network/` | P0 |
| AWS EKS (cluster, node groups, Karpenter, IRSA) | `terraform/modules/aws/eks/` | P0 |
| AWS IRSA (IAM roles per service account) | `terraform/modules/aws/irsa/` | P0 |
| AWS Storage (S3 buckets, EFS) | `terraform/modules/aws/storage/` | P0 |
| AWS DNS (Route53 zones, records) | `terraform/modules/aws/dns/` | P0 |
| AWS Registry (ECR repositories) | `terraform/modules/aws/registry/` | P0 |
| GCP Network (Shared VPC, Cloud VPN) | `terraform/modules/gcp/network/` | P1 |
| GCP GKE (cluster, node pools, Workload Identity) | `terraform/modules/gcp/gke/` | P1 |
| GCP Storage (GCS buckets) | `terraform/modules/gcp/storage/` | P1 |
| GCP DNS (Cloud DNS) | `terraform/modules/gcp/dns/` | P1 |
| Cross-Cloud VPN (AWS ↔ GCP IPSec) | `terraform/modules/cross-cloud/vpn/` | P1 |
| Cross-Cloud DNS (Route53 ↔ Cloud DNS sync) | `terraform/modules/cross-cloud/dns/` | P2 |
| Cross-Cloud Monitoring (federation) | `terraform/modules/cross-cloud/monitoring/` | P2 |
| Bootstrap (S3 + DynamoDB) | `terraform/bootstrap/` | P0 |
| Env: Dev | `terraform/envs/dev/` | P0 |
| Env: Staging | `terraform/envs/staging/` | P1 |
| Env: Prod | `terraform/envs/prod/` | P1 |
| Config generator | `terraform/scripts/generate-config.py` | P0 |
| Apply all script | `terraform/scripts/apply-all.sh` | P0 |

### Completion Criteria

- [ ] `terraform/modules/aws/network/` — VPC, subnets, TGW, NAT, endpoints (all code)
- [ ] `terraform/modules/aws/eks/` — Cluster, Karpenter, IRSA, node groups
- [ ] `terraform/envs/dev/` — Calls all modules, works end-to-end
- [ ] `terraform/bootstrap/setup.sh` — Creates S3 + DynamoDB
- [ ] `terraform/scripts/generate-config.py` — Reads config, generates tfvars
- [ ] `terraform/scripts/apply-all.sh` — Applies in dependency order

---

## Phase 3: Platform Core (Weeks 3-4)

**Goal**: Deploy and configure core platform services via ArgoCD.

### Deliverables

| Component | File | Priority |
|-----------|------|:--------:|
| ArgoCD + ApplicationSet | `platform/gitops/argocd/` | P0 |
| Cilium CNI + NetworkPolicies | `platform/networking/cilium/` | P0 |
| cert-manager + ClusterIssuer | `platform/networking/cert-manager/` | P0 |
| Gateway API CRDs | `platform/networking/gateway-api/` | P0 |
| Kyverno policies | `platform/security/kyverno/` | P0 |
| External Secrets + SecretStores | `platform/security/external-secrets/` | P0 |
| Vault (optional) | `platform/security/vault/` | P1 |
| CloudNativePG operator | `platform/storage/cnpg/` | P1 |
| Valkey operator | `platform/storage/valkey/` | P1 |
| Velero backup | `platform/storage/velero/` | P1 |
| Harbor registry | `platform/storage/harbor/` (under `ai/`) | P1 |

### Completion Criteria

- [ ] ArgoCD can sync from Git repo
- [ ] Cilium with Hubble UI accessible
- [ ] Kyverno enforcing baseline policies
- [ ] External Secrets syncing from AWS Secrets Manager
- [ ] Default-deny NetworkPolicies in place
- [ ] HTTPS certs provisioned via cert-manager

---

## Phase 4: Observability (Weeks 4-5)

**Goal**: Full metrics, logging, tracing, and alerting stack.

### Deliverables

| Component | File | Priority |
|-----------|------|:--------:|
| kube-prometheus-stack | `platform/observability/prometheus/` | P0 |
| Grafana + dashboards | `platform/observability/grafana/` | P0 |
| Loki + Promtail | `platform/observability/loki/` | P0 |
| Tempo (tracing) | `platform/observability/tempo/` | P1 |
| OpenTelemetry collector | `platform/observability/opentelemetry/` | P1 |
| OpenCost (GPU cost) | `platform/cost/opencost/` | P1 |
| NVIDIA DCGM Exporter | Via GPU Operator | P0 |

### Completion Criteria

- [ ] Prometheus scraping cluster + vLLM metrics
- [ ] Grafana dashboards: LLM Inference, GPU, Cost, Platform
- [ ] Loki collecting all pod logs
- [ ] Alertmanager configured with Slack/webhook
- [ ] OpenCost reporting GPU cost by namespace

---

## Phase 5: AI Infrastructure (Weeks 5-6)

**Goal**: GPU management, batch scheduling, event-driven autoscaling, model serving framework.

### Deliverables

| Component | File | Priority |
|-----------|------|:--------:|
| NVIDIA GPU Operator | `ai/gpu-operator/` | P0 |
| Kueue (GPU scheduling) | `ai/kueue/` | P0 |
| KEDA (autoscaling) | `ai/keda/` | P0 |
| KServe (model serving) | `ai/kserve/` | P0 |
| Gateway Inference Extension | `ai/gateway/` | P1 |
| llm-d (distributed, optional) | `ai/llm-d/` | P2 |
| Envoy AI Gateway | `ai/gateway/envoy-ai-gateway/` | P1 |

### Completion Criteria

- [ ] GPU Operator installed + DCGM metrics flowing
- [ ] Kueue queues configured + GPU quota per namespace
- [ ] KEDA ScaledObjects for vLLM metrics
- [ ] KServe with vLLM ServingRuntime
- [ ] Gateway API + InferenceExtension installed

---

## Phase 6: Model Serving (Weeks 7-8)

**Goal**: Deploy Gemma 2B with autoscaling, demonstrate distributed inference.

### Deliverables

| Component | File | Priority |
|-----------|------|:--------:|
| LLMInferenceService (single-node) | `ai/kserve/llminferenceservice-gemma2b.yaml` | P0 |
| KEDA ScaledObject | `ai/keda/scaled-object.yaml` | P0 |
| Gateway HTTPRoute | `ai/gateway/http-route.yaml` | P0 |
| Envoy AI Gateway config | `ai/gateway/envoy-ai-gateway/` | P1 |
| Chat completion app | `apps/chat/` | P1 |
| RAG service | `apps/rag/` | P2 |
| Multi-replica DP pattern | `ai/kserve/llmisvc-multi-replica.yaml` | P1 |
| Distributed TP pattern | (future) | P2 |
| Disaggregated PD pattern | (future) | P3 |

### Completion Criteria

- [ ] `gemma-2-2b-it` running on 1x T4 GPU
- [ ] OpenAI-compatible endpoint responding
- [ ] Autoscaling based on queue depth
- [ ] Grafana showing inference metrics
- [ ] Gateway API routing traffic
- [ ] Smoke test passes

---

## Phase 7: Polish & Portfolio (Weeks 9-10)

**Goal**: Production-hardening, documentation, demo preparation.

### Deliverables

| Item | Priority |
|------|:--------:|
| Grafana dashboards (5x) | P0 |
| Alerting rules configuration | P0 |
| Runbooks (common operations) | P1 |
| Demo scripts | P1 |
| README with architecture diagram | P1 |
| Interview talking points doc | P1 |
| Cost analysis (TCO comparison) | P2 |
| Load testing results | P2 |
| ADR completion | P2 |

### Completion Criteria

- [ ] All 5 Grafana dashboards functional
- [ ] Alertmanager configured with meaningful alerts
- [ ] Runbooks for: deploy, scale, upgrade, rollback, debug
- [ ] README with architecture diagram + one-command instructions
- [ ] Demo script: single command → running model
