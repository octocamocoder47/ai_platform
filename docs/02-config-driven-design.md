# Config-Driven Design

> **Source of Truth** — Defines the platform configuration schema and all supported parameters.
> Last updated: 2026-05-31

## Table of Contents

1. [Overview](#overview)
2. [Config File Location](#config-file-location)
3. [Schema Definition](#schema-definition)
4. [Config Processing Pipeline](#config-processing-pipeline)
5. [Environment Overrides](#environment-overrides)
6. [Secret Injection](#secret-injection)
7. [Validation Rules](#validation-rules)
8. [Example Configs](#example-configs)

---

## Overview

The platform is controlled entirely by YAML configuration files. Every aspect — from which cloud provider to use, to which model to serve, to which monitoring stack to deploy — is determined by a single config file.

### Design Rules

1. **Single source of truth**: One config file defines the complete platform state
2. **Deterministic**: Same config → same platform, every time
3. **Composable**: Multiple config files can exist for different environments/scenarios
4. **Validatable**: Configs are validated against a JSON Schema before use
5. **Versionable**: Configs live in Git with full history
6. **Secret-safe**: Secrets are referenced via environment variables, not embedded

---

## Config File Location

Config files live in the `config/` directory:

```
config/
├── demo.yaml           # Simple single-cloud demo
├── multi-account.yaml  # AWS multi-account with cross-account networking
├── multi-cloud.yaml    # AWS + GCP multi-cloud
└── production.yaml     # Full production configuration
```

The config file is selected at deploy time:

```bash
./scripts/deploy.sh --config config/demo.yaml
```

---

## Schema Definition

### Top-Level Structure

```yaml
# ============================================================
# AI Platform Configuration — Schema v1.0
# ============================================================
apiVersion: platform.ai/v1
kind: PlatformConfig
metadata:
  name: <string>           # Config name (e.g., "demo", "production")
  environment: <string>    # dev | staging | prod

spec:
  providers:     <ProvidersSpec>
  networking:    <NetworkingSpec>
  kubernetes:    <KubernetesSpec>
  inference:     <InferenceSpec>
  components:    <ComponentsSpec>
  observability: <ObservabilitySpec>
  security:      <SecuritySpec>
  cicd:          <CicdSpec>
  storage:       <StorageSpec>
```

### ProvidersSpec

```yaml
providers:
  primary: aws                    # aws | gcp | azure
  multi-cloud:
    enabled: false                # true to enable secondary cloud
    secondary: gcp                # gcp | azure | none
  aws:
    region: us-west-2
    accounts:
      - name: network             # Hub account
        id: ""                    # AWS account ID (fill in)
        role: hub                 # hub | spoke | shared | security
        regions:                   # Regions available in this account
          - us-west-2
      - name: workloads-dev
        id: ""
        role: spoke
        regions:
          - us-west-2
      - name: shared-services
        id: ""
        role: shared
        regions:
          - us-west-2
      - name: security
        id: ""
        role: security
        regions:
          - us-east-1             # Centralized logging/audit region
  gcp:
    enabled: false
    project: ""
    region: us-central1
    shared_vpc:
      enabled: false
      host_project: ""
```

### NetworkingSpec

```yaml
networking:
  topology: hub-spoke            # hub-spoke | mesh | single
  cross_account:
    enabled: false
    transit_gateway:
      enabled: true
      share_with_accounts: []    # List of spoke account names
    vpc_peering:
      enabled: false
  cross_cloud:
    enabled: false
    vpn:
      type: site-to-site         # site-to-site | private-interconnect
      bgp_asn: 64512
      tunnel_count: 2            # HA tunnels
    dns:
      enabled: true
      sync_enabled: true
  dns:
    provider: route53            # route53 | cloudflare | google-dns
    zone_name: ai-platform.example.com
    private_zone: true
  network_policies:
    default_deny: true
    enable_hubble: true          # Cilium Hubble UI
```

### KubernetesSpec

```yaml
kubernetes:
  kind: eks                      # eks | gke | aks
  version: "1.31"
  karpenter:
    enabled: true
  nodeGroups:
    system:
      name: system
      instanceType: t3.medium
      min: 2
      max: 5
      spot: true
      taints: []
      labels:
        node-type: system
    gpu-inference:
      name: gpu-inference
      instanceType: g5.xlarge    # 1x T4 GPU
      min: 1
      max: 10
      spot: false
      gpu:
        count: 1
        type: nvidia-tesla-t4
        sharing:
          strategy: time-slicing  # time-slicing | mig | none
          count: 4                # Partitions per GPU when sharing
      taints:
        - key: nvidia.com/gpu
          value: "true"
          effect: NoSchedule
      labels:
        node-type: gpu
        accelerator: nvidia-tesla-t4
    gpu-batch:
      name: gpu-batch
      instanceType: p5.48xlarge   # 8x H100
      min: 0
      max: 5
      spot: true
      gpu:
        count: 8
        type: nvidia-h100
        sharing:
          strategy: none
      taints:
        - key: nvidia.com/gpu
          value: "true"
          effect: NoSchedule
      labels:
        node-type: gpu-batch
        accelerator: nvidia-h100
```

### InferenceSpec

```yaml
inference:
  model:
    name: "google/gemma-2-2b-it"  # HuggingFace model ID
    source: huggingface            # huggingface | s3 | gcs | pvc
    hf_token: ${HF_TOKEN}          # Env var reference
    revision: main                 # Model revision/branch
  serving:
    engine: vllm
    engines: 1                     # Number of engine replicas
    tensorParallelSize: 1
    pipelineParallelSize: 1        # >1 for multi-node
    maxModelLen: 8192
    dtype: bfloat16
    gpuMemoryUtilization: 0.90
    enablePrefixCaching: true
    enableChunkedPrefill: false
    extraArgs: []
  autoscaling:
    enabled: true
    minReplicas: 1
    maxReplicas: 5
    metrics:
      - type: queue_depth
        name: vllm:num_requests_waiting
        threshold: 5
      - type: kv_cache
        name: vllm:gpu_cache_usage_perc
        threshold: 0.85
    cooldownPeriod: 300            # Scale-down stabilization (seconds)
  advanced:
    llm-d:
      enabled: false
      prefillDecode:
        enabled: false
        prefillGPU: nvidia-h100
        decodeGPU: nvidia-a100
        kvCacheOffload: true
    lmcache:
      enabled: false
      cpuOffload: true
      diskOffload: false
```

### ComponentsSpec

```yaml
components:
  gitops:
    type: argocd
    ha: true
    namespace: argocd
  networking:
    cni: cilium
    ingress:
      type: gateway-api           # gateway-api | ingress-nginx
      gatewayClass: aws           # aws | gcp | istio
    certManager:
      enabled: true
      issuer: letsencrypt-prod    # letsencrypt-prod | letsencrypt-staging
  security:
    policy:
      engine: kyverno             # kyverno | opa-gatekeeper
      mode: audit                 # audit | enforce
      policies:
        - require-labels
        - restrict-seccomp
        - require-nonroot
        - restrict-host-ports
    secrets:
      engine: external-secrets    # external-secrets | vault-secrets-operator
      backends:                   # Which secret stores to connect
        - type: aws
          name: aws-secrets-manager
        - type: gcp
          name: gcp-secret-manager
    vault:
      enabled: true
      mode: external              # external | integrated
      ha: true
    supplyChain:
      signing: cosign
      scanning: trivy
      sbom: syft
  storage:
    postgres:
      enabled: false
      operator: cnpg              # cnpg | crunchy
    redis:
      enabled: false
      operator: valkey             # valkey | redis-operator
    backup:
      enabled: true
      tool: velero
      schedule: "0 2 * * *"       # Daily at 2 AM
      retention: 30d
  cost:
    enabled: true
    tool: opencost                # opencost | kubecost
  ai:
    gpuOperator: true
    gpuOperatorVersion: "24.9.2"
    kserve: true
    kserveVersion: "v0.17.0"
    llm-d: false
    kueue: true
    keda: true
    volcano: false
    harbor: true                  # Container + model registry
```

### ObservabilitySpec

```yaml
observability:
  metrics:
    stack: kube-prometheus-stack
    retention: 30d
    storageSize: 50Gi
    serviceMonitors:
      - vllm-engine
      - nvidia-dcgm
      - kube-state-metrics
      - kubelet
      - node-exporter
      - envoy-gateway
      - keda
  logging:
    backend: loki
    retention: 7d
    storageSize: 100Gi
  tracing:
    backend: tempo
    sampling: 0.1                 # 10% sampling rate
    retention: 7d
    storageSize: 20Gi
  dashboards:
    enabled: true
    grafana:
      adminUser: admin
      adminPassword: ${GRAFANA_PASSWORD}
      ingress:
        enabled: false
        host: grafana.ai-platform.example.com
    custom:
      - name: llm-inference
        enabled: true
      - name: gpu-utilization
        enabled: true
      - name: cost-attribution
        enabled: true
      - name: platform-health
        enabled: true
      - name: kubernetes-overview
        enabled: true
  alerting:
    enabled: true
    channels:
      - type: slack
        webhook: ${SLACK_WEBHOOK}
        channel: "#ai-platform-alerts"
      - type: email
        address: "team@example.com"
    rules:
      - name: high-ttft
        expr: "vllm:time_to_first_token_seconds{quantile=\"0.99\"} > 5"
        severity: warning
      - name: kv-cache-pressure
        expr: "vllm:gpu_cache_usage_perc > 0.90"
        severity: warning
      - name: queue-depth
        expr: "vllm:num_requests_waiting > 10"
        severity: critical
      - name: gpu-memory
        expr: "DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL > 0.95"
        severity: critical
```

### SecuritySpec

```yaml
security:
  podSecurity:
    standard: restricted          # privileged | baseline | restricted
  networkPolicies:
    enabled: true
    defaultDeny: true
    allowDNS: true
    allowAPI: true
    allowMonitoring: true
  rbac:
    clusterAdmin: false           # Restrict cluster-admin role
    auditEnabled: true
  encryption:
    secrets: true                 # Encrypt secrets at rest (KMS)
    etcd: true                    # Encrypt etcd
  audit:
    enabled: true
    retention: 90d
    destination: s3               # s3 | cloudwatch | gcs
  containerSecurity:
    readOnlyRoot: true
    runAsNonRoot: true
    seccomp: RuntimeDefault
    seLinux: true
    privileged: false
    allowPrivilegeEscalation: false
    capabilities:
      drop: ["ALL"]
  imagePolicy:
    requireSigning: false         # Require Cosign signatures
    requireScanning: true         # Require Trivy scan pass
    registries:
      allowed: ["harbor.*", "docker.io/kserve*", "docker.io/vllm*"]
```

### CicdSpec

```yaml
cicd:
  provider: github-actions
  imageRegistry:
    type: harbor                  # harbor | ecr | gcr
    url: harbor.ai-platform.example.com
  signing:
    enabled: true
    key: ${COSIGN_PRIVATE_KEY}
    identity: ${COSIGN_IDENTITY}
  scanning:
    enabled: true
    severity: HIGH                # HIGH | CRITICAL
    failOnSeverity: true
  environments:
    dev:
      autoDeploy: true
      requiredApprovals: 0
    staging:
      autoDeploy: false
      requiredApprovals: 1
    prod:
      autoDeploy: false
      requiredApprovals: 2
      requireTag: true
      tagPattern: "^v[0-9]+\\.[0-9]+\\.[0-9]+$"
```

### StorageSpec

```yaml
storage:
  shared:
    type: efs                     # efs | gcs-fuse | ebs
    capacity: 100Gi
    accessMode: ReadWriteMany
  modelStorage:
    type: s3                      # s3 | gcs | minio
    bucket: ai-platform-models
    cacheSize: 50Gi               # Local NVMe cache for models
```

---

## Config Processing Pipeline

```
platform-config.yaml
        │
        ▼
┌───────────────────────────────┐
│  1. Validate (JSON Schema)    │
│  - Required fields present    │
│  - Types match                │
│  - References resolve          │
│  - Values in allowed range    │
└──────────────┬───────────────┘
               │
               ▼
┌───────────────────────────────┐
│  2. Inject Secrets            │
│  - Replace ${VAR} from env    │
│  - Or from vault              │
│  - Never log or persist       │
└──────────────┬───────────────┘
               │
               ▼
┌───────────────────────────────┐
│  3. Generate Terraform Vars   │
│  - Create .tfvars files       │
│  - One per account/region     │
│  - Derived from config        │
└──────────────┬───────────────┘
               │
               ▼
┌───────────────────────────────┐
│  4. Generate ArgoCD Apps      │
│  - ApplicationSets            │
│  - Per component enabled      │
│  - Values from config         │
└──────────────┬───────────────┘
               │
               ▼
┌───────────────────────────────┐
│  5. Generate K8s Manifests    │
│  - LLMInferenceService        │
│  - ScaledObject (KEDA)        │
│  - NetworkPolicies            │
│  - RBAC                       │
└──────────────┬───────────────┘
               │
               ▼
        Deploy / Apply
```

### Implementation: `scripts/generate-from-config.py`

This Python script reads the YAML config and generates all derived files:

```bash
# Usage
./scripts/generate-from-config.py config/demo.yaml

# Generated output:
# terraform/envs/dev/terraform.tfvars
# platform/gitops/argocd/applicationset.yaml
# ai/kserve/llminferenceservice-gemma2b.yaml
# ai/keda/scaled-object.yaml
# clusters/base/network-policies.yaml
```

---

## Environment Overrides

Config values can be overridden per environment using `values/` directory:

```
values/
├── dev.yaml          # Dev-specific overrides
├── staging.yaml      # Staging-specific overrides
└── prod.yaml         # Production-specific overrides
```

Override precedence (highest to lowest):
1. Command-line flag (`--set spec.providers.aws.region=us-east-1`)
2. Environment-specific override file
3. Main config file
4. Hardcoded defaults (minimal, safe defaults only)

Example override:

```yaml
# values/prod.yaml
spec:
  providers:
    aws:
      region: us-east-1
  kubernetes:
    nodeGroups:
      gpu-inference:
        instanceType: p5.48xlarge    # H100 for prod
        min: 3
  inference:
    model:
      name: "meta-llama/Llama-3.1-70B-Instruct"
    serving:
      tensorParallelSize: 8
      engines: 3
    autoscaling:
      minReplicas: 3
  components:
    gitops:
      ha: true    # HA ArgoCD in prod
  observability:
    alerting:
      enabled: true
```

---

## Secret Injection

Secrets are never stored in config files. Use `${VAR_NAME}` syntax:

```yaml
inference:
  model:
    hf_token: ${HF_TOKEN}
    # Also: ${VAULT:secret/data/hf:token}
```

Supported backends:
- `${VAR_NAME}` — Environment variable
- `${VAULT:path:key}` — HashiCorp Vault
- `${AWS:secret-name:key}` — AWS Secrets Manager
- `${GCP:secret-name:key}` — GCP Secret Manager

---

## Validation Rules

| Rule | Description | Error |
|------|-------------|-------|
| Required fields | `providers.primary`, `kubernetes.kind`, `inference.model.name` | "field is required" |
| Enum validation | `providers.primary` must be `aws\|gcp\|azure` | "must be one of: aws, gcp, azure" |
| Conditional required | `gcp.project` required when `gcp.enabled=true` | "gcp.project is required when gcp is enabled" |
| Secret references | `${VAR}` must be resolvable at deploy time | "secret ${VAR} is not set" |
| GPU sharing | `sharing.strategy=mig` requires `gpu.type` to support MIG | "gpu type does not support MIG" |
| Topology consistency | cross-cloud requires cross_account | "cross-cloud networking requires cross-account" |
| DNS uniqueness | No duplicate zone names across providers | "dns zone already exists" |

---

## Example Configs

See [12-config-examples.md](12-config-examples.md) for complete working examples:

| Example | Description | File |
|---------|-------------|------|
| **Demo** | Single AWS account, minimal platform | `config/demo.yaml` |
| **Multi-Account** | AWS with network + workload accounts | `config/multi-account.yaml` |
| **Multi-Cloud** | AWS + GCP with cross-cloud VPN | `config/multi-cloud.yaml` |
| **Production** | Full production with all features | `config/production.yaml` |
