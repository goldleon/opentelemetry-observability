import { WebTracerProvider } from '@opentelemetry/sdk-trace-web';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { ZoneContextManager } from '@opentelemetry/context-zone';
import { Resource } from '@opentelemetry/resources';
import { ATTR_SERVICE_NAME, ATTR_SERVICE_VERSION } from '@opentelemetry/semantic-conventions';
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { DocumentLoadInstrumentation } from '@opentelemetry/instrumentation-document-load';
import { UserInteractionInstrumentation } from '@opentelemetry/instrumentation-user-interaction';
import { FetchInstrumentation } from '@opentelemetry/instrumentation-fetch';
import { XMLHttpRequestInstrumentation } from '@opentelemetry/instrumentation-xml-http-request';
import { W3CTraceContextPropagator } from '@opentelemetry/core';
import { SpanStatusCode } from '@opentelemetry/api';
import { onLCP, onCLS, onINP, onFCP, onTTFB, Metric } from 'web-vitals';

function getOrCreateSessionId(): string {
  const STORAGE_KEY = 'otel_rum_session_id';
  let sessionId = sessionStorage.getItem(STORAGE_KEY);
  if (!sessionId) {
    sessionId = crypto.randomUUID();
    sessionStorage.setItem(STORAGE_KEY, sessionId);
  }
  return sessionId;
}

export function initRUM() {
  const sessionId = getOrCreateSessionId();

  const resource = new Resource({
    [ATTR_SERVICE_NAME]: 'storefront-spa',
    [ATTR_SERVICE_VERSION]: '2.4.1',
    'session.id': sessionId,
    'browser.user_agent': navigator.userAgent,
    'deployment.environment': 'production',
  });

  const provider = new WebTracerProvider({ resource });

  const exporter = new OTLPTraceExporter({
    url: 'https://telemetry-gateway.example.com/v1/traces',
    headers: {
      'x-client-token': 'frontend-token-sec-9812',
    },
  });

  provider.addSpanProcessor(
    new BatchSpanProcessor(exporter, {
      maxQueueSize: 200,
      maxExportBatchSize: 50,
      scheduledDelayMillis: 2000,
    })
  );

  // Critical: Zone.js context manager maintains traceparent across async Promises
  provider.register({
    contextManager: new ZoneContextManager(),
    propagator: new W3CTraceContextPropagator(),
  });

  // Auto-instrumentation with CORS propagation
  registerInstrumentations({
    instrumentations: [
      new DocumentLoadInstrumentation(),
      new UserInteractionInstrumentation({
        eventNames: ['click', 'submit'],
      }),
      new FetchInstrumentation({
        propagateTraceHeaderCorsUrls: [
          /https:\/\/api\.example\.com\/.*/,
          /https:\/\/checkout\.example\.com\/.*/,
        ],
        clearTimingResources: true,
      }),
      new XMLHttpRequestInstrumentation({
        propagateTraceHeaderCorsUrls: [
          /https:\/\/api\.example\.com\/.*/,
        ],
      }),
    ],
  });

  // Core Web Vitals (LCP, CLS, INP, FCP, TTFB)
  const tracer = provider.getTracer('web-vitals');

  const recordMetricSpan = (metric: Metric) => {
    const span = tracer.startSpan(`web-vital.${metric.name.toLowerCase()}`, {
      attributes: {
        'rum.cwv.name': metric.name,
        'rum.cwv.value': metric.value,
        'rum.cwv.rating': metric.rating,
        'rum.cwv.delta': metric.delta,
        'rum.cwv.id': metric.id,
        'session.id': sessionId,
      },
    });

    if (metric.rating === 'poor') {
      span.setStatus({
        code: SpanStatusCode.ERROR,
        message: `Poor ${metric.name} performance: ${metric.value}`,
      });
    } else {
      span.setStatus({ code: SpanStatusCode.OK });
    }
    span.end();
  };

  onLCP(recordMetricSpan);
  onCLS(recordMetricSpan);
  onINP(recordMetricSpan); // Modern replacement for FID
  onFCP(recordMetricSpan);
  onTTFB(recordMetricSpan);
}
