# Platform Components

> **Source of Truth** — All platform services managed by ArgoCD, their Helm values, and configuration.
> Last updated: 2026-05-31

## Table of Contents

1. [Overview](#overview)
2. [GitOps: ArgoCD](#gitops-argocd)
3. [Networking: Cilium + Gateway API + cert-manager](#networking-cilium--gateway-api--cert-manager)
4. [Security: Kyverno + External Secrets + Vault](#security-kyverno--external-secrets--vault)
5. [Storage: CloudNativePG + Valkey + Velero](#storage-cloudnativepg--valkey--velero)
6. [Cost: OpenCost](#cost-opencost)

---

## Overview

Platform components form Layer 3 of the architecture. They are managed entirely by ArgoCD through Helm charts. Each component is:

- **Opt-in**: Enabled/disabled via config `spec.components.*`
- **Configurable**: Values overridden per environment
- **Upgradable**: Pinned Helm chart version, updated via Renovate bot
- **Observable**: Ships with Prometheus ServiceMonitor and Grafana dashboard

---

## GitOps: ArgoCD

### Values

```yaml
# platform/gitops/argocd/values.yaml
argo-cd:
  global:
    domain: argocd.ai-platform.internal
  configs:
    cm:
      # Sync all resources from Git
      repositories: |
        - url: https://github.com/you/ai-platform
          type: git
      # SSO configuration (Dex)
      dex.config: |
        connectors:
          - type: github
            id: github
            name: GitHub
            config:
              clientID: $dex.github.clientID
              clientSecret: $dex.github.clientSecret
              orgs:
                - name: your-org
    rbac:
      policy.default: role:readonly
      policy.csv: |
        p, role:admin, applications, *, */*, allow
        p, role:admin, clusters, *, *, allow
        g, your-org/your-team, role:admin
  controller:
    resources:
      requests:
        cpu: "1"
        memory: 1Gi
  repoServer:
    resources:
      requests:
        cpu: "1"
        memory: 512Mi
  server:
    ingress:
      enabled: true
      ingressClassName: gateway-api
      hosts:
        - argocd.ai-platform.internal
      tls:
        - hosts:
            - argocd.ai-platform.internal
  ha:
    enabled: false  # Set to true via values/prod.yaml
```

### ApplicationSet

```yaml
# platform/gitops/argocd/applicationset.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: platform-components
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - name: cilium
            path: platform/networking/cilium
          - name: cert-manager
            path: platform/networking/cert-manager
          - name: kyverno
            path: platform/security/kyverno
          - name: external-secrets
            path: platform/security/external-secrets
          - name: prometheus
            path: platform/observability/prometheus
          - name: grafana
            path: platform/observability/grafana
          - name: loki
            path: platform/observability/loki
          - name: gpu-operator
            path: ai/gpu-operator
          - name: kserve
            path: ai/kserve
          - name: keda
            path: ai/keda
          - name: kueue
            path: ai/kueue
  template:
    metadata:
      name: '{{name}}'
    spec:
      project: platform
      source:
        repoURL: https://github.com/you/ai-platform
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{name}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        retry:
          limit: 5
```

---

## Networking: Cilium + Gateway API + cert-manager

### Cilium

```yaml
# platform/networking/cilium/values.yaml
cilium:
  version: "1.16.0"
  ipam:
    mode: kubernetes
  k8sServiceHost: ""  # Set via Terraform output
  k8sServicePort: 443
  hubble:
    enabled: true
    relay:
      enabled: true
    ui:
      enabled: true
      ingress:
        enabled: true
        hosts:
          - hubble.ai-platform.internal
  gatewayAPI:
    enabled: true
    enableAlpn: true
    enableAppProtocol: true
  l7Proxy: true
  enableL7Proxy: true
  encryption:
    type: wireguard  # Node-level encryption
  rollOutCiliumPods: true
  bandwidthManager:
    enabled: true
  bpf:
    masquerade: true
  loadBalancer:
    algorithm: maglev
  envoy:
    enabled: true  # Required for L7 policies
```

### Gateway API

```yaml
# platform/networking/gateway-api/values.yaml
gateway-api:
  crds:
    enabled: true  # Install Gateway API CRDs
  experimentalChannel:
    enabled: true  # For Inference Extension
```

### cert-manager

```yaml
# platform/networking/cert-manager/values.yaml
cert-manager:
  installCRDs: true
  clusterIssuers:
    - name: letsencrypt-prod
      acme:
        server: https://acme-v02.api.letsencrypt.org/directory
        email: admin@ai-platform.example.com
        privateKeySecretRef:
          name: letsencrypt-prod-key
        solvers:
          - selector:
              dnsZones:
                - "ai-platform.example.com"
            dns01:
              route53:
                region: us-west-2
```

---

## Security: Kyverno + External Secrets + Vault

### Kyverno

```yaml
# platform/security/kyverno/values.yaml
kyverno:
  version: "3.2.0"
  backgroundScan:
    enabled: true
  policies:
    # Generated from config — only enabled policies deployed
    - name: require-nonroot
      spec:
        validationFailureAction: Enforce
        rules:
          - name: check-nonroot
            match:
              any:
                - resources:
                    kinds:
                      - Pod
            validate:
              message: "Containers must run as non-root"
              anyPattern:
                - spec:
                    securityContext:
                      runAsNonRoot: true
                - spec:
                    containers:
                      - securityContext:
                          runAsNonRoot: true
    - name: restrict-seccomp
      spec:
        validationFailureAction: Enforce
        rules:
          - name: check-seccomp
            match:
              any:
                - resources:
                    kinds:
                      - Pod
            validate:
              message: "Seccomp profile must be RuntimeDefault"
              pattern:
                spec:
                  securityContext:
                    seccompProfile:
                      type: RuntimeDefault
    - name: deny-privileged
      spec:
        validationFailureAction: Enforce
        rules:
          - name: check-privileged
            match:
              any:
                - resources:
                    kinds:
                      - Pod
            validate:
              message: "Privileged containers are not allowed"
              pattern:
                spec:
                  containers:
                    - securityContext:
                        privileged: false
```

### External Secrets Operator

```yaml
# platform/security/external-secrets/values.yaml
external-secrets:
  installCRDs: true
  serviceMonitor:
    enabled: true

# SecretStore definitions (one per backend)
---
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: external-secrets
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
```

### HashiCorp Vault

```yaml
# platform/security/vault/values.yaml
vault:
  global:
    enabled: true
  server:
    ha:
      enabled: false  # HA for prod
    ingress:
      enabled: true
      hosts:
        - vault.ai-platform.internal
  injector:
    enabled: true
  ui:
    enabled: true
```

---

## Storage: CloudNativePG + Valkey + Velero

### CloudNativePG

```yaml
# platform/storage/cnpg/values.yaml
cloudnative-pg:
  installCRDs: true
  config:
    backup:
      schedule: "0 2 * * *"
      retentionPolicy: "30d"
```

### Valkey

```yaml
# platform/storage/valkey/values.yaml
valkey:
  architecture: replication
  auth:
    enabled: true
    existingSecret: valkey-auth
  persistence:
    size: 10Gi
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
```

### Velero

```yaml
# platform/storage/velero/values.yaml
velero:
  configuration:
    backupStorageLocation:
      - name: default
        provider: aws
        bucket: ai-platform-backups
        config:
          region: us-west-2
    volumeSnapshotLocation:
      - name: default
        provider: aws
        config:
          region: us-west-2
  schedules:
    daily:
      schedule: "0 2 * * *"
      template:
        ttl: 720h  # 30 days
  initContainers:
    - name: velero-plugin-for-aws
      image: velero/velero-plugin-for-aws:v1.10.0
      volumeMounts:
        - mountPath: /target
          name: plugins
```

---

## Cost: OpenCost

```yaml
# platform/cost/opencost/values.yaml
opencost:
  opencost:
    metrics:
      serviceMonitor:
        enabled: true
    prometheus:
      internal:
        enabled: false
      external:
        url: http://prometheus.monitoring.svc.cluster.local:9090
  pricing:
    enabled: true
    customPricing:
      CPU: 0.031611   # USD per CPU hour
      GPU: 0         # Will be overridden per GPU type
      GPU_ NVIDIA_TESLA_T4: 0.35
      GPU_ NVIDIA_A100: 1.50
      GPU_ NVIDIA_H100: 3.00
```
