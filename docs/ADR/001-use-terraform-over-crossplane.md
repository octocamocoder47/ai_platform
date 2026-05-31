# ADR-001: Use Terraform over Crossplane

**Status**: Accepted  
**Date**: 2026-05-31  
**Author**: Principal Platform Engineer

## Context

We need Infrastructure as Code to provision multi-cloud, cross-account infrastructure. The primary candidates are Terraform (HashiCorp) and Crossplane (CNCF).

## Decision

Use Terraform as the IaC tool for infrastructure provisioning.

## Rationale

1. **Broader provider ecosystem**: Terraform supports 2000+ providers including all AWS/GCP/Azure services. Crossplane has fewer official providers.
2. **Mature multi-account pattern**: Terraform's provider aliasing, `assume_role`, and `terraform_remote_state` are well-established for cross-account workflows.
3. **Remote state with locking**: S3 backend + DynamoDB locking is battle-tested at enterprise scale.
4. **Portfolio value**: Terraform is the industry standard for IaC. Hiring managers expect Terraform proficiency.
5. **Terraform Cloud**: Optional upgrade path for team collaboration, policy enforcement, and cost estimation.

## Trade-offs

- Two-tool problem: Terraform for infra, ArgoCD for in-cluster. Crossplane would unify both.
- Terraform state management adds complexity vs. Crossplane's in-cluster state.

## Mitigation

- Terraform handles only cloud infrastructure (L1). ArgoCD owns all Kubernetes resources (L3-L6).
- Clear separation of concerns: Terraform stops at `kubeconfig`. ArgoCD takes over from there.
