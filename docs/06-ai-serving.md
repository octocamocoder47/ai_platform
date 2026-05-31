# AI Serving Architecture

> **Source of Truth** — Distributed LLM inference design using vLLM, KServe, and llm-d.
> Last updated: 2026-05-31

## Table of Contents

1. [Overview](#overview)
2. [Model: Gemma 2B](#model-gemma-2b)
3. [Serving Stack Components](#serving-stack-components)
4. [Deployment Patterns (Progressive Complexity)](#deployment-patterns-progressive-complexity)
5. [Autoscaling Strategy](#autoscaling-strategy)
6. [Graceful Operations](#graceful-operations)
7. [Multi-Model Serving](#multi-model-serving)

---

## Overview

The AI serving stack demonstrates how a single LLM is deployed, scaled, and operated as a distributed service on Kubernetes. The architecture supports progression from simple single-replica serving to advanced distributed inference with disaggregated prefill/decode.

---

## Model: Gemma 2B

| Property | Value |
|----------|-------|
| **Model** | `google/gemma-2-2b-it` |
| **Parameters** | 2.6B |
| **License** | Apache 2.0 (no gated access) |
| **Context Length** | 8192 tokens |
| **Architecture** | Transformer decoder |
| **Precision** | bfloat16 |
| **VRAM Required** | ~4 GB (bfloat16) |
| **Single GPU** | T4 (16GB) — can fit 4x copies |
| **Source** | HuggingFace |

**Why Gemma 2B**:
- Apache 2.0 license — no restrictions, no gated access
- Small footprint — fast iteration, fits on T4 GPUs
- Real transformer architecture — valid for distributed inference demonstrations
- Instruction-tuned variant (`-it`) enables demos and chat applications

---

## Serving Stack Components

```
┌──────────────────────────────────────────────────────────────────────┐
│                      Gateway / Ingress Layer                          │
│  ┌────────────────┐  ┌──────────────────┐  ┌────────────────────┐   │
│  │ AWS ALB (L7)   │  │ Gateway API      │  │ Envoy AI Gateway   │   │
│  │ (external)     │──│ (internal)       │──│ (rate limit,       │   │
│  │                │  │                  │  │  auth, routing)    │   │
│  └────────────────┘  └──────────────────┘  └────────────────────┘   │
├──────────────────────────────────────────────────────────────────────┤
│                      Routing Layer                                    │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────────┐  │
│  │ KServe Operator  │  │ InferencePool    │  │ InferenceModel    │  │
│  │ (LLMInferenceSvc │  │ (GIE CRD)        │  │ (GIE CRD)         │  │
│  │  controller)     │  │                  │  │                   │  │
│  └──────────────────┘  └──────────────────┘  └───────────────────┘  │
│  ┌──────────────────┐  ┌──────────────────┐                          │
│  │ llm-d EPP        │  │ vLLM Router      │                          │
│  │ (Endpoint Picker │  │ (KV-cache-aware  │                          │
│  │  Pod/ Scheduler) │  │  session routing)│                          │
│  └──────────────────┘  └──────────────────┘                          │
├──────────────────────────────────────────────────────────────────────┤
│                      Inference Layer                                  │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  vLLM Engine Pods                                              │   │
│  │  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐              │   │
│  │  │ vLLM   │  │ vLLM   │  │ vLLM   │  │ vLLM   │              │   │
│  │  │ replica│  │ replica│  │ replica│  │ replica│              │   │
│  │  │ 1      │  │ 2      │  │ 3      │  │ N      │              │   │
│  │  │ T4 GPU │  │ T4 GPU │  │ T4 GPU │  │ T4 GPU │              │   │
│  │  └────────┘  └────────┘  └────────┘  └────────┘              │   │
│  │                                                               │   │
│  │  LeaderWorkerSet (for multi-node)                              │   │
│  │  ┌──────────────────────────────────────────────────────┐     │   │
│  │  │ Leader Pod (gRPC coordinator)                         │     │   │
│  │  │ Worker 0  │ Worker 1  │ Worker 2  │ Worker 3        │     │   │
│  │  │ GPU 0     │ GPU 1     │ GPU 2     │ GPU 3            │     │   │
│  │  └──────────────────────────────────────────────────────┘     │   │
│  └──────────────────────────────────────────────────────────────┘   │
├──────────────────────────────────────────────────────────────────────┤
│                      Observability Layer                             │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ Metrics Exposed by vLLM:                                      │   │
│  │ vllm:num_requests_waiting    (queue depth)                    │   │
│  │ vllm:num_requests_running    (current batch)                  │   │
│  │ vllm:time_to_first_token_seconds (TTFT latency)               │   │
│  │ vllm:request_latency_seconds (end-to-end)                     │   │
│  │ vllm:gpu_cache_usage_perc    (KV cache pressure)              │   │
│  │ vllm:num_requests_preempted  (preemption count)               │   │
│  └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Deployment Patterns (Progressive Complexity)

### Pattern 1: Single-Node vLLM (Gemma 2B — 1 GPU)

**Goal**: Deploy a single replica of Gemma 2B behind KServe.

```
                         ┌─────────────┐
                         │ Gateway API │
                         │ HTTPRoute   │
                         └──────┬──────┘
                                │
                         ┌──────▼──────┐
                         │ KServe      │
                         │ LLMInference│
                         │ Service     │
                         └──────┬──────┘
                                │
                         ┌──────▼──────┐
                         │ vLLM Pod    │
                         │ GPU: 1× T4 │
                         │ TP: 1      │
                         └─────────────┘
```

**Config**:

```yaml
inference:
  model:
    name: "google/gemma-2-2b-it"
  serving:
    engines: 1
    tensorParallelSize: 1
    pipelineParallelSize: 1
  autoscaling:
    minReplicas: 1
    maxReplicas: 3
```

**LLMInferenceService**:

```yaml
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: gemma-2-2b-it
  namespace: ai-inference
spec:
  model:
    uri: hf://google/gemma-2-2b-it
    name: google/gemma-2-2b-it
  replicas: 1
  template:
    containers:
      - name: main
        image: vllm/vllm-openai:latest
        args:
          - "--model"
          - "/mnt/models"
          - "--tensor-parallel-size"
          - "1"
          - "--max-model-len"
          - "8192"
          - "--dtype"
          - "bfloat16"
          - "--gpu-memory-utilization"
          - "0.90"
          - "--enable-prefix-caching"
        resources:
          limits:
            nvidia.com/gpu: "1"
            cpu: "8"
            memory: 32Gi
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 120
          periodSeconds: 30
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "sleep 30"]
  router:
    gateway: {}
    route: {}
    scheduler: {}
```

### Pattern 2: Multi-Replica Data Parallelism (Gemma 2B — 1 GPU each)

**Goal**: Scale horizontally with multiple replicas, each serving the same model.

```
                         ┌──────────────┐
                         │ Envoy AI     │
                         │ Gateway      │
                         └──────┬───────┘
                                │
                         ┌──────▼───────┐
                         │ InferencePool │
                         │ (GIE CRD)     │
                         └──────┬───────┘
                                │
           ┌────────────────────┼────────────────────┐
           │                    │                    │
     ┌─────▼─────┐       ┌─────▼─────┐       ┌─────▼─────┐
     │ vLLM Pod  │       │ vLLM Pod  │       │ vLLM Pod  │
     │ GPU: 1×T4 │       │ GPU: 1×T4 │       │ GPU: 1×T4 │
     │ TP: 1     │       │ TP: 1     │       │ TP: 1     │
     └───────────┘       └───────────┘       └───────────┘
```

**Config**:

```yaml
inference:
  model:
    name: "google/gemma-2-2b-it"
  serving:
    engines: 3
    tensorParallelSize: 1
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    metrics:
      - type: queue_depth
        threshold: 5
```

### Pattern 3: Multi-Node Tensor Parallelism (Future — Larger Model)

**Goal**: Distribute a single model across multiple GPUs/nodes using tensor parallelism.

```
                         ┌──────────────┐
                         │ KServe       │
                         │ LLMInfSvc    │
                         │ parallelism: │
                         │  TP: 4       │
                         │  DP: 2       │
                         └──────┬───────┘
                                │
                    ┌───────────┴───────────┐
                    │                       │
              ┌─────▼─────┐          ┌──────▼──────┐
              │ LWS Group  │          │  LWS Group  │
              │ (TP=4)     │          │  (TP=4)     │
              │            │          │             │
              │ ┌──────┐   │          │  ┌──────┐   │
              │ │Leader│   │          │  │Leader│   │
              │ │GPU 0  │   │          │  │GPU 0  │   │
              │ ├──────┤   │          │  ├──────┤   │
              │ │Worker│   │          │  │Worker│   │
              │ │GPU 1  │   │          │  │GPU 1  │   │
              │ ├──────┤   │          │  ├──────┤   │
              │ │Worker│   │          │  │Worker│   │
              │ │GPU 2  │   │          │  │GPU 2  │   │
              │ ├──────┤   │          │  ├──────┤   │
              │ │Worker│   │          │  │Worker│   │
              │ │GPU 3  │   │          │  │GPU 3  │   │
              │ └──────┘   │          │  └──────┘   │
              └────────────┘          └─────────────┘
```

### Pattern 4: Disaggregated Prefill/Decode (llm-d — Future)

**Goal**: Separate prefill (compute-intensive) and decode (memory-intensive) into independent pools.

See [01-architecture.md](01-architecture.md#pattern-3--disaggregated-prefilldecode-70b-405b-moe-models) for the full diagram.

---

## Autoscaling Strategy

### Why Not CPU-Based Scaling?

LLM inference is GPU-bound, not CPU-bound. CPU utilization stays flat regardless of load. Scaling must be based on vLLM-specific metrics.

### Metric Configuration

```yaml
# Config-driven KEDA ScaledObject
autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: queue_depth
      name: vllm:num_requests_waiting
      threshold: 5          # Scale up when 5+ requests waiting
    - type: kv_cache
      name: vllm:gpu_cache_usage_perc
      threshold: 0.85        # Scale up when KV cache > 85%
  cooldownPeriod: 300        # Wait 5 min before scaling down
  pollingInterval: 15        # Check every 15 seconds
```

### KEDA ScaledObject (Generated from Config)

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: gemma-2b-scaler
  namespace: ai-inference
spec:
  scaleTargetRef:
    apiVersion: serving.kserve.io/v1alpha1
    kind: LLMInferenceService
    name: gemma-2-2b-it
  pollingInterval: 15
  cooldownPeriod: 300
  minReplicaCount: 1
  maxReplicaCount: 5
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleDown:
          stabilizationWindowSeconds: 300
          policies:
            - type: Percent
              value: 100
              periodSeconds: 15
        scaleUp:
          stabilizationWindowSeconds: 0  # Immediate scale up
          policies:
            - type: Pods
              value: 2
              periodSeconds: 15
  triggers:
    - type: prometheus
      metricType: AverageValue
      metadata:
        serverAddress: http://prometheus.monitoring.svc.cluster.local:9090
        metricName: vllm_queue_depth
        query: |
          avg(vllm:num_requests_waiting{namespace="ai-inference"})
        threshold: "5"
    - type: prometheus
      metricType: AverageValue
      metadata:
        serverAddress: http://prometheus.monitoring.svc.cluster.local:9090
        metricName: vllm_kv_cache_usage
        query: |
          avg(vllm:gpu_cache_usage_perc{namespace="ai-inference"})
        threshold: "0.85"
    - type: prometheus
      metricType: AverageValue
      metadata:
        serverAddress: http://prometheus.monitoring.svc.cluster.local:9090
        metricName: vllm_running_requests
        query: |
          avg(vllm:num_requests_running{namespace="ai-inference"}) /
          avg(vllm:num_requests_running{namespace="ai-inference"}) + 1
        threshold: "0"
```

---

## Graceful Operations

### Pod Termination Grace Period

```yaml
# Required for vLLM — prevents dropping in-flight requests
terminationGracePeriodSeconds: 300  # 5 minutes for ongoing generations

lifecycle:
  preStop:
    exec:
      command:
        - /bin/sh
        - -c
        - |
          # Wait for load balancer to drain this pod
          sleep 30
          # Signal vLLM to stop accepting new requests
          # vLLM handles graceful shutdown internally
```

### Readiness and Liveness

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 60    # Model loading time
  periodSeconds: 10
  failureThreshold: 30       # 300 seconds max startup time

livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 120
  periodSeconds: 30
  failureThreshold: 10
```

### Shared Memory (Required for Tensor Parallelism)

```yaml
# Required for multi-GPU tensor parallelism
volumes:
  - name: shm
    emptyDir:
      medium: Memory
      sizeLimit: 20Gi
```

---

## Multi-Model Serving

The platform supports serving multiple models simultaneously via KServe LLMInferenceService:

```yaml
# gemma-2-2b-it.yaml
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: gemma-2-2b-it
---
# gemma-2-9b-it.yaml
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: gemma-2-9b-it
```

Each gets its own:
- LLMInferenceService CRD
- InferencePool + InferenceModel (GIE)
- HTTPRoute (for path/model-based routing)
- Autoscaling configuration

Clients select the model via the OpenAI API `model` field:

```bash
curl http://llm-inference.ai-platform.svc/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "google/gemma-2-2b-it",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```
