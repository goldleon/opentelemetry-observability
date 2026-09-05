---
description: Engineering custom OpenTelemetry Collector distributions with OCB, reducing CVE attack surfaces, and building distroless containers.
metadata:
  tags: [ocb, custom-collector, builder, distroless, cve-reduction, docker]
---

# Custom Distributions via OpenTelemetry Collector Builder (OCB)

The default `otelcol-contrib` binary contains 100+ receivers, processors, and exporters. In production enterprises, deploying standard contrib introduces significant vulnerabilities (CVEs), large container images (200MB+), and elevated baseline memory consumption.

The **OpenTelemetry Collector Builder (`ocb`)** compiles tailored collector binaries containing only required components.

---

## 1. Motivation: Security & Footprint Optimization

| Metric | `otelcol-contrib` (Default) | Custom OCB Binary |
| :--- | :--- | :--- |
| **Binary Size** | ~180MB - 240MB | **~35MB - 50MB** |
| **Container Base** | Debian / Alpine | **Distroless Nonroot** |
| **Component Count** | > 120 components | **15 - 20 components** |
| **CVE Vulnerabilities**| High (due to transitive deps) | **Minimized / Zero Known** |
| **Startup RAM** | ~90MB - 130MB | **~25MB - 40MB** |

---

## 2. The `builder-config.yaml` Specification

```yaml
dist:
  module: github.com/enterprise/otelcol-custom
  name: otelcol-custom
  description: "Enterprise Production OpenTelemetry Collector"
  output_path: /build/dist
  version: 1.4.0
  go: /usr/local/go/bin/go
  debug_compilation: false

extensions:
  - gomod: github.com/open-telemetry/opentelemetry-collector-contrib/extension/healthcheckextension v0.118.0
  - gomod: github.com/open-telemetry/opentelemetry-collector-contrib/extension/storage/filestorage v0.118.0
  - gomod: go.opentelemetry.io/collector/extension/zpagesextension v0.118.0

receivers:
  - gomod: go.opentelemetry.io/collector/receiver/otlpreceiver v0.118.0
  - gomod: github.com/open-telemetry/opentelemetry-collector-contrib/receiver/prometheusreceiver v0.118.0
  - gomod: github.com/open-telemetry/opentelemetry-collector-contrib/receiver/filelogreceiver v0.118.0

processors:
  - gomod: go.opentelemetry.io/collector/processor/memorylimiterprocessor v0.118.0
  - gomod: go.opentelemetry.io/collector/processor/batchprocessor v0.118.0
  - gomod: github.com/open-telemetry/opentelemetry-collector-contrib/processor/transformprocessor v0.118.0
  - gomod: github.com/open-telemetry/opentelemetry-collector-contrib/processor/filterprocessor v0.118.0
  - gomod: github.com/open-telemetry/opentelemetry-collector-contrib/processor/tailsamplingprocessor v0.118.0
  - gomod: github.com/open-telemetry/opentelemetry-collector-contrib/processor/k8sattributesprocessor v0.118.0

exporters:
  - gomod: go.opentelemetry.io/collector/exporter/otlpexporter v0.118.0
  - gomod: go.opentelemetry.io/collector/exporter/otlphttpexporter v0.118.0
  - gomod: github.com/open-telemetry/opentelemetry-collector-contrib/exporter/loadbalancingexporter v0.118.0
  - gomod: github.com/open-telemetry/opentelemetry-collector-contrib/exporter/prometheusexporter v0.118.0

connectors:
  - gomod: github.com/open-telemetry/opentelemetry-collector-contrib/connector/spanmetricsconnector v0.118.0
  - gomod: github.com/open-telemetry/opentelemetry-collector-contrib/connector/routingconnector v0.118.0

providers:
  - gomod: go.opentelemetry.io/collector/confmap/provider/envprovider v1.23.0
  - gomod: go.opentelemetry.io/collector/confmap/provider/fileprovider v1.23.0
  - gomod: go.opentelemetry.io/collector/confmap/provider/yamlprovider v1.23.0
```

---

## 3. Hardened Multi-Stage Distroless Docker Build

```dockerfile
# Stage 1: Build binary using official builder
FROM golang:1.24-alpine AS builder
RUN apk add --no-cache git ca-certificates make gcc musl-dev
ARG OCB_VERSION=0.118.0
RUN go install go.opentelemetry.io/collector/cmd/builder@v${OCB_VERSION}

WORKDIR /src
COPY builder-config.yaml .
RUN CGO_ENABLED=0 builder --config=builder-config.yaml

# Stage 2: Minimal Distroless Runtime
FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /build/dist/otelcol-custom /otelcol-custom
USER 65532:65532
EXPOSE 4317 4318 8888 13133
ENTRYPOINT ["/otelcol-custom"]
CMD ["--config=/etc/otelcol/config.yaml"]
```
