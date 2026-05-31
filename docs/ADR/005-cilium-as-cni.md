# ADR-005: Cilium as CNI

**Status**: Accepted  
**Date**: 2026-05-31  

## Context

We need a Container Network Interface (CNI) for Kubernetes that supports network policies, encryption, observability, and Gateway API.

## Decision

Use Cilium as the CNI plugin.

## Rationale

1. **eBPF-native**: No sidecars, no iptables — kernel-level efficiency and security.
2. **Hubble**: Built-in network observability with service map, flow logs, and policy verification.
3. **Gateway API support**: Cilium implements Gateway API natively, including experimental features like Inference Extension.
4. **Network Policies**: Full L3-L7 policy enforcement without sidecars.
5. **Encryption**: WireGuard-based node-to-node encryption built-in.
6. **Performance**: 2-3x faster than iptables-based solutions (Calico, Flannel).

## Trade-offs

- Requires Linux kernel 5.10+ (eBPF dependency).
- Learning curve for eBPF debugging.
- Some advanced features require Cilium-specific CRDs (CiliumNetworkPolicy).

## Mitigation

- EKS supports eBPF natively on Amazon Linux 2 (kernel 5.10+).
- Standard Kubernetes NetworkPolicy falls back for basic use cases.
- Cilium-specific CRDs used only when needed (L7 policies, Hubble).
