# Building Your Observability Stack

**A Hands-On Guide to Deploying OpenTelemetry Infrastructure**

---

## Table of Contents

- [Before We Begin](#before-we-begin)
- [What We're Building](#what-were-building)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Understanding the Phases](#understanding-the-phases)

### Phase 1: Single-Node Deployment
- [What You'll Build](#what-youll-build)
- [Step 1: Set Up Your Project](#step-1-set-up-your-project)
- [Step 2: Configure the OpenTelemetry Collector](#step-2-configure-the-opentelemetry-collector)
- [Step 3: Configure Prometheus](#step-3-configure-prometheus)
- [Step 4: Configure Loki](#step-4-configure-loki)
- [Step 5: Configure Grafana Data Sources](#step-5-configure-grafana-data-sources)
- [Step 6: Create the Docker Compose File](#step-6-create-the-docker-compose-file)
- [Step 7: Create Operational Scripts](#step-7-create-operational-scripts)
- [Step 8: Deploy](#step-8-deploy)
- [Step 9: Verify Everything Works](#step-9-verify-everything-works)
- [Step 10: Connect Your Applications](#step-10-connect-your-applications)
- [Phase 1 Complete](#phase-1-complete)

### Phase 2: Scalable Docker Deployment
- [What Changes in Phase 2](#what-changes-in-phase-2)
- [Phase 2 Architecture](#phase-2-architecture)
- [Step-by-Step Deployment](#step-1-navigate-to-scalable-configs)

### Phase 3: Kubernetes Deployment
- [Kubernetes Architecture](#kubernetes-architecture)
- [Deployment Steps](#step-1-review-kubernetes-manifests)

### Phase 4: Production Infrastructure (Terraform)
- [AWS Infrastructure](#phase-4-production-infrastructure-with-terraform)

### Automation Options
- [Ansible Deployment](#automated-deployment-with-ansible)

### Troubleshooting
- [The Debugging Mindset](#the-debugging-mindset)
- [Quick Diagnostic Commands](#quick-diagnostic-commands)
- [Common Issues](#common-issues)
- [Getting Help](#getting-help)

### Next Steps
- [What's Next](#whats-next)

---

## Quick Start (5 Minutes)

**Just want to get it running?** Use the pre-built configurations:

```bash
# Clone the repo
git clone <this-repo> && cd opensource-otel-setup

# Phase 1: Single-node (simplest)
cd docs/scalable/configs/docker
docker compose -f docker-compose-single.yaml up -d

# Access Grafana at http://localhost:3000 (admin/admin)
```

**Want scalable setup with Kafka?**
```bash
docker compose -f docker-compose-scalable.yaml up -d
```

**Want to understand what you're deploying?** Continue reading below.

---

## Before We Begin

This guide offers **two paths**:

| Path | Time | Best For |
|------|------|----------|
| **Quick Start** (above) | 5 min | Getting up and running fast |
| **Full Guide** (below) | 45 min+ | Understanding each component, customization |

**If you're new to observability**, I recommend reading through the full Phase 1 guide at least once. Understanding how the pieces fit together will save you hours of debugging later.

**Key principles:**
- **Start simple.** Phase 1 handles up to 50,000 events/sec—more than most teams need
- **Config files exist.** Everything is pre-built in `configs/`. You can use them directly or learn from them
- **Mistakes are expected.** The troubleshooting section covers common issues

If you haven't already, read the [Architecture Overview](./architecture.md) first—it explains the "why" behind each decision.

---

## Repository Structure

Before diving in, let's understand how this repository is organized. This will help you find the right configuration files:

```
docs/scalable/
├── README.md                    # Overview and quick start
├── architecture.md              # Deep-dive into design decisions
├── implementation-guide.md      # This file - step-by-step deployment
│
└── configs/                     # All configuration files
    │
    ├── docker/                  # Docker Compose deployments
    │   ├── docker-compose-single.yaml    # Phase 1: Single-node setup
    │   ├── docker-compose-scalable.yaml  # Phase 2: With Kafka
    │   ├── otel-collector.yaml           # Phase 1 collector config
    │   ├── otel-gateway.yaml             # Phase 2 gateway config
    │   ├── otel-processor.yaml           # Phase 2 processor config
    │   ├── haproxy.cfg                   # Load balancer config
    │   ├── tempo.yaml                    # Trace storage (Phase 2)
    │   ├── mimir.yaml                    # Metrics storage (Phase 2)
    │   ├── mimir-runtime.yaml            # Mimir runtime config
    │   ├── loki.yaml                     # Log storage
    │   ├── prometheus.yml                # Stack self-monitoring
    │   ├── alertmanager-fallback.yaml    # Alertmanager default config
    │   └── grafana/provisioning/         # Auto-configured datasources
    │
    ├── kubernetes/              # Kubernetes manifests
    │   ├── namespace.yaml                # observability namespace
    │   ├── kafka-cluster.yaml            # Strimzi Kafka cluster
    │   ├── minio.yaml                    # S3-compatible storage
    │   ├── otel-gateway.yaml             # Gateway Deployment + HPA
    │   ├── otel-processor.yaml           # Processor Deployment + HPA
    │   ├── tempo.yaml                    # Tempo StatefulSet
    │   ├── mimir.yaml                    # Mimir StatefulSet
    │   ├── loki.yaml                     # Loki StatefulSet
    │   ├── grafana.yaml                  # Grafana Deployment
    │   ├── prometheus.yaml               # Prometheus StatefulSet
    │   └── postgresql.yaml               # Grafana HA database
    │
    ├── terraform/               # AWS infrastructure
    │   ├── main.tf                       # EKS cluster, VPC, S3
    │   ├── variables.tf                  # Configurable inputs
    │   └── outputs.tf                    # Useful outputs
    │
    ├── ansible/                 # Automated deployment
    │   ├── playbook.yml                  # Main playbook
    │   ├── inventory.example             # Sample inventory
    │   └── templates/env.j2              # Environment template
    │
    └── scripts/                 # Operational scripts
        ├── backup.sh                     # Volume backup
        ├── restore.sh                    # Restore from backup
        └── health-check.sh               # Stack health check
```

**Which configs should you use?**

| Starting Point | Use These Files |
|---------------|-----------------|
| Learning/Dev | `docker/docker-compose-single.yaml` + `docker/otel-collector.yaml` |
| Production Docker | `docker/docker-compose-scalable.yaml` + all Docker configs |
| Kubernetes | Everything in `kubernetes/` |
| AWS Infrastructure | `terraform/` + `kubernetes/` |
| Automated VM Setup | `ansible/playbook.yml` |

---

## What We're Building

By the end of this guide, you'll have:

- **A central collector** that receives traces, metrics, and logs from all your applications
- **Persistent storage** for each type of telemetry (Jaeger for traces, Prometheus for metrics, Loki for logs)
- **Grafana dashboards** that let you explore and correlate all your data
- **Operational scripts** for backup, health checks, and maintenance
- **A clear upgrade path** when you need to scale

The setup is modular. You can stop at any phase and have a working system. Each subsequent phase adds capabilities but also complexity—only progress when you need the additional features.

---

## Prerequisites

Let me be specific about what you need:

**For Phase 1 (Single-Node):**
- A Linux server (VM, cloud instance, or bare metal) with 8+ GB RAM and 50+ GB SSD
- Docker Engine 20.10+ and Docker Compose V2
- Basic familiarity with YAML and command-line operations
- About 45 minutes of focused time

**For Phase 2 (Add Kafka):**
- Everything from Phase 1, plus 16+ GB RAM and 200+ GB SSD
- Understanding of networking basics (ports, DNS)
- About 2 hours

**For Phase 3 (Kubernetes):**
- A Kubernetes cluster (1.24+) with kubectl configured
- Familiarity with Kubernetes concepts (Deployments, Services, ConfigMaps)
- About 4 hours

Don't worry if you're not planning to go beyond Phase 1 right now. You can always come back to later phases when needed.

---

## Understanding the Phases

```
Phase 1              Phase 2                Phase 3              Phase 4
─────────            ─────────              ─────────            ─────────
Single Node          + Kafka & HA           Kubernetes           Advanced Storage
                     
┌──────────┐         ┌──────────┐           ┌──────────┐         ┌──────────┐
│ All-in   │         │ Gateway  │           │ Helm     │         │ Tempo    │
│ one box  │   →     │ + Kafka  │     →     │ charts   │    →    │ + S3     │
│ Docker   │         │ + LB     │           │ HPA      │         │ Mimir    │
│ Compose  │         │          │           │ PDB      │         │ + S3     │
└──────────┘         └──────────┘           └──────────┘         └──────────┘

When to move:        When to move:          When to move:
• >50K events/sec    • Kubernetes org       • Long retention
• Need HA            • >100K events/sec     • Cost optimization
• Backend maint.     • GitOps required      • Multi-year storage
```

**Most teams should start with Phase 1 and stay there until they have a specific reason to scale.** The single-node setup handles up to 50,000 events per second—that's a lot more than it sounds like.

---

# Phase 1: Single-Node Deployment

> **Using Pre-built Configs?** Skip to [Step 8: Deploy](#step-8-deploy). All config files referenced below already exist in `docs/scalable/configs/docker/`. The walkthrough explains what each config does—useful for learning and customization.

## What You'll Build

This phase deploys everything on a single server using Docker Compose:

```
┌───────────────────────────────────────────────────────────────────┐
│                         Your Server                               │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │               OpenTelemetry Collector                       │  │
│  │                                                             │  │
│  │  Receives OTLP → Queues to disk → Exports to backends       │  │
│  │        ↓              ↓                  ↓                  │  │
│  │     (4317)        (survives           (retries              │  │
│  │     (4318)         restart)           on failure)           │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                              │                                    │
│              ┌───────────────┼───────────────┐                    │
│              ▼               ▼               ▼                    │
│         ┌─────────┐    ┌──────────┐    ┌─────────┐                │
│         │ Jaeger  │    │Prometheus│    │  Loki   │                │
│         │ Traces  │    │ Metrics  │    │  Logs   │                │
│         └────┬────┘    └────┬─────┘    └────┬────┘                │
│              └───────────────┼───────────────┘                    │
│                              ▼                                    │
│                       ┌──────────┐                                │
│                       │ Grafana  │                                │
│                       │   :3000  │                                │
│                       └──────────┘                                │
└───────────────────────────────────────────────────────────────────┘
```

This setup is production-ready for many use cases. It includes persistent queues (data survives restarts), health checks (automatic recovery), and resource limits (predictable behavior under load).

---

## Step 1: Set Up Your Project

First, let's create a clean directory structure. This organization will make operations easier as your setup grows.

```bash
# Create the project directory
mkdir -p otel-stack && cd otel-stack

# Create the directory structure
mkdir -p configs scripts data backups
mkdir -p grafana/provisioning/datasources
mkdir -p grafana/provisioning/dashboards

# Create a .gitignore so you don't accidentally commit data
cat > .gitignore << 'EOF'
# Data directories (can be large, should be backed up separately)
data/
backups/

# Logs and temporary files
*.log
*.tmp

# Environment files with secrets
.env
.env.local
EOF

# Verify the structure
ls -la
```

You should see:
```
.gitignore
backups/
configs/
data/
grafana/
scripts/
```

**Why this structure?** 
- `configs/` holds all configuration files (version controlled)
- `data/` is where Docker volumes mount (not version controlled, backed up separately)
- `backups/` stores backup archives (not version controlled)
- `scripts/` contains operational scripts (version controlled)
- `grafana/provisioning/` enables auto-configuration of Grafana

---

## Step 2: Configure the OpenTelemetry Collector

The Collector is the heart of your observability pipeline. Let me walk you through this configuration section by section, because understanding it will help you troubleshoot issues later.

Create `configs/otel-collector.yaml`:

```yaml
# =============================================================================
# OpenTelemetry Collector Configuration
# =============================================================================
#
# This collector receives telemetry from your applications via OTLP and 
# forwards it to Jaeger (traces), Prometheus (metrics), and Loki (logs).
#
# Key reliability features:
# - Persistent queues: Data survives collector restarts
# - Memory limiter: Prevents out-of-memory crashes
# - Retry logic: Automatically retries failed exports
# - Health endpoint: Enables Docker health checks
#
# =============================================================================

# -----------------------------------------------------------------------------
# Extensions provide additional capabilities beyond the core pipeline
# -----------------------------------------------------------------------------
extensions:
  # Health check endpoint - Docker/K8s uses this to know if we're healthy
  health_check:
    endpoint: 0.0.0.0:13133
    path: /health
    check_collector_pipeline:
      enabled: true
      interval: 5m
      exporter_failure_threshold: 5

  # File-based storage for persistent queues
  # This is what makes data survive collector restarts
  file_storage:
    directory: /var/lib/otelcol/storage
    timeout: 10s
    compaction:
      on_start: true
      on_rebound: true
      directory: /var/lib/otelcol/storage

# -----------------------------------------------------------------------------
# Receivers define how data enters the collector
# -----------------------------------------------------------------------------
receivers:
  otlp:
    protocols:
      # gRPC is more efficient, preferred for most SDKs
      grpc:
        endpoint: 0.0.0.0:4317
        max_recv_msg_size_mib: 4
        max_concurrent_streams: 100
      # HTTP is useful for browsers and environments where gRPC is difficult
      http:
        endpoint: 0.0.0.0:4318
        cors:
          allowed_origins: ["*"]  # Restrict this in production

# -----------------------------------------------------------------------------
# Processors transform data as it flows through the pipeline
# -----------------------------------------------------------------------------
processors:
  # IMPORTANT: memory_limiter should always be first in the pipeline
  # It protects against out-of-memory crashes by dropping data when
  # memory usage is too high. This is better than crashing.
  memory_limiter:
    check_interval: 1s
    limit_mib: 1600        # 80% of our 2GB container limit
    spike_limit_mib: 400   # Allow temporary spikes above limit

  # Batch processor groups telemetry for efficient export
  # Without batching, we'd make a network call for every span/metric/log
  batch:
    timeout: 5s            # Send batch after 5 seconds, even if not full
    send_batch_size: 10000 # Target batch size
    send_batch_max_size: 15000

  # Resource processor adds metadata to all telemetry
  # Useful for identifying which collector processed the data
  resource:
    attributes:
      - key: deployment.environment
        value: "production"
        action: upsert
      - key: collector.name
        value: "otel-collector-single"
        action: upsert

# -----------------------------------------------------------------------------
# Exporters send data to backends
# -----------------------------------------------------------------------------
exporters:
  # Debug exporter - writes samples to collector logs
  # Useful for troubleshooting, minimal performance impact
  debug:
    verbosity: basic
    sampling_initial: 5
    sampling_thereafter: 200

  # Jaeger exporter for traces
  otlp/jaeger:
    endpoint: jaeger:4317
    tls:
      insecure: true  # OK for internal network, use TLS in production
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 10000
      storage: file_storage  # THIS IS KEY: persists queue to disk
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
      max_elapsed_time: 300s

  # Prometheus remote write for metrics
  prometheusremotewrite:
    endpoint: http://prometheus:9090/api/v1/write
    tls:
      insecure: true
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 10000
      storage: file_storage
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
      max_elapsed_time: 300s

  # Loki exporter for logs
  loki:
    endpoint: http://loki:3100/loki/api/v1/push
    default_labels_enabled:
      exporter: true
      level: true
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 10000
      storage: file_storage
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
      max_elapsed_time: 300s

# -----------------------------------------------------------------------------
# Service section wires everything together into pipelines
# -----------------------------------------------------------------------------
service:
  extensions: [health_check, file_storage]
  
  # Collector's own telemetry (for monitoring the monitor)
  telemetry:
    logs:
      level: info
      encoding: json
    metrics:
      level: detailed
      address: 0.0.0.0:8888

  # Data flows through pipelines: receivers → processors → exporters
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [otlp/jaeger]

    metrics:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [prometheusremotewrite]

    logs:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [loki]
```

**Key things to understand:**

1. **The `file_storage` extension** is what gives us persistent queues. When the collector receives data but can't immediately export it (backend down, network issue), it writes to disk. When it restarts, it reads from disk and continues where it left off.

2. **The `memory_limiter` must be first** in every pipeline. If it's not first, data might be processed and queued before the limiter can kick in, which defeats the purpose.

3. **Each exporter has `sending_queue` with `storage: file_storage`**. This is what makes queues persistent. Without it, queues only exist in memory and are lost on restart.

---

## Step 3: Configure Prometheus

Prometheus stores metrics and provides the query interface that Grafana uses.

Create `configs/prometheus.yml`:

```yaml
# =============================================================================
# Prometheus Configuration
# =============================================================================
#
# Prometheus does two things:
# 1. Receives metrics via remote write from the OTel Collector
# 2. Scrapes metrics from the observability stack itself (self-monitoring)
#

global:
  scrape_interval: 15s      # How often to collect metrics
  evaluation_interval: 15s  # How often to evaluate alerting rules
  
  # These labels are added to all metrics
  external_labels:
    cluster: 'single-node'
    environment: 'production'

# Alertmanager configuration (uncomment when you add Alertmanager)
alerting:
  alertmanagers:
    - static_configs:
        - targets: []

# Rule files for alerting (add later)
rule_files: []

# Scrape configurations - who to collect metrics from
scrape_configs:
  # Scrape Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
    metrics_path: /metrics
    
  # Scrape the OTel Collector
  # This is how you monitor your observability pipeline
  - job_name: 'otel-collector'
    static_configs:
      - targets: ['otel-collector:8888']
    metrics_path: /metrics
    
  # Scrape Jaeger
  - job_name: 'jaeger'
    static_configs:
      - targets: ['jaeger:14269']
    metrics_path: /metrics
    
  # Scrape Loki
  - job_name: 'loki'
    static_configs:
      - targets: ['loki:3100']
    metrics_path: /metrics
    
  # Scrape Grafana
  - job_name: 'grafana'
    static_configs:
      - targets: ['grafana:3000']
    metrics_path: /metrics

# Note: Remote write receiver is enabled via command-line flag in docker-compose
```

**Why scrape the stack itself?** This is monitoring the monitoring. If your collector is dropping data or your backends are struggling, you want to know before users notice. We'll create alerts for this later.

---

## Step 4: Configure Loki

Loki stores logs efficiently by only indexing labels, not log content.

Create `configs/loki.yaml`:

```yaml
# =============================================================================
# Loki Configuration
# =============================================================================
#
# Loki takes a different approach than Elasticsearch: it only indexes
# labels (like service name, log level), not the actual log content.
# This makes it much cheaper to run but means searches are label-first.
#
# Query pattern: First filter by labels (fast), then grep content (slower)
#

auth_enabled: false  # Single-tenant mode, no auth needed

server:
  http_listen_port: 3100
  grpc_listen_port: 9096
  log_level: info

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

# Query caching improves performance for repeated queries
query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100

# Schema configuration defines how data is stored
schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

# Ruler configuration (for log-based alerts)
ruler:
  alertmanager_url: http://localhost:9093

# Rate limiting and retention
limits_config:
  retention_period: 744h  # 31 days
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20
  max_streams_per_user: 10000
  max_line_size: 256kb

# Compaction settings
compactor:
  working_directory: /loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  retention_delete_worker_count: 150
```

**Important limits to understand:**

- `ingestion_rate_mb: 10` means Loki accepts up to 10 MB/s of logs. If your applications generate more, you'll see "rate limit exceeded" errors. Increase this if needed.
- `max_streams_per_user: 10000` limits unique label combinations. Each unique combination of labels creates a stream. High-cardinality labels (like user IDs) can exhaust this quickly.
- `retention_period: 744h` (31 days) controls how long logs are kept. Adjust based on your compliance needs and storage budget.

---

## Step 5: Configure Grafana Data Sources

Grafana needs to know how to connect to your backends. We'll use provisioning to configure this automatically.

Create `grafana/provisioning/datasources/datasources.yaml`:

```yaml
# =============================================================================
# Grafana Data Sources (Auto-provisioned)
# =============================================================================
#
# These data sources are automatically configured when Grafana starts.
# No manual setup required - just start the container and they're there.
#

apiVersion: 1

datasources:
  # Prometheus for metrics
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true  # This is the default for new panels
    editable: false  # Prevent accidental changes in UI
    jsonData:
      timeInterval: "15s"
      httpMethod: POST

  # Jaeger for traces
  - name: Jaeger
    type: jaeger
    access: proxy
    url: http://jaeger:16686
    editable: false
    jsonData:
      # Enable trace-to-logs correlation
      # Click a span → see related logs in Loki
      tracesToLogsV2:
        datasourceUid: loki
        spanStartTimeShift: '-1h'
        spanEndTimeShift: '1h'
        filterByTraceID: true
        filterBySpanID: false

  # Loki for logs
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    uid: loki  # Referenced by Jaeger for trace-to-logs
    editable: false
    jsonData:
      # Enable log-to-trace correlation
      # If log contains trace_id, clicking shows the trace
      derivedFields:
        - name: TraceID
          matcherRegex: '"trace_id":"(\w+)"'
          url: '$${__value.raw}'
          datasourceUid: jaeger
```

**The correlation configuration is important.** It enables clicking from a trace to related logs and vice versa—exactly what you need when debugging production issues.

---

## Step 6: Create the Docker Compose File

This is the main deployment file. I've added detailed comments explaining each section.

Create `docker-compose.yml`:

```yaml
# =============================================================================
# Docker Compose - Single Node Observability Stack
# =============================================================================
#
# This deploys a complete observability platform:
#   - OTel Collector: Receives all telemetry, routes to backends
#   - Jaeger: Stores and queries distributed traces
#   - Prometheus: Stores and queries metrics
#   - Loki: Stores and queries logs
#   - Grafana: Visualizes everything
#
# Quick commands:
#   docker compose up -d          # Start everything
#   docker compose ps             # Check status
#   docker compose logs -f        # Watch logs
#   docker compose down           # Stop everything
#   docker compose down -v        # Stop and delete data (careful!)
#

services:
  # ===========================================================================
  # OpenTelemetry Collector
  # ===========================================================================
  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.91.0
    container_name: otel-collector
    command: ["--config=/etc/otelcol/config.yaml"]
    
    volumes:
      - ./configs/otel-collector.yaml:/etc/otelcol/config.yaml:ro
      - otel-storage:/var/lib/otelcol  # Persistent queue storage
    
    ports:
      - "4317:4317"   # OTLP gRPC - primary ingestion
      - "4318:4318"   # OTLP HTTP - alternative ingestion
      - "8888:8888"   # Collector metrics (for self-monitoring)
      - "13133:13133" # Health check endpoint
    
    environment:
      # Tell Go to limit itself to 1.6GB (matches memory_limiter config)
      - GOMEMLIMIT=1600MiB
    
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 512M
    
    # IMPORTANT: otel-collector-contrib is a distroless image (no wget/curl)
    # We use --version as a simple liveness check. For production,
    # verify health externally: curl http://<host>:13133/health
    healthcheck:
      test: ["CMD", "/otelcol-contrib", "--version"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    
    restart: unless-stopped
    stop_grace_period: 30s  # Time to drain queues before stopping
    
    # Wait for backends to be healthy before starting
    depends_on:
      jaeger:
        condition: service_healthy
      prometheus:
        condition: service_healthy
      loki:
        condition: service_healthy
    
    networks:
      - observability
    
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ===========================================================================
  # Jaeger - Distributed Tracing
  # ===========================================================================
  jaeger:
    image: jaegertracing/all-in-one:1.53
    container_name: jaeger
    
    environment:
      # Use Badger for persistent storage (survives restarts)
      - SPAN_STORAGE_TYPE=badger
      - BADGER_EPHEMERAL=false
      - BADGER_DIRECTORY_VALUE=/badger/data
      - BADGER_DIRECTORY_KEY=/badger/key
      - BADGER_SPAN_STORE_TTL=720h  # 30 days retention
    
    volumes:
      - jaeger-data:/badger
    
    ports:
      - "16686:16686"  # Jaeger UI
      - "14268:14268"  # Accept Jaeger format (legacy compatibility)
    
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          cpus: '0.5'
          memory: 1G
    
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:14269/"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 15s
    
    restart: unless-stopped
    stop_grace_period: 30s
    networks:
      - observability
    
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ===========================================================================
  # Prometheus - Metrics Storage
  # ===========================================================================
  prometheus:
    image: prom/prometheus:v2.48.0
    container_name: prometheus
    
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--storage.tsdb.retention.size=40GB'
      - '--web.enable-lifecycle'
      - '--web.enable-remote-write-receiver'  # Accepts data from OTel Collector
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
    
    volumes:
      - ./configs/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    
    ports:
      - "9090:9090"
    
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          cpus: '0.5'
          memory: 1G
    
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9090/-/healthy"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 15s
    
    restart: unless-stopped
    stop_grace_period: 30s
    networks:
      - observability
    
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ===========================================================================
  # Loki - Log Aggregation
  # ===========================================================================
  loki:
    image: grafana/loki:2.9.3
    container_name: loki
    command: -config.file=/etc/loki/loki.yaml
    
    volumes:
      - ./configs/loki.yaml:/etc/loki/loki.yaml:ro
      - loki-data:/loki
    
    ports:
      - "3100:3100"
    
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 2G
        reservations:
          cpus: '0.25'
          memory: 512M
    
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3100/ready"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    
    restart: unless-stopped
    stop_grace_period: 30s
    networks:
      - observability
    
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ===========================================================================
  # Grafana - Visualization
  # ===========================================================================
  grafana:
    image: grafana/grafana:10.2.3
    container_name: grafana
    
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin  # CHANGE THIS IN PRODUCTION
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_SERVER_ROOT_URL=http://localhost:3000
      - GF_FEATURE_TOGGLES_ENABLE=traceqlEditor
    
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
    
    ports:
      - "3000:3000"
    
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G
        reservations:
          cpus: '0.25'
          memory: 256M
    
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3000/api/health"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    
    restart: unless-stopped
    
    depends_on:
      prometheus:
        condition: service_healthy
      jaeger:
        condition: service_healthy
      loki:
        condition: service_healthy
    
    networks:
      - observability
    
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

# =============================================================================
# Networks
# =============================================================================
networks:
  observability:
    driver: bridge
    name: observability

# =============================================================================
# Volumes - Persistent Storage
# =============================================================================
volumes:
  otel-storage:
    name: otel-storage
  jaeger-data:
    name: jaeger-data
  prometheus-data:
    name: prometheus-data
  loki-data:
    name: loki-data
  grafana-data:
    name: grafana-data
```

**Important configuration choices:**

1. **Resource limits** on every container prevent one component from starving others. The numbers here work for a single 8-CPU, 16GB server.

2. **Health checks** enable `depends_on` conditions. The collector won't start until backends are healthy, preventing startup failures.

3. **`stop_grace_period: 30s`** gives services time to drain in-flight data before shutting down. This is critical for the collector—it needs time to flush its queues.

4. **Named volumes** make backups easier. You can list volumes with `docker volume ls` and back them up individually.

---

## Step 7: Create Operational Scripts

These scripts make day-to-day operations easier. You'll thank yourself later for setting them up now.

### Backup Script

Create `scripts/backup.sh`:

```bash
#!/bin/bash
# =============================================================================
# Backup Script
# =============================================================================
#
# Creates compressed backups of all Docker volumes.
#
# Usage:
#   ./scripts/backup.sh                          # Backup to ./backups
#   BACKUP_DIR=/mnt/nfs ./scripts/backup.sh      # Backup to NFS mount
#
# Schedule with cron for automated daily backups:
#   0 2 * * * cd /path/to/otel-stack && ./scripts/backup.sh >> /var/log/otel-backup.log 2>&1
#

set -euo pipefail

# Configuration
BACKUP_DIR="${BACKUP_DIR:-./backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

# Volumes to backup (names must match docker-compose.yml)
# Phase 1 uses: otel-storage, jaeger-data, prometheus-data, loki-data, grafana-data
# Phase 2 uses: otel-scalable-* prefix (see docker-compose-scalable.yaml)
VOLUMES=(
  "otel-storage"
  "jaeger-data"
  "prometheus-data"
  "loki-data"
  "grafana-data"
)

echo "=========================================="
echo "Observability Stack Backup"
echo "=========================================="
echo "Time: $(date)"
echo "Destination: ${BACKUP_PATH}"
echo ""

# Create backup directory
mkdir -p "$BACKUP_PATH"

# Backup each volume
SUCCESS=0
FAILED=0

for volume in "${VOLUMES[@]}"; do
  echo -n "Backing up ${volume}... "
  
  if docker volume inspect "$volume" &>/dev/null; then
    if docker run --rm \
      -v "${volume}:/source:ro" \
      -v "${BACKUP_PATH}:/backup" \
      alpine tar czf "/backup/${volume}.tar.gz" -C /source . 2>/dev/null; then
      
      SIZE=$(du -sh "${BACKUP_PATH}/${volume}.tar.gz" | cut -f1)
      echo "OK (${SIZE})"
      ((SUCCESS++))
    else
      echo "FAILED"
      ((FAILED++))
    fi
  else
    echo "SKIPPED (volume not found)"
  fi
done

# Backup config files
echo -n "Backing up configs... "
tar czf "${BACKUP_PATH}/configs.tar.gz" \
  docker-compose.yml \
  configs/ \
  grafana/provisioning/ \
  scripts/ \
  2>/dev/null && echo "OK" || echo "FAILED"

# Create manifest
cat > "${BACKUP_PATH}/manifest.json" << EOF
{
  "timestamp": "${TIMESTAMP}",
  "date": "$(date -Iseconds)",
  "volumes_backed_up": ${SUCCESS},
  "volumes_failed": ${FAILED}
}
EOF

# Clean old backups
echo ""
echo "Cleaning backups older than ${RETENTION_DAYS} days..."
DELETED=$(find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -exec rm -rf {} \; -print | wc -l)
echo "Deleted ${DELETED} old backups"

# Summary
echo ""
echo "=========================================="
echo "Backup Complete"
echo "=========================================="
echo "Location: ${BACKUP_PATH}"
echo "Volumes: ${SUCCESS} succeeded, ${FAILED} failed"

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
```

Make it executable: `chmod +x scripts/backup.sh`

### Health Check Script

Create `scripts/health-check.sh`:

```bash
#!/bin/bash
# =============================================================================
# Health Check Script
# =============================================================================
#
# Checks all components and reports status.
#
# Usage:
#   ./scripts/health-check.sh           # Human-readable output
#   ./scripts/health-check.sh --json    # JSON output for automation
#

set -euo pipefail

# Configuration (override with environment variables if needed)
OTEL_COLLECTOR="${OTEL_COLLECTOR:-localhost}"
PROMETHEUS="${PROMETHEUS:-localhost}"
JAEGER="${JAEGER:-localhost}"
LOKI="${LOKI:-localhost}"
GRAFANA="${GRAFANA:-localhost}"

# Parse arguments
JSON_OUTPUT=false
[[ "${1:-}" == "--json" ]] && JSON_OUTPUT=true

# Track overall status
OVERALL=0
declare -A RESULTS

# Check function
check() {
  local name=$1
  local url=$2
  
  if curl -sf -o /dev/null --max-time 5 "$url" 2>/dev/null; then
    RESULTS[$name]="healthy"
  else
    RESULTS[$name]="unhealthy"
    OVERALL=1
  fi
}

# Run checks
check "collector-health" "http://${OTEL_COLLECTOR}:13133/health"
check "prometheus" "http://${PROMETHEUS}:9090/-/healthy"
check "jaeger" "http://${JAEGER}:16686/"
check "loki" "http://${LOKI}:3100/ready"
check "grafana" "http://${GRAFANA}:3000/api/health"

# Output
if [[ "$JSON_OUTPUT" == true ]]; then
  echo "{"
  echo "  \"timestamp\": \"$(date -Iseconds)\","
  echo "  \"status\": \"$([ $OVERALL -eq 0 ] && echo 'healthy' || echo 'degraded')\","
  echo "  \"components\": {"
  first=true
  for name in "${!RESULTS[@]}"; do
    [[ "$first" == true ]] || echo ","
    echo -n "    \"$name\": \"${RESULTS[$name]}\""
    first=false
  done
  echo ""
  echo "  }"
  echo "}"
else
  echo ""
  echo "Observability Stack Health Check"
  echo "================================="
  echo "Time: $(date)"
  echo ""
  
  for name in collector-health prometheus jaeger loki grafana; do
    status="${RESULTS[$name]:-unknown}"
    if [[ "$status" == "healthy" ]]; then
      echo "  ✓ $name"
    else
      echo "  ✗ $name"
    fi
  done
  
  echo ""
  if [[ $OVERALL -eq 0 ]]; then
    echo "Status: All systems operational"
  else
    echo "Status: Some components are degraded"
  fi
fi

exit $OVERALL
```

Make it executable: `chmod +x scripts/health-check.sh`

---

## Step 8: Deploy

Now let's bring everything up. This is the moment of truth.

```bash
# Make sure you're in the project directory
cd otel-stack

# Start all services in the background
docker compose up -d

# Watch the logs to see startup progress
docker compose logs -f
```

You'll see services starting in order: Jaeger, Prometheus, and Loki first (they have no dependencies), then the OTel Collector (waits for backends), then Grafana (waits for everything).

**What to look for:**
- Each service should log that it started successfully
- The collector should log "Everything is ready"
- No repeated error messages

Press `Ctrl+C` to stop watching logs (services keep running).

---

## Step 9: Verify Everything Works

Let's make sure the deployment is healthy.

### Check Container Status

```bash
docker compose ps
```

All containers should show `healthy`:

```
NAME             IMAGE                                        STATUS                   PORTS
grafana          grafana/grafana:10.2.3                      Up 2 minutes (healthy)   0.0.0.0:3000->3000/tcp
jaeger           jaegertracing/all-in-one:1.53               Up 3 minutes (healthy)   0.0.0.0:16686->16686/tcp
loki             grafana/loki:2.9.3                          Up 3 minutes (healthy)   0.0.0.0:3100->3100/tcp
otel-collector   otel/opentelemetry-collector-contrib:0.91.0  Up 2 minutes (healthy)   0.0.0.0:4317-4318->4317-4318/tcp
prometheus       prom/prometheus:v2.48.0                      Up 3 minutes (healthy)   0.0.0.0:9090->9090/tcp
```

### Run the Health Check Script

```bash
./scripts/health-check.sh
```

Should output:
```
Observability Stack Health Check
=================================
Time: Thu Jan 15 10:30:00 UTC 2025

  ✓ collector-health
  ✓ prometheus
  ✓ jaeger
  ✓ loki
  ✓ grafana

Status: All systems operational
```

### Access the UIs

Open these URLs in your browser:

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| Grafana | http://localhost:3000 | admin / admin |
| Jaeger | http://localhost:16686 | None |
| Prometheus | http://localhost:9090 | None |

### Send Test Data

Let's verify the collector is accepting data:

```bash
# Generate timestamps and send test trace
START_TIME=$(date +%s)000000000
END_TIME=$(( $(date +%s) + 1 ))000000000

curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d "{
    \"resourceSpans\": [{
      \"resource\": {
        \"attributes\": [{
          \"key\": \"service.name\",
          \"value\": {\"stringValue\": \"test-service\"}
        }]
      },
      \"scopeSpans\": [{
        \"spans\": [{
          \"traceId\": \"5B8EFFF798038103D269B633813FC60C\",
          \"spanId\": \"EEE19B7EC3C1B174\",
          \"name\": \"test-span\",
          \"kind\": 1,
          \"startTimeUnixNano\": \"${START_TIME}\",
          \"endTimeUnixNano\": \"${END_TIME}\"
        }]
      }]
    }]
  }"
```

Now go to Jaeger (http://localhost:16686):
1. Select "test-service" from the Service dropdown
2. Click "Find Traces"
3. You should see your test trace

**Congratulations!** Your observability stack is running.

---

## Step 10: Connect Your Applications

Now you need to send real telemetry from your applications. The configuration depends on your language, but the concept is the same: point the OTLP exporter at your collector.

### Environment Variables (All Languages)

Most OpenTelemetry SDKs respect these environment variables:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://your-collector-host:4317
OTEL_SERVICE_NAME=your-service-name
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production
```

If your collector is on the same host as your application (like in Docker Compose), use the service name or `host.docker.internal`.

### Quick Examples

**.NET:**
```csharp
builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddOtlpExporter(options => {
            options.Endpoint = new Uri("http://localhost:4317");
        }))
    .WithMetrics(metrics => metrics
        .AddAspNetCoreInstrumentation()
        .AddOtlpExporter(options => {
            options.Endpoint = new Uri("http://localhost:4317");
        }));
```

**Node.js:**
```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');

const sdk = new NodeSDK({
  serviceName: 'my-service',
  traceExporter: new OTLPTraceExporter({
    url: 'http://localhost:4317',
  }),
});
sdk.start();
```

**Python:**
```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

trace.set_tracer_provider(TracerProvider())
otlp_exporter = OTLPSpanExporter(endpoint="http://localhost:4317")
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(otlp_exporter))
```

For detailed integration guides, see the language-specific documentation in the `docs/` folder.

---

## Phase 1 Complete

At this point, you have a fully functional observability stack. Before moving to Phase 2, make sure:

- [ ] All services show "healthy"
- [ ] You can access Grafana and see data sources
- [ ] Test telemetry appears in Jaeger
- [ ] The backup script runs successfully
- [ ] Your applications are sending real telemetry

**You can stop here.** Phase 1 is production-ready for many teams. Only move to Phase 2 when you:
- Need to handle more than 50,000 events per second
- Require high availability (can't afford observability downtime)
- Need to do maintenance on backends without losing data

---

# Phase 2: Adding Kafka for Reliability

> **All configs are pre-built.** Unlike Phase 1 (which walks through creating configs), Phase 2 uses ready-to-deploy files from `docs/scalable/configs/docker/`. Just run `docker compose -f docker-compose-scalable.yaml up -d`.

When you've outgrown Phase 1—either hitting throughput limits, needing high availability, or requiring backend maintenance without data loss—it's time to add Kafka as a buffer layer.

## What Changes in Phase 2

```
Phase 1:                           Phase 2:
                                   
Apps → Collector → Backends        Apps → Gateways → Kafka → Processors → Backends
       (single)                           (many)      ↓       (many)
                                                   (buffer)
```

The key architectural changes:
1. **Split collectors** into Gateways (receive only) and Processors (export only)
2. **Add Kafka** between them for durable buffering
3. **Add HAProxy** for load balancing across gateways
4. **Replace Jaeger with Tempo** for scalable trace storage
5. **Replace Prometheus with Mimir** for scalable metrics storage

## Prerequisites

- Phase 1 running successfully (or at least understood)
- Server with 16+ GB RAM and 200+ GB SSD
- Basic understanding of Kafka concepts

## Step 1: Navigate to Scalable Configs

All Phase 2 configuration files are in the `configs/docker/` directory:

```bash
cd docs/scalable/configs/docker
ls -la
```

You should see:
```
docker-compose-scalable.yaml    # Main deployment file
docker-compose-single.yaml      # Phase 1 reference (simpler setup)
otel-gateway.yaml               # Gateway collector config
otel-processor.yaml             # Processor collector config  
otel-collector.yaml             # Phase 1 collector (reference)
haproxy.cfg                     # Load balancer config
tempo.yaml                      # Trace storage config (replaces Jaeger)
mimir.yaml                      # Metrics storage config (replaces Prometheus for app metrics)
mimir-runtime.yaml              # Mimir runtime configuration
loki.yaml                       # Log storage config
prometheus.yml                  # Stack self-monitoring only
alertmanager-fallback.yaml      # Default alertmanager config for Mimir
grafana/                        # Grafana provisioning (datasources)
```

> **Key Change from Phase 1:** In Phase 2, we replace Jaeger with **Tempo** (better at scale, uses object storage) and add **Mimir** for application metrics (Prometheus still monitors the stack itself). This is an important architectural decision that enables unlimited retention and horizontal scaling.

## Step 2: Understand the Components

Before deploying, let's understand what each component does:

### HAProxy (Load Balancer)
```
Incoming OTLP → HAProxy:4317 → Gateway 1, 2, 3...
                      ↓
              Health-aware routing
              Round-robin distribution
```

HAProxy accepts all incoming telemetry and distributes it across healthy gateway collectors. If a gateway goes down, HAProxy automatically stops sending traffic to it.

### Gateway Collectors
```
OTLP → Gateway → Kafka Topics
                   ├── otlp-traces
                   ├── otlp-metrics
                   └── otlp-logs
```

Gateways are stateless and fast. They validate incoming data, batch it efficiently, and publish to Kafka. They don't process or sample—that comes later.

### Kafka (Message Queue)
```
Gateways → Kafka (12 partitions each topic) → Processors
              ↓
         24h retention
         Replication factor 1 (Docker)
```

Kafka provides durable buffering. Data is written to disk and survives component restarts. If processors are down, data queues in Kafka until they recover.

### Processor Collectors
```
Kafka → Processor → Sampling → Tempo/Mimir/Loki
                        ↓
                  Keep errors
                  Keep slow traces
                  Sample 10% rest
```

Processors consume from Kafka and do the heavy lifting: tail-based sampling, attribute enrichment, and export to backends. They can scale independently based on load.

### Storage Backends

| Component | Replaces | Why |
|-----------|----------|-----|
| **Tempo** | Jaeger | Object storage native, cheaper at scale, TraceQL |
| **Mimir** | Prometheus | Horizontally scalable, unlimited retention |
| **Loki** | (same) | Already scalable by design |

### Complete Data Flow Diagram

Understanding the complete data flow helps with debugging:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                DATA FLOW                                          │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│  Your Applications                                                               │
│       │                                                                          │
│       │ OTLP (gRPC :4317 or HTTP :4318)                                          │
│       ▼                                                                          │
│  ┌─────────────┐                                                                 │
│  │  HAProxy    │  Load balances across healthy gateways                          │
│  │  :4317/:4318│  Stats UI at :8404/stats                                        │
│  └──────┬──────┘                                                                 │
│         │                                                                        │
│         ▼                                                                        │
│  ┌─────────────────────────────────────────────────────────────────┐             │
│  │              Gateway Collectors (stateless, scalable)           │             │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐                          │             │
│  │  │Gateway 1│  │Gateway 2│  │Gateway 3│  ... (scale with load)   │             │
│  │  └────┬────┘  └────┬────┘  └────┬────┘                          │             │
│  │       │           │           │                                  │             │
│  │       └───────────┼───────────┘                                  │             │
│  └───────────────────┼──────────────────────────────────────────────┘             │
│                      │                                                            │
│                      ▼                                                            │
│  ┌──────────────────────────────────────────────────────────────────┐            │
│  │                    Kafka (KRaft mode, no Zookeeper)              │            │
│  │  Topics:                                                          │            │
│  │    • otlp-traces  (12 partitions, 24h retention)                 │            │
│  │    • otlp-metrics (12 partitions, 24h retention)                 │            │
│  │    • otlp-logs    (12 partitions, 24h retention)                 │            │
│  └───────────────────────────┬──────────────────────────────────────┘            │
│                              │                                                    │
│                              ▼                                                    │
│  ┌───────────────────────────────────────────────────────────────────┐           │
│  │             Processor Collectors (stateless, scalable)            │           │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐                      │           │
│  │  │Processor 1│  │Processor 2│  │Processor 3│  ... (scale with load)│          │
│  │  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘                      │           │
│  │        │              │              │                             │           │
│  │        │   Processing applied:                                    │           │
│  │        │   • Memory limiting (OOM protection)                     │           │
│  │        │   • Tail-based sampling (keep errors, slow traces, 10%)  │           │
│  │        │   • Resource attributes added                            │           │
│  │        │   • Batching for efficient export                        │           │
│  │        │              │              │                             │           │
│  └────────┼──────────────┼──────────────┼─────────────────────────────┘           │
│           │              │              │                                         │
│           ▼              ▼              ▼                                         │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐                                   │
│  │   Tempo    │  │   Mimir    │  │    Loki    │                                   │
│  │  (Traces)  │  │ (Metrics)  │  │   (Logs)   │                                   │
│  │   :3200    │  │   :9009    │  │   :3100    │                                   │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘                                   │
│        │               │               │                                          │
│        └───────────────┼───────────────┘                                          │
│                        ▼                                                          │
│               ┌────────────────┐                                                  │
│               │    Grafana     │  Unified visualization                           │
│               │     :3000      │  with correlation links                          │
│               └────────────────┘                                                  │
│                                                                                   │
│  ┌────────────────┐                                                              │
│  │   Prometheus   │  Monitors all the above components (stack self-monitoring)   │
│  │     :9090      │  Scrapes metrics from every service                          │
│  └────────────────┘                                                              │
│                                                                                   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

**Why this architecture?**
1. **HAProxy** provides single entry point, health-aware routing, and easy scaling
2. **Kafka** decouples ingestion from processing - backends can be down without losing data
3. **Gateways** are fast and stateless - easy to scale, quick to restart
4. **Processors** do heavy lifting - can scale independently based on processing needs
5. **Separate storage backends** - each optimized for its data type (traces, metrics, logs)

## Step 3: Deploy the Stack

```bash
# From the docker config directory
cd docs/scalable/configs/docker

# Start everything
docker compose -f docker-compose-scalable.yaml up -d

# Watch the logs
docker compose -f docker-compose-scalable.yaml logs -f
```

Wait for all services to become healthy (2-3 minutes for Kafka to fully start):

```bash
docker compose -f docker-compose-scalable.yaml ps
```

Expected output:
```
NAME              STATUS                   PORTS
grafana           Up (healthy)             0.0.0.0:3000->3000/tcp
haproxy           Up (healthy)             0.0.0.0:4317-4318->4317-4318/tcp
kafka             Up (healthy)             0.0.0.0:9092->9092/tcp
loki              Up (healthy)             0.0.0.0:3100->3100/tcp
mimir             Up (healthy)             0.0.0.0:9009->9009/tcp
otel-gateway-1    Up (healthy)             4317-4318/tcp
otel-gateway-2    Up (healthy)             4317-4318/tcp
otel-processor-1  Up (healthy)             
otel-processor-2  Up (healthy)             
prometheus        Up (healthy)             0.0.0.0:9090->9090/tcp
tempo             Up (healthy)             0.0.0.0:3200->3200/tcp
```

## Step 4: Scale the Collectors

The real power of Phase 2 is horizontal scaling. Scale gateways and processors based on load:

```bash
# Scale to 3 gateways and 3 processors
docker compose -f docker-compose-scalable.yaml up -d --scale otel-gateway=3 --scale otel-processor=3

# Verify scaling
docker compose -f docker-compose-scalable.yaml ps | grep otel
```

**When to scale gateways:** High CPU on existing gateways, HAProxy showing uneven distribution
**When to scale processors:** Kafka consumer lag increasing, high memory usage on processors

## Step 5: Verify Data Flow

### Check HAProxy Stats
Open http://localhost:8404/stats in your browser. You should see:
- Backend servers (gateways) listed as UP
- Request counts distributed across gateways

### Check Kafka Topics
```bash
# List topics
docker compose -f docker-compose-scalable.yaml exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --list

# Check topic offsets (messages in queue)
docker compose -f docker-compose-scalable.yaml exec kafka kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list localhost:9092 --topic otlp-traces
```

### Check Collector Metrics
```bash
# Gateway metrics (receiving)
curl -s http://localhost:8888/metrics | grep otelcol_receiver_accepted

# Processor metrics (exporting) - need to find processor port
docker compose -f docker-compose-scalable.yaml exec otel-processor-1 wget -qO- http://localhost:8888/metrics | grep otelcol_exporter_sent
```

### Send Test Data
```bash
# Same test as Phase 1 - HAProxy routes to gateways
START_TIME=$(date +%s)000000000
END_TIME=$(( $(date +%s) + 1 ))000000000

curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d "{
    \"resourceSpans\": [{
      \"resource\": {
        \"attributes\": [{
          \"key\": \"service.name\",
          \"value\": {\"stringValue\": \"test-service-phase2\"}
        }]
      },
      \"scopeSpans\": [{
        \"spans\": [{
          \"traceId\": \"5B8EFFF798038103D269B633813FC60D\",
          \"spanId\": \"EEE19B7EC3C1B175\",
          \"name\": \"test-span-phase2\",
          \"kind\": 1,
          \"startTimeUnixNano\": \"${START_TIME}\",
          \"endTimeUnixNano\": \"${END_TIME}\"
        }]
      }]
    }]
  }"
```

### Verify in Grafana

1. Open http://localhost:3000 (admin/admin)
2. Go to Explore
3. Select **Tempo** datasource
4. Search for service "test-service-phase2"
5. You should see your test trace

## Step 6: Update Application Configuration

Your applications now send to HAProxy instead of directly to a collector:

```bash
# Same endpoint - HAProxy handles routing
OTEL_EXPORTER_OTLP_ENDPOINT=http://your-server:4317
```

No application code changes needed—just update the endpoint if it was pointing to a specific collector.

## Step 7: Monitor the Stack

Prometheus scrapes all components. Check the pre-configured alerts:

```bash
# View active alerts
curl http://localhost:9090/api/v1/alerts | jq

# View specific metrics
curl 'http://localhost:9090/api/v1/query?query=otelcol_exporter_queue_size'
```

Key metrics to watch:
- `otelcol_exporter_queue_size` - Should stay low
- `otelcol_exporter_send_failed_*` - Should be zero
- `kafka_consumergroup_lag` - Consumer lag (if using kafka-exporter)

## Phase 2 Complete

You now have a scalable, highly-available observability stack:

- ✅ Multiple gateways behind load balancer
- ✅ Kafka buffer for durability
- ✅ Multiple processors with tail sampling
- ✅ Scalable storage backends (Tempo, Mimir, Loki)
- ✅ Stack self-monitoring with Prometheus
- ✅ Unified visualization in Grafana

**Move to Phase 3 (Kubernetes) when:**
- Your organization has standardized on Kubernetes
- You need GitOps workflows
- You want auto-scaling based on metrics
- You're running in multiple regions

---

# Phase 3: Kubernetes Deployment

Phase 3 deploys the same architecture on Kubernetes, gaining:
- Auto-scaling with Horizontal Pod Autoscaler
- Self-healing with pod restart policies
- GitOps-friendly declarative configuration
- Pod disruption budgets for safe maintenance
- Ingress for external access

## Prerequisites

- Kubernetes cluster (1.24+) with kubectl configured
- Familiarity with Kubernetes concepts (Deployments, Services, ConfigMaps)
- Storage class available for PersistentVolumeClaims
- (Optional) Ingress controller installed

## Step 1: Review Kubernetes Manifests

All Kubernetes manifests are in `configs/kubernetes/`:

```bash
cd docs/scalable/configs/kubernetes
ls -la
```

```
namespace.yaml       # Observability namespace
kafka-cluster.yaml   # Strimzi Kafka (requires operator)
minio.yaml           # S3-compatible object storage
otel-gateway.yaml    # Gateway deployment + HPA + PDB
otel-processor.yaml  # Processor deployment + HPA + PDB
tempo.yaml           # Trace storage StatefulSet
mimir.yaml           # Metrics storage StatefulSet
loki.yaml            # Log storage StatefulSet
grafana.yaml         # Visualization deployment + Ingress
postgresql.yaml      # Grafana HA database
prometheus.yaml      # Stack monitoring
```

## Step 2: Install Prerequisites

### Install Strimzi Kafka Operator
```bash
# Create Kafka namespace
kubectl create namespace kafka

# Install Strimzi operator
kubectl apply -f 'https://strimzi.io/install/latest?namespace=kafka'

# Wait for operator to be ready
kubectl wait deployment/strimzi-cluster-operator --for=condition=Available -n kafka --timeout=300s
```

## Understanding the Init Container Pattern

**Important:** The Kubernetes manifests for Tempo, Mimir, and Loki use an **init container pattern** for credential handling.

**Why is this needed?**

Kubernetes ConfigMaps don't support environment variable substitution. When you write `${S3_ACCESS_KEY}` in a ConfigMap, it's stored literally as the string `${S3_ACCESS_KEY}`, not the actual value.

**How we solve it:**

```
┌─────────────────────────────────────────────────────────────────┐
│                     Pod Startup Sequence                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Init Container (config-init) starts:                        │
│     ┌──────────────────────────────────────────────────────┐    │
│     │  - Reads /config-template/tempo.yaml (from ConfigMap) │    │
│     │  - Reads S3_ACCESS_KEY and S3_SECRET_KEY from Secret  │    │
│     │  - Uses `envsubst` to replace ${VAR} placeholders     │    │
│     │  - Writes rendered config to /config/tempo.yaml       │    │
│     └──────────────────────────────────────────────────────┘    │
│                              │                                   │
│                              ▼                                   │
│  2. Main Container (tempo) starts:                              │
│     ┌──────────────────────────────────────────────────────┐    │
│     │  - Reads /config/tempo.yaml (with real credentials)   │    │
│     │  - Connects to S3 successfully                        │    │
│     └──────────────────────────────────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**The init container in each manifest:**
```yaml
initContainers:
  - name: config-init
    image: bhgedigital/envsubst:latest  # Small image with envsubst
    env:
      - name: S3_ACCESS_KEY
        valueFrom:
          secretKeyRef:
            name: tempo-s3-credentials
            key: access-key
      - name: S3_SECRET_KEY
        valueFrom:
          secretKeyRef:
            name: tempo-s3-credentials
            key: secret-key
    command: ['sh', '-c', 'envsubst < /config-template/tempo.yaml > /config/tempo.yaml']
    volumeMounts:
      - name: config-template    # ConfigMap with ${VAR} placeholders
        mountPath: /config-template
      - name: config-rendered    # emptyDir for rendered config
        mountPath: /config
```

**If you're using AWS IRSA:** You can simplify this by removing access keys entirely. IRSA injects credentials automatically via the pod's service account. Update the ConfigMaps to remove the `access_key` and `secret_key` fields.

## Step 3: Deploy in Order

The deployment order matters due to dependencies:

```bash
# 1. Create namespaces
kubectl apply -f namespace.yaml
kubectl create namespace minio

# 2. Deploy MinIO (object storage)
kubectl apply -f minio.yaml
kubectl wait pod/minio-0 --for=condition=Ready -n minio --timeout=300s

# 3. Deploy Kafka cluster
kubectl apply -f kafka-cluster.yaml
kubectl wait kafka/otel-kafka --for=condition=Ready -n kafka --timeout=600s

# 4. Deploy storage backends
kubectl apply -f tempo.yaml
kubectl apply -f mimir.yaml
kubectl apply -f loki.yaml

# Wait for backends
kubectl wait pod/tempo-0 --for=condition=Ready -n observability --timeout=300s
kubectl wait pod/mimir-0 --for=condition=Ready -n observability --timeout=300s
kubectl wait pod/loki-0 --for=condition=Ready -n observability --timeout=300s

# 5. Deploy monitoring
kubectl apply -f prometheus.yaml
kubectl apply -f postgresql.yaml

# 6. Deploy Grafana
kubectl apply -f grafana.yaml

# 7. Deploy collectors (last - they need backends ready)
kubectl apply -f otel-gateway.yaml
kubectl apply -f otel-processor.yaml
```

## Step 4: Verify Deployment

```bash
# Check all pods
kubectl get pods -n observability
kubectl get pods -n kafka
kubectl get pods -n minio

# Check services
kubectl get svc -n observability

# Check HPA status
kubectl get hpa -n observability
```

Expected output:
```
NAME                   READY   STATUS    RESTARTS   AGE
grafana-xxx-yyy        1/1     Running   0          5m
loki-0                 1/1     Running   0          8m
mimir-0                1/1     Running   0          8m
otel-gateway-xxx       1/1     Running   0          3m
otel-gateway-yyy       1/1     Running   0          3m
otel-gateway-zzz       1/1     Running   0          3m
otel-processor-xxx     1/1     Running   0          3m
otel-processor-yyy     1/1     Running   0          3m
otel-processor-zzz     1/1     Running   0          3m
prometheus-0           1/1     Running   0          5m
tempo-0                1/1     Running   0          8m
```

## Step 5: Configure Ingress

Update the Grafana ingress with your domain:

```bash
kubectl edit ingress grafana -n observability
```

Or apply a custom ingress:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: observability
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
    - host: grafana.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 3000
```

## Step 6: Configure Applications

Applications should send telemetry to the gateway service:

```bash
# Get the gateway service endpoint
kubectl get svc otel-gateway -n observability
```

Configure your applications:
```bash
# If applications are in the same cluster
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-gateway.observability.svc.cluster.local:4317

# If applications are external (requires LoadBalancer or Ingress)
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-gateway.yourdomain.com:4317
```

## Step 7: Expose Gateway Externally (Optional)

For applications outside the cluster, expose the gateway:

**Option A: LoadBalancer**
```bash
kubectl patch svc otel-gateway -n observability -p '{"spec": {"type": "LoadBalancer"}}'
```

**Option B: Ingress (gRPC)**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: otel-gateway
  namespace: observability
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
spec:
  rules:
    - host: otel.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: otel-gateway
                port:
                  number: 4317
```

## Step 8: Verify Auto-Scaling

The HPA will automatically scale collectors based on CPU/memory:

```bash
# Watch HPA status
kubectl get hpa -n observability -w

# Generate load and watch scaling
# (Send high volume of telemetry)

# Check scaled pods
kubectl get pods -n observability -l app=otel-gateway
```

## Step 9: Test Pod Disruption Budget

PDBs ensure minimum availability during maintenance:

```bash
# Check PDB status
kubectl get pdb -n observability

# Try draining a node (PDB will prevent too many pods from evicting)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

## Customizing for Production

### Update Storage Classes

Edit each StatefulSet to use your cluster's storage class:

```bash
# Find your storage classes
kubectl get storageclass

# Update manifests
sed -i 's/storageClassName: standard/storageClassName: your-storage-class/g' *.yaml
```

### Update Credentials

**MinIO:**
```bash
kubectl create secret generic minio-credentials -n minio \
  --from-literal=root-user='your-access-key' \
  --from-literal=root-password='your-secret-key' \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Update S3 credentials in each backend:**
```bash
kubectl create secret generic tempo-s3-credentials -n observability \
  --from-literal=access-key='your-access-key' \
  --from-literal=secret-key='your-secret-key' \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Enable Grafana HA with PostgreSQL

Uncomment the PostgreSQL environment variables in `grafana.yaml`:
```yaml
env:
  - name: GF_DATABASE_TYPE
    value: "postgres"
  - name: GF_DATABASE_HOST
    value: "postgresql.observability.svc.cluster.local:5432"
  # ... etc
```

## Phase 3 Complete

You now have a production-ready Kubernetes deployment:

- ✅ Auto-scaling collectors (HPA)
- ✅ High availability with PDBs
- ✅ Object storage backend (MinIO/S3)
- ✅ Kafka for durable buffering (Strimzi)
- ✅ Stack self-monitoring
- ✅ Ingress for external access

---

# Phase 4: Production Infrastructure with Terraform

If you're deploying on AWS and want proper infrastructure-as-code, use the Terraform configuration to provision:

- **VPC** with public/private subnets across 3 AZs
- **EKS cluster** with managed node groups
- **S3 bucket** for object storage (Tempo, Mimir, Loki)
- **IAM roles** for service account integration (IRSA)

## Step 1: Review Terraform Configuration

```bash
cd docs/scalable/configs/terraform
ls -la
```

```
main.tf          # VPC, EKS, S3, IAM resources
variables.tf     # Configurable inputs (region, cluster name, node sizes)
outputs.tf       # Useful outputs (cluster endpoint, S3 bucket, IRSA roles)
```

## Step 2: Create Your Variables File

```bash
# Copy example and customize
cat > terraform.tfvars << 'EOF'
# AWS Configuration
aws_region  = "us-west-2"
environment = "production"

# Cluster Configuration
cluster_name       = "observability-prod"
kubernetes_version = "1.28"

# Node Group Sizing (adjust based on expected load)
system_node_instance_types       = ["t3.medium"]
system_node_desired_size         = 2
observability_node_instance_types = ["t3.xlarge"]
observability_node_desired_size   = 3

# Retention (days)
trace_retention_days   = 30
metrics_retention_days = 90
logs_retention_days    = 30
EOF
```

## Step 3: Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan -var-file="terraform.tfvars"

# Apply (this takes 15-20 minutes for EKS)
terraform apply -var-file="terraform.tfvars"
```

## Step 4: Configure kubectl

```bash
# Get the kubeconfig command from outputs
terraform output kubeconfig_command

# Run it (example)
aws eks update-kubeconfig --region us-west-2 --name observability-prod
```

## Step 5: Update Kubernetes Configs for AWS

The Terraform outputs include S3 configuration snippets for each backend:

```bash
# Get S3 configuration for Tempo
terraform output tempo_s3_config

# Get S3 configuration for Mimir  
terraform output mimir_s3_config

# Get S3 configuration for Loki
terraform output loki_s3_config

# Get the IAM role ARN for service accounts
terraform output s3_irsa_role_arn
```

Update the Kubernetes manifests to:
1. Use the S3 bucket instead of MinIO
2. Add the IRSA annotation to service accounts
3. Remove access key/secret key (IRSA handles auth)

Example service account annotation:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tempo
  namespace: observability
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/observability-prod-s3-access
```

## Step 6: Deploy Kubernetes Resources

```bash
cd ../kubernetes

# Apply in order (skip minio.yaml - using S3 instead)
kubectl apply -f namespace.yaml
kubectl apply -f kafka-cluster.yaml
kubectl apply -f tempo.yaml
kubectl apply -f mimir.yaml
kubectl apply -f loki.yaml
kubectl apply -f prometheus.yaml
kubectl apply -f grafana.yaml
kubectl apply -f otel-gateway.yaml
kubectl apply -f otel-processor.yaml
```

---

# Automated Deployment with Ansible

For VM-based deployments (not Kubernetes), use Ansible to automate the entire setup:

## What Ansible Deploys

The playbook handles:
- Docker installation (if not present)
- Directory structure creation
- Configuration file deployment
- Docker Compose stack startup
- Systemd service setup (auto-start on boot)
- Backup cron job configuration

## Step 1: Configure Inventory

```bash
cd docs/scalable/configs/ansible

# Copy and edit the inventory
cp inventory.example inventory
```

Edit `inventory` with your server details:
```ini
[observability]
# Single server
prod-observability ansible_host=10.0.1.100

[observability:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/id_rsa

# Choose deployment type
deployment_type=scalable  # or 'single' for Phase 1

# Credentials (CHANGE THESE)
grafana_admin_password=your-secure-password

# Versions (optional - defaults are tested)
otel_collector_version=0.91.0
```

## Step 2: Run the Playbook

```bash
# Dry run first
ansible-playbook -i inventory playbook.yml --check

# Deploy for real
ansible-playbook -i inventory playbook.yml

# Deploy scalable setup specifically
ansible-playbook -i inventory playbook.yml -e deployment_type=scalable
```

## Step 3: Verify Deployment

After completion, the playbook displays access information:
```
============================================
Observability Stack Deployed Successfully!
============================================

Access URLs:
  - Grafana:    http://10.0.1.100:3000 (admin/your-secure-password)
  - Prometheus: http://10.0.1.100:9090
  - Tempo:      http://10.0.1.100:3200

OTLP Endpoints:
  - gRPC: 10.0.1.100:4317
  - HTTP: 10.0.1.100:4318

Management Commands:
  - Status:  cd /opt/observability && docker compose ps
  - Logs:    cd /opt/observability && docker compose logs -f
  - Restart: systemctl restart observability
============================================
```

## What Gets Installed

| Path | Contents |
|------|----------|
| `/opt/observability/` | Main installation directory |
| `/opt/observability/docker-compose.yaml` | Deployment file |
| `/opt/observability/*.yaml` | All configuration files |
| `/opt/observability/grafana/` | Grafana provisioning |
| `/opt/observability/backups/` | Backup storage |
| `/etc/systemd/system/observability.service` | Systemd service |

The stack auto-starts on boot via systemd and runs daily backups at 2 AM.

---

# Troubleshooting

When things go wrong—and they will—here's how to diagnose and fix common issues.

## The Debugging Mindset

Before diving into specific issues, let me share how I approach troubleshooting observability systems:

1. **Start with health checks.** Is the component actually running? Is it healthy?
2. **Check the logs.** What errors or warnings is it reporting?
3. **Check resource usage.** Is it out of memory? CPU-bound? Out of disk?
4. **Check connectivity.** Can components reach each other?
5. **Check the data path.** Is data getting in? Is it getting out?

### Quick Diagnostic Commands

```bash
# Are containers running and healthy?
docker compose ps

# What's in the logs? (last 100 lines, errors only)
docker compose logs --tail=100 2>&1 | grep -i error

# Resource usage (CPU, memory)
docker stats --no-stream

# Disk usage
docker system df -v

# Is the collector receiving data?
curl -s http://localhost:8888/metrics | grep otelcol_receiver_accepted

# Is the collector exporting data?
curl -s http://localhost:8888/metrics | grep otelcol_exporter_sent
```

## Common Issues

### "OTel Collector keeps restarting"

**Symptom:** The collector container restarts every few minutes.

**Likely cause:** Out of memory (OOM killed).

**Diagnosis:**
```bash
docker stats otel-collector --no-stream
docker inspect otel-collector | grep -i oom
docker compose logs otel-collector | tail -50
```

**Fix:** The collector is receiving more data than it can handle with current memory limits. Options:

1. **Increase memory limits** in docker-compose.yml and otel-collector.yaml:
   ```yaml
   # docker-compose.yml
   deploy:
     resources:
       limits:
         memory: 4G  # Was 2G
   
   # otel-collector.yaml
   processors:
     memory_limiter:
       limit_mib: 3200  # Was 1600
   ```

2. **Enable sampling** to reduce data volume (see Architecture doc for sampling strategies)

3. **Add more collectors** (Phase 2)

### "Data not appearing in Grafana"

**Symptom:** Dashboards show "No data" even though applications are sending telemetry.

**Diagnosis:** Work through the data path:

```bash
# 1. Is the collector receiving data?
curl -s http://localhost:8888/metrics | grep otelcol_receiver_accepted
# Should show non-zero counts

# 2. Is the collector exporting successfully?
curl -s http://localhost:8888/metrics | grep otelcol_exporter_sent
# Should show non-zero counts, no errors

# 3. Is data in the backends?
# For traces:
curl http://localhost:16686/api/services
# Should list services

# For metrics:
curl 'http://localhost:9090/api/v1/query?query=up'
# Should show metric values
```

**Common causes:**
- Application isn't actually sending data (check application logs)
- Wrong endpoint in application configuration
- Collector can't reach backends (network issue)
- Time range in Grafana is wrong (check the time picker)

### "Jaeger queries are slow"

**Symptom:** Searching for traces takes 10+ seconds or times out.

**Likely cause:** Too much data, storage can't keep up.

**Diagnosis:**
```bash
# Check storage size
docker compose exec jaeger du -sh /badger

# Check Jaeger metrics
curl -s http://localhost:14269/metrics | grep jaeger_query
```

**Fix:**
1. **Reduce retention:**
   ```yaml
   environment:
     - BADGER_SPAN_STORE_TTL=168h  # 7 days instead of 30
   ```

2. **Enable sampling** in the collector to reduce trace volume

3. **Move to Phase 2** with Tempo (uses object storage, handles more data)

### "Loki 'rate limit exceeded'"

**Symptom:** Collector logs show Loki rejecting data with rate limit errors.

**Diagnosis:**
```bash
docker compose logs loki | grep -i "rate\|limit"
curl -s http://localhost:3100/metrics | grep loki_distributor_ingester
```

**Fix:** Increase limits in `configs/loki.yaml`:
```yaml
limits_config:
  ingestion_rate_mb: 20       # Was 10
  ingestion_burst_size_mb: 40 # Was 20
```

Then restart Loki: `docker compose restart loki`

### "Can't connect to backends"

**Symptom:** Collector logs show "connection refused" or similar errors.

**Diagnosis:**
```bash
# Test connectivity from collector container
docker compose exec otel-collector wget -q -O- http://jaeger:14269/
docker compose exec otel-collector wget -q -O- http://prometheus:9090/-/healthy
docker compose exec otel-collector wget -q -O- http://loki:3100/ready

# Check if backends are on the same network
docker network inspect observability
```

**Common causes:**
- Service name mismatch (config says "jaeger" but service is named "tracing")
- Backends not healthy yet (check `depends_on` conditions)
- Not on the same Docker network

---

## Phase 2 Specific Issues

### "Kafka not starting (KRaft mode)"

**Symptom:** Kafka container fails to start or keeps restarting.

**Diagnosis:**
```bash
docker compose -f docker-compose-scalable.yaml logs kafka | tail -50
```

**Common causes and fixes:**
1. **Insufficient memory:** Kafka needs at least 2GB. Check `docker stats kafka`.
2. **Corrupt KRaft metadata:** If you changed the cluster ID, delete the volume:
   ```bash
   docker compose -f docker-compose-scalable.yaml down
   docker volume rm otel-scalable-kafka
   docker compose -f docker-compose-scalable.yaml up -d
   ```

### "Consumer lag keeps growing"

**Symptom:** Data is being produced to Kafka but not consumed fast enough.

**Diagnosis:**
```bash
# Check consumer group lag
docker compose -f docker-compose-scalable.yaml exec kafka \
  kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group otel-trace-processors
```

**Fix:** Scale up processors:
```bash
docker compose -f docker-compose-scalable.yaml up -d --scale otel-processor=4
```

### "HAProxy shows all backends down"

**Symptom:** Stats page (`:8404/stats`) shows red for all gateways.

**Diagnosis:**
```bash
# Check if gateways are running
docker compose -f docker-compose-scalable.yaml ps | grep gateway

# Check gateway health directly
curl http://localhost:13133/health  # Won't work - internal only
docker compose -f docker-compose-scalable.yaml exec otel-gateway-1 \
  wget -qO- http://localhost:13133/health
```

**Common causes:**
- Gateways not started yet (Kafka must be healthy first)
- Network misconfiguration

---

## Kubernetes Specific Issues

### "Pods stuck in Pending"

**Symptom:** Pods won't start, stay in Pending state.

**Diagnosis:**
```bash
kubectl describe pod <pod-name> -n observability
```

**Common causes:**
1. **Insufficient resources:** Check node capacity:
   ```bash
   kubectl describe nodes | grep -A 5 "Allocated resources"
   ```
2. **PVC not binding:** Check storage class:
   ```bash
   kubectl get pvc -n observability
   kubectl get storageclass
   ```
3. **Node selector/taints:** Check if pods can schedule:
   ```bash
   kubectl get nodes --show-labels
   ```

### "Init container failing"

**Symptom:** Pods in `Init:Error` or `Init:CrashLoopBackOff` state.

**Diagnosis:**
```bash
# Check init container logs
kubectl logs <pod-name> -n observability -c config-init

# Check if secrets exist
kubectl get secret tempo-s3-credentials -n observability
kubectl get secret mimir-s3-credentials -n observability
kubectl get secret loki-s3-credentials -n observability
```

**Common causes:**
1. **Secret not created:** Create the required secrets (see credentials section above)
2. **Wrong secret keys:** Verify the secret has `access-key` and `secret-key` keys
3. **ConfigMap not mounted:** Check the pod spec for volume mount issues

### "S3 connection errors in backends"

**Symptom:** Tempo/Mimir/Loki can't write to S3/MinIO.

**Diagnosis:**
```bash
kubectl logs tempo-0 -n observability | grep -i "s3\|error"
kubectl logs mimir-0 -n observability | grep -i "s3\|error"
kubectl logs loki-0 -n observability | grep -i "s3\|error"
```

**Common causes:**
1. **MinIO not ready:** Check MinIO pods:
   ```bash
   kubectl get pods -n minio
   kubectl logs minio-0 -n minio
   ```
2. **Buckets not created:** MinIO init job should create them:
   ```bash
   kubectl logs -l app=minio-init -n minio
   ```
3. **Wrong credentials:** Verify credentials match between secrets
4. **Wrong endpoint:** Should be `minio.minio.svc.cluster.local:9000`

### "Kafka topics not created (Strimzi)"

**Symptom:** Processors can't consume - topics don't exist.

**Diagnosis:**
```bash
kubectl get kafkatopic -n kafka
kubectl describe kafkatopic otlp-traces -n kafka
```

**Fix:** Ensure Kafka cluster is ready:
```bash
kubectl get kafka -n kafka
kubectl wait kafka/otel-kafka --for=condition=Ready -n kafka --timeout=600s
```

---

## Getting Help

If you're stuck:

1. **Check the logs carefully.** The answer is usually there.
2. **Search the error message.** Someone has probably hit this before.
3. **Check the component's GitHub issues.** Known bugs are often documented.
4. **Ask with context.** Include logs, configuration, and what you've already tried.

---

## What's Next

Once your stack is stable:

1. **Set up alerting** - Configure alerts for error rates, latency, and resource usage
2. **Create dashboards** - Build dashboards for your specific services
3. **Document runbooks** - Write down how to handle common issues
4. **Test backups** - Actually restore from a backup to make sure it works
5. **Plan for growth** - Monitor capacity and plan Phase 2 before you need it

For architecture details and design decisions, see the [Architecture Overview](./architecture.md).

---

## Quick Reference

### Port Reference

| Service | Port | Purpose |
|---------|------|---------|
| **OTLP gRPC** | 4317 | Primary telemetry ingestion |
| **OTLP HTTP** | 4318 | Alternative telemetry ingestion |
| **Grafana** | 3000 | Visualization UI |
| **Prometheus** | 9090 | Metrics query UI |
| **Tempo** | 3200 | Trace query API |
| **Loki** | 3100 | Log query API |
| **Mimir** | 9009 | Metrics storage API |
| **Jaeger** | 16686 | Legacy trace UI (Phase 1) |
| **Kafka** | 9092 | Message broker (Phase 2) |
| **HAProxy Stats** | 8404 | Load balancer stats (Phase 2) |
| **Collector Metrics** | 8888 | Collector self-metrics |
| **Collector Health** | 13133 | Health check endpoint |

### Key Metrics to Monitor

```promql
# Collector receiving data?
otelcol_receiver_accepted_spans{receiver="otlp"}
otelcol_receiver_accepted_metric_points{receiver="otlp"}
otelcol_receiver_accepted_log_records{receiver="otlp"}

# Collector exporting successfully?
otelcol_exporter_sent_spans
otelcol_exporter_send_failed_spans

# Queue backing up?
otelcol_exporter_queue_size
otelcol_exporter_queue_capacity

# Memory pressure?
otelcol_processor_memory_limiter_refused_spans
```

### Common Commands

```bash
# Phase 1 - Start/Stop
docker compose up -d
docker compose down

# Phase 2 - Start/Stop
docker compose -f docker-compose-scalable.yaml up -d
docker compose -f docker-compose-scalable.yaml down

# Phase 2 - Scale collectors
docker compose -f docker-compose-scalable.yaml up -d --scale otel-gateway=3 --scale otel-processor=3

# Watch logs
docker compose logs -f otel-collector
docker compose -f docker-compose-scalable.yaml logs -f otel-gateway

# Check health
./scripts/health-check.sh
./scripts/health-check.sh --json

# Backup
./scripts/backup.sh
BACKUP_DIR=/mnt/backups ./scripts/backup.sh

# Kubernetes - Check status
kubectl get pods -n observability
kubectl get hpa -n observability
kubectl logs -f deploy/otel-gateway -n observability
```

### File Locations (After Ansible Deployment)

| Path | Contents |
|------|----------|
| `/opt/observability/` | Main installation |
| `/opt/observability/docker-compose.yaml` | Deployment file |
| `/opt/observability/backups/` | Backup archives |
| `/opt/observability/logs/` | Log files |
| `/var/lib/docker/volumes/otel-*` | Docker volumes |

### Environment Variables for Applications

```bash
# Basic configuration
OTEL_SERVICE_NAME=your-service-name
OTEL_EXPORTER_OTLP_ENDPOINT=http://collector-host:4317
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production

# Optional: Use HTTP instead of gRPC
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_EXPORTER_OTLP_ENDPOINT=http://collector-host:4318

# Optional: Set sampling
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1  # 10% sampling
```

---

## Summary: Choosing Your Path

| Scenario | Recommended Phase | Key Files |
|----------|-------------------|-----------|
| **Learning/Development** | Phase 1 | `docker-compose-single.yaml`, `otel-collector.yaml` |
| **Small production (<50K eps)** | Phase 1 | Same as above |
| **Medium production** | Phase 2 | `docker-compose-scalable.yaml`, `otel-gateway.yaml`, `otel-processor.yaml` |
| **Kubernetes org** | Phase 3 | All `kubernetes/*.yaml` files |
| **AWS production** | Phase 4 + 3 | `terraform/` + `kubernetes/` |
| **VM automation** | Ansible | `ansible/playbook.yml` |

**Remember:** Start simple, scale when needed. Most teams run Phase 1 successfully for years.
