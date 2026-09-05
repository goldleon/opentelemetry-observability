---
name: opentelemetry-observability
description: >-
  Use when architecting, implementing, or troubleshooting OpenTelemetry (OTel) observability, eBPF telemetry, continuous profiling, OpAMP fleet management, context correlation, custom collectors (OCB), or distributed systems tracing.
metadata:
  category: architecture
  triggers: opentelemetry, otel, observability, collector, tracing, metrics, logs, profiles, ebpf, beyla, opamp, w3c-tracecontext, baggage, exemplars, ocb, tail-sampling, clickhouse, tempo, mimir
---

# OpenTelemetry, eBPF & Distributed Systems Observability

The definitive architectural guide and operational toolkit for building cloud-native, production-grade observability platforms using OpenTelemetry (OTel), eBPF, OpAMP, continuous profiling, and distributed systems design patterns.

## ⚡ Quick Decision Tree

### What are you designing or implementing?

1. **Signals, API/SDK & Conventions:**
   - Understanding Traces, Metrics, Logs, and Profiles data models → [Core Concepts & Signals](references/core-concepts-and-signals.md)
   - API vs. SDK boundaries, batching, thread safety, and built-in samplers → [OTel Specification](references/otel-specification.md)
   - Semantic Conventions (`http.*`, `db.*`, `messaging.*`, `gen_ai.*`) and Schema URLs → [Semantic Conventions & Schemas](references/semantic-conventions-and-schemas.md)

2. **Fleet Management & Remoting:**
   - Remote fleet control, binary upgrades, and dynamic configuration via OpAMP → [OpAMP Fleet Management](references/opamp-fleet-management.md)

3. **Context & Correlation Mechanics:**
   - W3C TraceContext, BaggageSpanProcessor, Log Bridge API, and OpenMetrics Exemplars → [Correlation Mechanisms](references/correlation-mechanisms.md)
   - Tracing asynchronous boundaries: Span Links vs. Parent-Child, Kafka, and clock skew → [Distributed Causality](references/distributed-causality.md)

4. **Collector Architecture & Custom Distributions:**
   - Pipeline sequencing rules, OTTL transformations, and connectors (`spanmetrics`, `routing`) → [Pipelines & Routing](references/pipelines-and-routing.md)
   - Building a minimal, hardened custom collector binary via OCB → [Custom Collectors with OCB](references/custom-collectors-ocb.md)
   - Sizing formulas, memory limiter, GOMEMLIMIT, and persistent queues (`file_storage`) → [Performance & Tuning](references/performance-and-tuning.md)
   - Scaling tail-based sampling with two-tier consistent hashing (`loadbalancingexporter`) → [Sampling & Scaling](references/sampling-and-scaling.md)

5. **eBPF & Continuous Profiling:**
   - Zero-code kernel instrumentation (kprobes, fentry, uprobes for TLS, Beyla, CO-RE) → [eBPF Observability](references/ebpf-observability.md)
   - OTel Profiling Data Model (OTEP 0212), on/off-CPU flamegraphs, and symbolication → [Continuous Profiling](references/continuous-profiling.md)

6. **Infrastructure & Backends:**
   - Kubernetes topologies (DaemonSet vs. Gateway vs. Sidecar) and Operator CRDs → [Kubernetes Topologies](references/kubernetes-topologies.md)
   - Storage backends: ClickHouse MergeTree schemas, Grafana Mimir, and Tempo v2 Parquet → [Storage Backends](references/storage-backends.md)

---

## 🏛️ End-to-End Enterprise Architecture

```
+---------------------------------------------------------------------------------------------+
| KUBERNETES NODE                                                                             |
|                                                                                             |
|  +---------------------------+   +---------------------------+   +-----------------------+  |
|  | App Pod A (Go / Java)     |   | App Pod B (Node / Python) |   | Uninstrumented Pod C  |  |
|  | - OTel SDK (W3C Propagator|   | - OTel SDK (Log Bridge)   |   | (Standard TLS HTTP)   |  |
|  +---------------------------+   +---------------------------+   +-----------------------+  |
|               | (OTLP:4317)                   | (OTLP:4317)                  | (Raw Socket) |
|               v                               v                              v              |
|  +-----------------------------------------------------------+  +------------------------+  |
|  | NODE AGENT: OTel Collector (DaemonSet)                    |  | eBPF AGENT: Beyla      |  |
|  | - Receivers: otlp (grpc/http), filelog, hostmetrics       |  | - Hooks: SSL_read/write|  |
|  | - Processors: memory_limiter, k8sattributes, batch        |  |   kprobe/fentry tcp    |  |
|  | - Exporters:                                              |  | - Generates: OTLP Spans|  |
|  |     * Traces  -> loadbalancingexporter (hash: trace_id) -+  |    RED Metrics         |  |
|  |     * Metrics/Logs -> otlpexporter ----------------------+--+------------------------+  |
|  +----------------------------------------------------------|--|----------------------------+
+-------------------------------------------------------------|--|----------------------------+
                                                              |  |
                                                              v  v
+---------------------------------------------------------------------------------------------+
| STATEFUL GATEWAY CLUSTER (StatefulSet + HPA)                                                |
|                                                                                             |
|  +----------------------------------------------------+  +--------------------------------+ |
|  | GATEWAY TIER 2: TRACES & SAMPLING                  |  | GATEWAY TIER 2: METRICS & LOGS | |
|  | - Processor: memory_limiter                        |  | - Processor: memory_limiter    | |
|  | - Processor: tail_sampling (100% 5xx, 1% baseline) |  | - Processor: transform (OTTL)  | |
|  | - Connector: spanmetrics (RED metrics from spans)  |  | - Processor: batch             | |
|  | - Exporter:  otlp -> Grafana Tempo / ClickHouse    |  | - Exporter:  Mimir / Loki / CH | |
|  +----------------------------------------------------+  +--------------------------------+ |
+---------------------------------------------------------------------------------------------+
                               |                                             |
                               v                                             v
               [ Distributed Object Store / ClickHouse ]     [ Prometheus Mimir / S3 ]
```

---

## 🛑 Critical Anti-Patterns & Operational Rules

1. **Pipeline Sequencing Violation**:
   - **Anti-pattern**: Placing `batch` before `memory_limiter` or `tail_sampling`.
   - **Rule**: `memory_limiter` **MUST** be the first processor in every pipeline. `batch` **MUST** be the last processor immediately preceding exporters.
2. **Baggage Cardinality Leaks**:
   - **Anti-pattern**: Automatically copying all W3C Baggage entries onto span attributes or Prometheus metrics.
   - **Rule**: Never expose raw baggage globally. Implement a strict whitelist (`SelectiveBaggageSpanProcessor`) to prevent metrics TSDB cardinality explosions.
3. **Parent-Child in Asynchronous Message Queues**:
   - **Anti-pattern**: Making a batch consumer span the child of an individual message producer span.
   - **Rule**: Asynchronous message batches, pub/sub fan-outs, and saga compensations must use **Span Links**, preserving independent trace timelines.
4. **Unbounded Uretprobes in eBPF**:
   - **Anti-pattern**: Attaching `uretprobe` to high-frequency inner loops (10k+ req/sec).
   - **Rule**: On kernels < 6.11, `uretprobe` breakpoint context-switches degrade p99 latency by 15-25%. Use entry `uprobe` with map timestamps combined with socket `fexit` on read/write syscalls.
5. **Layer 4 gRPC Load Balancing Bottleneck**:
   - **Anti-pattern**: Routing high-volume gRPC OTLP traffic through standard Kubernetes ClusterIP services.
   - **Rule**: gRPC multiplexes traffic over persistent HTTP/2 TCP streams, causing extreme load hotspotting on a single collector pod. Always use Layer 7 load balancing (Envoy) or enforce `max_connection_age: 120s` on collector gRPC receivers.

---

## 📂 Repository Reference Index

| Topic | Reference Document | Production Examples |
| :--- | :--- | :--- |
| **Signals & Data Models** | [core-concepts-and-signals.md](references/core-concepts-and-signals.md) | [go-context-propagation.go](examples/code/go-context-propagation.go) |
| **OTel Specifications** | [otel-specification.md](references/otel-specification.md) | [prometheus-exemplars.go](examples/code/prometheus-exemplars.go) |
| **Semantic Conventions** | [semantic-conventions-and-schemas.md](references/semantic-conventions-and-schemas.md) | [genai-instrumentation.go](examples/code/genai-instrumentation.go) |
| **OpAMP Fleet Management** | [opamp-fleet-management.md](references/opamp-fleet-management.md) | [supervisor-config.yaml](examples/opamp/supervisor-config.yaml) |
| **Context & Correlation** | [correlation-mechanisms.md](references/correlation-mechanisms.md) | [span-guided-profiling.go](examples/code/span-guided-profiling.go) |
| **Distributed Causality** | [distributed-causality.md](references/distributed-causality.md) | [kafka-span-links.go](examples/code/kafka-span-links.go) |
| **eBPF Instrumentation** | [ebpf-observability.md](references/ebpf-observability.md) | [beyla-config.yaml](examples/ebpf/beyla-config.yaml), [beyla-daemonset.yaml](examples/ebpf/beyla-daemonset.yaml) |
| **Continuous Profiling** | [continuous-profiling.md](references/continuous-profiling.md) | [span-guided-profiling.go](examples/code/span-guided-profiling.go) |
| **Custom Collectors (OCB)**| [custom-collectors-ocb.md](references/custom-collectors-ocb.md) | [ocb-builder-config.yaml](examples/collector/ocb-builder-config.yaml), [Dockerfile](examples/docker/Dockerfile.distroless) |
| **Pipelines & OTTL** | [pipelines-and-routing.md](references/pipelines-and-routing.md) | [gateway-tail-sampling-config.yaml](examples/collector/gateway-tail-sampling-config.yaml) |
| **Sampling & Scaling** | [sampling-and-scaling.md](references/sampling-and-scaling.md) | [agent-daemonset-config.yaml](examples/collector/agent-daemonset-config.yaml) |
| **Tuning & Sizing** | [performance-and-tuning.md](references/performance-and-tuning.md) | [gateway-statefulset.yaml](examples/kubernetes/gateway-statefulset.yaml) |
| **Kubernetes Topologies** | [kubernetes-topologies.md](references/kubernetes-topologies.md) | [agent-daemonset.yaml](examples/kubernetes/agent-daemonset.yaml), [CRDs](examples/kubernetes/opentelemetry-collector-crd.yaml) |
| **Storage Backends** | [storage-backends.md](references/storage-backends.md) | [clickhouse-otel-schema.sql](examples/storage/clickhouse-otel-schema.sql) |

---

## ✅ Pre-Deploy Verification Checklist

- [ ] All collector pipelines have `memory_limiter` configured as the first processor.
- [ ] Container `resources.limits.memory` has `GOMEMLIMIT` set to ~90% of the limit.
- [ ] Exporters connecting to remote backends have `sending_queue` backed by `file_storage`.
- [ ] Tail-sampling gateway pods receive cohesive traces via Tier 1 `loadbalancingexporter` on `trace_id`.
- [ ] Ingress gRPC receivers enforce `max_connection_age` or run behind an L7 Envoy proxy.
- [ ] Kernel eBPF auto-instrumentation drops unneeded privileges and retains only `CAP_BPF`, `CAP_PERFMON`, and `CAP_NET_ADMIN`.
- [ ] OpAMP Supervisor runs as an external watchdog handling graceful rolling updates and config rollback.
