---
description: Tail-based sampling architectures, two-tier consistent hashing with loadbalancingexporter, and high-throughput sampling policies.
metadata:
  tags: [sampling, tail-sampling, loadbalancingexporter, consistent-hashing, scaling]
---

# Sampling & Scaling at Scale

Balancing observability fidelity with telemetry volume requires intelligent sampling topologies.

---

## 1. Head-Based vs. Tail-Based Sampling

- **Head-Based Sampling (SDK Level)**: Sampling decision is made at the root span before latency or errors occur. Fast and stateless, but inevitably discards critical 5xx errors or unexpected latency outliers when sample rates are low.
- **Tail-Based Sampling (Collector Level)**: Collector buffers all spans belonging to a trace until the transaction finishes. Evaluates rules on the **entire trace** (e.g., keep 100% of errors, 100% of slow requests, 1% of normal requests).

---

## 2. Two-Tier Consistent Hashing Architecture

**The Challenge**: A distributed trace consists of multiple spans emitted across various microservices. In a multi-replica collector deployment behind a Round-Robin load balancer, different spans of the same trace land on different collector pods, breaking tail sampling.

**The Solution**:
1. **Tier 1 (Agent / Router Tier)**: Stateless collectors run on each node (DaemonSet) with `loadbalancingexporter` configured with `routing_key: "trace_id"`.
2. **Consistent Hashing**: The exporter hashes the 16-byte `trace_id` to route all spans of that trace to the exact same Tier 2 Gateway replica.
3. **Tier 2 (Gateway Tier)**: StatefulSet running `tail_sampling` with guaranteed trace-span cohesion.

```
Microservice Spans
       │
       ▼ (Local Node OTLP)
[ Tier 1: Agent DaemonSet ] (Runs loadbalancingexporter)
       │
       │ Consistent Hash: hash(trace_id) % Gateway_Replicas
       ├─────────────────────┬─────────────────────┐
       ▼                     ▼                     ▼
[ Gateway Pod 0 ]     [ Gateway Pod 1 ]     [ Gateway Pod N ]
(tail_sampling A)     (tail_sampling B)     (tail_sampling C)
       │                     │                     │
       └─────────────────────┼─────────────────────┘
                             ▼ (Sampled Traces: 100% Errors, 1% Normal)
               [ Grafana Tempo / ClickHouse ]
```

---

## 3. Production `tail_sampling` Policy

```yaml
processors:
  tail_sampling:
    decision_wait: 10s       # Wait time for late-arriving spans before deciding
    num_traces: 100000        # In-memory trace cache limit
    expected_new_traces_per_sec: 5000
    decision_cache:
      sampled_cache_size: 50000
      non_sampled_cache_size: 50000
    policies:
      # 1. Keep 100% of traces with error status
      - name: error-status
        type: status_code
        status_code: { status_codes: [ ERROR ] }
      # 2. Keep 100% of HTTP 5xx responses
      - name: http-5xx
        type: numeric_attribute
        numeric_attribute:
          key: http.response.status_code
          min_value: 500
          max_value: 599
      # 3. Keep 100% of slow requests (> 1.5s)
      - name: high-latency
        type: latency
        latency: { threshold_ms: 1500 }
      # 4. Statistical baseline: keep 1% of normal requests
      - name: probabilistic-sample
        type: probabilistic
        probabilistic: { sampling_percentage: 1.0 }
```
