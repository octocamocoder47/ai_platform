# Configuration Examples

> **Source of Truth** — Reference configurations for different deployment scenarios.
> Last updated: 2026-05-31

## Example Index

| Config | File | Description |
|--------|------|-------------|
| Demo (Single AWS) | `config/demo.yaml` | Single account, minimal platform, 1 GPU node |
| Multi-Account | `config/multi-account.yaml` | Hub-spoke with 4 accounts, TGW, cross-account |
| Multi-Cloud | `config/multi-cloud.yaml` | AWS + GCP with cross-cloud VPN |
| Production | `config/production.yaml` | Full production with all features, HA |

---

## 1. Demo Config

**File**: `config/demo.yaml`

```yaml
apiVersion: platform.ai/v1
kind: PlatformConfig
metadata:
  name: demo
  environment: dev

spec:
  providers:
    primary: aws
    multi-cloud:
      enabled: false
    aws:
      region: us-west-2
      accounts:
        - name: demo
          id: ""  # <-- Fill in your AWS account ID
          role: all-in-one

  networking:
    topology: single
    dns:
      enabled: false  # Skip DNS for demo
    network_policies:
      default_deny: false  # Relaxed for demo

  kubernetes:
    kind: eks
    version: "1.31"
    nodeGroups:
      system:
        instanceType: t3.medium
        min: 1
        max: 2
        spot: true
      gpu-inference:
        instanceType: g5.xlarge    # 1x T4
        min: 1
        max: 3
        gpu:
          count: 1
          type: nvidia-tesla-t4

  inference:
    model:
      name: "google/gemma-2-2b-it"
      hf_token: ${HF_TOKEN}
    serving:
      engines: 1
      tensorParallelSize: 1
    autoscaling:
      enabled: true
      minReplicas: 1
      maxReplicas: 3

  components:
    gitops:
      type: argocd
    networking:
      cni: cilium
      ingress:
        type: ingress-nginx  # Simpler for demo
      certManager: false
    security:
      policy: kyverno
      secrets: external-secrets
      vault: false
    storage:
      backup: false
    cost: false
    ai:
      gpuOperator: true
      kserve: true
      llm-d: false
      kueue: true
      keda: true

  observability:
    metrics:
      stack: kube-prometheus-stack
    logging: false
    tracing: false
    alerting: false
```

---

## 2. Multi-Account Config

**File**: `config/multi-account.yaml`

```yaml
apiVersion: platform.ai/v1
kind: PlatformConfig
metadata:
  name: multi-account
  environment: dev

spec:
  providers:
    primary: aws
    aws:
      accounts:
        - name: network
          id: "111111111111"
          role: hub
          regions: [us-west-2]
        - name: workloads-dev
          id: "222222222222"
          role: spoke
          regions: [us-west-2]
        - name: shared-services
          id: "333333333333"
          role: shared
          regions: [us-west-2]

  networking:
    topology: hub-spoke
    cross_account:
      enabled: true
      transit_gateway:
        enabled: true
        share_with_accounts: [workloads-dev, shared-services]
    dns:
      zone_name: ai-platform.internal
      private_zone: true
    network_policies:
      default_deny: true

  kubernetes:
    kind: eks
    version: "1.31"
    karpenter:
      enabled: true
    nodeGroups:
      system:
        instanceType: t3.medium
        min: 2
        max: 5
      gpu-inference:
        instanceType: g5.xlarge
        min: 1
        max: 5
        gpu:
          type: nvidia-tesla-t4
          count: 1
      gpu-batch:
        instanceType: p5.48xlarge
        min: 0
        max: 2
        spot: true
        gpu:
          type: nvidia-h100
          count: 8

  inference:
    model:
      name: "google/gemma-2-2b-it"
      hf_token: ${HF_TOKEN}
    serving:
      engines: 2
    autoscaling:
      minReplicas: 1
      maxReplicas: 5

  components:
    gitops:
      type: argocd
      ha: true
    networking:
      cni: cilium
      ingress:
        type: gateway-api
      certManager: true
    security:
      policy: kyverno
      secrets: external-secrets
      vault: true
    storage:
      backup:
        enabled: true
        tool: velero
    cost:
      enabled: true
      tool: opencost
    ai:
      gpuOperator: true
      kserve: true
      kueue: true
      keda: true

  observability:
    metrics:
      stack: kube-prometheus-stack
    logging:
      backend: loki
    tracing:
      backend: tempo
    alerting:
      enabled: true
      channels:
        - type: slack
          webhook: ${SLACK_WEBHOOK}
```

---

## 3. Multi-Cloud Config

**File**: `config/multi-cloud.yaml`

```yaml
apiVersion: platform.ai/v1
kind: PlatformConfig
metadata:
  name: multi-cloud
  environment: staging

spec:
  providers:
    primary: aws
    multi-cloud:
      enabled: true
      secondary: gcp
    aws:
      region: us-west-2
      accounts:
        - name: network
          id: "111111111111"
          role: hub
        - name: workloads
          id: "222222222222"
          role: spoke
    gcp:
      enabled: true
      project: ai-platform-gcp
      region: us-central1
      shared_vpc:
        enabled: true
        host_project: ai-platform-gcp-host

  networking:
    topology: hub-spoke
    cross_account:
      enabled: true
    cross_cloud:
      enabled: true
      vpn:
        type: site-to-site
        bgp_asn: 64512
    dns:
      zone_name: ai-platform.internal
      private_zone: true

  kubernetes:
    kind: eks
    version: "1.31"
    nodeGroups:
      system:
        instanceType: t3.medium
        min: 2
      gpu-inference:
        instanceType: g5.xlarge
        min: 1
        gpu:
          type: nvidia-tesla-t4

  inference:
    model:
      name: "google/gemma-2-2b-it"
      hf_token: ${HF_TOKEN}
    serving:
      engines: 2

  components:
    gitops:
      type: argocd
    networking:
      cni: cilium
      ingress:
        type: gateway-api
    ai:
      gpuOperator: true
      kserve: true

  observability:
    metrics:
      stack: kube-prometheus-stack
```

---

## 4. Production Config

**File**: `config/production.yaml`

See [02-config-driven-design.md](02-config-driven-design.md) for the full production configuration. Key differences from demo:

- HA ArgoCD (3 replicas)
- Karpenter for dynamic GPU provisioning
- llm-d for distributed inference (multi-node)
- HA Vault (3 replicas)
- Full observability with 30-day retention
- Default-deny NetworkPolicies
- Cosign-required image signing
- PagerDuty + Slack alerting
- GPU cost attribution
- Velero backups
- Staging + Prod environments with approval gates
