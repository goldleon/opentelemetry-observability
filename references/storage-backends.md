---
description: Encyclopedic guide to high-cardinality storage architectures for OpenTelemetry across ClickHouse, Grafana LGTM (Mimir, Tempo v2, Loki), VictoriaMetrics, and OpenSearch.
metadata:
  tags: [storage, clickhouse, mimir, tempo, loki, victoriametrics, opensearch, parquet, tsdb, bloom-filter]
---

# High-Cardinality Storage Architectures for OpenTelemetry

Operating enterprise observability backends at scales exceeding millions of spans, logs, and metric data points per second demands specialized storage systems. Telemetry architectures have moved away from generic relational databases to columnar engines, immutable TSDB blocks, and log-structured merge trees (LSM).

---

## 1. Storage Engine Comparative Architecture Matrix

| Storage System | Primary Signals | Storage Architecture | Indexing Model | High-Cardinality Handling | Best Used For |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **ClickHouse** | Traces, Logs, Metrics, Profiles | Columnar MergeTree (LSM) on NVMe/S3 | Sparse Primary Key (`ORDER BY`) + Bloom Filters | **Best-in-class**: Vectorized SIMD scans avoid indexing every attribute | Unified single-store telemetry, custom analytics, SQL queries |
| **Grafana Tempo v2** | Traces | Columnar Apache Parquet on Object Storage | Tag Bloom Filter + TraceQL streaming engine | Discards index entirely for payload attributes; streams Parquet columns | Cloud-native tracing with zero-dependency object storage |
| **Grafana Mimir** | Metrics | Multi-tenant Prometheus TSDB blocks on S3/GCS | Inverted index (postings list) + Memcached cache | Enforces strict label limits; uses postings cache and chunking | Massive Prometheus ecosystem, Prometheus alert rules |
| **Grafana Loki** | Logs | TSDB Index + Chunks on Object Storage | Index on stream labels; **Structured Metadata** for OTel | Does NOT index log line content; attaches OTel attributes as structured metadata | Cloud-native Kubernetes logging, LogQL integration |
| **VictoriaMetrics**| Metrics | Custom MergeTree TSDB | Fast inverted index (`indexdb`) | **High**: Extremely low RAM per million time-series, built-in dedup | High-throughput metric alternative to Prometheus/Mimir |
| **OpenSearch** | Traces, Logs | Lucene Inverted Index + Columnar Doc Values | Inverted full-text index + BKD trees | Resource-intensive; requires index rotation (ISM) and rollover | Full-text log search, SIEM, security analytics |

---

## 2. ClickHouse: Unified Telemetry Architecture

ClickHouse is a columnar OLAP database capable of ingesting gigabytes of telemetry per second with 10x-15x compression.

```
Incoming OTLP Telemetry
           │
           ▼
[ OTel Collector clickhouseexporter ] (Batches 10k+ rows)
           │
           ├── Traces  ────────► [ otel_traces (ReplacingMergeTree) ]
           ├── Logs    ────────► [ otel_logs (MergeTree) ]
           ├── Gauges  ────────► [ otel_metrics_gauge (ReplacingMergeTree) ]
           ├── Sums    ────────► [ otel_metrics_sum (SummingMergeTree) ]
           └── Histograms ─────► [ otel_metrics_histogram (AggregatingMergeTree) ]
```

### 2.1 Engine Specialization
- **`ReplacingMergeTree`**: Deduplicates spans and gauge observations on the primary key during background merges, resolving retries or duplicate deliveries.
- **`SummingMergeTree(value)`**: Automatically sums incoming metric deltas or counters sharing the same label dimensions, collapsing millions of rows into aggregated summaries.
- **`AggregatingMergeTree`**: Maintains intermediate aggregate states (e.g., quantiles, histograms) using aggregate functions (`quantilesExactWeightedState`).

### 2.2 Specialized Codecs & Compression
- **`DoubleDelta, ZSTD(1)` on Timestamps**: Since telemetry timestamps are monotonic, storing the second delta ($t_2 - t_1$) compresses timestamps by up to **90%**.
- **`Gorilla, ZSTD(1)` on Floats**: The Gorilla algorithm XORs consecutive floating-point values, achieving 80%+ compression on metric values.
- **`T64, ZSTD(1)` on Integers**: Truncates unused high bits before applying Zstandard compression.
- **`LowCardinality(String)`**: Automatically builds in-memory dictionaries for repeated strings (`service_name`, `status_code`).

### 2.3 Secondary Skip Indexes
- **`bloom_filter(0.001)` on `trace_id`**: Allows $O(1)$ single-trace lookups by skipping 99.9% of data parts on disk.
- **`tokenbf_v1` on Log Body & Span Attributes**: Tokenizes sentences and JSON into n-grams for instantaneous substring and regex searches without building a monolithic inverted index.

---

## 3. Grafana Tempo v2: Columnar Parquet Architecture

Grafana Tempo v2 transitioned from proprietary block files to standard **Apache Parquet**.

```
[ Tempo Ingester ]
       │ Writes 1GB Parquet blocks to WAL
       ▼
[ Storage: S3 / GCS / Azure Blob ]
  ├── data/
  │   ├── block_1.parquet (Span Kind, Status, Service, Attributes)
  │   └── block_2.parquet (Bloom Filter on Tag Names & Values)
       │
       ▼
[ Tempo Querier & TraceQL Engine ]
  Stream Parquet column chunks directly from S3 -> Filter via SIMD -> Emit trace
```

### 3.1 TraceQL Streaming
Traditional tracing databases index every span tag (e.g., `user_id`, `http.status_code`) in a secondary database. At 500k spans/sec, index maintenance degrades cluster health.
- Tempo v2 does **not** index every tag.
- It stores spans in partitioned Parquet files with **Tag Bloom Filters**.
- When a TraceQL query executes (e.g., `{ .http.status_code == 500 && .duration > 2s }`):
  1. The bloom filter skips Parquet files that do not contain the tag.
  2. The querier streams column chunks into RAM.
  3. Evaluates expressions using vectorized execution in Go.

---

## 4. Grafana Mimir: Scalable TSDB Blocks

Grafana Mimir scales Prometheus to 1+ billion active time series.

### 4.1 Architecture Components
- **Distributor**: Stateless HTTP receiver that computes consistent hashes of metric label sets and forwards them across a token ring to Ingesters.
- **Ingester**: Holds the latest 2 hours of time-series samples in memory chunks. Flushes immutable TSDB blocks to cloud object storage.
- **Store-Gateway**: Serves historical queries by querying TSDB blocks in object storage. Caches inverted index postings in Memcached to ensure low-latency dashboard loads.
- **Compactor**: Merges 2-hour TSDB blocks into 12-hour and 24-hour blocks, deduplicating high-availability replicas and applying global retention limits.

---

## 5. Grafana Loki: TSDB & Structured Metadata

The primary failure mode in log management is **label cardinality explosion** (e.g., putting `user_id` or `order_id` into a Loki label).

### 5.1 The Structured Metadata Revolution (Loki 3.0+)
OpenTelemetry logs contain hundreds of resource and log attributes.
- **Old Pattern**: Putting attributes in labels crashed Loki index storage; parsing with JSON filters slowed queries down.
- **Modern Pattern (Structured Metadata)**:
  - Low-cardinality metadata (`service.name`, `environment`, `cluster`) become **Loki Stream Labels**.
  - High-cardinality OTel attributes (`trace_id`, `span_id`, `user.id`, `exception.stacktrace`) are stored as **Structured Metadata** alongside the log chunk.
  - Queries can filter directly on structured metadata (`| trace_id = "..."`) with zero index overhead!

---

## 6. Production Backends Summary & Reference Manifests

Production configuration files for all backends are available in the repository:
- **ClickHouse (All Signals)**: [`clickhouse-otel-full-schema.sql`](../examples/storage/clickhouse-otel-full-schema.sql)
- **Grafana Mimir**: [`mimir-production-config.yaml`](../examples/storage/mimir-production-config.yaml)
- **Grafana Tempo v2**: [`tempo-v2-parquet-config.yaml`](../examples/storage/tempo-v2-parquet-config.yaml)
- **Grafana Loki**: [`loki-tsdb-config.yaml`](../examples/storage/loki-tsdb-config.yaml)
- **VictoriaMetrics**: [`victoriametrics-otel-config.yaml`](../examples/storage/victoriametrics-otel-config.yaml)
