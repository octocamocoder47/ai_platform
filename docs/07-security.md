# Security Architecture

> **Source of Truth** — Zero-trust security design covering supply chain, cluster, network, and runtime.
> Last updated: 2026-05-31

## Table of Contents

1. [Overview](#overview)
2. [Supply Chain Security](#supply-chain-security)
3. [Kubernetes Security](#kubernetes-security)
4. [Network Security](#network-security)
5. [Secret Management](#secret-management)
6. [Identity & Access](#identity--access)

---

## Overview

Security follows a defense-in-depth, zero-trust model. The attack surface is minimized at every layer — from the CI/CD pipeline through infrastructure provisioning to the runtime cluster. Everything is explicit allow; nothing is default-open.

---

## Supply Chain Security

```
Developer Push
     │
     ▼
┌──────────────────────────────────────────────────────────────┐
│  GitHub Actions                                                │
│                                                               │
│  1. Lint + Format Check                                        │
│  2. Unit Tests                                                 │
│  3. Security Scan (gitleaks) — hard fail on secrets            │
│  4. Build Container Image                                      │
│  5. Vulnerability Scan (Trivy) — fail on HIGH/CRITICAL         │
│  6. Generate SBOM (Syft)                                       │
│  7. Sign Image (Cosign)                                        │
│  8. Attest (in-toto)                                           │
│  9. Push to Harbor Registry                                    │
│                                                               │
└──────────────────────────────────────────────────────────────┘
     │
     ▼
Harbor Registry
  - Image stored with signature
  - SBOM stored as OCI artifact
  - Vulnerability report stored
     │
     ▼
Kubernetes Admission (Kyverno)
  - Verify signature (if requireSigning: true)
  - Check vulnerability threshold
  - Validate allowed registries
  - Enforce Pod Security Standards
```

### Trivy Configuration

```yaml
# .github/workflows/image-build.yaml
- name: Scan image
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ steps.build.outputs.image }}
    format: sarif
    output: trivy-results.sarif
    severity: HIGH,CRITICAL
    exit-code: 1  # Fail on HIGH/CRITICAL
```

### Cosign Signing

```bash
# Image signing
cosign sign --key $COSIGN_KEY \
  --annotations "repo=$GITHUB_REPOSITORY" \
  --annotations "workflow=$GITHUB_WORKFLOW" \
  $IMAGE_URI

# Image verification (admission)
cosign verify --key $COSIGN_PUBLIC_KEY $IMAGE_URI
```

### SBOM Generation

```bash
# Generate SPDX-formatted SBOM
syft $IMAGE_URI -o spdx-json=sbom.spdx.json

# Attach as OCI artifact
oras attach $IMAGE_URI \
  --artifact-type application/spdx+json \
  sbom.spdx.json
```

---

## Kubernetes Security

### Pod Security Standards

```yaml
# Enforced via Kyverno or namespace labels
apiVersion: v1
kind: Namespace
metadata:
  name: ai-inference
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Container Security Context

```yaml
# Applied to all platform workloads
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  seccompProfile:
    type: RuntimeDefault
  seLinuxOptions: {}
  supplementalGroups: []
seLinuxOptions: null
---
# Per-container (vLLM example)
containers:
  - name: vllm
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      readOnlyRootFilesystem: true
      privileged: false
      runAsNonRoot: true
```

### Admission Control

```yaml
# Kyverno ClusterPolicy — block privileged pods
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: deny-privileged
spec:
  validationFailureAction: Enforce
  rules:
    - name: deny-privileged
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
                  allowPrivilegeEscalation: false
```

### RBAC Model

```yaml
# No default ClusterRoleBindings
# Each service account gets explicit roles only

apiVersion: v1
kind: ServiceAccount
metadata:
  name: kserve-controller
  namespace: kserve
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/kserve-controller
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kserve-controller
rules:
  - apiGroups: ["serving.kserve.io"]
    resources: ["inferenceservices", "llminferenceservices"]
    verbs: ["*"]
  - apiGroups: [""]
    resources: ["pods", "services", "configmaps", "secrets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # No cluster-admin, no wildcard verbs
```

---

## Network Security

### Default-Deny Egress

```yaml
# CiliumNetworkPolicy — block all egress by default
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: default-deny-egress
spec:
  endpointSelector: {}
  egress:
    - toEndpoints:
        - {}  # No endpoints = deny all
```

### Explicit Allow Egress (DNS Example)

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-dns
  namespace: "*"
spec:
  endpointSelector: {}
  egress:
    - toEndpoints:
        - matchLabels:
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
          rules:
            dns:
              - matchPattern: "*"
```

### vLLM Inference Network Policy

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: vllm-inference
  namespace: ai-inference
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: vllm
  ingress:
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: envoy
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
  egress:
    - toEndpoints:
        - matchLabels:
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
    - toEntities:
        - health          # K8s health probes
    - toServices:
        - name: vault
          namespace: vault
```

---

## Secret Management

### Architecture

```
External Secrets Operator          HashiCorp Vault
     │                                    │
     │ syncs from                         │ stores
     ▼                                    ▼
┌──────────────┐                  ┌──────────────┐
│ SecretStore   │                  │ Vault Server │
│ (AWS Secrets  │                  │ (encrypted   │
│  Manager)     │                  │  storage)    │
└──────┬───────┘                  └──────┬───────┘
       │                                 │
       └──────────┬──────────────────────┘
                  │
                  ▼
         ┌────────────────┐
         │ K8s Secret     │
         │ (auto-created  │
         │  by ESO)       │
         └────────────────┘
                  │
                  ▼
         ┌────────────────┐
         │ Workload Pod    │
         │ (mounts secret) │
         └────────────────┘
```

### ExternalSecret Example

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: hf-token
  namespace: ai-inference
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: huggingface-secret
    creationPolicy: Owner
  data:
    - secretKey: HF_TOKEN
      remoteRef:
        key: ai-platform/huggingface
        property: token
```

---

## Identity & Access

### IRSA (IAM Roles for Service Accounts)

```hcl
# Terraform
module "irsa" {
  source = "../../modules/aws/irsa"
  
  cluster_name       = module.eks.cluster_name
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url
  
  service_accounts = {
    "kube-system:cluster-autoscaler" = {
      policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEKSClusterAutoscalerRole"]
    }
    "kserve:kserve-controller" = {
      policy = data.aws_iam_policy_document.kserve.json
    }
    "ai-inference:model-puller" = {
      policy = data.aws_iam_policy_document.model_s3_access.json
    }
  }
}
```

### OIDC with Dex

```yaml
# ArgoCD SSO via Dex
configs:
  cm:
    dex.config: |
      connectors:
        - type: github
          id: github
          name: GitHub
          config:
            clientID: $DEX_GITHUB_CLIENT_ID
            clientSecret: $DEX_GITHUB_CLIENT_SECRET
            orgs:
              - name: your-org
```
