# OpenTelemetry Observability Stack

A production-ready, reliable observability infrastructure for any application. Get distributed tracing, metrics, and logging in minutes.

## Requirements

- Docker Engine 20.10+
- Docker Compose v2+ (for resource limits)
- Linux recommended for full host metrics (see [macOS note](#macos-note))

### System Resources

| Scenario | CPU | RAM | Disk | Use Case |
|----------|-----|-----|------|----------|
| **Minimum** | 4 cores | 8 GB | 20 GB | Development, light testing |
| **Recommended** | 8 cores | 16 GB | 50 GB | Small production, <10 apps |
| **Production** | 12+ cores | 24+ GB | 100+ GB | Medium production, 10-50 apps |

**Per-Service Resource Limits (pre-configured):**

| Service | CPU Limit | Memory Limit | CPU Reserved | Memory Reserved |
|---------|-----------|--------------|--------------|-----------------|
| Jaeger | 2 cores | 4 GB | 0.5 cores | 1 GB |
| Prometheus | 2 cores | 4 GB | 0.5 cores | 1 GB |
| OTel Collector | 2 cores | 2 GB | 0.5 cores | 512 MB |
| Loki | 1 core | 2 GB | 0.25 cores | 512 MB |
| Grafana | 1 core | 1 GB | 0.25 cores | 256 MB |
| Node Exporter | 0.5 cores | 256 MB | 0.1 cores | 64 MB |
| **Total** | **8.5 cores** | **13.25 GB** | **2.1 cores** | **3.3 GB** |

> **Note:** "Reserved" resources are guaranteed minimums. "Limits" are maximums under load. Actual usage at idle is much lower (~2 cores, ~4GB RAM).

### Disk Space

| Data Type | Default Retention | Est. Size/Day | 30-Day Storage |
|-----------|-------------------|---------------|----------------|
| Traces (Jaeger) | 30 days | 1-5 GB | 30-150 GB |
| Metrics (Prometheus) | 30 days | 500 MB-2 GB | 15-60 GB |
| Logs (Loki) | 30 days | 1-10 GB | 30-300 GB |
| Container logs | Rotated | Max 790 MB | 790 MB |

> Disk usage varies significantly based on telemetry volume. Start with 50GB and monitor usage.

### Network

| Port | Protocol | Purpose |
|------|----------|---------|
| 4317 | TCP (gRPC) | OTLP telemetry ingestion |
| 4318 | TCP (HTTP) | OTLP telemetry ingestion |
| 3000 | TCP | Grafana UI |
| 16686 | TCP | Jaeger UI |
| 9090 | TCP | Prometheus UI |
| 3100 | TCP | Loki API |
| 9100 | TCP | Node Exporter metrics |

### Capacity Guidelines

This single-node setup handles approximately:

| Metric | Light Load | Moderate Load | Heavy Load |
|--------|------------|---------------|------------|
| Spans/second | <1,000 | 1,000-10,000 | 10,000-50,000 |
| Metric series | <100,000 | 100,000-500,000 | 500,000-1,000,000 |
| Log lines/second | <1,000 | 1,000-10,000 | 10,000-50,000 |
| Connected apps | 1-5 | 5-20 | 20-50 |

For higher loads, see [Scaling Guide](#scaling-guide).

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

### Logs & Debugging

```bash
make logs            # View all service logs (follow mode)
make logs-collector  # OTel Collector logs only
make logs-jaeger     # Jaeger logs only
make logs-loki       # Loki logs only
make logs-prometheus # Prometheus logs only
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
| **Log Rotation** | Container logs auto-rotate to prevent disk fill |

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

### Container Logs

All containers have log rotation configured to prevent disk exhaustion. Logs automatically rotate when they reach their size limit.

| Service | Max Size | Max Files | Total Max |
|---------|----------|-----------|-----------|
| OTel Collector | 50MB | 5 | 250MB |
| Loki | 50MB | 5 | 250MB |
| Jaeger | 30MB | 3 | 90MB |
| Prometheus | 20MB | 3 | 60MB |
| Grafana | 10MB | 3 | 30MB |
| Node Exporter | 10MB | 2 | 20MB |

**View logs:**

```bash
# All services (follow mode)
make logs

# Specific service
docker logs otel-collector
docker logs otel-collector --tail 100        # Last 100 lines
docker logs otel-collector --since 1h        # Last hour
docker logs otel-collector -f                # Follow/stream

# By service name
make logs-collector    # OTel Collector logs
make logs-jaeger       # Jaeger logs
make logs-loki         # Loki logs
make logs-prometheus   # Prometheus logs
```

**Check log disk usage:**

```bash
# See log file sizes for all containers
docker system df -v | grep -E "CONTAINER|otel"

# Detailed log path for a specific container
docker inspect --format='{{.LogPath}}' otel-collector
```

**Note:** These are Docker container logs (stdout/stderr). Your application logs sent via OTLP are stored in Loki and viewable in Grafana.

### Failure Behavior & Error Handling

Understanding how the system behaves during failures helps you operate it confidently.

#### What Happens When Components Fail

| Component | If It Fails | Data Impact | Auto-Recovery |
|-----------|-------------|-------------|---------------|
| **OTel Collector** | Apps get connection errors | Queued data persists on disk, replays on restart | Yes (health check) |
| **Jaeger** | Collector queues traces | No trace loss (queued) | Yes (health check) |
| **Prometheus** | Metrics scraping stops | Gap in metrics during downtime | Yes (health check) |
| **Loki** | Collector queues logs | No log loss (queued) | Yes (health check) |
| **Grafana** | Dashboards unavailable | No data loss (read-only) | Yes (health check) |
| **Node Exporter** | Host metrics stop | Gap in host metrics | Yes (health check) |

#### Data Flow Under Pressure

```
Normal Load:
  App → Collector → Backend    [All data flows through]

Backend Slow/Down:
  App → Collector → [Queue fills] → Backend
                    ↓
              Queue persisted to disk (survives restart)

Queue Full (extreme):
  App → Collector → [Queue FULL] → Backpressure to app
                                   (app retries or drops)
```

#### Retry & Backpressure Behavior

| Scenario | Behavior | Configuration |
|----------|----------|---------------|
| **Backend temporarily down** | Retry with exponential backoff (1s → 60s) | `retry_on_failure` in collector |
| **Backend slow** | Queue fills, continues retrying | `sending_queue.queue_size: 10000` |
| **Queue full** | Backpressure applied, oldest data may drop | Memory limiter triggers |
| **Collector memory high** | Refuses new data temporarily | `memory_limiter` processor |
| **Collector restart** | Queue replays from disk | `file_storage` extension |

#### Error Handling Timeline

```
t=0s    Backend goes down
t=1s    First retry attempt
t=2s    Second retry (exponential backoff)
t=4s    Third retry
...
t=60s   Retries capped at 60s intervals
t=300s  Max elapsed time - data export fails, next batch tried
        (Queue preserves data, keeps retrying)

Meanwhile: Queue fills on disk, up to 10,000 items per exporter
```

### Recovery Procedures

#### Service Won't Start

```bash
# Check what's wrong
docker compose logs <service-name> --tail 50

# Common fixes:
docker compose down                    # Clean shutdown
docker volume ls                       # Check volumes exist
docker compose up -d                   # Restart
make status                            # Verify health
```

#### Data Corruption Recovery

```bash
# Option 1: Restore from backup
./scripts/restore.sh ./backups/<latest>

# Option 2: Reset specific service (loses that service's data)
docker compose stop <service>
docker volume rm opensource-otel-setup_<service>-data
docker compose up -d <service>

# Option 3: Full reset (loses ALL data)
make clean                             # Requires confirmation
make up
```

#### High Memory / OOM Issues

```bash
# Check current memory usage
docker stats --no-stream

# Reduce retention (less data stored)
# Edit .env:
TRACES_RETENTION=168h    # 7 days instead of 30
METRICS_RETENTION=7d
LOGS_RETENTION=168h

# Restart to apply
make restart
```

#### Queue Building Up (Data Backlog)

```bash
# Check queue size
curl -s http://localhost:8888/metrics | grep queue_size

# If queue is full, check backend health:
make status

# Force restart collector to replay queue
docker compose restart otel-collector
```

### Troubleshooting

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| No traces in Jaeger | Collector not receiving data | Check app config, verify `localhost:4317` reachable |
| No metrics in Prometheus | Scrape targets down | Check http://localhost:9090/targets |
| No logs in Loki | Log pipeline issue | Check `make logs-collector` for errors |
| High memory usage | Too much data / long retention | Reduce retention, add sampling |
| Disk filling up | Data retention too long | Reduce retention, run `make clean` |
| Services keep restarting | Resource limits too low | Increase limits in `docker-compose.yml` |
| "Connection refused" | Service not ready | Wait for health checks, check `make status` |
| Slow queries in Grafana | Too much data to scan | Add time filters, reduce retention |

#### Debug Checklist

```bash
# 1. Check all services are healthy
make status

# 2. Check for resource issues
docker stats --no-stream

# 3. Check collector is receiving data
curl -s http://localhost:8888/metrics | grep otelcol_receiver

# 4. Check for export errors
curl -s http://localhost:8888/metrics | grep otelcol_exporter

# 5. Check active alerts
make alerts

# 6. View recent logs
make logs-collector | tail -100
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

### Resource Limits

See [System Resources](#system-resources) for detailed CPU/memory limits per service.

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

### When to Scale

Monitor these metrics to know when you're approaching limits:

```bash
make metrics   # View current throughput
make alerts    # Check for capacity warnings
```

**Signs you need to scale:**
- Collector queue size consistently > 5000
- Memory usage > 80% of limits
- Query latency increasing
- Dropped spans/metrics alerts firing

### Scaling Options

| Approach | When to Use | Complexity |
|----------|-------------|------------|
| **Vertical** (more CPU/RAM) | First option, up to 16 cores/32GB | Low |
| **Retention reduction** | Storage issues | Low |
| **Sampling** | High trace volume | Medium |
| **Horizontal** (multiple nodes) | Beyond single-node limits | High |

### Single-Node Limits

See [Capacity Guidelines](#capacity-guidelines) for detailed throughput limits.

For workloads exceeding 50K spans/second or 1M metric series, see [Architecture Proposal](docs/scalable-architecture-proposal.md) for horizontal scaling with Kafka, Kubernetes, and distributed storage.

## License

MIT License - use freely in your projects.

## Contributing

Issues and PRs welcome!
