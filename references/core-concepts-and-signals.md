---
description: Deep dive into the 4 core telemetry signals (Traces, Metrics, Logs, Profiles), their data models, instruments, and aggregation semantics.
metadata:
  tags: [signals, traces, metrics, logs, profiles, data-models, exemplars]
---

# Core Concepts & Telemetry Signals

OpenTelemetry provides a single, unified standard across the four primary pillars of observability: **Traces**, **Metrics**, **Logs**, and **Profiles** (OTEP 0212), alongside auxiliary metadata carriers (**Resources**, **Attributes**, and **Baggage**).

---

## 1. Traces (Distributed Transaction Graphs)

A distributed trace represents the end-to-end latency journey of a request through a distributed system. A trace is a Directed Acyclic Graph (DAG) composed of one or more **Spans**.

```
Trace: Checkout Transaction (TraceID: 4bf92f3577b34da6a3ce929d0e0e4736)
├── Span 1: HTTP POST /checkout (SERVER) [0ms ------------------------- 450ms]
│   ├── Span 2: Authenticate Token (INTERNAL) [5ms --- 45ms]
│   ├── Span 3: gRPC CheckInventory (CLIENT) [50ms ------------- 180ms]
│   └── Span 4: gRPC ProcessPayment (CLIENT) [190ms -------------------- 440ms]
│       └── Span 5: Kafka Produce "payment.completed" (PRODUCER) [410ms - 435ms]
```

### 1.1 Span Anatomy & Lifecycle
Every Span encapsulates:
- **`TraceID`**: 16-byte (128-bit) globally unique identifier for the distributed trace.
- **`SpanID`**: 8-byte (64-bit) globally unique identifier for the individual unit of work.
- **`ParentSpanID`**: 8-byte identifier of the caller span (empty for root spans).
- **`Name`**: Low-cardinality human-readable identifier (e.g., `POST /orders`, `SELECT FROM users`).
- **`Kind`**: The operational relationship of the span:
  - `SERVER`: Synchronous incoming request (e.g., HTTP server, gRPC server).
  - `CLIENT`: Synchronous outgoing request (e.g., HTTP client, database query).
  - `PRODUCER`: Asynchronous job creation (e.g., publishing to Kafka, RabbitMQ, SQS).
  - `CONSUMER`: Asynchronous job processing (e.g., reading from Kafka).
  - `INTERNAL`: Internal in-process calculation (e.g., parsing JSON, crypto operations).
- **`Timestamps`**: Start and End timestamps in Unix nanoseconds.
- **`Status`**: `UNSET` (default), `OK` (explicit success), or `ERROR` (operation failed).
- **`Attributes`**: Key-value pairs adhering to Semantic Conventions (e.g., `http.response.status_code = 200`).
- **`Events`**: Structured, timestamped annotations within the span (in-span logs).
- **`Links`**: Causal references to one or more other spans across independent traces.

---

## 2. Metrics (Aggregated Numerical Data)

Metrics quantify system behavior over time. While traces provide request-level depth, metrics provide statistical breadth (rates, counts, distributions).

### 2.1 The 6 Metric Instrument Types

| Instrument Type | Synchronous / Asynchronous | Monotonic? | Aggregation | Primary Use Cases |
| :--- | :--- | :--- | :--- | :--- |
| **`Counter`** | Synchronous | **Yes** (values $\ge 0$) | Sum | Total requests, bytes sent, error counts |
| **`UpDownCounter`** | Synchronous | **No** (can $+/-$) | Sum | Active connections, queue depth, thread pool size |
| **`Histogram`** | Synchronous | N/A | Explicit/Exponential Buckets | Request duration, payload sizes, database latency |
| **`ObservableCounter`** | Asynchronous (Callback) | **Yes** (monotonic) | Sum | OS page faults, CPU clock ticks read from `/proc` |
| **`ObservableUpDownCounter`** | Asynchronous (Callback) | **No** | Sum | Memory usage from runtime stats, open file descriptors |
| **`ObservableGauge`** | Asynchronous (Callback) | **No** | Last Value | CPU temperature, battery percentage, room humidity |

### 2.2 Aggregation Temporality: Delta vs. Cumulative

```
Timeline:              t=0s       t=10s      t=20s      t=30s
Events during window:  0 reqs     15 reqs    25 reqs    10 reqs
-----------------------------------------------------------------
Cumulative Metric:     0          15         40         50
Delta Metric:          0          15         25         10
```

- **Cumulative Temporality**: Reports the total aggregated value since the process started ($t_0$). Standard for Prometheus and OpenMetrics. Survives network packet loss without data gaps, but requires rate computation over time windows.
- **Delta Temporality**: Reports the change since the previous collection interval ($t - \Delta t$). Standard for cloud monitoring backends (Datadog, AWS CloudWatch, Google Cloud Monitoring) and distributed aggregation gateways.

### 2.3 Exponential Bucket Histograms
Traditional explicit bucket histograms require predefined boundaries (e.g., `[0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]`). If latency shifts outside these bounds, resolution is lost.
- **Exponential Histograms**: Automatically scale buckets dynamically based on a base scale factor $2^{2^{-	ext{scale}}}$. Provides high dynamic range and bounded memory without manual bucket tuning.

---

## 3. Logs (Discrete Diagnostic Events)

OpenTelemetry unifies logging through the **Log Data Model** and the **Log Bridge API**.

### 3.1 LogRecord Specification
A standard OpenTelemetry LogRecord contains:
- **`Timestamp`**: Time in Unix nanoseconds when the original log event occurred.
- **`ObservedTimestamp`**: Time when the log record was ingested by the OpenTelemetry collector or SDK.
- **`SeverityNumber`**: Standardized integer from `1` to `24` grouped into 6 severities:
  - `1-4`: TRACE
  - `5-8`: DEBUG
  - `9-12`: INFO
  - `13-16`: WARN
  - `17-20`: ERROR
  - `21-24`: FATAL
- **`SeverityText`**: The original logging level from the application (e.g., `"CRITICAL"`, `"INFO"`).
- **`Body`**: The log message or structured payload (`AnyValue`: string, int, double, bytes, map, array).
- **`Attributes`**: Structured contextual metadata (e.g., `user.id`, `exception.stacktrace`).
- **`TraceID` & `SpanID`**: 16-byte and 8-byte references linking the log to active distributed traces.
- **`TraceFlags`**: 1-byte bitmap (including recorded/sampled bit).

### 3.2 The Log Bridge API vs. Direct Logging
- **The Log Bridge API**: Developers do not write OTel logging code directly. Instead, existing logging libraries (Logback, Zap, SLF4J, Winston, Log4j2) install an OpenTelemetry Log Appender.
- The appender extracts the current OTel `Context`, injects `trace_id` and `span_id`, translates the record to `LogRecord`, and forwards it over OTLP.

---

## 4. Profiles (Continuous Runtime Execution Analysis)

Defined in **OTEP 0212**, profiling is the fourth core signal in OpenTelemetry.

### 4.1 The OTLP Profiles Data Model (`profiles.proto`)
Continuous profiling samples call stacks at regular intervals (e.g., 49Hz). To avoid sending megabytes of duplicate strings and stack traces, the data model normalizes profiles into a **Shared Dictionary Table**:
- `string_table`: Deduplicated array of all strings (package names, function names, files).
- `function_table`: Indexed functions referencing string indices.
- `location_table`: Instruction pointers and memory mappings linked to functions.
- `stack_table`: Array of location indices representing complete call stacks.
- `sample_table`: Integer references: `{stack_index, values[], link_index (trace_id, span_id)}`.

### 4.2 Profile Types
- **CPU Time (On-CPU)**: Wall-clock execution on hardware cores.
- **Off-CPU Time**: Time threads spend blocked on I/O, mutex locks, or channel receives.
- **Memory Allocations**: Heap bytes allocated vs. heap objects currently in-use.
- **Thread Contention**: Lock acquisition delays and blocked goroutines/threads.
