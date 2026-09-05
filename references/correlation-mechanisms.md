---
description: Comprehensive guide to telemetry correlation mechanics, W3C TraceContext, Baggage, the OpenTelemetry Log Bridge API, and OpenMetrics Exemplars.
metadata:
  tags: [correlation, tracecontext, baggage, log-bridge, exemplars, mdc]
---

# Telemetry Correlation Mechanics & Context Propagation

Correlating distributed traces, diagnostic logs, aggregated metrics, and continuous profiles allows engineers to navigate across telemetry pillars seamlessly during production triage.

---

## 1. W3C TraceContext Specification

The W3C TraceContext standard defines unified HTTP headers and gRPC metadata keys used across distributed systems.

### 1.1 The `traceparent` Header (Mandatory)
A 4-part hyphen-delimited string (55 characters):
`00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`

- **`version`** (`00`): Currently 00. `ff` is invalid.
- **`trace_id`** (32 hex characters / 16 bytes): Globally unique identifier for the distributed transaction. Cannot be all zeros.
- **`parent_id`** (16 hex characters / 8 bytes): Identifier of the caller span (`span_id`). Cannot be all zeros.
- **`trace_flags`** (2 hex characters / 8-bit bitmap):
  - Bit `0` (`01`): **Sampled / Recorded flag**. When set, signals that the caller chose to record and export this trace.

### 1.2 The `tracestate` Header (Optional Routing Metadata)
A comma-delimited list of opaque key-value pairs (max 32 members):
`rojo=123,congo=456,tenant1@vendor=opaqueValue`
Used to forward vendor-specific or cluster-routing metadata across heterogeneous cloud hops without corrupting standard W3C context.

---

## 2. W3C Baggage & The `BaggageSpanProcessor` Pattern

W3C Baggage carries contextual key-value pairs across process boundaries alongside distributed traces (`baggage: user_id=alice,tenant=gold,region=us-east-1`).

> [!CAUTION]
> **Cardinality Explosion Hazard**: W3C Baggage is an **in-memory context carrier**. It is **NOT** automatically attached to span attributes or Prometheus metrics. Automatically converting all baggage keys into metric dimensions will crash time-series databases.

### The `SelectiveBaggageSpanProcessor` Solution
To selectively expose authorized business keys as span attributes, install a custom SDK `SpanProcessor`:

```go
type SelectiveBaggageSpanProcessor struct {
    allowedKeys map[string]struct{}
}

func NewSelectiveBaggageSpanProcessor(keys ...string) *SelectiveBaggageSpanProcessor {
    set := make(map[string]struct{})
    for _, k := range keys {
        set[k] = struct{}{}
    }
    return &SelectiveBaggageSpanProcessor{allowedKeys: set}
}

func (p *SelectiveBaggageSpanProcessor) OnStart(parent context.Context, s trace.ReadWriteSpan) {
    bag := baggage.FromContext(parent)
    for _, member := range bag.Members() {
        if _, ok := p.allowedKeys[member.Key()]; ok {
            s.SetAttributes(attribute.String("baggage."+member.Key(), member.Value()))
        }
    }
}
func (p *SelectiveBaggageSpanProcessor) OnEnd(s trace.ReadOnlySpan) {}
func (p *SelectiveBaggageSpanProcessor) Shutdown(ctx context.Context) error { return nil }
func (p *SelectiveBaggageSpanProcessor) ForceFlush(ctx context.Context) error { return nil }
```

---

## 3. Trace-to-Logs Correlation & The Log Bridge API

Connecting isolated log lines with distributed traces requires injecting active span identifiers into log structures.

### 3.1 Structured Logging via MDC (Mapped Diagnostic Context)
Logging frameworks format log lines with `trace_id` and `span_id`:
```json
{
  "timestamp": "2026-09-05T18:40:00.123Z",
  "level": "ERROR",
  "message": "Payment authorization rejected by upstream gateway",
  "service.name": "order-service",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7",
  "trace_flags": "01",
  "error.code": "CARD_EXPIRED"
}
```
In Grafana Loki or Elasticsearch, querying by `trace_id` instantly returns all structured logs emitted across all microservices participating in that exact request.

### 3.2 The OpenTelemetry Log Bridge Architecture
Rather than replacing existing logging libraries, OpenTelemetry introduces the **Log Bridge API**:
1. Applications continue logging using native frameworks (Zap, Logback, SLF4J).
2. The installed **OTel Log Appender** intercepts the log event.
3. It inspects the current `trace.SpanFromContext(ctx)`.
4. It wraps the log into an OTel `LogRecord` with explicit `TraceID`, `SpanID`, and `TraceFlags`.
5. It submits the record to the SDK `BatchLogRecordProcessor` for asynchronous export over OTLP directly to the collector.

---

## 4. Trace-to-Metrics Correlation & OpenMetrics Exemplars

**Exemplars** attach specific trace identifiers directly to metric observations without inflating metric label cardinality.

```
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{le="0.1"} 2400
http_request_duration_seconds_bucket{le="0.5"} 3100
http_request_duration_seconds_bucket{le="1.0"} 3150 # {trace_id="4bf92f3577b34da6a3ce929d0e0e4736"} 0.852 1788630000.123
http_request_duration_seconds_bucket{le="+Inf"} 3152
http_request_duration_seconds_count 3152
http_request_duration_seconds_sum 420.5
```

- **Storage Efficiency**: Prometheus (2.26+) and Grafana Mimir store exemplars in a lightweight, circular in-memory buffer without creating new time-series streams.
- **Workflow in Grafana**: In metric histogram panels, outlier latency observations render as interactive dots. Clicking any outlier dot immediately navigates to the distributed trace in Grafana Tempo or Jaeger.
