package main

import (
	"context"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

var genaiTracer = otel.Tracer("genai-agent-client")

// RecordChatCompletion instruments an LLM call using OTel GenAI Semantic Conventions
func RecordChatCompletion(ctx context.Context, model string, promptTokens, completionTokens int, finishReason string) {
	ctx, span := genaiTracer.Start(ctx, "chat "+model,
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			attribute.String("gen_ai.system", "openai"),
			attribute.String("gen_ai.request.model", model),
			attribute.String("gen_ai.response.model", model),
			attribute.Int("gen_ai.usage.input_tokens", promptTokens),
			attribute.Int("gen_ai.usage.output_tokens", completionTokens),
			attribute.StringSlice("gen_ai.response.finish_reasons", []string{finishReason}),
			semconv.ServerAddressKey.String("api.openai.com"),
			semconv.ServerPortKey.Int(443),
		),
	)
	defer span.End()
}
