# ADR-004: llm-d for Distributed Inference

**Status**: Accepted (Phase 6+ — optional, toggle via config)  
**Date**: 2026-05-31  

## Context

For models that exceed single-node GPU capacity (70B+ parameters), we need distributed inference across multiple nodes with features like disaggregated prefill/decode, KV cache offloading, and intelligent routing.

## Decision

Use llm-d (CNCF Sandbox) as the distributed inference layer, toggled via config.

## Rationale

1. **CNCF Sandbox project**: Founded by Red Hat, Google Cloud, IBM Research, CoreWeave, NVIDIA — strong founding team.
2. **Disaggregated prefill/decode**: Separate compute (prefill) and memory (decode) phases for cost optimization.
3. **KV-cache-aware routing**: Envoy-based intelligent routing to cache-hot instances.
4. **NIXL/UCX integration**: Efficient KV cache transfer between nodes.
5. **KServe integration**: LLMInferenceService CRD inherits llm-d capabilities.

## Trade-offs

- CNCF Sandbox stage — early, API may change.
- Higher operational complexity than single-node vLLM.
- Requires fast inter-node networking (RDMA) for optimal performance.

## Mitigation

- llm-d is config-toggle only. Default deployment is single-node vLLM via KServe.
- Phase 6+ only. Not required for Gemma 2B but demonstrates the architecture.
- Fallback to vLLM Production Stack with multi-node support if needed.
