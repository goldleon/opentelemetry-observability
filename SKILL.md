---
name: opentelemetry-observability
description: >-
  Use when architecting, implementing, or troubleshooting OpenTelemetry (OTel) observability, eBPF telemetry, continuous profiling, OpAMP fleet management, context correlation, custom collectors (OCB), service mesh, RUM, or distributed systems tracing.
metadata:
  category: architecture
  triggers: opentelemetry, otel, observability, collector, tracing, metrics, logs, profiles, ebpf, beyla, opamp, w3c-tracecontext, baggage, exemplars, ocb, tail-sampling, rum, service-mesh, envoy, istio, servicegraph, slo, mwmbr, clickhouse, tempo, mimir
---

# OpenTelemetry, eBPF & Distributed Systems Observability

The definitive end-to-end architectural guide and operational toolkit for building cloud-native, production-grade observability platforms using OpenTelemetry (OTel), eBPF, OpAMP, continuous profiling, service mesh, real user monitoring (RUM), and distributed systems design patterns.

## ⚡ Quick Decision Tree

### What are you designing or implementing?

1. **Signals, API/SDK & Conventions:**
   - Understanding Traces, Metrics, Logs, and Profiles data models → [Core Concepts & Signals](references/core-concepts-and-signals.md)
   - API vs. SDK boundaries, batching, thread safety, and built-in samplers → [OTel Specification](references/otel-specification.md)
   - Semantic Conventions (`http.*`, `db.*`, `messaging.*`, `gen_ai.*`) and Schema URLs → [Semantic Conventions & Schemas](references/semantic-conventions-and-schemas.md)

2. **Frontend, Mobile & Ingress:**
   - Web RUM, Core Web Vitals (INP, LCP, CLS), and CORS context propagation → [Frontend & Mobile RUM](references/frontend-and-mobile-rum.md)
   - Envoy Proxy tracer, Istio service mesh, and API Gateways (Kong, Traefik) → [Ingress & Service Mesh](references/ingress-and-service-mesh.md)

3. **Fleet Management & Remoting:**
   - Remote fleet control, binary upgrades, and dynamic configuration via OpAMP → [OpAMP Fleet Management](references/opamp-fleet-management.md)

4. **Context & Correlation Mechanics:**
   - W3C TraceContext, BaggageSpanProcessor, Log Bridge API, and OpenMetrics Exemplars → [Correlation Mechanisms](references/correlation-mechanisms.md)
   - Tracing asynchronous boundaries: Span Links vs. Parent-Child, Kafka, and clock skew → [Distributed Causality](references/distributed-causality.md)
   - Tracing CI/CD pipelines (GitHub Actions, GitLab CI, Jenkins) → [CI/CD Observability](references/cicd-observability.md)

5. **Collector Architecture, Pipelines & Topology:**
   - Pipeline sequencing rules, OTTL transformations, and connectors (`spanmetrics`, `routing`) → [Pipelines & Routing](references/pipelines-and-routing.md)
   - Building a minimal, hardened custom collector binary via OCB → [Custom Collectors with OCB](references/custom-collectors-ocb.md)
   - Dynamic APM DAG topology generation from spans via `servicegraphconnector` → [Service Graphs & Topology](references/service-graphs-and-topology.md)
   - Sizing formulas, memory limiter, GOMEMLIMIT, and persistent queues (`file_storage`) → [Performance & Tuning](references/performance-and-tuning.md)
   - Scaling tail-based sampling with two-tier consistent hashing (`loadbalancingexporter`) → [Sampling & Scaling](references/sampling-and-scaling.md)

6. **eBPF & Continuous Profiling:**
   - Zero-code kernel instrumentation (kprobes, fentry, uprobes for TLS, Beyla, CO-RE) → [eBPF Observability](references/ebpf-observability.md)
   - OTel Profiling Data Model (OTEP 0212), on/off-CPU flamegraphs, and symbolication → [Continuous Profiling](references/continuous-profiling.md)

7. **Infrastructure, Backends & Alerting:**
   - Kubernetes topologies (DaemonSet vs. Gateway vs. Sidecar) and Operator CRDs → [Kubernetes Topologies](references/kubernetes-topologies.md)
   - Multi-signal storage backends: ClickHouse, Grafana Mimir, Tempo v2, Loki, VictoriaMetrics → [Storage Backends](references/storage-backends.md)
   - Google SRE Multi-Window Multi-Burn-Rate (MWMBR) SLO alerting → [SLOs & Burn-Rate Alerting](references/slos-and-burn-rate-alerting.md)

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
                                        │ OTLP (gRPC :4317 / HTTP :4318)
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ 3. OPENTELEMETRY COLLECTOR PIPELINE                                                         │
│                                                                                             │
│  Receivers: otlp (grpc/http), filelog, hostmetrics                                          │
│  Processors: memory_limiter, batch, transform (sanitize PII), tail_sampling                │
│  Connectors:                                                                                │
│   ├── servicegraphconnector  ──> DAG Service Map Metrics (request_total, duration)          │
│   └── spanmetricsconnector   ──> RED & SLO Metrics (calls_total, latency buckets)           │
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

## 🛑 Critical Anti-Patterns & Operational Rules

1. **Pipeline Sequencing Violation**:
   - **Anti-pattern**: Placing `batch` before `memory_limiter` or `tail_sampling`.
   - **Rule**: `memory_limiter` **MUST** be the first processor in every pipeline. `batch` **MUST** be the last processor immediately preceding exporters.
2. **Baggage Cardinality Leaks**:
   - **Anti-pattern**: Automatically copying all W3C Baggage entries onto span attributes or Prometheus metrics.
   - **Rule**: Never expose raw baggage globally. Implement a strict whitelist (`SelectiveBaggageSpanProcessor`) to prevent metrics TSDB cardinality explosions.
3. **Trace Breaking at the API Gateway**:
   - **Anti-pattern**: Configuring an API gateway (Kong, Envoy, NGINX) to unconditionally overwrite `trace_id`.
   - **Rule**: Gateways must preserve and validate incoming W3C `traceparent` headers to keep frontend user interactions connected with backend microservices.
4. **Parent-Child in Asynchronous Message Queues**:
   - **Anti-pattern**: Making a batch consumer span the child of an individual message producer span.
   - **Rule**: Asynchronous message batches, pub/sub fan-outs, and saga compensations must use **Span Links**, preserving independent trace timelines.
5. **Missing ZoneContextManager in Browsers**:
   - **Anti-pattern**: Initializing browser tracing without `@opentelemetry/context-zone`.
   - **Rule**: Asynchronous JavaScript promises drop thread context; Zone.js is required to carry the active span across asynchronous callbacks and fetch calls.
6. **Layer 4 gRPC Load Balancing Bottleneck**:
   - **Anti-pattern**: Routing high-volume gRPC OTLP traffic through standard Kubernetes ClusterIP services.
   - **Rule**: gRPC multiplexes traffic over persistent HTTP/2 TCP streams, causing extreme load hotspotting on a single collector pod. Always use Layer 7 load balancing (Envoy) or enforce `max_connection_age: 120s` on collector gRPC receivers.

---

## 📂 Repository Reference Index

| Topic | Reference Document | Production Examples |
| :--- | :--- | :--- |
| **Signals & Data Models** | [core-concepts-and-signals.md](references/core-concepts-and-signals.md) | [go-context-propagation.go](examples/code/go-context-propagation.go) |
| **OTel Specifications** | [otel-specification.md](references/otel-specification.md) | [prometheus-exemplars.go](examples/code/prometheus-exemplars.go) |
| **Semantic Conventions** | [semantic-conventions-and-schemas.md](references/semantic-conventions-and-schemas.md) | [genai-instrumentation.go](examples/code/genai-instrumentation.go) |
| **Frontend & Web RUM** | [frontend-and-mobile-rum.md](references/frontend-and-mobile-rum.md) | [rum-browser-tracing.ts](examples/frontend/rum-browser-tracing.ts) |
| **Ingress & Service Mesh**| [ingress-and-service-mesh.md](references/ingress-and-service-mesh.md) | [envoy.yaml](examples/mesh/envoy-opentelemetry.yaml), [istio.yaml](examples/mesh/istio-telemetry.yaml) |
| **CI/CD Observability** | [cicd-observability.md](references/cicd-observability.md) | [github-actions.yaml](examples/cicd/github-actions-otel.yaml), [gitlab-ci.yaml](examples/cicd/gitlab-ci-otel.yaml) |
| **OpAMP Fleet Management**| [opamp-fleet-management.md](references/opamp-fleet-management.md) | [supervisor-config.yaml](examples/opamp/supervisor-config.yaml) |
| **Context & Correlation** | [correlation-mechanisms.md](references/correlation-mechanisms.md) | [span-guided-profiling.go](examples/code/span-guided-profiling.go) |
| **Distributed Causality** | [distributed-causality.md](references/distributed-causality.md) | [kafka-span-links.go](examples/code/kafka-span-links.go) |
| **eBPF Instrumentation** | [ebpf-observability.md](references/ebpf-observability.md) | [beyla-config.yaml](examples/ebpf/beyla-config.yaml), [beyla-daemonset.yaml](examples/ebpf/beyla-daemonset.yaml) |
| **Continuous Profiling** | [continuous-profiling.md](references/continuous-profiling.md) | [span-guided-profiling.go](examples/code/span-guided-profiling.go) |
| **Custom Collectors (OCB)**| [custom-collectors-ocb.md](references/custom-collectors-ocb.md) | [ocb-builder-config.yaml](examples/collector/ocb-builder-config.yaml), [Dockerfile](examples/docker/Dockerfile.distroless) |
| **Pipelines & OTTL** | [pipelines-and-routing.md](references/pipelines-and-routing.md) | [gateway-tail-sampling-config.yaml](examples/collector/gateway-tail-sampling-config.yaml) |
| **Service Graphs (APM)** | [service-graphs-and-topology.md](references/service-graphs-and-topology.md) | [gateway-tail-sampling-config.yaml](examples/collector/gateway-tail-sampling-config.yaml) |
| **Sampling & Scaling** | [sampling-and-scaling.md](references/sampling-and-scaling.md) | [agent-daemonset-config.yaml](examples/collector/agent-daemonset-config.yaml) |
| **Tuning & Sizing** | [performance-and-tuning.md](references/performance-and-tuning.md) | [gateway-statefulset.yaml](examples/kubernetes/gateway-statefulset.yaml) |
| **Kubernetes Topologies** | [kubernetes-topologies.md](references/kubernetes-topologies.md) | [agent-daemonset.yaml](examples/kubernetes/agent-daemonset.yaml), [CRDs](examples/kubernetes/opentelemetry-collector-crd.yaml) |
| **Storage Backends** | [storage-backends.md](references/storage-backends.md) | [clickhouse.sql](examples/storage/clickhouse-otel-full-schema.sql), [mimir.yaml](examples/storage/mimir-production-config.yaml), [tempo.yaml](examples/storage/tempo-v2-parquet-config.yaml) |
| **SLO & Burn-Rate Alerts**| [slos-and-burn-rate-alerting.md](references/slos-and-burn-rate-alerting.md) | [slo-mwmbr-rules.yaml](examples/alerting/slo-mwmbr-rules.yaml), [alertmanager.yaml](examples/alerting/alertmanager.yaml) |

---

## ✅ Pre-Deploy Verification Checklist

- [ ] All collector pipelines have `memory_limiter` configured as the first processor.
- [ ] Ingress gateways and CORS preflight explicitly allow `traceparent`, `tracestate`, and `baggage`.
- [ ] Browser RUM initializes `ZoneContextManager` to prevent async context drop.
- [ ] Container `resources.limits.memory` has `GOMEMLIMIT` set to ~90% of the limit.
- [ ] Exporters connecting to remote backends have `sending_queue` backed by `file_storage`.
- [ ] Tail-sampling gateway pods receive cohesive traces via Tier 1 `loadbalancingexporter` on `trace_id`.
- [ ] Service Graph connector is wired between traces pipeline and metrics pipeline for DAG topology.
- [ ] Ingress gRPC receivers enforce `max_connection_age` or run behind an L7 Envoy proxy.
- [ ] Kernel eBPF auto-instrumentation drops unneeded privileges and retains only `CAP_BPF`, `CAP_PERFMON`, and `CAP_NET_ADMIN`.
- [ ] Multi-Window Multi-Burn-Rate (MWMBR) rules are loaded in Prometheus for proactive error budget protection.
