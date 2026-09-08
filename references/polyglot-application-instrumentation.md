# Polyglot Production Application Instrumentation

Complete, production-grade patterns for instrumenting enterprise applications across the primary programming language ecosystems: Java (Spring Boot 3 + Virtual Threads), Python (FastAPI + AsyncIO), Node.js/TypeScript (Express / Next.js), and .NET 8 (Activity API).

---

## 1. Java 21 & Spring Boot 3 (Virtual Threads)

Spring Boot 3.2+ introduces Java 21 Virtual Threads (`Project Loom`). Traditional `ThreadLocal` context propagation breaks if not handled correctly by the OpenTelemetry SDK.

### Key Rules
- Use `opentelemetry-extension-annotations` or native OpenTelemetry Java SDK with `io.opentelemetry.context.Context`.
- Context automatically flows across virtual threads when using OpenTelemetry Javaagent 2.x+.
- Correlate SLF4J / Logback with OpenTelemetry MDC using `OpenTelemetryAppender`.

> ⚠️ Verify current version: `1.36.0` below is the OTel Java SDK/API version at time of writing. Check https://github.com/open-telemetry/opentelemetry-java/releases for the current release before pinning it in a real `pom.xml`.

```xml
<!-- pom.xml snippet -->
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-api</artifactId>
    <version>1.36.0</version>
</dependency>
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-extension-annotations</artifactId>
    <version>1.36.0</version>
</dependency>
```

---

## 2. Python (FastAPI + AsyncIO + Structlog)

In asynchronous Python, `contextvars` must be used rather than thread-locals. OpenTelemetry's Python SDK integrates directly with `contextvars`.

### Key Rules
- Wrap asynchronous endpoints with `@tracer.start_as_current_span()`.
- Inject `trace_id` and `span_id` into `structlog` processors for high-density JSON logging.
- Ensure database drivers (e.g. `asyncpg`, `psycopg3`, `SQLAlchemy`) use OTel instrumentors (`SQLAlchemyInstrumentor`, `HTTPXClientInstrumentor`).

---

## 3. Node.js & TypeScript (Express / Next.js)

Node.js asynchronous event loops require `AsyncLocalStorage` for context propagation.

### Key Rules
- Initialize the OpenTelemetry SDK before loading any other modules (via `-r ./instrumentation.ts` or Node `--import`).
- Use `@opentelemetry/sdk-node` with `@opentelemetry/auto-instrumentations-node`.
- Inject trace context into structured loggers like Winston or Pino.

---

## 4. .NET 8 / C# (ASP.NET Core & Activity API)

.NET has built-in, native OpenTelemetry primitives inside the BCL via `System.Diagnostics.Activity` and `System.Diagnostics.ActivitySource`.

### Key Rules
- Do NOT create custom tracing wrappers; use `System.Diagnostics.ActivitySource`.
- Register OpenTelemetry via `builder.Services.AddOpenTelemetry().WithTracing().WithMetrics()`.
- OTLP export is natively integrated into `OpenTelemetry.Exporter.OpenTelemetryProtocol`.
