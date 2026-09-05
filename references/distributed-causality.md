---
description: Distributed systems causality, Span Links vs Parent Spans, Kafka context propagation, clock skew correction, and failure modes.
metadata:
  tags: [causality, span-links, kafka, clock-skew, retry-storms, cascading-timeouts]
---

# Distributed Systems Causality & Asynchronous Tracing

Accurately representing causal relationships across asynchronous boundaries, message queues, and out-of-sync distributed clocks is essential for microservice observability.

---

## 1. Span Links vs. Parent-Child Relationships

```
SYNCHRONOUS RPC (Parent-Child)
Client Span [0ms ---------------------------------------------- 100ms]
    └── Server Child Span [10ms ------------------------- 80ms]

ASYNCHRONOUS BATCHING (Span Links)
Producer Span 1 (Order 101) [0ms -- 20ms]
Producer Span 2 (Order 102) [5ms -- 25ms]
                                \       /
                         (Span Links)  (Span Links)
                                  v   v
Batch Consumer Worker Span [100ms --------------------------- 350ms]
    ├── Process Order 101 [110ms ---- 200ms]
    └── Process Order 102 [210ms ---- 330ms]
```

### 1.1 Architectural Decision Matrix

| Workflow Pattern | Relationship Type | Rationale |
| :--- | :--- | :--- |
| **Synchronous HTTP / gRPC** | **Parent-Child** | Strict temporal nesting; child latency directly bounds parent execution. |
| **Message Queue Consumer Batching** | **Span Links** | A consumer reads 100 unrelated messages. Linking preserves independent root traces without falsifying trace timelines. |
| **Pub/Sub Fan-Out** | **Span Links** | One event triggers 10 asynchronous workers with independent lifecycles. |
| **Sagas & Retry Queues** | **Span Links** | Operations re-entering workflows; avoids creating invalid cyclical DAGs. |

---

## 2. Kafka Context Propagation via Record Headers

In Apache Kafka, context is propagated using byte array headers:
- `traceparent`: `00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`
- `tracestate`: `congo=123`

The consumer extracts the producer's context, starts a new `CONSUMER` span, and attaches a `trace.Link` referencing the extracted `SpanContext`.

---

## 3. Clock Skew & Algorithmic Adjustment

In distributed systems, physical wall clocks drift continuously. If a downstream server lags the upstream server by 30ms, child spans appear to start **before** the parent call was sent.

### The Bounded Causality Algorithm
Tracing backends apply adjustments based on causality invariants:
1. `t_child_start >= t_parent_send`
2. `t_child_end <= t_parent_recv`
3. Child span duration (`delta_t = t_child_end - t_child_start`) is accurate via monotonic clocks.

```
Skew Offset delta = ((t_parent_send + t_parent_recv) / 2) - ((t_child_start + t_child_end) / 2)
```
The backend shifts the child span and its descendants forward by delta.

---

## 4. Microservice Failure Signatures

### 4.1 Retry Storms
- **Signature**: Exponential surge in downstream spans with 100% error status (`503` / `DEADLINE_EXCEEDED`), while the count of unique root trace IDs remains flat.
- **Mitigation**: Exponential backoff with full jitter and a strict 10% client retry budget.

### 4.2 Thundering Herds (Cache Stampedes)
- **Signature**: Simultaneous execution of hundreds of identical database queries across independent trace IDs immediately following a cache key TTL expiration.
- **Mitigation**: Singleflight pattern (in-process mutex locking) or probabilistic early expiration (XFetch algorithm).

### 4.3 Cascading Timeouts & Deadline Propagation
- **Signature**: Upstream parent spans terminate with `CANCELLED`, while downstream child spans continue executing for seconds, burning CPU and I/O.
- **Mitigation**: Propagate deadlines (`grpc-timeout`, `x-envoy-expected-rq-timeout-ms`, or W3C Baggage). Abort execution if remaining time <= 0.
