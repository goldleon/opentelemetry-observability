package main

import (
	"context"

	"github.com/segmentio/kafka-go"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

// KafkaHeaderCarrier adapts Kafka headers to OpenTelemetry TextMapCarrier
type KafkaHeaderCarrier []kafka.Header

func (c KafkaHeaderCarrier) Get(key string) string {
	for _, h := range c {
		if h.Key == key {
			return string(h.Value)
		}
	}
	return ""
}
func (c KafkaHeaderCarrier) Set(key string, val string) {}
func (c KafkaHeaderCarrier) Keys() []string {
	keys := make([]string, 0, len(c))
	for _, h := range c {
		keys = append(keys, h.Key)
	}
	return keys
}

func ProcessKafkaBatch(ctx context.Context, messages []kafka.Message) {
	tr := otel.GetTracerProvider().Tracer("kafka-consumer")
	propagator := otel.GetTextMapPropagator()

	for _, msg := range messages {
		// 1. Extract remote Producer's SpanContext from message headers
		producerCtx := propagator.Extract(ctx, KafkaHeaderCarrier(msg.Headers))
		remoteSpanCtx := trace.SpanContextFromContext(producerCtx)

		var spanOpts []trace.SpanStartOption
		spanOpts = append(spanOpts,
			trace.WithSpanKind(trace.SpanKindConsumer),
			trace.WithAttributes(
				semconv.MessagingSystemKey.String("kafka"),
				semconv.MessagingDestinationNameKey.String(msg.Topic),
				semconv.MessagingKafkaMessageOffsetKey.Int64(msg.Offset),
			),
		)

		// 2. Attach Span Link to maintain causal link without invalid parent-child nesting
		if remoteSpanCtx.IsValid() {
			spanOpts = append(spanOpts, trace.WithLinks(trace.Link{
				SpanContext: remoteSpanCtx,
			}))
		}

		// 3. Start independent processing span
		_, span := tr.Start(ctx, "process_order_event", spanOpts...)
		handleOrder(msg.Value)
		span.End()
	}
}

func handleOrder(val []byte) {}
