---
description: OpenTelemetry servicegraphconnector architecture, computing dynamic Directed Acyclic Graph (DAG) service maps from spans.
metadata:
  tags: [service-graph, apm, topology, dag, servicegraphconnector]
---

# Service Graphs & APM Topology Generation

Modern APM dashboards render living dependency topologies showing service-to-service communication edges, request rates, error percentages, and latency percentiles.

The OpenTelemetry Collector **`servicegraphconnector`** generates this entire topological DAG directly from in-flight traces in real time, without storing or scanning raw trace databases!

---

## 1. How the `servicegraphconnector` Works

1. **Span Pairing**:
   - The connector examines incoming spans.
   - When a `SPAN_KIND_CLIENT` span and a `SPAN_KIND_SERVER` span share the same `trace_id` and parent relationship, the connector extracts:
     - Client service: `client`
     - Server service: `server`
     - Edge status: `failed=true|false`
     - Edge latency: $\Delta t$
2. **Virtual Node Ingestion**:
   - For database calls (e.g. `db.system=postgresql`), message queues, or uninstrumented external APIs, only a client span exists.
   - The connector synthesizes a **virtual server node** using `peer.service` or `net.peer.name`.
3. **Metric Emission**:
   The connector emits three standard Prometheus metrics:
   - `traces_servicegraph_request_total`: Request counter with `client`, `server`, `connection_type`, `failed`.
   - `traces_servicegraph_request_failed_total`: Failed request counter.
   - `traces_servicegraph_request_server_seconds`: Duration histogram.

---

## 2. Production Collector Pipeline Wiring

```yaml
connectors:
  servicegraph:
    latency_histogram_buckets: [2ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s]
    dimensions:
      - http.method
      - http.status_code
    store:
      ttl: 2s
      max_items: 250000

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlp/tempo, servicegraph]
    metrics/servicegraph:
      receivers: [servicegraph]
      processors: [memory_limiter, batch]
      exporters: [prometheus]
```
