---
description: Kubernetes deployment topologies for OpenTelemetry (DaemonSet, Gateway, Sidecar) and OpenTelemetry Operator CRDs.
metadata:
  tags: [kubernetes, daemonset, statefulset, operator, crd, auto-instrumentation]
---

# Kubernetes Topologies & Operator CRDs

Choosing the correct deployment pattern balances resource consumption, security boundaries, and telemetry capabilities.

---

## 1. Deployment Model Comparison

| Dimension | DaemonSet (Node Agent) | Gateway Cluster (Deployment / StatefulSet) | Sidecar Pattern |
| :--- | :--- | :--- | :--- |
| **Resource Efficiency** | **Highest** (1 per node) | **High** (dynamically shared pool) | **Lowest** (overhead per pod) |
| **Blast Radius** | Medium (node level) | Low (distributed behind HPA) | **Lowest** (single pod) |
| **Host Metric Access** | **Native** (/proc, /sys) | None (Network ingestion only) | None |
| **Tail-Based Sampling** | Not feasible alone | **Native** (with consistent hashing) | Not feasible |
| **Best Used For** | Log tailing, host metrics, local OTLP | Tail sampling, heavy enrichment, egress | Fargate, Serverless, Multi-tenant |

---

## 2. OpenTelemetry Operator CRDs

The CNCF OpenTelemetry Operator manages collectors and injects language SDKs declaratively.

### 2.1 `OpenTelemetryCollector` CRD
```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: cluster-gateway
  namespace: monitoring
spec:
  mode: deployment
  replicas: 3
  image: ghcr.io/enterprise/otelcol-custom:1.4.0
  resources:
    limits:
      cpu: "2"
      memory: 4Gi
    requests:
      cpu: "500m"
      memory: 1Gi
  config:
    receivers:
      otlp:
        protocols:
          grpc: { endpoint: 0.0.0.0:4317 }
          http: { endpoint: 0.0.0.0:4318 }
    processors:
      memory_limiter:
        check_interval: 250ms
        limit_percentage: 80
        spike_limit_percentage: 20
      batch:
        send_batch_size: 8192
        timeout: 1s
    exporters:
      otlp/tempo:
        endpoint: tempo.monitoring.svc.cluster.local:4317
        tls: { insecure: true }
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [otlp/tempo]
```

### 2.2 `Instrumentation` CRD (Zero-Code Injection)
Injects Java, Node.js, Python, or Go auto-instrumentation agents directly into pods via annotations (`instrumentation.opentelemetry.io/inject-java: "true"`):

> ⚠️ Verify current version: the four auto-instrumentation image tags below release independently. Check https://github.com/open-telemetry/opentelemetry-operator/releases for the current tags before applying this CR.

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: auto-instrumentation
  namespace: default
spec:
  exporter:
    endpoint: http://otel-agent.monitoring.svc.cluster.local:4318
  propagators:
    - tracecontext
    - baggage
  java:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:2.0.0
  nodejs:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.55.0
  python:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:0.50b0
  go:
    image: ghcr.io/open-telemetry/opentelemetry-go-instrumentation/autoinstrumentation-go:v0.19.0-alpha
```
