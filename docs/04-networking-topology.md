# Networking Topology

> **Source of Truth** — Cross-account and cross-cloud networking design with zero-trust principles.
> Last updated: 2026-05-31

## Table of Contents

1. [Overview](#overview)
2. [Single-Account Topology](#single-account-topology)
3. [Multi-Account Topology (Hub-Spoke)](#multi-account-topology-hub-spoke)
4. [Multi-Cloud Topology](#multi-cloud-topology)
5. [Kubernetes Networking](#kubernetes-networking)
6. [DNS Architecture](#dns-architecture)
7. [Default-Deny Rules](#default-deny-rules)
8. [Network Policies (Cilium)](#network-policies-cilium)

---

## Overview

All networking is defined as Terraform code. No manually created VPCs, subnets, or routes exist. The networking topology is determined by the configuration file:

```yaml
networking:
  topology: hub-spoke       # single | hub-spoke | mesh
  cross_account:
    enabled: true
  cross_cloud:
    enabled: false
```

---

## Single-Account Topology

```
┌─────────────────────────────────────────────────────────────────────┐
│  AWS Account                                                        │
│  Region: us-west-2                                                  │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  VPC: 10.0.0.0/16                                            │   │
│  │                                                               │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │   │
│  │  │ Public Subnet│  │ Private SYS  │  │ Private GPU  │        │   │
│  │  │ 10.0.1.0/24  │  │ 10.0.10.0/24│  │ 10.0.20.0/24│        │   │
│  │  │ AZ-a         │  │ AZ-a         │  │ AZ-a         │        │   │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘        │   │
│  │         │                 │                 │                 │   │
│  │  ┌──────┴───────┐  ┌──────┴───────┐  ┌──────┴───────┐        │   │
│  │  │ Public Subnet│  │ Private SYS  │  │ Private GPU  │        │   │
│  │  │ 10.0.2.0/24  │  │ 10.0.11.0/24│  │ 10.0.21.0/24│        │   │
│  │  │ AZ-b         │  │ AZ-b         │  │ AZ-b         │        │   │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘        │   │
│  │         │                 │                 │                 │   │
│  │  ┌──────┴───────┐  ┌──────┴───────┐  ┌──────┴───────┐        │   │
│  │  │ Public Subnet│  │ Private SYS  │  │ Private GPU  │        │   │
│  │  │ 10.0.3.0/24  │  │ 10.0.12.0/24│  │ 10.0.22.0/24│        │   │
│  │  │ AZ-c         │  │ AZ-c         │  │ AZ-c         │        │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘        │   │
│  │                                                               │   │
│  │  ┌──────────────────────────────────────────┐                 │   │
│  │  │ NAT Gateway (x3, one per AZ)              │                 │   │
│  │  │ Internet Gateway (for public subnets)      │                 │   │
│  │  │ VPC Endpoints: S3, ECR, DynamoDB, STS     │                 │   │
│  │  │ Flow Logs → CloudWatch Logs → S3          │                 │   │
│  │  └──────────────────────────────────────────┘                 │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

**CIDR plan**:

| Purpose | CIDR | Usage |
|---------|------|-------|
| Public (NLB/ALB) | 10.0.1.0/24 - 10.0.3.0/24 | Load balancers, bastion |
| Private System | 10.0.10.0/24 - 10.0.12.0/24 | System pods, ArgoCD, monitoring |
| Private GPU Inference | 10.0.20.0/24 - 10.0.22.0/24 | vLLM, KServe inference pods |
| Private GPU Batch | 10.0.30.0/24 - 10.0.32.0/24 | Training, batch inference |

---

## Multi-Account Topology (Hub-Spoke)

```
┌────────────────────────────────────────────────────────────────────────────┐
│  Organization: ai-platform.example.com                                      │
│                                                                             │
│  ┌──────────────────────────────────────────────┐                           │
│  │  Network Account (Hub) 111111111111          │                           │
│  │  ┌────────────────────────────────────┐      │                           │
│  │  │  VPC: 10.0.0.0/16 (us-west-2)      │      │                           │
│  │  │  ├── Public Subnets                │      │                           │
│  │  │  ├── Private Subnets (TGW attach)  │      │                           │
│  │  │  ├── Transit Gateway (TGW)         │      │                           │
│  │  │  ├── Route53 Private Zone          │      │                           │
│  │  │  ├── CloudWatch (centralized)      │      │                           │
│  │  │  └── VPN Endpoints (cross-cloud)   │      │                           │
│  │  └────────────────────────────────────┘      │                           │
│  └──────────────────────┬───────────────────────┘                           │
│                          │ TGW (shared via RAM)                             │
│                          │                                                  │
│  ┌───────────────────────┼─────────────────────────────────────────┐       │
│  │                       │                                          │       │
│  │  ┌────────────────────┴──────┐    ┌─────────────────────────┐   │       │
│  │  │  Workload Dev (Spoke)     │    │  Workload Prod (Spoke)  │   │       │
│  │  │  222222222222              │    │  333333333333            │   │       │
│  │  │                           │    │                          │   │       │
│  │  │  VPC: 10.1.0.0/16        │    │  VPC: 10.2.0.0/16        │   │       │
│  │  │  ├── TGW Attachment       │    │  ├── TGW Attachment      │   │       │
│  │  │  ├── EKS Cluster (dev)    │    │  ├── EKS Cluster (prod)  │   │       │
│  │  │  └── VPC Endpoints        │    │  └── VPC Endpoints       │   │       │
│  │  └──────────────────────────┘    └──────────────────────────┘   │       │
│  │                                                                 │       │
│  │  ┌──────────────────────────┐    ┌──────────────────────────┐   │       │
│  │  │  Shared Services (Spoke) │    │  Security (Spoke)        │   │       │
│  │  │  444444444444             │    │  555555555555             │   │       │
│  │  │                           │    │                           │   │       │
│  │  │  VPC: 10.3.0.0/16        │    │  VPC: 10.4.0.0/16        │   │       │
│  │  │  ├── Harbor Registry      │    │  ├── CloudTrail          │   │       │
│  │  │  ├── Vault Server         │    │  ├── GuardDuty           │   │       │
│  │  │  └── Artifact Store       │    │  └── Audit Logs          │   │       │
│  │  └──────────────────────────┘    └──────────────────────────┘   │       │
│  └─────────────────────────────────────────────────────────────────┘       │
└────────────────────────────────────────────────────────────────────────────┘
```

### Cross-Account Access Patterns

| Source Account → Target Account | Method | Purpose |
|:---|:---|:---|
| Workload → Network | TGW Attachment + RAM | Private routing to hub services |
| Workload → Shared | TGW routing | Access to Harbor, Vault |
| Workload → Security | TGW routing + VPC endpoints | Log delivery, audit |
| Network → Workload | TGW routing | Health monitoring |
| Shared → All | TGW routing | Registry pull, secrets sync |

### IAM Cross-Account Roles

Each account has a `TerraformDeployer` role that the provisioning account assumes:

```hcl
# Deployed in each spoke account
resource "aws_iam_role" "terraform_deployer" {
  name = "TerraformDeployer"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.hub_account_id}:root"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = var.external_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.terraform_deployer.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
```

---

## Multi-Cloud Topology

```
┌──────────────────────────────────────────┐     ┌──────────────────────────────────────┐
│  AWS (us-west-2)                         │     │  GCP (us-central1)                    │
│                                          │     │                                      │
│  ┌────────────────────────────────────┐  │     │  ┌────────────────────────────────┐  │
│  │  Network Account VPC              │  │     │  │  Shared VPC                    │  │
│  │  10.0.0.0/16                      │  │     │  │  10.100.0.0/16                 │  │
│  │                                   │  │     │  │                                │  │
│  │  Transit Gateway                  │──┼─────┼──│  Cloud Router                  │  │
│  │                                   │  │     │  │  + Cloud VPN Gateway            │  │
│  │  VPN Connection (2 tunnels)       │──┼─────┼──│  + VPN Tunnels (HA)            │  │
│  │  - Tunnel 1: 169.254.10.1/30     │  │     │  │  - Tunnel 1: 169.254.10.2/30    │  │
│  │  - Tunnel 2: 169.254.10.5/30     │  │     │  │  - Tunnel 2: 169.254.10.6/30    │  │
│  │  - BGP ASN: 64512                │──┼─────┼──│  - BGP ASN: 64513               │  │
│  │                                   │  │     │  │  - BGP: 10.100.0.0/16, 10.101.0.0/16│
│  │  Route53 Private Zone             │  │     │  │  - Cloud DNS Zone               │  │
│  │  .ai-platform.internal            │──┼─────┼──│  .ai-platform.internal          │  │
│  │                                   │  │     │  │                                │  │
│  │  EKS Pod CIDR: 10.200.0.0/16     │──┼─────┼──│  GKE Pod CIDR: 10.201.0.0/16    │  │
│  │  EKS Service CIDR: 172.20.0.0/16 │  │     │  │  GKE Service CIDR: 172.21.0.0/16│  │
│  └────────────────────────────────────┘  │     │  └────────────────────────────────┘  │
└──────────────────────────────────────────┘     └──────────────────────────────────────┘
```

### Cross-Cloud Routing

| Prefix | Route | Next Hop |
|--------|-------|----------|
| 10.0.0.0/16 | AWS VPC | Local |
| 10.1.0.0/16 | AWS Workload Dev | TGW → VPC attachment |
| 10.2.0.0/16 | AWS Workload Prod | TGW → VPC attachment |
| 10.100.0.0/16 | GCP Shared VPC | VPN Tunnel |
| 10.101.0.0/16 | GCP Workload | VPN Tunnel |
| 10.200.0.0/16 | EKS Pods (AWS) | Local |
| 10.201.0.0/16 | GKE Pods (GCP) | VPN Tunnel → Cloud Router |

### DNS Resolution (Cross-Cloud)

```
aws Route53 Private Zone          gcp Cloud DNS Zone
  .ai-platform.internal             .ai-platform.internal
        │                                  │
        └──────────── DNS Sync ────────────┘
                        │
              (cross-cloud/dns module)

Records:
- *.us-west-2.ai-platform.internal  → EKS services
- *.us-central1.ai-platform.internal → GKE services
- llm-inference.ai-platform.internal  → Global VIP
```

---

## Kubernetes Networking

### Cilium CNI

- **CNI**: Cilium (eBPF-based)
- **IPAM**: Kubernetes Pod CIDR (no overlay, native routing)
- **Service Mesh**: Cilium L7 policies (replaces need for Istio when in mesh mode)
- **Hubble**: Flow visibility, service map, network policy verification

### Network Policy Architecture

Default-deny ingress and egress for all namespaces:

```yaml
# clusters/base/network-policies/default-deny.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: default-deny
  namespace: "*"
spec:
  endpointSelector: {}
  ingress:
    - fromEndpoints:
        - {}  # None by default — explicitly allowed only
  egress:
    - toEndpoints:
        - {}  # None by default
```

Per-namespace policies allow specific traffic:

```yaml
# clusters/base/network-policies/allow-monitoring.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-prometheus-scrape
  namespace: ai-inference
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: vllm
  ingress:
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: prometheus
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
```

### VPC Endpoints (AWS)

All traffic to AWS services goes through VPC endpoints — no internet gateway for cluster traffic:

| Service | Endpoint Type | Required By |
|---------|:------------:|-------------|
| S3 | Gateway | Model storage, logs |
| ECR | Interface | Container image pull |
| ECR DKR | Interface | Container image pull |
| STS | Interface | IRSA token exchange |
| DynamoDB | Gateway | State locking |
| CloudWatch | Interface | Logs, metrics |
| Secrets Manager | Interface | Secret retrieval |
| KMS | Interface | Encryption |
| EC2 | Interface | Cluster autoscaler |

---

## Default-Deny Rules

Nothing is open by default. Everything must be explicitly allowed.

### VPC Security Groups

| Security Group | Ingress | Egress | Purpose |
|----------------|---------|--------|---------|
| `eks-cluster-sg` | TCP 443 from VPC CIDR | All to VPC CIDR | K8s API server |
| `eks-node-sg` | Cluster SG, self | All to VPC CIDR | Worker nodes |
| `gpu-node-sg` | Cluster SG, self | All to VPC CIDR, S3/ECR endpoints | GPU nodes |
| `harbor-sg` | TCP 443 from spoke VPCs | TCP 443 to internet (registries) | Registry |
| `vault-sg` | TCP 8200 from spoke VPCs | None to internet | Secrets |

### Network ACLs

No default NACLs (VPC default is allow-all). Explicit NACLs deny all traffic:

```hcl
# Default-Deny NACL
resource "aws_network_acl" "private" {
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids
  
  # Deny all inbound (explicit deny)
  ingress {
    rule_no  = 100
    protocol = -1
    action   = "deny"
    cidr_block = "0.0.0.0/0"
    from_port = 0
    to_port   = 0
  }
  
  # Deny all outbound (explicit deny)
  egress {
    rule_no  = 100
    protocol = -1
    action   = "deny"
    cidr_block = "0.0.0.0/0"
    from_port = 0
    to_port   = 0
  }
  
  tags = var.tags
}

# Then add NACL rules for specific traffic only in higher rule numbers
# (lower number = higher precedence, so denies above override allows)
resource "aws_network_acl_rule" "allow_ephemeral" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 200
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 1024
  to_port        = 65535
}
```

### IAM Policies

All IAM roles start with zero permissions. Access scoped to least-privilege:

```hcl
# EKS Node Role — only what nodes need
data "aws_iam_policy_document" "eks_node" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "s3:GetObject",
    ]
    resources = ["*"]
  }
}
```

---

## Network Policies (Cilium)

Full CiliumNetworkPolicy reference (generated from config):

```yaml
# Policy classes determined by config:
# security.networkPolicies.defaultDeny: true

# 1. Base — All namespaces, default-deny ingress + egress
# 2. kube-system — Allow kube-dns, allow API server
# 3. argocd — Allow argocd-server ingress, allow git egress
# 4. ai-inference — Allow vLLM inference ingress, allow model pull egress
# 5. monitoring — Allow Prometheus scrape, allow Grafana ingress
# 6. cross-namespace — Explicit allow for service-to-service
```
