package main

import (
	"context"
	"runtime/pprof"

	"go.opentelemetry.io/otel"
)

// ExecuteWithProfileContext correlates Go runtime pprof profiles directly with OTel Spans
func ExecuteWithProfileContext(ctx context.Context, operationName string, fn func(context.Context)) {
	tr := otel.GetTracerProvider().Tracer("profile-aware-service")
	ctx, span := tr.Start(ctx, operationName)
	defer span.End()

	sc := span.SpanContext()

	// Inject active TraceID and SpanID into pprof goroutine labels
	pprof.Do(ctx, pprof.Labels(
		"trace_id", sc.TraceID().String(),
		"span_id",  sc.SpanID().String(),
	), func(ctx context.Context) {
		// All CPU samples and heap allocations inside this closure will be tagged
		fn(ctx)
	})
}
