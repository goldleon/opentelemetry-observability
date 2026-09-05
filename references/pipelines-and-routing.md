---
description: OpenTelemetry Collector pipeline engine, sequencing rules, OTTL syntax, spanmetrics, and routing connectors.
metadata:
  tags: [pipelines, ottl, spanmetrics, routing, connectors, transform]
---

# Pipelines, OTTL & Connectors

Collector pipelines define how telemetry flows from ingestion to egress. Correct sequencing and declarative transformation prevent memory exhaustion and data corruption.

---

## 1. Pipeline Execution Semantics & Sequencing Rules

In every pipeline, processor sequence is deterministic:
1. **`memory_limiter` MUST ALWAYS BE FIRST**: It monitors runtime heap and drops data or issues backpressure before queues allocate additional memory.
2. **Context & Resource Processors**: `k8sattributes`, `resourcedetection`, and `transform` must run before filtering so downstream stages have complete metadata.
3. **Filter & Tail Sampling**: Drops unneeded spans/logs before expensive batch serialization.
4. **`batch` MUST ALWAYS BE LAST**: Placed immediately before exporters to build optimal payload frames for network transport.

```
[ RECEIVER: otlp ]
       │
       ▼
[ PROCESSOR 1: memory_limiter ]  <-- FIRST: Prevents OOM crashes
       │
       ▼
[ PROCESSOR 2: k8sattributes ]   <-- Enrich pod/namespace metadata
       │
       ▼
[ PROCESSOR 3: transform (OTTL)] <-- Redact PII, clean routes
       │
       ▼
[ PROCESSOR 4: tail_sampling ]   <-- Discard unneeded traces
       │
       ▼
[ PROCESSOR 5: batch ]           <-- LAST: Group into optimal network frames
       │
       ▼
[ EXPORTER: otlp / tempo ]
```

---

## 2. OpenTelemetry Transformation Language (OTTL)

OTTL provides declarative, domain-specific expressions for manipulating telemetry directly inside the collector pipeline (`transformprocessor`).

```yaml
processors:
  transform/production:
    error_mode: ignore
    trace_statements:
      - context: span
        statements:
          # Redact sensitive authentication tokens in query strings
          - replace_all_patterns(attributes, "value", "token=[^&]+", "token=REDACTED")
          # Normalize HTTP route as span name
          - set(name, Concat([attributes["http.request.method"], " ", attributes["http.route"]], "")) where attributes["http.route"] != nil
          # Drop health-check spans completely
          - drop() where attributes["http.route"] == "/healthz" or attributes["http.route"] == "/ready"

    log_statements:
      - context: log
        statements:
          # Parse raw JSON string bodies into structured attributes
          - merge_maps(attributes, ParseJSON(body), "insert") where IsString(body)
          # Scrub credit card PANs via regex
          - replace_all_patterns(attributes, "value", "\\b(?:\\d[ -]*?){13,16}\\b", "[REDACTED_PAN]")
```

---

## 3. Connectors: `spanmetrics` & `routing`

Connectors act as an exporter in one pipeline and a receiver in another without network hops.

### 3.1 `spanmetrics` Connector
Computes Golden Signals (Request Rate, Error Count, and Latency Histograms) from incoming traces before traces are sampled or discarded.
```yaml
connectors:
  spanmetrics:
    histogram:
      explicit:
        buckets: [2ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s]
    dimensions:
      - name: http.response.status_code
      - name: http.request.method
```

### 3.2 `routing` Connector
Routes telemetry dynamically to specific pipelines based on resource attributes:
```yaml
connectors:
  routing:
    table:
      - statement: route() where resource.attributes["cloud.provider"] == "aws"
        pipelines: [traces/aws]
      - statement: route() where resource.attributes["cloud.provider"] == "gcp"
        pipelines: [traces/gcp]
```
