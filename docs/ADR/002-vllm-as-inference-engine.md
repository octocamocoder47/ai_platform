# ADR-002: vLLM as Inference Engine

**Status**: Accepted  
**Date**: 2026-05-31  

## Context

We need a high-performance inference engine for serving LLMs on Kubernetes. Options include vLLM, Text Generation Inference (TGI), TensorRT-LLM, and SGLang.

## Decision

Use vLLM as the primary inference engine.

## Rationale

1. **70,000+ GitHub stars**: Largest community, most active development.
2. **100+ model architectures**: Supports far more models than alternatives.
3. **PagedAttention**: Innovative KV cache management, 2-4x higher throughput.
4. **OpenAI-compatible API**: Drop-in replacement for existing applications.
5. **Hardware agnostic**: NVIDIA, AMD, Intel, Google TPU, CPU — no vendor lock-in.
6. **PyTorch Foundation project**: Long-term sustainability guarantee.
7. **Production Stack project**: Reference Helm chart with router, observability.
8. **KServe-native**: First-class support as ServingRuntime in KServe.

## Trade-offs

- TensorRT-LLM can be faster on NVIDIA-only stacks but requires NVIDIA lock-in.
- TGI has simpler deployment but fewer features and slower innovation.

## Mitigation

- vLLM supports multiple backends. Can switch to SGLang or TGI via config change.
- Architecture abstracts engine behind KServe ServingRuntime — swap is config-only.
