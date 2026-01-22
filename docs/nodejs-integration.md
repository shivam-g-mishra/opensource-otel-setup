# Node.js Integration Guide

This guide shows how to integrate your Node.js application with the OpenTelemetry observability stack.

## Prerequisites

- Node.js 16+ application
- OpenTelemetry stack running (`./scripts/start.sh`)

## 1. Install NPM Packages

```bash
npm install @opentelemetry/sdk-node \
            @opentelemetry/api \
            @opentelemetry/auto-instrumentations-node \
            @opentelemetry/exporter-trace-otlp-grpc \
            @opentelemetry/exporter-metrics-otlp-grpc \
            @opentelemetry/exporter-logs-otlp-grpc \
            @opentelemetry/sdk-logs \
            @opentelemetry/api-logs \
            winston \
            winston-transport
```

## 2. Create Instrumentation File

Create `instrumentation.js` at the root of your project:

```javascript
// instrumentation.js
// This file MUST be loaded before your application code
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-grpc');
const { OTLPLogExporter } = require('@opentelemetry/exporter-logs-otlp-grpc');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { BatchLogRecordProcessor } = require('@opentelemetry/sdk-logs');
const { Resource } = require('@opentelemetry/resources');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');

const OTEL_ENDPOINT = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4317';

// Define service resource
const resource = new Resource({
  [SemanticResourceAttributes.SERVICE_NAME]: process.env.SERVICE_NAME || 'my-nodejs-service',
  [SemanticResourceAttributes.SERVICE_VERSION]: process.env.SERVICE_VERSION || '1.0.0',
  [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: process.env.NODE_ENV || 'development',
});

// Create exporters
const traceExporter = new OTLPTraceExporter({
  url: OTEL_ENDPOINT,
});

const metricExporter = new OTLPMetricExporter({
  url: OTEL_ENDPOINT,
});

const logExporter = new OTLPLogExporter({
  url: OTEL_ENDPOINT,
});

// Configure and start the SDK
const sdk = new NodeSDK({
  resource: resource,
  traceExporter: traceExporter,
  metricReader: new PeriodicExportingMetricReader({
    exporter: metricExporter,
    exportIntervalMillis: 10000, // Export every 10 seconds
  }),
  logRecordProcessor: new BatchLogRecordProcessor(logExporter),
  instrumentations: [
    getNodeAutoInstrumentations({
      // Disable fs instrumentation to reduce noise
      '@opentelemetry/instrumentation-fs': { enabled: false },
      // Configure HTTP instrumentation
      '@opentelemetry/instrumentation-http': {
        ignoreIncomingPaths: ['/health', '/ready', '/metrics'],
      },
    }),
  ],
});

// Graceful shutdown
process.on('SIGTERM', () => {
  sdk.shutdown()
    .then(() => console.log('OpenTelemetry SDK shut down successfully'))
    .catch((error) => console.log('Error shutting down SDK', error))
    .finally(() => process.exit(0));
});

sdk.start();
console.log('OpenTelemetry SDK started');

module.exports = sdk;
```

## 3. Configure Your Application

### Option A: Using --require flag (Recommended)

Start your application with the instrumentation loaded first:

```bash
node --require ./instrumentation.js app.js
```

Or in `package.json`:

```json
{
  "scripts": {
    "start": "node --require ./instrumentation.js app.js",
    "dev": "node --require ./instrumentation.js --watch app.js"
  }
}
```

### Option B: Import at the top of your entry file

```javascript
// app.js - import instrumentation FIRST
require('./instrumentation');

const express = require('express');
const app = express();

// ... rest of your application
```

## 4. Add Custom Spans

```javascript
const { trace } = require('@opentelemetry/api');

// Get a tracer
const tracer = trace.getTracer('my-service');

async function processOrder(orderId) {
  // Create a custom span
  return tracer.startActiveSpan('processOrder', async (span) => {
    try {
      // Add attributes to the span
      span.setAttribute('order.id', orderId);
      span.setAttribute('order.type', 'standard');

      // Nested span
      await tracer.startActiveSpan('validateOrder', async (validateSpan) => {
        // Validation logic
        validateSpan.setAttribute('validation.status', 'passed');
        validateSpan.end();
      });

      // Process order logic here
      const result = await doSomething();
      
      span.setStatus({ code: 1 }); // OK
      return result;
    } catch (error) {
      span.recordException(error);
      span.setStatus({ code: 2, message: error.message }); // ERROR
      throw error;
    } finally {
      span.end();
    }
  });
}
```

## 5. Add Custom Metrics

```javascript
const { metrics } = require('@opentelemetry/api');

// Get a meter
const meter = metrics.getMeter('my-service');

// Create metrics
const requestCounter = meter.createCounter('requests_total', {
  description: 'Total number of requests',
});

const requestDuration = meter.createHistogram('request_duration_ms', {
  description: 'Request duration in milliseconds',
  unit: 'ms',
});

const activeConnections = meter.createUpDownCounter('active_connections', {
  description: 'Number of active connections',
});

// Use in your code
app.use((req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = Date.now() - start;
    
    requestCounter.add(1, {
      method: req.method,
      route: req.route?.path || req.path,
      status_code: res.statusCode,
    });
    
    requestDuration.record(duration, {
      method: req.method,
      route: req.route?.path || req.path,
    });
  });
  
  next();
});
```

## 6. Configure Logging with Winston

Create a Winston logger that exports logs via OTLP:

```javascript
// logger.js
const winston = require('winston');
const { logs, SeverityNumber } = require('@opentelemetry/api-logs');

// Custom transport to send logs to OTel
class OTelTransport extends require('winston-transport') {
  constructor(opts) {
    super(opts);
    this.logger = logs.getLogger('winston');
  }

  log(info, callback) {
    setImmediate(() => this.emit('logged', info));

    const severityMap = {
      error: SeverityNumber.ERROR,
      warn: SeverityNumber.WARN,
      info: SeverityNumber.INFO,
      debug: SeverityNumber.DEBUG,
    };

    this.logger.emit({
      severityNumber: severityMap[info.level] || SeverityNumber.INFO,
      severityText: info.level.toUpperCase(),
      body: info.message,
      attributes: {
        ...info,
        level: undefined,
        message: undefined,
      },
    });

    callback();
  }
}

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  defaultMeta: { service: process.env.SERVICE_NAME || 'my-nodejs-service' },
  transports: [
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.simple()
      ),
    }),
    new OTelTransport(),
  ],
});

module.exports = logger;
```

Usage:

```javascript
const logger = require('./logger');

logger.info('User logged in', { userId: '123', action: 'login' });
logger.error('Failed to process payment', { orderId: '456', error: 'Insufficient funds' });
```

## 7. Express.js Example

Complete example with Express:

```javascript
// app.js
require('./instrumentation');

const express = require('express');
const { trace, SpanStatusCode } = require('@opentelemetry/api');
const logger = require('./logger');

const app = express();
app.use(express.json());

const tracer = trace.getTracer('express-app');

// Health check (not traced)
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

// Example endpoint with custom tracing
app.get('/api/users/:id', async (req, res) => {
  const span = trace.getActiveSpan();
  span?.setAttribute('user.id', req.params.id);
  
  try {
    logger.info('Fetching user', { userId: req.params.id });
    
    // Simulate database call with custom span
    const user = await tracer.startActiveSpan('db.getUser', async (dbSpan) => {
      dbSpan.setAttribute('db.system', 'postgresql');
      dbSpan.setAttribute('db.operation', 'SELECT');
      
      // Simulate latency
      await new Promise(resolve => setTimeout(resolve, 50));
      
      dbSpan.end();
      return { id: req.params.id, name: 'John Doe' };
    });
    
    res.json(user);
  } catch (error) {
    logger.error('Failed to fetch user', { userId: req.params.id, error: error.message });
    span?.recordException(error);
    span?.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
    res.status(500).json({ error: 'Internal server error' });
  }
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  logger.info(`Server started on port ${PORT}`);
});
```

## 8. Environment Variables

Set these in your environment or `.env` file:

```bash
# OpenTelemetry Configuration
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
SERVICE_NAME=my-nodejs-service
SERVICE_VERSION=1.0.0
NODE_ENV=development

# Logging
LOG_LEVEL=info
```

## 9. Docker Compose Integration

If your app runs in Docker, use the network:

```yaml
services:
  my-app:
    build: .
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
      - SERVICE_NAME=my-nodejs-service
      - NODE_ENV=production
    networks:
      - observability

networks:
  observability:
    external: true
    name: observability
```

## 10. TypeScript Support

For TypeScript, install type definitions:

```bash
npm install -D @types/node
```

And use ES modules in `instrumentation.ts`:

```typescript
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
// ... rest of the configuration
```

## Viewing Your Data

- **Traces**: http://localhost:16686 (Jaeger)
- **Metrics**: http://localhost:3000 (Grafana)
- **Logs**: http://localhost:3000 (Grafana → Explore → Loki)

## Troubleshooting

### Traces not appearing
1. Ensure the OTel Collector is running: `./scripts/status.sh`
2. Check your `OTEL_EXPORTER_OTLP_ENDPOINT` is correct
3. Verify instrumentation is loaded first (before any imports)

### High memory usage
- Reduce metric export interval
- Disable unused auto-instrumentations
- Enable sampling for high-traffic services

### Missing spans
- Ensure async context is properly propagated
- Use `startActiveSpan` instead of `startSpan` for automatic context propagation
