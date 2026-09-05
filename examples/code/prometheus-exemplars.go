package main

import (
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"go.opentelemetry.io/otel/trace"
)

var (
	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "Duration of HTTP requests in seconds with exemplars.",
			Buckets: []float64{0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0},
		},
		[]string{"path", "status"},
	)
)

func init() {
	prometheus.MustRegister(httpRequestDuration)
}

func InstrumentWithExemplar(path string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := &statusResponseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		next(rw, r)

		duration := time.Since(start).Seconds()

		// Extract active trace_id from OpenTelemetry Span Context
		span := trace.SpanFromContext(r.Context())
		spanContext := span.SpanContext()

		if spanContext.HasTraceID() && spanContext.IsSampled() {
			observer := httpRequestDuration.WithLabelValues(path, http.StatusText(rw.statusCode))
			if exemplarObserver, ok := observer.(prometheus.ExemplarObserver); ok {
				exemplarObserver.ObserveWithExemplar(duration, prometheus.Labels{
					"trace_id": spanContext.TraceID().String(),
				})
				return
			}
		}

		httpRequestDuration.WithLabelValues(path, http.StatusText(rw.statusCode)).Observe(duration)
	}
}

type statusResponseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *statusResponseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}
