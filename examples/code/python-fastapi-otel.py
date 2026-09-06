"""
Production OpenTelemetry FastAPI Service with AsyncIO, Structlog, and Context Propagation.
"""
import asyncio
import logging
from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI, Request, Response
from opentelemetry import baggage, trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.resources import SERVICE_NAME, SERVICE_VERSION, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.trace import Status, StatusCode
import structlog

# 1. Setup OpenTelemetry TracerProvider
resource = Resource.create(attributes={
    SERVICE_NAME: "order-service",
    SERVICE_VERSION: "2.4.0",
    "deployment.environment": "production"
})
provider = TracerProvider(resource=resource)
otlp_exporter = OTLPSpanExporter(endpoint="otel-gateway.monitoring.svc:4317", insecure=True)
provider.add_span_processor(BatchSpanProcessor(otlp_exporter))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer("order-service", "2.4.0")

# 2. Configure Structlog with OTel Context Injection
def add_opentelemetry_context(logger, method_name, event_dict):
    current_span = trace.get_current_span()
    if current_span and current_span.is_recording():
        ctx = current_span.get_span_context()
        event_dict["trace_id"] = trace.format_trace_id(ctx.trace_id)
        event_dict["span_id"] = trace.format_span_id(ctx.span_id)
        event_dict["trace_sampled"] = ctx.trace_flags.sampled
    return event_dict

structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        add_opentelemetry_context,
        structlog.processors.JSONRenderer()
    ],
    logger_factory=structlog.PrintLoggerFactory()
)
logger = structlog.get_logger()

# 3. Lifespan handler
@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    logger.info("Service initialized with OpenTelemetry instrumentation")
    yield
    provider.shutdown()

app = FastAPI(title="OrderService", lifespan=lifespan)
FastAPIInstrumentor.instrument_app(app, tracer_provider=provider)

@app.get("/orders/{order_id}")
async def get_order(order_id: str, request: Request) -> dict:
    # Set W3C Baggage for downstream propagation
    ctx = baggage.set_baggage("tenant.id", "acme-corp")

    with tracer.start_as_current_span("process-order", context=ctx) as span:
        span.set_attribute("order.id", order_id)
        span.set_attribute("app.version", "2.4.0")

        logger.info("Processing order in async handler", order_id=order_id)

        # Async sub-task with context preservation
        async def async_inventory_check():
            with tracer.start_as_current_span("inventory-lookup") as child_span:
                child_span.set_attribute("inventory.item", order_id)
                await asyncio.sleep(0.05)
                logger.info("Inventory confirmed for item", order_id=order_id)

        await async_inventory_check()
        span.set_status(Status(StatusCode.OK))
        return {"status": "success", "order_id": order_id}
