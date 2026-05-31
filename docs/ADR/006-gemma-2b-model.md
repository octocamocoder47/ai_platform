# ADR-006: Gemma 2B as Reference Model

**Status**: Accepted  
**Date**: 2026-05-31  

## Context

We need a reference LLM for the platform that can be deployed, tested, and demonstrated without licensing complications or excessive GPU requirements.

## Decision

Use `google/gemma-2-2b-it` as the primary reference model.

## Rationale

1. **Apache 2.0 license**: No gated access, no commercial restrictions, no approval required.
2. **Small footprint**: 2.6B parameters, ~4GB VRAM in bfloat16. Fits on a single T4 (16GB) with room for KV cache.
3. **Multiple copies per GPU**: A single T4 can run 4x Gemma 2B copies, enabling multi-model demos.
4. **Real transformer architecture**: Valid architecture for demonstrating tensor/pipeline parallelism concepts.
5. **Instruction-tuned variant** (`-it`): Enables chat demos and RAG application demonstrations.
6. **Fast iteration**: Model downloads and loads in under 60 seconds.

## Trade-offs

- Not a frontier model. Cannot demonstrate distributed inference at scale.
- Limited benchmark relevance (not production-grade for enterprise tasks).

## Mitigation

- Gemma 2B is the development and demo model.
- Config can point to any HuggingFace model (Llama 3.1, Qwen, DeepSeek) for production.
- Architecture supports 70B+ models via config change (more GPUs needed).
