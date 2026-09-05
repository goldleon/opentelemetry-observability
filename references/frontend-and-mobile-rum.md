---
description: Comprehensive guide to Frontend and Mobile Real User Monitoring (RUM), Core Web Vitals (INP, LCP, CLS), W3C TraceContext over CORS, and session correlation.
metadata:
  tags: [rum, frontend, browser, mobile, cwv, inp, lcp, cls, cors, faro]
---

# Frontend & Mobile Real User Monitoring (RUM)

Bridging client-side browser and mobile application telemetry with backend distributed microservices provides true end-to-end observability across the user journey.

---

## 1. W3C TraceContext Propagation over CORS

When a browser single-page app (SPA) calls backend APIs across different domains, browsers enforce preflight HTTP `OPTIONS` requests.

### 1.1 Preflight Configuration Requirements
For browsers to forward `traceparent`, `tracestate`, and `baggage`, the backend ingress proxy must return:
```http
Access-Control-Allow-Origin: https://app.example.com
Access-Control-Allow-Headers: Content-Type, Authorization, traceparent, tracestate, baggage
Access-Control-Expose-Headers: traceparent, tracestate, baggage
Access-Control-Allow-Credentials: true
```

### 1.2 The `ZoneContextManager` Requirement
In modern JavaScript/TypeScript runtimes, asynchronous callbacks and `Promise.then()` chains drop thread-local variables.
- The `@opentelemetry/context-zone` package patches the browser microtask queue via `Zone.js`.
- Without `ZoneContextManager`, child HTTP `fetch()` requests cannot inherit the active user-interaction span, breaking distributed traces into disconnected fragments.

---

## 2. Core Web Vitals (CWV) Telemetry

OpenTelemetry RUM captures Google Core Web Vitals directly as span events and OTLP metrics:
- **`LCP` (Largest Contentful Paint)**: Render time of the largest image/text block. Target $\le 2.5	ext{s}$.
- **`CLS` (Cumulative Layout Shift)**: Visual stability score. Target $\le 0.1$.
- **`INP` (Interaction to Next Paint)**: Measures user interface responsiveness to clicks, taps, and keypresses. **Replaced legacy FID (First Input Delay) in March 2024**. Target $\le 200	ext{ms}$.
- **`TTFB` (Time to First Byte)**: Server response latency. Target $\le 800	ext{ms}$.

---

## 3. Production References
- Production implementation: [`rum-browser-tracing.ts`](../examples/frontend/rum-browser-tracing.ts)
