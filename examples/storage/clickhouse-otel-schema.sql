-- Production ClickHouse Schema for OpenTelemetry Traces
CREATE DATABASE IF NOT EXISTS otel_telemetry;

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
