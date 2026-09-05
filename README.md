# OpenTelemetry Observability Skill for Antigravity

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-v1.30+-orange.svg)](https://opentelemetry.io)
[![eBPF](https://img.shields.io/badge/eBPF-Linux_5.8+-green.svg)](https://ebpf.io)

An enterprise-grade, authoritative knowledge repository, architecture guide, and operational skill for Antigravity and AI coding agents. This repository covers the complete OpenTelemetry ecosystem: Traces, Metrics, Logs, Profiles, OpAMP fleet management, eBPF auto-instrumentation, continuous profiling, distributed systems causality, custom collector engineering with OCB, and high-cardinality storage.

---

## 🏛️ Architecture & Knowledge Graph

```
                                +---------------------------+
                                |  Application Runtimes     |
                                |  (Go, Java, Python, Node) |
                                +---------------------------+
                                              |
                     +------------------------+------------------------+
                     | (OTel API / SDK)                                | (Raw Sockets / TLS)
                     v                                                 v
        +----------------------------+                   +----------------------------+
        | In-Process OTel SDK        |                   | eBPF Auto-Instrumentation  |
        | - W3C TraceContext         |                   | - Grafana Beyla            |
        | - BaggageSpanProcessor     |                   | - kprobes / fentry / TC    |
        | - Log Bridge API           |                   | - TLS Uprobes (Plaintext)  |
        | - OpenMetrics Exemplars    |                   | - Lockless SPSC RingBuffer |
        +----------------------------+                   +----------------------------+
                     |                                                 |
                     | (OTLP gRPC:4317 / HTTP:4318)                    | (OTLP)
                     +------------------------+------------------------+
                                              |
                                              v
                              +-------------------------------+
                              | Tier 1: Node Agent DaemonSet  |
                              | - OTel Custom Distribution    |
                              | - k8sattributes, hostmetrics  |
                              | - loadbalancingexporter       |
                              |   (Hash: trace_id)            |
                              +-------------------------------+
                                              |
                                              | (Consistent Hash by TraceID)
                                              v
                              +-------------------------------+
                              | Tier 2: Stateful Gateway Pool |
                              | - tail_sampling processor     |
                              | - spanmetrics connector       |
                              | - file_storage disk queue     |
                              +-------------------------------+
                                              |
             +--------------------------------+--------------------------------+
             |                                |                                |
             v                                v                                v
+--------------------------+    +--------------------------+    +--------------------------+
| Traces & Latency Graphs  |    | Metrics & Time-Series    |    | Logs & Events            |
| - Grafana Tempo / Jaeger |    | - Prometheus / Mimir     |    | - Grafana Loki           |
| - ClickHouse (MergeTree) |    | - ClickHouse Metrics     |    | - ClickHouse (Logs)      |
+--------------------------+    +--------------------------+    +--------------------------+
```

---

## 📂 Repository Contents

```
.
├── SKILL.md                                # Master skill manifest with trigger conditions & anti-patterns
├── README.md                               # Project documentation and architectural overview
├── LICENSE                                 # Apache 2.0 License
├── references/                             # Detailed technical specifications and guides
│   ├── core-concepts-and-signals.md        # The 4 signals: Traces, Metrics, Logs, Profiles
│   ├── otel-specification.md               # API vs SDK, in-memory buffering, batching, and samplers
│   ├── semantic-conventions-and-schemas.md # SemConv (HTTP, DB, RPC, Messaging, GenAI/LLM) & Schema URLs
│   ├── opamp-fleet-management.md           # Open Agent Management Protocol (Supervisor vs Extension)
│   ├── correlation-mechanisms.md           # W3C TraceContext, Baggage, Log Bridge, Exemplars
│   ├── ebpf-observability.md               # kprobes, fentry/fexit, uprobes, TLS, Beyla, CO-RE/BTF
│   ├── continuous-profiling.md             # OTel Profiling Data Model (OTEP 0212), on/off-CPU flamegraphs
│   ├── distributed-causality.md            # Span Links vs Parent Spans, Kafka, clock skew, failure modes
│   ├── custom-collectors-ocb.md            # OpenTelemetry Collector Builder (OCB), distroless builds
│   ├── pipelines-and-routing.md            # Pipeline rules, OTTL syntax, spanmetrics & routing connectors
│   ├── sampling-and-scaling.md             # Head vs tail sampling, 2-tier consistent hashing
│   ├── performance-and-tuning.md           # memory_limiter formulas, GOMEMLIMIT, file_storage queues
│   ├── kubernetes-topologies.md            # DaemonSet vs Gateway vs Sidecar, OTel Operator CRDs
│   └── storage-backends.md                 # ClickHouse MergeTree schemas, Grafana Mimir, Tempo v2
└── examples/                               # Production-ready configuration and code snippets
    ├── collector/                          # Agent, Gateway, and OCB builder configurations
    ├── opamp/                              # OpAMP Supervisor and Collector Extension configs
    ├── ebpf/                               # Beyla config and hardened Kubernetes DaemonSet
    ├── kubernetes/                         # Production DaemonSet, StatefulSet, and Operator CRDs
    ├── storage/                            # ClickHouse SQL schema with Bloom filters & codecs
    ├── docker/                             # Multi-stage distroless Dockerfile for custom collectors
    └── code/                               # Go, Kafka, Prometheus, Profiling, and GenAI examples
```

---

## 🚀 Installation into Antigravity

To register this skill in your local Antigravity environment:

```bash
# Option 1: Symlink into Antigravity skills directory
ln -s "$(pwd)" ~/.gemini/config/skills/opentelemetry-observability

# Option 2: Copy directly
mkdir -p ~/.gemini/config/skills/opentelemetry-observability
cp -R * ~/.gemini/config/skills/opentelemetry-observability/
```

Once installed, Antigravity will automatically load this skill when prompted about OpenTelemetry, eBPF, collector configuration, telemetry correlation, OpAMP, or distributed systems tracing.

---

## 📄 License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
