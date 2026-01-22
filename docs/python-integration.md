# Python Integration Guide

This guide shows how to integrate your Python application with the OpenTelemetry observability stack.

## Prerequisites

- Python 3.8+ application
- OpenTelemetry stack running (`./scripts/start.sh`)

## 1. Install Packages

```bash
pip install opentelemetry-api \
            opentelemetry-sdk \
            opentelemetry-exporter-otlp-proto-grpc \
            opentelemetry-instrumentation \
            opentelemetry-instrumentation-requests \
            opentelemetry-instrumentation-flask \
            opentelemetry-instrumentation-fastapi \
            opentelemetry-instrumentation-sqlalchemy \
            opentelemetry-instrumentation-logging
```

Or add to `requirements.txt`:

```
opentelemetry-api>=1.20.0
opentelemetry-sdk>=1.20.0
opentelemetry-exporter-otlp-proto-grpc>=1.20.0
opentelemetry-instrumentation>=0.41b0
opentelemetry-instrumentation-requests>=0.41b0
opentelemetry-instrumentation-flask>=0.41b0
opentelemetry-instrumentation-fastapi>=0.41b0
opentelemetry-instrumentation-sqlalchemy>=0.41b0
opentelemetry-instrumentation-logging>=0.41b0
```

## 2. Create Telemetry Module

Create `telemetry.py`:

```python
# telemetry.py
import os
import logging
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource, SERVICE_NAME, SERVICE_VERSION, DEPLOYMENT_ENVIRONMENT
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry._logs import set_logger_provider

# Configuration
OTEL_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "localhost:4317")
SERVICE_NAME_VALUE = os.getenv("SERVICE_NAME", "my-python-service")
SERVICE_VERSION_VALUE = os.getenv("SERVICE_VERSION", "1.0.0")
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")


def setup_telemetry():
    """Initialize OpenTelemetry with traces, metrics, and logs."""
    
    # Create resource with service information
    resource = Resource.create({
        SERVICE_NAME: SERVICE_NAME_VALUE,
        SERVICE_VERSION: SERVICE_VERSION_VALUE,
        DEPLOYMENT_ENVIRONMENT: ENVIRONMENT,
    })
    
    # Setup Tracing
    trace_provider = TracerProvider(resource=resource)
    trace_exporter = OTLPSpanExporter(
        endpoint=OTEL_ENDPOINT,
        insecure=True
    )
    trace_provider.add_span_processor(BatchSpanProcessor(trace_exporter))
    trace.set_tracer_provider(trace_provider)
    
    # Setup Metrics
    metric_exporter = OTLPMetricExporter(
        endpoint=OTEL_ENDPOINT,
        insecure=True
    )
    metric_reader = PeriodicExportingMetricReader(
        metric_exporter,
        export_interval_millis=10000  # Export every 10 seconds
    )
    meter_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
    metrics.set_meter_provider(meter_provider)
    
    # Setup Logging
    log_exporter = OTLPLogExporter(
        endpoint=OTEL_ENDPOINT,
        insecure=True
    )
    logger_provider = LoggerProvider(resource=resource)
    logger_provider.add_log_record_processor(BatchLogRecordProcessor(log_exporter))
    set_logger_provider(logger_provider)
    
    # Add OTLP handler to root logger
    handler = LoggingHandler(level=logging.INFO, logger_provider=logger_provider)
    logging.getLogger().addHandler(handler)
    
    print(f"OpenTelemetry initialized for {SERVICE_NAME_VALUE}")
    
    return trace.get_tracer(SERVICE_NAME_VALUE)


def get_tracer(name: str = None):
    """Get a tracer instance."""
    return trace.get_tracer(name or SERVICE_NAME_VALUE)


def get_meter(name: str = None):
    """Get a meter instance."""
    return metrics.get_meter(name or SERVICE_NAME_VALUE)
```

## 3. Flask Application Example

```python
# app.py
import logging
from flask import Flask, request, jsonify
from opentelemetry import trace
from opentelemetry.trace import SpanKind, Status, StatusCode
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor

from telemetry import setup_telemetry, get_tracer, get_meter

# Initialize telemetry FIRST
tracer = setup_telemetry()

# Create Flask app
app = Flask(__name__)

# Auto-instrument Flask and requests library
FlaskInstrumentor().instrument_app(app)
RequestsInstrumentor().instrument()

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create custom metrics
meter = get_meter()
request_counter = meter.create_counter(
    "requests_total",
    description="Total number of requests",
    unit="1"
)
request_duration = meter.create_histogram(
    "request_duration_ms",
    description="Request duration in milliseconds",
    unit="ms"
)


@app.route('/health')
def health():
    return jsonify({"status": "healthy"})


@app.route('/api/users/<user_id>')
def get_user(user_id):
    # Get current span and add attributes
    span = trace.get_current_span()
    span.set_attribute("user.id", user_id)
    
    logger.info(f"Fetching user {user_id}")
    
    try:
        # Create a child span for database operation
        with tracer.start_as_current_span("db.get_user", kind=SpanKind.CLIENT) as db_span:
            db_span.set_attribute("db.system", "postgresql")
            db_span.set_attribute("db.operation", "SELECT")
            db_span.set_attribute("db.statement", "SELECT * FROM users WHERE id = ?")
            
            # Simulate database call
            import time
            time.sleep(0.05)
            
            user = {"id": user_id, "name": "John Doe", "email": "john@example.com"}
        
        # Record metrics
        request_counter.add(1, {"endpoint": "/api/users", "status": "success"})
        
        return jsonify(user)
        
    except Exception as e:
        logger.error(f"Error fetching user {user_id}: {e}")
        span.record_exception(e)
        span.set_status(Status(StatusCode.ERROR, str(e)))
        request_counter.add(1, {"endpoint": "/api/users", "status": "error"})
        return jsonify({"error": "Internal server error"}), 500


@app.route('/api/orders', methods=['POST'])
def create_order():
    span = trace.get_current_span()
    data = request.get_json()
    
    logger.info(f"Creating order for user {data.get('user_id')}")
    
    with tracer.start_as_current_span("process_order") as order_span:
        order_span.set_attribute("order.user_id", data.get('user_id'))
        order_span.set_attribute("order.items_count", len(data.get('items', [])))
        
        # Validate order
        with tracer.start_as_current_span("validate_order"):
            # Validation logic
            pass
        
        # Process payment
        with tracer.start_as_current_span("process_payment", kind=SpanKind.CLIENT):
            import time
            time.sleep(0.1)  # Simulate payment processing
        
        # Save to database
        with tracer.start_as_current_span("save_order", kind=SpanKind.CLIENT):
            import time
            time.sleep(0.05)
    
    return jsonify({"order_id": "12345", "status": "created"}), 201


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
```

## 4. FastAPI Application Example

```python
# main.py
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from opentelemetry import trace
from opentelemetry.trace import SpanKind, Status, StatusCode
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor

from telemetry import setup_telemetry, get_tracer, get_meter

# Initialize telemetry
tracer = setup_telemetry()

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    logger.info("Application starting up")
    yield
    # Shutdown
    logger.info("Application shutting down")


app = FastAPI(title="My FastAPI Service", lifespan=lifespan)

# Auto-instrument FastAPI
FastAPIInstrumentor.instrument_app(app)
HTTPXClientInstrumentor().instrument()

# Create custom metrics
meter = get_meter()
active_requests = meter.create_up_down_counter(
    "active_requests",
    description="Number of active requests"
)


@app.get("/health")
async def health():
    return {"status": "healthy"}


@app.get("/api/users/{user_id}")
async def get_user(user_id: str):
    span = trace.get_current_span()
    span.set_attribute("user.id", user_id)
    
    logger.info(f"Fetching user {user_id}")
    
    with tracer.start_as_current_span("db.get_user", kind=SpanKind.CLIENT) as db_span:
        db_span.set_attribute("db.system", "postgresql")
        
        import asyncio
        await asyncio.sleep(0.05)  # Simulate async DB call
        
        return {"id": user_id, "name": "John Doe"}


@app.post("/api/process")
async def process_data(data: dict):
    span = trace.get_current_span()
    
    active_requests.add(1)
    try:
        with tracer.start_as_current_span("process_data") as process_span:
            process_span.set_attribute("data.size", len(str(data)))
            
            # Processing logic
            import asyncio
            await asyncio.sleep(0.1)
            
            logger.info("Data processed successfully")
            return {"status": "processed"}
    finally:
        active_requests.add(-1)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

## 5. Add Custom Spans

```python
from opentelemetry import trace
from opentelemetry.trace import SpanKind

tracer = trace.get_tracer("my-service")

# Synchronous span
def process_item(item_id: str):
    with tracer.start_as_current_span(
        "process_item",
        kind=SpanKind.INTERNAL,
        attributes={"item.id": item_id}
    ) as span:
        try:
            # Your processing logic
            result = do_something(item_id)
            span.set_attribute("item.processed", True)
            return result
        except Exception as e:
            span.record_exception(e)
            span.set_status(Status(StatusCode.ERROR, str(e)))
            raise


# Async span
async def fetch_external_data(url: str):
    with tracer.start_as_current_span(
        "fetch_external_data",
        kind=SpanKind.CLIENT,
        attributes={"http.url": url}
    ) as span:
        import httpx
        async with httpx.AsyncClient() as client:
            response = await client.get(url)
            span.set_attribute("http.status_code", response.status_code)
            return response.json()


# Manual span management
def complex_operation():
    span = tracer.start_span("complex_operation")
    try:
        # Step 1
        span.add_event("Starting step 1")
        step1_result = do_step1()
        
        # Step 2
        span.add_event("Starting step 2", {"step1_result": str(step1_result)})
        step2_result = do_step2(step1_result)
        
        span.set_status(Status(StatusCode.OK))
        return step2_result
    except Exception as e:
        span.record_exception(e)
        span.set_status(Status(StatusCode.ERROR))
        raise
    finally:
        span.end()
```

## 6. Add Custom Metrics

```python
from opentelemetry import metrics

meter = metrics.get_meter("my-service")

# Counter - for counting events
request_counter = meter.create_counter(
    name="http_requests_total",
    description="Total HTTP requests",
    unit="1"
)

# Usage
request_counter.add(1, {"method": "GET", "endpoint": "/api/users", "status": "200"})

# Histogram - for measuring distributions (latency, sizes)
request_latency = meter.create_histogram(
    name="http_request_duration_seconds",
    description="HTTP request latency",
    unit="s"
)

# Usage
import time
start = time.time()
# ... do work ...
duration = time.time() - start
request_latency.record(duration, {"method": "GET", "endpoint": "/api/users"})

# UpDownCounter - for values that go up and down
active_connections = meter.create_up_down_counter(
    name="active_connections",
    description="Number of active connections"
)

# Usage
active_connections.add(1)   # Connection opened
active_connections.add(-1)  # Connection closed

# Observable Gauge - for async measurements
def get_cpu_usage(options):
    import psutil
    yield metrics.Observation(psutil.cpu_percent(), {"cpu": "total"})

meter.create_observable_gauge(
    name="system_cpu_usage",
    callbacks=[get_cpu_usage],
    description="Current CPU usage",
    unit="%"
)
```

## 7. Context Propagation

For distributed tracing across services:

```python
from opentelemetry import trace
from opentelemetry.propagate import inject, extract
import requests

# When making outbound HTTP requests, inject context
def call_downstream_service(url: str, data: dict):
    headers = {}
    inject(headers)  # Inject trace context into headers
    
    response = requests.post(url, json=data, headers=headers)
    return response.json()

# When receiving requests, extract context (usually handled by instrumentation)
from flask import request

@app.before_request
def extract_trace_context():
    ctx = extract(request.headers)
    # Context is now available for child spans
```

## 8. Environment Variables

```bash
# OpenTelemetry Configuration
OTEL_EXPORTER_OTLP_ENDPOINT=localhost:4317
SERVICE_NAME=my-python-service
SERVICE_VERSION=1.0.0
ENVIRONMENT=development

# Logging
LOG_LEVEL=INFO

# Optional: Sampling (for high-traffic services)
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1  # Sample 10% of traces
```

## 9. Docker Compose Integration

```yaml
services:
  my-python-app:
    build: .
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector:4317
      - SERVICE_NAME=my-python-service
      - ENVIRONMENT=production
    networks:
      - observability

networks:
  observability:
    external: true
    name: observability
```

## 10. Auto-Instrumentation (Alternative)

You can also use automatic instrumentation without code changes:

```bash
# Install auto-instrumentation package
pip install opentelemetry-distro opentelemetry-exporter-otlp

# Install all available instrumentations
opentelemetry-bootstrap -a install

# Run your app with auto-instrumentation
opentelemetry-instrument \
    --service_name my-python-service \
    --exporter_otlp_endpoint http://localhost:4317 \
    python app.py
```

## Viewing Your Data

- **Traces**: http://localhost:16686 (Jaeger)
- **Metrics**: http://localhost:3000 (Grafana)
- **Logs**: http://localhost:3000 (Grafana → Explore → Loki)

## Troubleshooting

### Traces not appearing
1. Verify OTel stack is running: `./scripts/status.sh`
2. Check endpoint configuration (should be `host:port`, not `http://host:port` for gRPC)
3. Ensure `setup_telemetry()` is called before any instrumented code

### Memory leaks
- Ensure spans are properly ended (use context managers)
- Check batch processor queue sizes
- Enable sampling for high-traffic services

### Missing async context
- Use `start_as_current_span` for automatic context propagation
- For manual context management, use `trace.use_span(span)` context manager
