# Security, Compliance, PII Redaction & Multi-Tenancy

Observability pipelines aggregate high-privilege infrastructure metrics, application debug logs, and customer transaction traces. Without stringent security controls, telemetry collectors become attack vectors and compliance hazards (GDPR, HIPAA, PCI-DSS).

---

## 1. Zero-Trust Telemetry Architecture

```
[ Application Pod ]
       │  (Plaintext unix domain socket or localhost:4317)
       ▼
[ Node DaemonSet Agent ]
       │  (Mutual TLS: Port 4317 with client certificate verification)
       │  (Token: Bearer token authentication)
       ▼
[ Gateway StatefulSet Pool ]
       │  (Redaction: Mask PII / Drop sensitive headers)
       │  (Tenant Tagging: Inject X-Scope-OrgID / tenant_id)
       │  (TLS v1.3 + Signed CA)
       ▼
[ Encrypted Storage: ClickHouse / Mimir / Tempo / S3 ]
```

---

## 2. Mutual TLS (mTLS) Configuration

Configure mutual certificate validation between Agent DaemonSets and Gateway clusters:

### Gateway Receiver mTLS
```yaml
receivers:
  otlp/mtls:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
        tls:
          cert_file: /etc/otel/certs/server.crt
          key_file: /etc/otel/certs/server.key
          client_ca_file: /etc/otel/certs/ca.crt
          client_auth_type: RequireAndVerifyClientCert
          min_version: "1.3"
```

### Agent Exporter mTLS
```yaml
exporters:
  otlp/gateway:
    endpoint: otel-gateway.observability.svc.cluster.local:4317
    tls:
      ca_file: /etc/otel/certs/ca.crt
      cert_file: /etc/otel/certs/client.crt
      key_file: /etc/otel/certs/client.key
      insecure: false
```

---

## 3. PII Redaction with `redactionprocessor`

The `redactionprocessor` blocks sensitive attributes and applies regex sanitization to string bodies before telemetry leaves the network perimeter:

```yaml
processors:
  redaction:
    # Allowlist of attributes permitted through the pipeline
    allowlist_attributes:
      - service.name
      - service.version
      - http.method
      - http.status_code
      - http.route
      - k8s.*
    # Regex masks applied to all string values in attributes and logs
    blocked_values:
      - "(?i)bearer\s+[a-zA-Z0-9_\-\.]{20,}"
      - "\b4[0-9]{12}(?:[0-9]{3})?\b" # Visa CC
      - "\b5[1-5][0-9]{14}\b"         # MasterCard CC
      - "\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b" # US SSN
      - "(?i)(api[_-]?key|secret|password)\s*[:=]\s*['"][^'"]+['"]"
    summary: silent
```

---

## 4. Multi-Tenancy & Tenant Routing

In shared infrastructure, telemetry from multiple departments, tenants, or customers must be isolated.

### Pattern: Header Extraction & Routing Processor
```yaml
processors:
  routing/by_tenant:
    from_attribute: "X-Scope-OrgID"
    attribute_source: context # extracts from incoming gRPC/HTTP metadata
    table:
      - value: "tenant-enterprise-a"
        exporters: [otlp/tenant_a_backend]
      - value: "tenant-enterprise-b"
        exporters: [otlp/tenant_b_backend]
    default_exporters: [otlp/shared_sandbox_backend]
```

### Downstream Propagation (`X-Scope-OrgID`)
When exporting to Grafana Mimir, Loki, or Tempo multi-tenant clusters:
```yaml
exporters:
  otlphttp/mimir:
    endpoint: http://mimir-distributor.monitoring.svc:8080/otlp
    headers:
      X-Scope-OrgID: "${TENANT_ID}"
```
