package main

import (
	"context"
	"fmt"
	"net/http"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/baggage"
	"go.opentelemetry.io/otel/propagation"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

var tracer = otel.Tracer("order-service-handler")

// HttpMiddleware extracts W3C TraceContext and Baggage and initializes a child server span
func HttpMiddleware(next http.Handler) http.Handler {
	propagator := propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	)

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// 1. Extract W3C Traceparent and Baggage from incoming HTTP Headers
		ctx := propagator.Extract(r.Context(), propagation.HeaderCarrier(r.Header))

		// 2. Start a child span rooted in the extracted context
		ctx, span := tracer.Start(ctx, fmt.Sprintf("%s %s", r.Method, r.URL.Path),
			trace.WithSpanKind(trace.SpanKindServer),
			trace.WithAttributes(
				semconv.HTTPRequestMethodKey.String(r.Method),
				semconv.URLPathKey.String(r.URL.Path),
				semconv.ClientAddressKey.String(r.RemoteAddr),
			),
		)
		defer span.End()

		// 3. Inspect and read W3C Baggage safely
		bag := baggage.FromContext(ctx)
		if tenantMember := bag.Member("tenant.id"); tenantMember.Value() != "" {
			span.SetAttributes(semconv.EnduserIDKey.String(tenantMember.Value()))
		}

		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
