package com.example.observability;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.baggage.Baggage;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.Scope;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Production OpenTelemetry Spring Boot 3 with Java 21 Virtual Threads
 * Demonstrates context propagation across virtual threads and Logback MDC correlation.
 */
@SpringBootApplication
public class Application {

    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }

    // Java 21 Virtual Thread Executor
    @Bean
    public ExecutorService virtualThreadExecutor() {
        return Executors.newVirtualThreadPerTaskExecutor();
    }
}

@RestController
class OrderController {
    private static final Logger log = LoggerFactory.getLogger(OrderController.class);
    private final Tracer tracer = GlobalOpenTelemetry.getTracer("com.example.orders", "1.0.0");
    private final ExecutorService virtualExecutor;

    public OrderController(ExecutorService virtualExecutor) {
        this.virtualExecutor = virtualExecutor;
    }

    @GetMapping("/orders/{id}")
    public String getOrder(@PathVariable String id) {
        // Start manual span
        Span span = tracer.spanBuilder("process-order")
                .setSpanKind(SpanKind.SERVER)
                .setAttribute(AttributeKey.stringKey("order.id"), id)
                .startSpan();

        try (Scope scope = span.makeCurrent()) {
            // Set correlation identifiers into SLF4J MDC
            MDC.put("trace_id", span.getSpanContext().getTraceId());
            MDC.put("span_id", span.getSpanContext().getSpanId());

            // Propagate tenant via W3C Baggage
            Baggage baggage = Baggage.current().toBuilder()
                    .put("tenant.id", "enterprise-corp")
                    .build();

            try (Scope baggageScope = baggage.makeCurrent()) {
                log.info("Processing order {} within span", id);

                // Asynchronously dispatch to Java 21 Virtual Thread with Context wrapping
                Context currentContext = Context.current();
                virtualExecutor.submit(currentContext.wrap(() -> {
                    Span asyncSpan = tracer.spanBuilder("async-validation")
                            .setParent(currentContext)
                            .startSpan();
                    try (Scope asyncScope = asyncSpan.makeCurrent()) {
                        log.info("Executing async validation on virtual thread: {}", Thread.currentThread());
                        Thread.sleep(50);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                    } finally {
                        asyncSpan.end();
                    }
                }));

                span.setStatus(StatusCode.OK);
                return "Order processed: " + id;
            }
        } catch (Exception e) {
            span.recordException(e);
            span.setStatus(StatusCode.ERROR, e.getMessage());
            throw e;
        } finally {
            MDC.clear();
            span.end();
        }
    }
}
