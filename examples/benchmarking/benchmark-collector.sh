#!/usr/bin/env bash
# ==============================================================================
# OpenTelemetry Collector Performance & Load Benchmarking Script
# Uses official telemetrygen tool to simulate high-throughput production load
# ==============================================================================

set -euo pipefail

TARGET_HOST="${1:-127.0.0.1}"
TARGET_PORT="${2:-4317}"
DURATION="${3:-60s}"
WORKERS="${4:-8}"
RATE="${5:-5000}" # Spans/Logs per second per worker

echo "=========================================================="
echo "Starting OpenTelemetry Collector Load Benchmark"
echo "Target Endpoint:  ${TARGET_HOST}:${TARGET_PORT}"
echo "Duration:         ${DURATION}"
echo "Workers:          ${WORKERS}"
echo "Rate per worker:  ${RATE}/sec (Total target: $((WORKERS * RATE))/sec)"
echo "=========================================================="

# Check if telemetrygen is installed, or pull via go install
if ! command -v telemetrygen &> /dev/null; then
    echo "telemetrygen not found. Installing via go install github.com/open-telemetry/opentelemetry-collector-contrib/cmd/telemetrygen@latest..."
    go install github.com/open-telemetry/opentelemetry-collector-contrib/cmd/telemetrygen@latest
fi

echo ""
echo "--> 1. Running Trace Ingestion Benchmark..."
telemetrygen traces \
    --otlp-endpoint="${TARGET_HOST}:${TARGET_PORT}" \
    --otlp-insecure \
    --duration="${DURATION}" \
    --workers="${WORKERS}" \
    --rate="${RATE}" \
    --service="benchmark-load-service"

echo ""
echo "--> 2. Running Metrics Ingestion Benchmark..."
telemetrygen metrics \
    --otlp-endpoint="${TARGET_HOST}:${TARGET_PORT}" \
    --otlp-insecure \
    --duration="${DURATION}" \
    --workers="${WORKERS}" \
    --rate="${RATE}"

echo ""
echo "--> 3. Running Logs Ingestion Benchmark..."
telemetrygen logs \
    --otlp-endpoint="${TARGET_HOST}:${TARGET_PORT}" \
    --otlp-insecure \
    --duration="${DURATION}" \
    --workers="${WORKERS}" \
    --rate="${RATE}"

echo ""
echo "=========================================================="
echo "Benchmark run completed successfully!"
echo "Check collector metrics at http://${TARGET_HOST}:8888/metrics"
echo "Key metrics to verify:"
echo " - otelcol_receiver_accepted_spans"
echo " - otelcol_receiver_refused_spans"
echo " - otelcol_process_runtime_heap_alloc_bytes"
echo " - otelcol_exporter_queue_size"
echo "=========================================================="
