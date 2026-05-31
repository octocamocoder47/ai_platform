# ADR-003: KServe for Model Serving

**Status**: Accepted  
**Date**: 2026-05-31  

## Context

We need a Kubernetes-native model serving framework that can manage LLM deployments with autoscaling, canary rollouts, and multi-model routing.

## Decision

Use KServe (v0.17+) with LLMInferenceService CRD.

## Rationale

1. **CNCF incubating**: Graduation track, strong community backing.
2. **LLMInferenceService CRD**: Purpose-built for GenAI with prefill-decode separation, multi-node parallelism, and intelligent routing.
3. **llm-d integration**: KServe embeds llm-d's scheduling (EPP, InferencePool, InferenceModel) natively.
4. **Canary deployments**: Built-in traffic splitting for safe model rollouts.
5. **Scale-to-zero**: KEDA integration for cost savings on low-traffic models.
6. **Multi-framework**: Supports vLLM, Triton, TensorFlow, PyTorch, ONNX under one API.
7. **ServingRuntime abstraction**: Swap inference engines via config change.

## Trade-offs

- More complex than raw vLLM Deployments.
- LLMInferenceService is alpha in v0.17 (GA expected in v0.18).

## Mitigation

- Fallback to standard InferenceService for basic deployments.
- Use vLLM Production Stack Helm chart as alternative if KServe issues arise.
