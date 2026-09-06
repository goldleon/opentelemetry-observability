# Telemetry FinOps, Cardinality Control & Cost Optimization

Telemetry cardinality explosion and runaway ingestion rates represent the single largest operational cost vulnerability in enterprise observability. This guide outlines battle-tested mechanisms to control metric, trace, and log volumes before ingestion.

---

## 1. High Cardinality Mechanics

A metric time series is uniquely identified by its metric name plus the set of all key-value label pairs:
$$\text{Total Active Series} = \prod_{i=1}^{n} |V_i|$$
Where $|V_i|$ is the count of distinct values for label $i$.
If a developer attaches `user_id` ($10^6$ values) or `order_id` ($10^7$ values) as a Prometheus/OTel metric dimension, time-series storage (Mimir, Prometheus, VictoriaMetrics) crashes with Out-Of-Memory (OOM) errors and storage costs multiply exponentially.

### Cardinality Killers
1. `user_id`, `email`, `session_id` on metrics (belong only in traces/logs or exemplars).
2. Ephemeral container/pod IDs on long-lived aggregations.
3. Raw URL paths (`/api/v1/users/e7b99c1f-998a...`) instead of parameterized routes (`/api/v1/users/{id}`).
4. Exception stack trace strings attached as metric labels.

---

## 2. Metric Cardinality Stripping via OTTL

Use `transformprocessor` on the metric datapoint context to drop or replace high-cardinality attributes:

```yaml
processors:
  transform/strip_metric_cardinality:
    error_mode: ignore
    metric_statements:
      - context: datapoint
        statements:
          # Drop unique user identifiers from all metrics
          - delete_key(datapoint.attributes, "user.id")
          - delete_key(datapoint.attributes, "account.id")
          - delete_key(datapoint.attributes, "device.id")
          - delete_key(datapoint.attributes, "ip")
          # Normalize dynamic URL paths to route templates
          - replace_pattern(datapoint.attributes["http.target"], "/[0-9a-fA-F-]{36}", "/:id")
          - replace_pattern(datapoint.attributes["http.target"], "/[0-9]{4,}", "/:id")
```

---

## 3. High-Frequency Health Check & Probe Suppression

Kubernetes liveness and readiness probes (`/healthz`, `/readyz`, `/metrics`, `kube-probe`) often account for 60-80% of total span and log volume in high-density clusters.

### Trace & Log Filtering Configuration
```yaml
processors:
  filter/drop_probes:
    error_mode: ignore
    traces:
      span:
        - 'attributes["http.target"] == "/healthz"'
        - 'attributes["http.target"] == "/readyz"'
        - 'attributes["http.target"] == "/livez"'
        - 'attributes["http.target"] == "/metrics"'
        - 'IsMatch(attributes["http.user_agent"], ".*kube-probe.*")'
        - 'IsMatch(name, ".*healthcheck.*")'
    logs:
      log_record:
        - 'IsMatch(body, ".*GET /(healthz|readyz|livez|metrics).*200.*")'
        - 'IsMatch(attributes["http.user_agent"], ".*kube-probe.*")'
```

---

## 4. Sampling Strategies & FinOps Impact

```
Raw Telemetry Generation (100% Volume)
   │
   ├── Head Sampling (SDK-level: ParentBased(TraceIdRatioBased(0.05)))
   │      └── Drops 95% of traffic before network transmission
   │
   └── Tail Sampling (Gateway-level: Collector)
          ├── Retain 100% of HTTP 5xx errors (status.code == ERROR)
          ├── Retain 100% of Latency Outliers (> 1500ms)
          ├── Retain 10% of HTTP 4xx client errors
          └── Retain 1% of nominal HTTP 200 OK traffic
```

### Head vs Tail Trade-off Analysis
| Parameter | Head Sampling | Tail Sampling |
| :--- | :--- | :--- |
| **Enforcement Point** | Application SDK | Collector Gateway (LoadBalanced) |
| **Network Egress Cost** | Lowest (dropped in memory) | Standard (all spans reach gateway) |
| **Storage Cost** | Low | Optimized (only valuable traces kept) |
| **Error Visibility** | Poor (errors might be dropped) | 100% guaranteed error retention |
| **CPU / RAM Overhead** | Negligible | Moderate (spans buffered in memory) |

---

## 5. Log Aggregation & Attribute Trimming

Log bodies often repeat resource attributes or carry bloated stack traces.
1. **Deduplication**: Strip redundant resource attributes (`k8s.namespace.name`, `k8s.pod.name`) if already indexed in Elasticsearch/Loki/ClickHouse.
2. **Body Truncation**: Enforce maximum byte size on log messages to prevent single runaway log lines from exhausting memory buffers:
```yaml
processors:
  transform/truncate_logs:
    error_mode: ignore
    log_statements:
      - context: log
        statements:
          - truncate_all(log.attributes, 1024)
```
