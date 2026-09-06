/**
 * Production OpenTelemetry Node.js / Express / TypeScript Initialization
 * Must be executed before any other application imports via:
 * node --import ./instrumentation.ts index.js
 */

import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-grpc';
import { PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics';
import { Resource } from '@opentelemetry/resources';
import { ATTR_SERVICE_NAME, ATTR_SERVICE_VERSION } from '@opentelemetry/semantic-conventions';
import { trace, context, SpanStatusCode } from '@opentelemetry/api';
import express, { Request, Response } from 'express';
import winston from 'winston';

// 1. Configure OpenTelemetry SDK
const sdk = new NodeSDK({
  resource: new Resource({
    [ATTR_SERVICE_NAME]: 'checkout-api',
    [ATTR_SERVICE_VERSION]: '1.8.0',
    'deployment.environment': 'production',
  }),
  traceExporter: new OTLPTraceExporter({
    url: 'grpc://otel-gateway.monitoring.svc:4317',
  }),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter({
      url: 'grpc://otel-gateway.monitoring.svc:4317',
    }),
    exportIntervalMillis: 15000,
  }),
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-fs': { enabled: false }, // Avoid FS span bloat
    }),
  ],
});

sdk.start();

// 2. Configure Winston logger with Trace-to-Log Correlation
const logger = winston.createLogger({
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format((info) => {
      const activeSpan = trace.getActiveSpan();
      if (activeSpan) {
        const spanContext = activeSpan.spanContext();
        info.trace_id = spanContext.traceId;
        info.span_id = spanContext.spanId;
        info.trace_flags = spanContext.traceFlags;
      }
      return info;
    })(),
    winston.format.json()
  ),
  transports: [new winston.transports.Console()],
});

// 3. Express Application
const app = express();
const tracer = trace.getTracer('checkout-api', '1.8.0');

app.post('/checkout', async (req: Request, res: Response) => {
  const span = tracer.startSpan('execute-payment');

  try {
    await context.with(trace.setSpan(context.active(), span), async () => {
      span.setAttribute('payment.gateway', 'stripe');
      logger.info('Starting checkout transaction payment');

      // Simulate payment delay
      await new Promise((resolve) => setTimeout(resolve, 100));

      span.setStatus({ code: SpanStatusCode.OK });
      res.json({ status: 'completed' });
    });
  } catch (error: any) {
    span.recordException(error);
    span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
    res.status(500).json({ error: 'Transaction failed' });
  } finally {
    span.end();
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  logger.info(`Server listening on port ${PORT}`);
});

process.on('SIGTERM', () => {
  sdk.shutdown()
    .then(() => process.exit(0))
    .catch((err) => process.exit(1));
});
