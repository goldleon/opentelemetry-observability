# Resilience, Backpressure & Persistent Buffering

In distributed architectures, storage backends (ClickHouse, Mimir, Tempo) experience maintenance windows, network partitions, and ingestion throttling. Collectors must gracefully absorb spikes and backpressure without crashing from Out-Of-Memory (OOM) or dropping critical telemetry.

---

## 1. Backpressure Chain Mechanics

```
[ Application SDK ]
       ▲
   (HTTP 429 / gRPC UNAVAILABLE)
       │
[ Collector Memory Limiter Processor ]
   (Drops data or rejects incoming calls when RAM > 80%)
       │
[ Exporter In-Memory / File-Backed Queue ]
   (Buffers data when downstream is slow/offline)
       │
   (HTTP 429 / Throttling)
       ▼
[ Telemetry Storage Backend ]
```

---

## 2. Persistent Disk Queuing via `file_storage`

By default, the OpenTelemetry Collector exporter queue resides strictly in process RAM. If the collector pod restarts or crashes while the backend is down, queued telemetry is permanently lost.

The `file_storage` extension persists the exporter queue to a dedicated Kubernetes `PersistentVolume` (SSD):

```yaml
extensions:
  file_storage/disk_buffer:
    directory: /var/lib/otelcol/queue
    timeout: 10s
    compaction:
      on_start: true
      directory: /var/lib/otelcol/queue/compacted
    max_total_storage_size_mib: 10240 # 10 GB persistent buffer

exporters:
  otlp/resilient:
    endpoint: tempo.storage.svc:4317
    sending_queue:
      enabled: true
      storage: file_storage/disk_buffer
      queue_size: 50000
      num_consumers: 16
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 60s
      max_elapsed_time: 30m
```

---

## 3. Memory Limiter Rules of Thumb

The `memory_limiter` MUST be the very first processor in every pipeline.

```yaml
processors:
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80       # Hard ceiling: Reject data at 80% of pod cgroup limit
    spike_limit_percentage: 20 # Soft ceiling: Buffer headroom for GC allocation bursts
```

### Golden Formula for Kubernetes Resources
- Pod Memory Limit: $M$ (e.g., `4Gi`)
- Go `GOMEMLIMIT`: Set to $85\%$ of $M$ (`3.4Gi`)
- `check_interval`: `1s`
- `limit_percentage`: `80%`
- `spike_limit_percentage`: `20%`
$$\text{Effective Trigger Threshold} = 80\% - 20\% = 60\% \text{ of } M$$
This ensures the Go garbage collector and collector backpressure trip well before the Kubernetes kernel OOM-killer fires.

---

## 4. Graceful Shutdown & Drain Timeouts

When Kubernetes issues `SIGTERM` to a collector pod:
1. Pod enters `Terminating` state.
2. Service endpoint removes pod from kube-proxy routing.
3. Collector stops accepting new spans/metrics.
4. Collector exporter flushes all in-flight queues to persistent storage or backends.

```yaml
# In Deployment / StatefulSet spec:
spec:
  terminationGracePeriodSeconds: 60
```
In collector configuration:
```yaml
service:
  telemetry:
    resource:
      service.name: "otel-gateway"
```
