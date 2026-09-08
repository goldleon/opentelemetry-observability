# OpenTelemetry Observability Skill for Antigravity

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-v1.30+-orange.svg)](https://opentelemetry.io)
[![eBPF](https://img.shields.io/badge/eBPF-Linux_5.8+-green.svg)](https://ebpf.io)

An enterprise-grade, authoritative knowledge repository, architecture guide, and operational skill for Antigravity and AI coding agents. This repository covers the complete, end-to-end OpenTelemetry ecosystem: Traces, Metrics, Logs, Profiles, OpAMP fleet management, eBPF auto-instrumentation, continuous profiling, distributed systems causality, frontend RUM (Core Web Vitals), ingress & service mesh, CI/CD pipeline tracing, APM service graphs, OTTL transformation recipes, FinOps cardinality control, zero-trust mTLS security, resilient disk-backed buffering, polyglot application instrumentation, Helm & Terraform IaC, high-cardinality storage, and Google SRE multi-burn-rate alerting.

---

## 🏛️ End-to-End Enterprise Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ 1. EDGE & CLIENT RUNTIME (Browser / Mobile / CI Pipelines)                                  │
│                                                                                             │
│  [ Web Browser: Faro / @opentelemetry/sdk-trace-web ]         [ CI/CD Runners: GHA/GitLab ] │
│   • CWV (LCP, CLS, INP) Spans & Metrics                        • Pipeline Root Spans        │
│   • Session ID & Baggage Generation                            • Step & Stage Child Spans   │
│   • W3C `traceparent`, `tracestate`, `baggage`                 • VCS & Commit Metadata      │
└───────────────────────────────────────┬───────────────────────────────────┬─────────────────┘
                                        │ HTTP/Fetch + CORS                 │ OTLP / gRPC
                                        ▼                                   ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ 2. INGRESS, API GATEWAY & SERVICE MESH                                                      │
│                                                                                             │
│  [ Kong / Traefik / Envoy / Istio Ingress Gateway ]                                         │
│   • Validates & propagates inbound `traceparent` (avoids trace breaking)                    │
│   • Generates Ingress Gateway Server Span (SPAN_KIND_SERVER)                                │
│   • Downstream Envoy Sidecars / Istio Service Mesh inject client/server span pairs          │
└───────────────────────────────────────┬─────────────────────────────────────────────────────┘
                                        │ OTLP (mTLS gRPC :4317 / HTTP :4318)
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ 3. OPENTELEMETRY COLLECTOR PIPELINE                                                         │
│                                                                                             │
│  Receivers: otlp (grpc/http), filelog, hostmetrics                                          │
│  Processors: memory_limiter, redaction (PII), transform (OTTL), filter, batch               │
│  Connectors:                                                                                │
│   ├── servicegraphconnector  ──> DAG Service Map Metrics (request_total, duration)          │
│   └── spanmetricsconnector   ──> RED & SLO Metrics (calls_total, latency buckets)           │
│  Extensions: file_storage (disk-backed persistent queue for downstream resilience)          │
└───────────────────────┬───────────────────────────────────────────┬─────────────────────────┘
                        │ Metrics (PromQL)                          │ Traces (OTLP)
                        ▼                                           ▼
┌───────────────────────────────────────────────┐   ┌─────────────────────────────────────────┐
│ 4. METRICS & ALERTING                         │   │ 5. DISTRIBUTED TRACE STORAGE & APM      │
│                                               │   │                                         │
│  [ Prometheus / Mimir / VictoriaMetrics ]     │   │  [ Grafana Tempo / ClickHouse / Jaeger ]│
│   • Multi-Window Multi-Burn-Rate (MWMBR) SLOs │   │   • Dynamic APM DAG Topology Graph      │
│   • Alertmanager (Critical Page / Warning)    │   │   • Exemplar links to traces            │
└───────────────────────────────────────────────┘   └─────────────────────────────────────────┘
```

---

## 📂 Repository Contents

```
.
├── SKILL.md                                # Master skill manifest with trigger conditions & anti-patterns
├── README.md                               # Project documentation and architectural overview
├── LICENSE                                 # Apache 2.0 License
├── references/                             # Detailed technical specifications and guides (26 files)
│   ├── core-concepts-and-signals.md        # The 4 signals: Traces, Metrics, Logs, Profiles
│   ├── otel-specification.md               # API vs SDK, in-memory buffering, batching, and samplers
│   ├── semantic-conventions-and-schemas.md # SemConv (HTTP, DB, RPC, Messaging, GenAI/LLM) & Schema URLs
│   ├── frontend-and-mobile-rum.md          # Web RUM, Core Web Vitals (INP, LCP, CLS), CORS propagation
│   ├── ingress-and-service-mesh.md         # Envoy Proxy OTel tracer, Istio Telemetry API, Kong/Traefik
│   ├── cicd-observability.md               # CI/CD pipeline tracing (GitHub Actions, GitLab CI, Jenkins)
│   ├── opamp-fleet-management.md           # Open Agent Management Protocol (Supervisor vs Extension)
│   ├── correlation-mechanisms.md           # W3C TraceContext, Baggage, Log Bridge, Exemplars
│   ├── ebpf-observability.md               # kprobes, fentry/fexit, uprobes, TLS, Beyla, CO-RE/BTF
│   ├── continuous-profiling.md             # OTel Profiling Data Model (OTEP 0212), on/off-CPU flamegraphs
│   ├── distributed-causality.md            # Span Links vs Parent Spans, Kafka, clock skew, failure modes
│   ├── custom-collectors-ocb.md            # OpenTelemetry Collector Builder (OCB), distroless builds
│   ├── pipelines-and-routing.md            # Pipeline rules, OTTL syntax, spanmetrics & routing connectors
│   ├── ottl-transformation-language.md     # OTTL specification, contexts, function index, and recipes
│   ├── cardinality-and-cost-optimization.md# Metric cardinality stripping, FinOps, probe suppression
│   ├── security-compliance-and-pii.md      # Zero-trust mTLS, redactionprocessor, multi-tenancy routing
│   ├── resilience-and-backpressure.md      # file_storage persistent queues, memory_limiter formulas
│   ├── service-graphs-and-topology.md      # APM service map generation via servicegraphconnector
│   ├── sampling-and-scaling.md             # Head vs tail sampling, 2-tier consistent hashing
│   ├── performance-and-tuning.md           # memory_limiter formulas, GOMEMLIMIT, file_storage queues
│   ├── collector-deployment-patterns.md    # 6 patterns: DaemonSet, Gateway, Sidecar, Fargate, Multi-Tier, Signal-Isolated
│   ├── kubernetes-topologies.md            # DaemonSet vs Gateway vs Sidecar, OTel Operator CRDs
│   ├── infrastructure-as-code.md           # GitOps, Helm, Terraform, and config validation pipelines
│   ├── storage-backends.md                 # ClickHouse, Grafana Mimir, Tempo v2, Loki, VictoriaMetrics
│   ├── slos-and-burn-rate-alerting.md      # Google SRE Multi-Window Multi-Burn-Rate (MWMBR) alerting
│   └── polyglot-application-instrumentation.md # Java Spring Boot, Python FastAPI, Node.js, .NET patterns
└── examples/                               # Production-ready configuration and code snippets
    ├── collector/                          # Agent, Gateway, OTTL cookbook, FinOps, mTLS, and OCB configs
    ├── opamp/                              # OpAMP Supervisor and Collector Extension configs
    ├── ebpf/                               # Beyla config and hardened Kubernetes DaemonSet
    ├── frontend/                           # Browser RUM with CWV and ZoneContextManager
    ├── mesh/                               # Envoy OTel tracer, Istio Telemetry CRD, Kong plugin
    ├── cicd/                               # GitHub Actions & GitLab CI pipeline tracing configs
    ├── kubernetes/                         # Production DaemonSet, StatefulSet, Sidecar, Hybrid, Signal-Isolated & Fargate
    ├── storage/                            # ClickHouse multi-signal SQL, Mimir, Tempo, Loki, VictoriaMetrics
    ├── alerting/                           # Prometheus MWMBR SLO rules and Alertmanager routing
    ├── docker/                             # Multi-stage distroless Dockerfile for custom collectors
    ├── code/                               # Polyglot apps (Java, Python, Node, .NET, Go, Kafka, GenAI)
    ├── helm/                               # Production Helm chart (opentelemetry-stack)
    ├── terraform/                          # Terraform module for OpenTelemetry Operator
    └── benchmarking/                       # telemetrygen load testing and benchmarking script
```

---

## 🚀 Installation into Antigravity

To register this skill in your local Antigravity environment:

```bash
# Direct Copy
mkdir -p ~/.gemini/config/skills/opentelemetry-observability
cp -R * ~/.gemini/config/skills/opentelemetry-observability/
```

---

## 🚀 Installation into Claude Code

`SKILL.md`'s YAML frontmatter format is shared across Claude Code and Antigravity, so the same contents drop in unchanged — only the destination directory differs.

```bash
# Project-level (this repo's skill available only inside one project)
mkdir -p .claude/skills/opentelemetry-observability
cp -R * .claude/skills/opentelemetry-observability/

# User-level (skill available across all your projects)
mkdir -p ~/.claude/skills/opentelemetry-observability
cp -R * ~/.claude/skills/opentelemetry-observability/
```

---

## 📄 License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
