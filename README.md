# OpenTelemetry Observability Stack

A production-ready observability infrastructure for any application. Get distributed tracing, metrics, and logging in minutes.

## Quick Start

```bash
# Clone and start
git clone https://github.com/shivam-g-mishra/opensource-otel-setup.git
cd opensource-otel-setup
make up
```

**That's it!** Your observability stack is running:

| Service | URL | Purpose |
|---------|-----|---------|
| **Grafana** | http://localhost:3000 | Dashboards (admin/admin) |
| **Jaeger** | http://localhost:16686 | Trace explorer |
| **Prometheus** | http://localhost:9090 | Metrics |

## Connect Your Application

Send telemetry data to:
- **OTLP gRPC**: `localhost:4317` (recommended)
- **OTLP HTTP**: `localhost:4318`

### Quick Examples

<details>
<summary><b>.NET</b></summary>

```bash
dotnet add package OpenTelemetry.Extensions.Hosting
dotnet add package OpenTelemetry.Exporter.OpenTelemetryProtocol
```

```csharp
builder.Services.AddOpenTelemetry()
    .WithTracing(t => t.AddAspNetCoreInstrumentation()
        .AddOtlpExporter(o => o.Endpoint = new Uri("http://localhost:4317")))
    .WithMetrics(m => m.AddAspNetCoreInstrumentation()
        .AddOtlpExporter(o => o.Endpoint = new Uri("http://localhost:4317")));
```
</details>

<details>
<summary><b>Node.js</b></summary>

```bash
npm install @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node \
            @opentelemetry/exporter-trace-otlp-grpc
```

```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({ url: 'http://localhost:4317' }),
  instrumentations: [getNodeAutoInstrumentations()],
});
sdk.start();
```
</details>

<details>
<summary><b>Python</b></summary>

```bash
pip install opentelemetry-distro opentelemetry-exporter-otlp
opentelemetry-bootstrap -a install
```

```bash
# Run with auto-instrumentation
opentelemetry-instrument --service_name my-service \
    --exporter_otlp_endpoint http://localhost:4317 \
    python app.py
```
</details>

<details>
<summary><b>Go</b></summary>

```bash
go get go.opentelemetry.io/otel \
       go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc
```

```go
exporter, _ := otlptracegrpc.New(ctx,
    otlptracegrpc.WithEndpoint("localhost:4317"),
    otlptracegrpc.WithInsecure(),
)
```
</details>

**Full integration guides:** [.NET](docs/dotnet-integration.md) | [Node.js](docs/nodejs-integration.md) | [Python](docs/python-integration.md) | [Go](docs/go-integration.md)

## Common Commands

```bash
make up          # Start the stack
make down        # Stop the stack
make status      # Check service health
make logs        # View all logs
make clean       # Remove all data
make help        # Show all commands
```

Or use Docker Compose directly:
```bash
docker compose up -d      # Start
docker compose down       # Stop
docker compose logs -f    # View logs
```

## Configuration

Create a `.env` file to customize settings:

```bash
# Copy example config
cp env.example .env
```

### Key Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `TRACES_RETENTION` | 720h (30d) | How long to keep traces |
| `METRICS_RETENTION` | 30d | How long to keep metrics |
| `LOGS_RETENTION` | 720h (30d) | How long to keep logs |
| `GRAFANA_ADMIN_PASSWORD` | admin | Grafana admin password |

### Optional: Include Seq for .NET

```bash
make up-seq
# Seq UI: http://localhost:5380
```

## What's Included

```
┌─────────────────────────────────────────────────────────────┐
│                     Your Application                         │
└─────────────────────────────┬───────────────────────────────┘
                              │ OTLP (gRPC :4317 / HTTP :4318)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    OTel Collector                            │
│         (receives, processes, exports telemetry)             │
└────────────┬─────────────────┬─────────────────┬────────────┘
             │                 │                 │
             ▼                 ▼                 ▼
      ┌──────────┐      ┌──────────┐      ┌──────────┐
      │  Jaeger  │      │Prometheus│      │   Loki   │
      │ (traces) │      │(metrics) │      │  (logs)  │
      └────┬─────┘      └────┬─────┘      └────┬─────┘
           └─────────────────┼─────────────────┘
                             ▼
                      ┌──────────┐
                      │ Grafana  │
                      │(dashboards)│
                      └──────────┘
```

### Pre-built Dashboards

Grafana includes auto-provisioned dashboards:
- **OpenTelemetry Collector** - Collector health & throughput
- **Application Metrics** - RED metrics (Rate, Errors, Duration)

### Fault Tolerance

- **Memory limiter** - Prevents OOM crashes
- **Retry on failure** - Auto-retries with exponential backoff
- **Sending queues** - Buffers data during backend outages
- **Persistent storage** - Data survives restarts
- **Health checks** - All services monitored

## Project Structure

```
opensource-otel-setup/
├── Makefile                    # Easy commands (make help)
├── docker-compose.yml          # Service definitions
├── otel-collector-config.yaml  # Collector pipelines
├── prometheus/prometheus.yml   # Metrics scraping
├── loki/loki-config.yaml       # Log aggregation
├── grafana/provisioning/       # Dashboards & datasources
├── scripts/                    # Shell scripts
├── docs/                       # Integration guides
└── env.example                 # Configuration template
```

## Debug Endpoints

| Endpoint | URL |
|----------|-----|
| Collector health | http://localhost:13133/health |
| Collector debug | http://localhost:55679/debug/tracez |
| Prometheus targets | http://localhost:9090/targets |

## Production Considerations

1. **Change default passwords** - Update `GRAFANA_ADMIN_PASSWORD`
2. **Configure retention** - Set appropriate `*_RETENTION` values
3. **Enable TLS** - Secure OTLP endpoints for external access
4. **Resource limits** - Add CPU/memory limits in docker-compose
5. **Backup volumes** - Backup data directories regularly

## License

MIT License - use freely in your projects.

## Contributing

Issues and PRs welcome!
