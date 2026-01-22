# OpenTelemetry Observability Stack

A production-ready, reliable observability infrastructure for any application. Get distributed tracing, metrics, and logging in minutes.

## Requirements

- Docker Engine 20.10+
- Docker Compose v2+ (for resource limits)
- ~8GB RAM recommended for the full stack
- ~20GB disk space for data retention
- Linux recommended for full host metrics (see [macOS note](#macos-note))

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
| **Prometheus** | http://localhost:9090 | Metrics & alerts |
| **Node Exporter** | http://localhost:9100 | Host metrics |

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

## Commands

### Core Commands

```bash
make up          # Start the stack
make down        # Stop the stack (data preserved)
make restart     # Restart all services
make status      # Check service health
make logs        # View all logs
```

### Operations

```bash
make deploy      # Zero-downtime deployment
make backup      # Backup all data and configs
make restore     # Restore from backup
make clean       # Remove all data (destructive!)
```

### Development

```bash
make up-seq      # Start with Seq (for .NET)
make validate    # Validate configurations
make pull        # Pull latest images
make alerts      # View active alerts
make metrics     # Show collector throughput
```

Run `make help` for all available commands.

## Reliability Features

This stack is built for production reliability:

| Feature | Description |
|---------|-------------|
| **Persistent Queues** | Data survives collector restarts |
| **Resource Limits** | Prevents OOM crashes, isolates services |
| **Health Checks** | Auto-restart unhealthy containers |
| **Graceful Shutdown** | Zero data loss during deployments |
| **Retry Policies** | Exponential backoff for transient failures |
| **Automated Backups** | Scripts for backup and restore |
| **Self-Monitoring** | 30+ alerting rules included |

### Backup & Restore

```bash
# Create backup
make backup
# Backups stored in ./backups/YYYYMMDD_HHMMSS/

# Restore from backup
./scripts/restore.sh ./backups/20260122_020000

# Automated backups (add to cron)
0 2 * * * /path/to/scripts/backup.sh
```

### Zero-Downtime Deployment

```bash
# Standard deployment (includes backup)
make deploy

# Quick deployment (skip backup)
make deploy-quick

# Deploy with image updates
make deploy-pull
```

## Configuration

Create a `.env` file to customize settings:

```bash
cp env.example .env
```

### Key Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `TRACES_RETENTION` | 720h (30d) | How long to keep traces |
| `METRICS_RETENTION` | 30d | How long to keep metrics |
| `LOGS_RETENTION` | 720h (30d) | How long to keep logs |
| `GRAFANA_ADMIN_PASSWORD` | admin | Grafana admin password |

### Resource Limits (Pre-configured)

| Service | CPU | Memory |
|---------|-----|--------|
| OTel Collector | 2 cores | 2 GB |
| Prometheus | 2 cores | 4 GB |
| Jaeger | 2 cores | 4 GB |
| Loki | 1 core | 2 GB |
| Grafana | 1 core | 1 GB |
| Node Exporter | 0.5 cores | 256 MB |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Your Application                         │
└─────────────────────────────┬───────────────────────────────┘
                              │ OTLP (gRPC :4317 / HTTP :4318)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    OTel Collector                            │
│    [Persistent Queues] [Memory Limiter] [Retry Policies]    │
└────────────┬─────────────────┬─────────────────┬────────────┘
             │                 │                 │
             ▼                 ▼                 ▼
      ┌──────────┐      ┌──────────┐      ┌──────────┐
      │  Jaeger  │      │Prometheus│      │   Loki   │
      │ (traces) │      │(metrics) │      │  (logs)  │
      │ [Badger] │      │  [TSDB]  │      │  [TSDB]  │
      └────┬─────┘      └─────┬────┘      └────┬─────┘
           │                  │                │
           │           ┌──────┴──────┐         │
           │           │Node Exporter│         │
           │           │(host metrics)│         │
           │           └─────────────┘         │
           └──────────────────┬────────────────┘
                              ▼
                       ┌──────────┐
                       │ Grafana  │
                       │(dashboards)│
                       └──────────┘
```

## Pre-built Dashboards

Grafana includes auto-provisioned dashboards:
- **OpenTelemetry Collector** - Collector health & throughput
- **Application Metrics** - RED metrics (Rate, Errors, Duration)

## Alerting

30+ pre-configured alerts monitor the stack and infrastructure:

- **Collector alerts**: Down, high memory, queue filling, dropping data
- **Prometheus alerts**: Down, high memory, storage filling
- **Loki alerts**: Down, request errors, high latency
- **Jaeger alerts**: Down, storage high
- **Infrastructure alerts**: Disk usage, memory usage, CPU, network, clock skew

View alerts: `make alerts` or visit http://localhost:9090/alerts

## Project Structure

```
opensource-otel-setup/
├── Makefile                    # Easy commands (make help)
├── docker-compose.yml          # Service definitions
├── otel-collector-config.yaml  # Collector pipelines
├── prometheus/
│   ├── prometheus.yml          # Metrics scraping
│   └── alerts/                 # Alerting rules
├── loki/loki-config.yaml       # Log aggregation
├── grafana/provisioning/       # Dashboards & datasources
├── scripts/
│   ├── start.sh               # Start script
│   ├── stop.sh                # Stop script
│   ├── status.sh              # Health check
│   ├── backup.sh              # Backup data
│   ├── restore.sh             # Restore data
│   └── deploy.sh              # Zero-downtime deploy
├── docs/                       # Integration guides
└── env.example                 # Configuration template
```

## Debug Endpoints

| Endpoint | URL |
|----------|-----|
| Collector health | http://localhost:13133/health |
| Collector debug | http://localhost:55679/debug/tracez |
| Prometheus targets | http://localhost:9090/targets |
| Prometheus alerts | http://localhost:9090/alerts |
| Node Exporter metrics | http://localhost:9100/metrics |

## Production Checklist

- [ ] Change `GRAFANA_ADMIN_PASSWORD` in `.env`
- [ ] Configure retention settings for your needs
- [ ] Set up automated backups (`make backup` in cron)
- [ ] Review and customize alerting rules
- [ ] Enable TLS for external OTLP endpoints
- [ ] Monitor disk usage (alerts pre-configured)
- [ ] Test restore procedure (`make restore`)

## macOS Note

On macOS, Docker runs containers in a Linux VM. The Node Exporter will report metrics from this VM, not your Mac host. For true macOS host metrics:

1. Install node_exporter via Homebrew: `brew install node_exporter`
2. Run it natively: `node_exporter --web.listen-address=:9100`
3. Update Prometheus to scrape `host.docker.internal:9100` instead of `node-exporter:9100`

The infrastructure alerts (disk, memory, CPU) will still work but will monitor the Docker VM on macOS.

## Scaling Guide

This single-node setup handles:
- ~50K spans/second
- ~500K active metric series
- ~100MB/s log ingestion

For larger workloads, see [Architecture Proposal](tmp/scalable-architecture-proposal.md) for horizontal scaling with Kafka, Kubernetes, and distributed storage.

## License

MIT License - use freely in your projects.

## Contributing

Issues and PRs welcome!
