---
description: Production performance tuning, memory_limiter sizing formulas, Go GOMEMLIMIT, persistent file_storage queues, and gRPC L4/L7 mitigations.
metadata:
  tags: [tuning, sizing, memory-limiter, gomemlimit, file-storage, grpc]
---

# Performance Tuning, Sizing & Resilience

Operating OpenTelemetry Collectors under sustained high-throughput workloads requires defensive memory tuning and resilient queue architectures.

---

## 1. `memory_limiter` Tuning Formula

The `memory_limiter` prevents Linux kernel Out-Of-Memory (OOM) kills by dropping data or issuing backpressure when memory approaches limits.

```
limit_percentage = 100% - ((Spike Overhead + GC Headroom) / Total Pod Memory * 100%)
```

- Recommended values for container memory limit (e.g., 4096MiB):
  - `check_interval`: `250ms` (checks heap 4 times/sec)
  - `limit_percentage`: `80%`
  - `spike_limit_percentage`: `20%`

### Go Runtime Garbage Collection (`GOMEMLIMIT`)
- Set environment variable `GOMEMLIMIT=3600MiB` when container memory limit is `4096MiB` (90% of cgroup limit).
- Prevents aggressive GC thrashing while guaranteeing Go runtime GC cycles trigger before hitting the cgroup hard ceiling.

---

## 2. Persistent Disk-Backed Queues via `file_storage`

Default exporter queues reside in volatile RAM. During downstream backend outages, memory buffers saturate and drop telemetry. The `file_storage` extension provisions write-ahead persistent storage on attached SSD/NVMe volumes.

```yaml
extensions:
  file_storage/traces:
    directory: /var/lib/otelcol/file_storage/traces
    timeout: 1s
    max_mb: 10240 # 10GB disk buffer

exporters:
  otlp/tempo:
    endpoint: tempo-distributor.monitoring.svc.cluster.local:4317
    sending_queue:
      enabled: true
      num_consumers: 16
      queue_size: 50000
      storage: file_storage/traces
    retry_on_failure:
      enabled: true
      initial_interval: 1s
      max_interval: 30s
      max_elapsed_time: 15m
```

---

## 3. gRPC Layer 4 vs. Layer 7 Load Balancing Bottleneck

- **The Problem**: Standard Kubernetes Services load-balance at Layer 4 (TCP). OTLP gRPC multiplexes all RPCs over a single persistent TCP connection. 50 application pods establish connections that stay glued to specific collector pods, causing severe hotspotting.
- **The Mitigations**:
  1. Deploy an **Envoy L7 proxy** for multiplexed frame-level balancing.
  2. Enforce **`max_connection_age: 120s`** on collector gRPC receivers to force clients to reconnect and rebalance periodically:
     ```yaml
     receivers:
       otlp:
         protocols:
           grpc:
             endpoint: 0.0.0.0:4317
             keepalive:
               server_parameters:
                 max_connection_age: 120s
                 max_connection_age_grace: 30s
     ```
