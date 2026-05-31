# Observability Architecture

> **Source of Truth** — Metrics, logging, tracing, dashboards, and alerting design.
> Last updated: 2026-05-31

## Stack Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│  METRICS                LOGS                TRACES                   │
│                                                                     │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐            │
│  │ Prometheus   │   │ Loki         │   │ Tempo        │            │
│  │ + AlertMgr   │   │              │   │              │            │
│  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘            │
│         │                  │                  │                      │
│         ▼                  ▼                  ▼                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    Grafana                                    │  │
│  │  Data Sources: Prometheus, Loki, Tempo, OpenCost              │  │
│  │  Dashboards: LLM Inference, GPU, Cost, Platform, K8s         │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  OpenCost                                                     │  │
│  │  GPU cost attribution by namespace, model, team               │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Metrics

| Metric | Source | Type | Alert Threshold | Why It Matters |
|--------|--------|:----:|:---------------:|----------------|
| `vllm:num_requests_waiting` | vLLM | Gauge | > 10 | Queue building = need to scale |
| `vllm:gpu_cache_usage_perc` | vLLM | Gauge | > 0.90 | KV cache under pressure |
| `vllm:time_to_first_token_seconds` | vLLM | Histogram | p99 > 5s | User-perceived latency |
| `vllm:num_requests_running` | vLLM | Gauge | — | Current throughput |
| `DCGM_FI_DEV_GPU_UTIL` | DCGM Exporter | Gauge | — | GPU duty cycle |
| `DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL` | DCGM Exporter | Gauge | > 0.95 | GPU OOM risk |
| `container_cpu_usage_seconds_total` | kubelet | Counter | — | CPU usage |
| `container_memory_working_set_bytes` | kubelet | Gauge | > 0.90 limit | Memory pressure |

## Dashboards

### LLM Inference Dashboard
- TTFT (p50, p95, p99) over time
- Number of running/pending/finished requests
- GPU KV cache usage (per GPU)
- Token throughput (input + output tokens/sec)
- Request latency distribution
- Queue depth

### GPU Utilization Dashboard
- GPU utilization per node/pod
- GPU memory usage per node/pod
- GPU temperature
- GPU power consumption
- MIG partition utilization (if enabled)

### Cost Attribution Dashboard
- GPU cost per namespace
- GPU cost per model
- GPU cost per team
- Cumulative cost over time

### Platform Health Dashboard
- Cluster resource usage (CPU, memory, pods)
- Node health
- PVC usage
- Service availability
- API error rates

## ServiceMonitors

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vllm-engine
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: vllm
  namespaceSelector:
    matchNames:
      - ai-inference
  endpoints:
    - port: metrics
      interval: 15s
      path: /metrics
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nvidia-dcgm
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/component: gpu-metrics
  namespaceSelector:
    any: true
  endpoints:
    - port: metrics
      interval: 15s
      path: /metrics
```

## Alerting Rules

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: ai-platform-alerts
  namespace: monitoring
spec:
  groups:
    - name: llm-inference
      rules:
        - alert: HighTTFT
          expr: |
            histogram_quantile(0.99,
              rate(vllm:time_to_first_token_seconds_bucket[5m])
            ) > 5
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "TTFT P99 > 5s"
            description: "Model {{ $labels.model }} TTFT P99 is {{ $value }}s"

        - alert: KVCachePressure
          expr: vllm:gpu_cache_usage_perc > 0.90
          for: 2m
          labels:
            severity: warning
          annotations:
            summary: "KV cache > 90%"
            description: "GPU {{ $labels.gpu }} KV cache at {{ $value }}%"

        - alert: QueueGrowing
          expr: vllm:num_requests_waiting > 10
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "Request queue growing"
            description: "{{ $value }} requests waiting for {{ $labels.model }}"

    - name: gpu
      rules:
        - alert: GPUMemoryPressure
          expr: |
            DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL > 0.95
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "GPU memory > 95%"
            description: "GPU {{ $labels.gpu_uuid }} memory at {{ $value }}%"
```
