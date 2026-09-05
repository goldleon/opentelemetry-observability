---
description: High-cardinality storage architectures for OpenTelemetry, ClickHouse MergeTree schemas, Grafana Mimir, and Tempo v2 Parquet.
metadata:
  tags: [storage, clickhouse, mimir, tempo, parquet, traceql, bloom-filters]
---

# High-Cardinality Storage Backends

Handling gigabytes per second of distributed telemetry requires columnar storage, vectorized SIMD query engines, and sparse indexing.

---

## 1. ClickHouse for OpenTelemetry Traces & Logs

ClickHouse provides an ultra-fast, columnar engine using MergeTree tables and specialized column codecs.

### 1.1 Key Architectural Optimizations
- **Primary Sort Key (`ORDER BY`)**: Ordered from lowest cardinality to highest: `(tenant_id, service_name, span_name, toUnixTimestamp(timestamp), trace_id, span_id)`. Ensures consecutive rows from the same service compress efficiently together.
- **Specialized Codecs**:
  - `DoubleDelta, ZSTD(1)` on timestamps: Stores deltas of deltas, reducing timestamp footprint by 90%.
  - `T64, ZSTD(1)` on `duration_ns`: Truncates high unused bits of 64-bit integer durations.
  - `LowCardinality(String)`: Dictionary encodes repeated strings into internal 8/16-bit IDs.
- **Secondary Skip Indexes**:
  - `bloom_filter(0.001)` on `trace_id`: Allows single-trace lookups to skip 99.9% of data parts without full-table scanning.

---

## 2. Grafana Mimir for High-Cardinality Metrics

Grafana Mimir stores Prometheus metrics as immutable 2-hour TSDB blocks in cloud object storage (S3, GCS).
- **Inverted Index Postings Cache**: Caches inverted index postings in Memcached/Redis to accelerate regex and multi-label label queries across millions of series.
- **Compactor Tier**: Compacts and deduplicates 2-hour TSDB blocks into 12-hour and 24-hour blocks, applying retention policies without cluster downtime.

---

## 3. Grafana Tempo v2 (Parquet & TraceQL)

Tempo v2 replaced proprietary block formats with **Apache Parquet**:
- Columnar layout stores span attributes, events, and links in partitioned Parquet files on object storage.
- **TraceQL Streaming Engine**: Evaluates complex distributed queries (e.g., `{ span.http.status_code >= 500 && span.duration > 1s }`) directly against column chunks without maintaining an expensive full-text search index.
