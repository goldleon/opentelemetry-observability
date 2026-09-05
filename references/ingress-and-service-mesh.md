---
description: Ingress gateways, Envoy Proxy OpenTelemetry tracer, Istio service mesh Telemetry API, and Kong/Traefik API gateway configurations.
metadata:
  tags: [envoy, istio, service-mesh, ingress, kong, traefik, gateway]
---

# Ingress & Service Mesh Observability

API gateways and service meshes sit at the boundary between public networks and internal microservices. They are responsible for extracting external trace contexts, injecting gateway server spans, and propagating context downstream.

---

## 1. Gateway Trace Continuation vs. Overwriting

> [!WARNING]
> **Trace Disconnection Hazard**: By default, some ingress gateways generate a new random `trace_id` for incoming traffic. This completely severs browser RUM traces from backend traces!
> **Rule**: Configure your ingress gateway with `header_type: "w3c"` to honor and validate incoming `traceparent` headers.

---

## 2. Envoy OpenTelemetry Tracer (`envoy.tracers.opentelemetry`)

Envoy provides native OpenTelemetry tracing integrated into the `HttpConnectionManager` filter.
- Streams OTLP spans directly to the OpenTelemetry Collector over gRPC (`4317`).
- Implements asynchronous, non-blocking gRPC streaming without stalling client HTTP connections.
- Automatically populates standard HTTP semantic conventions (`http.response.status_code`, `http.request.method`, `client.address`).

---

## 3. Istio Telemetry API

In modern Istio (1.15+), tracing is configured declaratively using the `Telemetry` CRD and `meshConfig.extensionProviders` in `istio-system`.
- Injects sidecar proxies (Envoy) that emit spans on both client and server sides of every pod-to-pod interaction.
- Allows attaching custom baggage tags (e.g. `cluster_id`, `client_session_id`) into distributed traces.

---

## 4. Production Manifests
- Envoy Configuration: [`envoy-opentelemetry.yaml`](../examples/mesh/envoy-opentelemetry.yaml)
- Istio Telemetry CRD: [`istio-telemetry.yaml`](../examples/mesh/istio-telemetry.yaml)
- Kong Gateway Plugin: [`kong-plugin.yaml`](../examples/mesh/kong-plugin.yaml)
