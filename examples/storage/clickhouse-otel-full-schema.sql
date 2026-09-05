-- ========================================================================
-- ClickHouse Production OpenTelemetry Unified Telemetry Schema
-- Engines: ReplacingMergeTree, SummingMergeTree, AggregatingMergeTree
-- Optimized for high throughput, SIMD vectorized scans, and low byte overhead.
-- ========================================================================

CREATE DATABASE IF NOT EXISTS otel_telemetry;

-- ------------------------------------------------------------------------
-- 1. TRACES TABLE
-- ------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS otel_telemetry.otel_traces
(
    tenant_id LowCardinality(String) CODEC(ZSTD(1)),
    timestamp DateTime64(9, 'UTC') CODEC(DoubleDelta, ZSTD(1)),
    
    trace_id FixedString(16) CODEC(ZSTD(1)),
    span_id FixedString(8) CODEC(ZSTD(1)),
    parent_span_id FixedString(8) CODEC(ZSTD(1)),
    trace_state String CODEC(ZSTD(1)),
    
    service_name LowCardinality(String) CODEC(ZSTD(1)),
    span_name LowCardinality(String) CODEC(ZSTD(1)),
    span_kind LowCardinality(String) CODEC(ZSTD(1)),
    duration_ns UInt64 CODEC(T64, ZSTD(1)),
    
    status_code LowCardinality(String) CODEC(ZSTD(1)),
    status_message String CODEC(ZSTD(1)),
    
    resource_attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    span_attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    events Nested
    (
        timestamp DateTime64(9, 'UTC'),
        name LowCardinality(String),
        attributes Map(LowCardinality(String), String)
    ) CODEC(ZSTD(1)),
    links Nested
    (
        trace_id FixedString(16),
        span_id FixedString(8),
        trace_state String,
        attributes Map(LowCardinality(String), String)
    ) CODEC(ZSTD(1)),

    INDEX idx_trace_id trace_id TYPE bloom_filter(0.001) GRANULARITY 1,
    INDEX idx_span_attr_keys mapKeys(span_attributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_span_attr_vals mapValues(span_attributes) TYPE tokenbf_v1(10240, 2, 0) GRANULARITY 1,
    INDEX idx_duration duration_ns TYPE minmax GRANULARITY 1
)
ENGINE = ReplacingMergeTree()
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (tenant_id, service_name, span_name, toUnixTimestamp(timestamp), trace_id, span_id)
TTL toDateTime(timestamp) + INTERVAL 30 DAY
SETTINGS index_granularity = 8192, ttl_only_drop_parts = 1;

-- ------------------------------------------------------------------------
-- 2. LOGS TABLE
-- ------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS otel_telemetry.otel_logs
(
    tenant_id LowCardinality(String) CODEC(ZSTD(1)),
    timestamp DateTime64(9, 'UTC') CODEC(DoubleDelta, ZSTD(1)),
    observed_timestamp DateTime64(9, 'UTC') CODEC(DoubleDelta, ZSTD(1)),

    trace_id FixedString(16) CODEC(ZSTD(1)),
    span_id FixedString(8) CODEC(ZSTD(1)),
    trace_flags UInt8 CODEC(T64, ZSTD(1)),

    severity_number UInt8 CODEC(T64, ZSTD(1)),
    severity_text LowCardinality(String) CODEC(ZSTD(1)),
    service_name LowCardinality(String) CODEC(ZSTD(1)),
    
    body String CODEC(ZSTD(3)),
    resource_attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    log_attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),

    INDEX idx_trace_id trace_id TYPE bloom_filter(0.001) GRANULARITY 1,
    INDEX idx_body_token body TYPE tokenbf_v1(16384, 3, 0) GRANULARITY 1,
    INDEX idx_log_attr_keys mapKeys(log_attributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_log_attr_vals mapValues(log_attributes) TYPE tokenbf_v1(10240, 2, 0) GRANULARITY 1
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (tenant_id, service_name, severity_number, toUnixTimestamp(timestamp), trace_id)
TTL toDateTime(timestamp) + INTERVAL 30 DAY
SETTINGS index_granularity = 8192, ttl_only_drop_parts = 1;

-- ------------------------------------------------------------------------
-- 3. METRICS GAUGE (Latest Value)
-- ------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS otel_telemetry.otel_metrics_gauge
(
    tenant_id LowCardinality(String) CODEC(ZSTD(1)),
    metric_name LowCardinality(String) CODEC(ZSTD(1)),
    timestamp DateTime64(3, 'UTC') CODEC(DoubleDelta, ZSTD(1)),
    
    service_name LowCardinality(String) CODEC(ZSTD(1)),
    attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    resource_attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),

    value Float64 CODEC(Gorilla, ZSTD(1))
)
ENGINE = ReplacingMergeTree()
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (tenant_id, metric_name, service_name, attributes, timestamp)
TTL toDateTime(timestamp) + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- ------------------------------------------------------------------------
-- 4. METRICS SUM (SummingMergeTree for Cumulative Totals)
-- ------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS otel_telemetry.otel_metrics_sum
(
    tenant_id LowCardinality(String) CODEC(ZSTD(1)),
    metric_name LowCardinality(String) CODEC(ZSTD(1)),
    timestamp DateTime64(3, 'UTC') CODEC(DoubleDelta, ZSTD(1)),
    
    service_name LowCardinality(String) CODEC(ZSTD(1)),
    attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    resource_attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),

    value Float64 CODEC(Gorilla, ZSTD(1))
)
ENGINE = SummingMergeTree(value)
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (tenant_id, metric_name, service_name, attributes, timestamp)
TTL toDateTime(timestamp) + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- ------------------------------------------------------------------------
-- 5. METRICS HISTOGRAM (AggregatingMergeTree for Statistical Buckets)
-- ------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS otel_telemetry.otel_metrics_histogram
(
    tenant_id LowCardinality(String) CODEC(ZSTD(1)),
    metric_name LowCardinality(String) CODEC(ZSTD(1)),
    timestamp DateTime64(3, 'UTC') CODEC(DoubleDelta, ZSTD(1)),
    
    service_name LowCardinality(String) CODEC(ZSTD(1)),
    attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    resource_attributes Map(LowCardinality(String), String) CODEC(ZSTD(1)),

    count UInt64 CODEC(T64, ZSTD(1)),
    sum Float64 CODEC(Gorilla, ZSTD(1)),
    bucket_counts Array(UInt64) CODEC(ZSTD(1)),
    explicit_bounds Array(Float64) CODEC(ZSTD(1)),
    
    -- Exemplars: Array of linked traces
    exemplars Nested
    (
        timestamp DateTime64(9, 'UTC'),
        value Float64,
        trace_id FixedString(16),
        span_id FixedString(8)
    ) CODEC(ZSTD(1))
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (tenant_id, metric_name, service_name, attributes, timestamp)
TTL toDateTime(timestamp) + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;
