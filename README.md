# 🔭 OpenTelemetry Observability Stack

A **production-ready**, **reusable** observability infrastructure using OpenTelemetry. Drop this into any project to get distributed tracing, metrics, and logging in minutes.

## 🚀 Quick Start

```bash
# Clone the repo
git clone https://github.com/shivam-g-mishra/opensource-otel-setup.git
cd opensource-otel-setup

# Start the stack
./scripts/start.sh

# Or with Docker Compose directly
docker compose up -d
```

**That's it!** Open:
- 📊 **Jaeger** (Traces): http://localhost:16686
- 📈 **Grafana** (Dashboards): http://localhost:3000 (admin/admin)
- 🔍 **Prometheus** (Metrics): http://localhost:9090
- 📜 **Loki** (Logs): http://localhost:3100

## 📦 What's Included

| Service | Purpose | Port |
|---------|---------|------|
| **Jaeger** | Distributed tracing | 16686 |
| **Prometheus** | Metrics collection & storage | 9090 |
| **Loki** | Log aggregation | 3100 |
| **Grafana** | Dashboards & visualization | 3000 |
| **OTel Collector** | Unified telemetry pipeline | 4317 (gRPC), 4318 (HTTP) |
| **Seq** (optional) | Structured logging for .NET | 5380 |

## 🔧 Connect Your Application

### Send telemetry to:
- **OTLP gRPC**: `localhost:4317` (recommended)
- **OTLP HTTP**: `localhost:4318` (for browsers)

### .NET Example

```csharp
// Program.cs
builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddOtlpExporter(opts => opts.Endpoint = new Uri("http://localhost:4317")))
    .WithMetrics(metrics => metrics
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddOtlpExporter(opts => opts.Endpoint = new Uri("http://localhost:4317")));
```

### Node.js Example

```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-grpc');

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({ url: 'http://localhost:4317' }),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter({ url: 'http://localhost:4317' }),
  }),
});

sdk.start();
```

### Python Example

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

trace.set_tracer_provider(TracerProvider())
otlp_exporter = OTLPSpanExporter(endpoint="http://localhost:4317", insecure=True)
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(otlp_exporter))
```

### Go Example

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
)

exporter, _ := otlptracegrpc.New(ctx,
    otlptracegrpc.WithEndpoint("localhost:4317"),
    otlptracegrpc.WithInsecure(),
)
```

### Detailed Integration Guides

For comprehensive setup instructions with custom spans, metrics, and logging:

- [.NET Integration Guide](docs/dotnet-integration.md)
- [Node.js Integration Guide](docs/nodejs-integration.md)
- [Python Integration Guide](docs/python-integration.md)
- [Go Integration Guide](docs/go-integration.md)

## 📁 Project Structure

```
opensource-otel-setup/
├── docker-compose.yml          # Main compose file
├── otel-collector-config.yaml  # OTel Collector configuration
├── prometheus/
│   └── prometheus.yml          # Prometheus scrape configs
├── grafana/
│   └── provisioning/
│       ├── datasources/        # Auto-configured datasources
│       └── dashboards/         # Pre-built dashboards
├── scripts/
│   ├── start.sh               # Start the stack
│   ├── stop.sh                # Stop the stack
│   └── status.sh              # Check health status
└── docs/                      # Additional documentation
```

## ⚙️ Configuration

### Environment Variables

Create a `.env` file to customize:

```bash
# Ports
JAEGER_UI_PORT=16686
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
OTEL_GRPC_PORT=4317
OTEL_HTTP_PORT=4318

# Grafana
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=admin

# Prometheus
PROMETHEUS_RETENTION=15d

# Service metadata (added to all telemetry)
SERVICE_NAMESPACE=my-company
DEPLOYMENT_ENV=production
```

### Include Seq (for .NET apps)

```bash
# Start with Seq
./scripts/start.sh --seq

# Or
docker compose --profile seq up -d
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Your Applications                              │
│            (.NET, Node.js, Python, Go, Java, etc.)                      │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ OTLP (gRPC/HTTP)
                                     │ Traces, Metrics, Logs
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          OTel Collector                                  │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────────────┐          │
│  │ Receivers│───▶│  Processors  │───▶│      Exporters       │          │
│  │  (OTLP)  │    │ (batch,mem)  │    │ (jaeger,prom,loki)   │          │
│  └──────────┘    └──────────────┘    └──────────┬───────────┘          │
└─────────────────────────────────────────────────┼───────────────────────┘
              ┌───────────────────────────────────┼───────────────────────┐
              │                                   │                       │
              ▼                                   ▼                       ▼
 ┌─────────────────────┐         ┌─────────────────────┐    ┌─────────────────────┐
 │       Jaeger        │         │     Prometheus      │    │        Loki         │
 │      (Traces)       │         │      (Metrics)      │    │       (Logs)        │
 └──────────┬──────────┘         └──────────┬──────────┘    └──────────┬──────────┘
            │                               │                          │
            └───────────────────────────────┼──────────────────────────┘
                                            │
                                            ▼
                               ┌─────────────────────┐
                               │      Grafana        │
                               │   (Dashboards)      │
                               │ Trace↔Log linking   │
                               └─────────────────────┘
```

## 🛡️ Fault Tolerance

The OTel Collector includes:

| Feature | Description |
|---------|-------------|
| **Memory Limiter** | Prevents OOM crashes (512MB limit) |
| **Retry on Failure** | Auto-retries failed exports (5s → 30s backoff) |
| **Sending Queue** | Buffers 5000 items during outages |
| **Health Checks** | All services have health endpoints |

## 🔍 Debug Endpoints

| Endpoint | URL | Purpose |
|----------|-----|---------|
| Collector Health | http://localhost:13133/health | Liveness check |
| Collector ZPages | http://localhost:55679/debug/tracez | Debug traces |
| Collector Metrics | http://localhost:8889/metrics | Self-monitoring |
| Prometheus | http://localhost:9090/targets | Scrape targets |
| Loki Ready | http://localhost:3100/ready | Loki readiness |
| Loki Metrics | http://localhost:3100/metrics | Loki self-monitoring |

## 📊 Pre-built Dashboards

Grafana comes with auto-provisioned datasources and dashboards:

**Datasources:**
- **Prometheus** - for metrics queries
- **Jaeger** - for trace exploration (with trace-to-logs linking)
- **Loki** - for log queries (with log-to-trace linking)

**Included Dashboards:**
- **OpenTelemetry Collector** - Monitor collector health, throughput, and queue sizes
- **Application Metrics** - RED metrics (Rate, Errors, Duration) for your services

Import additional community dashboards from [Grafana.com](https://grafana.com/grafana/dashboards/).

## 🚀 Production Deployment

For production, consider:

1. **Persistent storage**: Mount volumes for data retention
2. **Authentication**: Enable auth on Grafana, Jaeger
3. **TLS**: Secure OTLP endpoints
4. **High Availability**: Run multiple collector instances
5. **Alerting**: Configure Prometheus AlertManager

## 📝 License

MIT License - feel free to use in your projects!

## 🤝 Contributing

Contributions welcome! Please open an issue or PR.
