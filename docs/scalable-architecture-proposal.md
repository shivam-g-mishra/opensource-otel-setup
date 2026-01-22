# Scalable OpenTelemetry Observability Stack
## Architecture Proposal

**Version:** 1.1  
**Date:** January 2026  
**Status:** Proposal

---

## Table of Contents

1. [Single-Node Reliability Improvements](#single-node-reliability-improvements) ⭐ **START HERE**
2. [Current Architecture](#current-architecture-single-node)
3. [Scalable Architecture](#proposed-scalable-architecture)
4. [Deployment Options](#deployment-options)
5. [Implementation Phases](#implementation-phases)

---

## Single-Node Reliability Improvements

Before scaling horizontally, maximize the reliability of your single-node setup. These improvements provide **significant resilience gains with minimal complexity**.

### Quick Wins Summary

| Improvement | Benefit | Effort |
|-------------|---------|--------|
| Persistent queues | No data loss on restart | Low |
| Resource limits | Prevent OOM crashes | Low |
| Health checks + auto-restart | Self-healing | Low |
| Backup automation | Disaster recovery | Low |
| Retry policies | Handle transient failures | Medium |
| Self-monitoring + alerts | Proactive issue detection | Medium |
| Graceful shutdown | Zero data loss on deploy | Medium |

---

### 1. Persistent Queues (Prevent Data Loss)

**Problem**: If OTel Collector restarts, in-flight data in memory queues is lost.

**Solution**: Use the `file_storage` extension to persist queues to disk.

```yaml
# otel-collector-config.yaml - Enhanced with persistent queues

extensions:
  file_storage:
    directory: /var/lib/otelcol/storage
    timeout: 10s
    compaction:
      on_start: true
      on_rebound: true
      directory: /var/lib/otelcol/storage

exporters:
  otlp/jaeger:
    endpoint: jaeger:4317
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 10000
      storage: file_storage    # ← Persist to disk
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
      max_elapsed_time: 300s

  loki:
    endpoint: http://loki:3100/loki/api/v1/push
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 10000
      storage: file_storage    # ← Persist to disk
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s

service:
  extensions: [health_check, file_storage]
  # ... pipelines
```

**Docker Compose change**:
```yaml
otel-collector:
  volumes:
    - ./otel-collector-config.yaml:/etc/otel-collector-config.yaml:ro
    - otel-collector-storage:/var/lib/otelcol/storage  # ← Add persistent volume

volumes:
  otel-collector-storage:
    driver: local
```

**Result**: Data survives collector restarts. Queue replays on startup.

---

### 2. Resource Limits (Prevent OOM & Noisy Neighbors)

**Problem**: Unbounded memory usage can crash containers or affect other services.

**Solution**: Set explicit resource limits in Docker Compose.

```yaml
# docker-compose.yml - With resource limits

services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.91.0
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 512M
    # ... rest of config

  prometheus:
    image: prom/prometheus:v2.48.0
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          cpus: '0.5'
          memory: 1G

  loki:
    image: grafana/loki:2.9.0
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 2G
        reservations:
          cpus: '0.25'
          memory: 512M

  jaeger:
    image: jaegertracing/all-in-one:1.51
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          cpus: '0.5'
          memory: 1G

  grafana:
    image: grafana/grafana:10.2.0
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G
        reservations:
          cpus: '0.25'
          memory: 256M
```

**OTel Collector memory limiter** (already in config, verify values):
```yaml
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 1800        # 90% of container limit (2G)
    spike_limit_mib: 400   # Allow temporary spikes
    limit_percentage: 0    # Disable percentage-based (use MiB)
```

---

### 3. Health Checks & Auto-Restart

**Problem**: Services can become unhealthy without crashing.

**Solution**: Comprehensive health checks with automatic restart.

```yaml
# docker-compose.yml - Enhanced health checks

services:
  otel-collector:
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:13133/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 10s

  prometheus:
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9090/-/healthy"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s

  loki:
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3100/ready"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s

  jaeger:
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:16686"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s

  grafana:
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3000/api/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s
    depends_on:
      prometheus:
        condition: service_healthy
      jaeger:
        condition: service_healthy
      loki:
        condition: service_healthy
```

---

### 4. Graceful Shutdown (Zero Data Loss on Deploy)

**Problem**: Abrupt container stops can lose in-flight data.

**Solution**: Configure proper shutdown handling.

```yaml
# docker-compose.yml - Graceful shutdown

services:
  otel-collector:
    stop_grace_period: 30s  # Wait for queues to flush
    # ...

  prometheus:
    stop_grace_period: 30s
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.enable-lifecycle'  # Enable graceful shutdown endpoint
    # ...

  loki:
    stop_grace_period: 30s
    # ...
```

**Deployment script** (`scripts/deploy.sh`):
```bash
#!/bin/bash
# Zero-downtime deployment script

set -e

echo "Starting graceful deployment..."

# 1. Stop accepting new connections (if using external LB)
# curl -X POST http://lb/drain

# 2. Wait for in-flight requests to complete
echo "Waiting for queues to drain..."
sleep 10

# 3. Gracefully stop services
echo "Stopping services gracefully..."
docker compose stop --timeout 30

# 4. Pull new images
echo "Pulling latest images..."
docker compose pull

# 5. Start services
echo "Starting services..."
docker compose up -d

# 6. Wait for health checks
echo "Waiting for services to be healthy..."
sleep 15

# 7. Verify health
./scripts/status.sh

echo "Deployment complete!"
```

---

### 5. Automated Backups

**Problem**: Data loss from disk failure, corruption, or accidental deletion.

**Solution**: Scheduled backup script for all volumes.

```bash
#!/bin/bash
# scripts/backup.sh - Automated backup script

set -e

BACKUP_DIR="${BACKUP_DIR:-/backups/otel-stack}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

mkdir -p "$BACKUP_PATH"

echo "Starting backup to ${BACKUP_PATH}..."

# Backup each volume
for volume in prometheus-data grafana-data loki-data jaeger-data otel-collector-storage; do
    echo "Backing up ${volume}..."
    docker run --rm \
        -v "${volume}:/source:ro" \
        -v "${BACKUP_PATH}:/backup" \
        alpine tar czf "/backup/${volume}.tar.gz" -C /source .
done

# Backup configurations
echo "Backing up configurations..."
tar czf "${BACKUP_PATH}/configs.tar.gz" \
    docker-compose.yml \
    otel-collector-config.yaml \
    prometheus/ \
    loki/ \
    grafana/

# Calculate backup size
BACKUP_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
echo "Backup complete: ${BACKUP_PATH} (${BACKUP_SIZE})"

# Clean old backups
echo "Cleaning backups older than ${RETENTION_DAYS} days..."
find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -exec rm -rf {} \;

echo "Backup finished successfully!"
```

**Cron job** (`/etc/cron.d/otel-backup`):
```cron
# Daily backup at 2 AM
0 2 * * * root /opt/otel-stack/scripts/backup.sh >> /var/log/otel-backup.log 2>&1
```

**Restore script** (`scripts/restore.sh`):
```bash
#!/bin/bash
# scripts/restore.sh - Restore from backup

set -e

BACKUP_PATH="$1"

if [ -z "$BACKUP_PATH" ]; then
    echo "Usage: $0 <backup_path>"
    echo "Example: $0 /backups/otel-stack/20260122_020000"
    exit 1
fi

echo "WARNING: This will overwrite current data!"
read -p "Are you sure? (yes/no): " confirm
[ "$confirm" = "yes" ] || exit 1

echo "Stopping services..."
docker compose down

echo "Restoring volumes..."
for volume in prometheus-data grafana-data loki-data jaeger-data otel-collector-storage; do
    if [ -f "${BACKUP_PATH}/${volume}.tar.gz" ]; then
        echo "Restoring ${volume}..."
        docker volume rm "${volume}" 2>/dev/null || true
        docker volume create "${volume}"
        docker run --rm \
            -v "${volume}:/dest" \
            -v "${BACKUP_PATH}:/backup:ro" \
            alpine tar xzf "/backup/${volume}.tar.gz" -C /dest
    fi
done

echo "Starting services..."
docker compose up -d

echo "Restore complete!"
```

---

### 6. Self-Monitoring & Alerting

**Problem**: Issues go unnoticed until users complain.

**Solution**: Monitor the monitoring stack itself with alerts.

**Prometheus alerts** (`prometheus/alerts/otel-stack-alerts.yml`):
```yaml
groups:
  - name: otel-stack-reliability
    rules:
      # Collector alerts
      - alert: OTelCollectorDown
        expr: up{job="otel-collector"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "OTel Collector is down"
          
      - alert: OTelCollectorHighMemory
        expr: otelcol_process_memory_rss / 1024 / 1024 > 1600
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "OTel Collector memory usage > 1.6GB"
          
      - alert: OTelCollectorQueueFilling
        expr: otelcol_exporter_queue_size > 5000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "OTel Collector export queue is filling up"
          
      - alert: OTelCollectorDroppedData
        expr: rate(otelcol_processor_dropped_spans[5m]) > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "OTel Collector is dropping spans"

      - alert: OTelCollectorExportFailures
        expr: rate(otelcol_exporter_send_failed_spans[5m]) > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "OTel Collector failing to export spans"

      # Storage alerts
      - alert: PrometheusHighMemory
        expr: process_resident_memory_bytes{job="prometheus"} / 1024 / 1024 / 1024 > 3
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Prometheus memory usage > 3GB"

      - alert: LokiIngestionErrors
        expr: rate(loki_distributor_ingester_append_failures_total[5m]) > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Loki ingestion failures detected"

      - alert: JaegerStorageFull
        expr: jaeger_badger_lsm_size_bytes / 1024 / 1024 / 1024 > 50
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Jaeger storage > 50GB"

      # Disk alerts
      - alert: HighDiskUsage
        expr: (node_filesystem_size_bytes - node_filesystem_free_bytes) / node_filesystem_size_bytes > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk usage > 85%"

      - alert: CriticalDiskUsage
        expr: (node_filesystem_size_bytes - node_filesystem_free_bytes) / node_filesystem_size_bytes > 0.95
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Disk usage > 95%"
```

**Update Prometheus config** (`prometheus/prometheus.yml`):
```yaml
# Add alerting rules
rule_files:
  - /etc/prometheus/alerts/*.yml

# Optional: Add Alertmanager
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          # - alertmanager:9093
```

---

### 7. Enhanced Retry Policies

**Problem**: Transient network issues cause data loss.

**Solution**: Comprehensive retry configuration with exponential backoff.

```yaml
# otel-collector-config.yaml - Enhanced retry policies

exporters:
  otlp/jaeger:
    endpoint: jaeger:4317
    tls:
      insecure: true
    timeout: 30s
    retry_on_failure:
      enabled: true
      initial_interval: 1s      # Start with 1s
      randomization_factor: 0.5 # Add jitter
      multiplier: 2             # Double each retry
      max_interval: 60s         # Cap at 60s
      max_elapsed_time: 300s    # Give up after 5 min
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 10000
      storage: file_storage

  prometheus:
    endpoint: "0.0.0.0:8889"
    # Prometheus exporter doesn't need retry (it's pull-based)

  loki:
    endpoint: http://loki:3100/loki/api/v1/push
    timeout: 30s
    retry_on_failure:
      enabled: true
      initial_interval: 1s
      randomization_factor: 0.5
      multiplier: 2
      max_interval: 60s
      max_elapsed_time: 300s
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 10000
      storage: file_storage
```

---

### 8. Connection Pooling & Keep-Alive

**Problem**: Connection overhead and dropped connections.

**Solution**: Configure persistent connections.

```yaml
# otel-collector-config.yaml - Connection optimization

exporters:
  otlp/jaeger:
    endpoint: jaeger:4317
    tls:
      insecure: true
    keepalive:
      time: 30s
      timeout: 10s
      permit_without_stream: true
    balancer_name: round_robin  # For multiple backends
```

---

### 9. Rate Limiting (Protect Backends)

**Problem**: Traffic spikes can overwhelm storage backends.

**Solution**: Add rate limiting in the collector.

```yaml
# otel-collector-config.yaml - Rate limiting

processors:
  # Existing processors...
  
  # Rate limiter for traces
  probabilistic_sampler:
    sampling_percentage: 100  # Adjust under load (e.g., 50%)
    
  # Alternatively, use tail sampling to keep important traces
  tail_sampling:
    decision_wait: 10s
    num_traces: 50000
    expected_new_traces_per_sec: 1000
    policies:
      # Always keep errors
      - name: errors
        type: status_code
        status_code: {status_codes: [ERROR]}
      # Always keep slow traces
      - name: slow-traces
        type: latency
        latency: {threshold_ms: 1000}
      # Sample the rest
      - name: probabilistic
        type: probabilistic
        probabilistic: {sampling_percentage: 20}
```

---

### 10. Startup Dependencies & Ordering

**Problem**: Services fail if dependencies aren't ready.

**Solution**: Proper dependency ordering with health checks.

```yaml
# docker-compose.yml - Proper startup ordering

services:
  jaeger:
    # No dependencies, starts first
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:16686"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 10s

  prometheus:
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9090/-/healthy"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 15s

  loki:
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3100/ready"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 15s

  otel-collector:
    depends_on:
      jaeger:
        condition: service_healthy
      prometheus:
        condition: service_healthy
      loki:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:13133/health"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 10s

  grafana:
    depends_on:
      prometheus:
        condition: service_healthy
      jaeger:
        condition: service_healthy
      loki:
        condition: service_healthy
```

---

### Single-Node Reliability Checklist

```
□ Persistent queues enabled (file_storage extension)
□ Resource limits set for all containers
□ Health checks configured with start_period
□ Auto-restart enabled (restart: unless-stopped)
□ Graceful shutdown configured (stop_grace_period)
□ Backup script created and scheduled
□ Restore script tested
□ Self-monitoring alerts configured
□ Retry policies with exponential backoff
□ Dependency ordering with health conditions
□ Deploy script for zero-downtime updates
□ Log rotation configured
□ Disk space monitoring enabled
```

---

### Single-Node Capacity Limits

With these improvements, a single-node setup can reliably handle:

| Resource | Recommended Minimum | Expected Throughput |
|----------|---------------------|---------------------|
| CPU | 8 cores | ~50K spans/sec |
| Memory | 16 GB | ~500K active series |
| Disk | 500 GB SSD | ~30 days retention |
| Network | 1 Gbps | ~100 MB/sec ingest |

**When to scale beyond single-node:**
- Sustained > 50K events/sec
- Need for HA (zero downtime)
- Multiple data centers
- Compliance requirements (geographic separation)

---

## Executive Summary

This document proposes an evolution of the OpenTelemetry Observability Stack from a single-node setup to a horizontally scalable, highly available architecture suitable for production workloads of any size.

### Goals
1. **Single-Node Reliability** - Maximize resilience before scaling
2. **Horizontal Scalability** - Handle millions of spans/metrics/logs per second
3. **High Availability** - No single point of failure
4. **Fault Tolerance** - Graceful degradation, no data loss
5. **Multi-Platform** - Docker, Kubernetes, and bare-metal/VPS deployments
6. **Ease of Use** - Simple to deploy and operate

---

## Current Architecture (Single Node)

```
┌─────────────────────────────────────────────────────────────┐
│                     Applications                             │
└─────────────────────────────┬───────────────────────────────┘
                              │ OTLP
                              ▼
                    ┌──────────────────┐
                    │  OTel Collector  │  ← Single point of failure
                    └────────┬─────────┘
           ┌─────────────────┼─────────────────┐
           ▼                 ▼                 ▼
     ┌──────────┐     ┌──────────┐     ┌──────────┐
     │  Jaeger  │     │Prometheus│     │   Loki   │
     │(in-memory)│    │ (single) │     │ (single) │
     └──────────┘     └──────────┘     └──────────┘
```

### Limitations
- Single OTel Collector = bottleneck and SPOF
- In-memory/single-node storage = data loss on restart
- No horizontal scaling
- Limited to ~10K spans/sec, ~100K metrics

---

## Proposed Scalable Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Applications                                    │
│                    (instrumented with OpenTelemetry)                        │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │ OTLP (gRPC/HTTP)
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         INGESTION LAYER                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      Load Balancer (L4/L7)                           │   │
│  │              (HAProxy / NGINX / Cloud LB / K8s Ingress)              │   │
│  └───────────┬─────────────────┬─────────────────┬─────────────────────┘   │
│              ▼                 ▼                 ▼                          │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐                     │
│  │OTel Collector │ │OTel Collector │ │OTel Collector │  ← Horizontally     │
│  │   Gateway 1   │ │   Gateway 2   │ │   Gateway N   │    Scalable         │
│  └───────┬───────┘ └───────┬───────┘ └───────┬───────┘                     │
│          └─────────────────┼─────────────────┘                              │
│                            ▼                                                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          MESSAGE QUEUE LAYER                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        Apache Kafka                                   │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │   │
│  │  │traces-topic │  │metrics-topic│  │ logs-topic  │                  │   │
│  │  │(partitioned)│  │(partitioned)│  │(partitioned)│                  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│         Provides: Buffering, Replay, Decoupling, Back-pressure             │
└─────────────────────────────────────────────────────────────────────────────┘
                                  │
          ┌───────────────────────┼───────────────────────┐
          ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PROCESSING LAYER                                     │
│                    (OTel Collectors - Processing Mode)                       │
│  ┌───────────────┐     ┌───────────────┐     ┌───────────────┐             │
│  │Trace Processor│     │Metric Processor│    │ Log Processor │             │
│  │   Pool (N)    │     │    Pool (N)    │    │   Pool (N)    │             │
│  └───────┬───────┘     └───────┬───────┘     └───────┬───────┘             │
└──────────┼─────────────────────┼─────────────────────┼──────────────────────┘
           ▼                     ▼                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          STORAGE LAYER                                       │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │  Tempo Cluster  │  │  Mimir Cluster  │  │  Loki Cluster   │             │
│  │   (Traces)      │  │   (Metrics)     │  │    (Logs)       │             │
│  │                 │  │                 │  │                 │             │
│  │  ┌───────────┐  │  │  ┌───────────┐  │  │  ┌───────────┐  │             │
│  │  │Distributor│  │  │  │Distributor│  │  │  │Distributor│  │             │
│  │  │  Ingester │  │  │  │  Ingester │  │  │  │  Ingester │  │             │
│  │  │  Querier  │  │  │  │  Querier  │  │  │  │  Querier  │  │             │
│  │  │ Compactor │  │  │  │ Compactor │  │  │  │ Compactor │  │             │
│  │  └───────────┘  │  │  └───────────┘  │  │  └───────────┘  │             │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘             │
│           └────────────────────┼────────────────────┘                       │
│                                ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │              Object Storage (S3 / MinIO / GCS / Azure Blob)          │   │
│  │                        (Long-term retention)                          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        VISUALIZATION LAYER                                   │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    Grafana (HA with shared DB)                        │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐      ┌──────────────────┐    │   │
│  │  │Grafana 1│  │Grafana 2│  │Grafana N│ ───▶ │PostgreSQL/MySQL  │    │   │
│  │  └─────────┘  └─────────┘  └─────────┘      │  (shared state)  │    │   │
│  │           └──────────┬──────────┘           └──────────────────┘    │   │
│  └──────────────────────┼──────────────────────────────────────────────┘   │
└─────────────────────────┼───────────────────────────────────────────────────┘
                          ▼
                    ┌──────────┐
                    │  Users   │
                    └──────────┘
```

---

## Component Deep Dive

### 1. Ingestion Layer

#### Load Balancer
- **Purpose**: Distribute incoming telemetry across collector instances
- **Options**:
  - **Kubernetes**: Use Service (ClusterIP) + Ingress
  - **Docker/VPS**: HAProxy, NGINX, Traefik
  - **Cloud**: AWS ALB/NLB, GCP LB, Azure LB

#### OTel Collector Gateway Pool
- **Role**: Receive, validate, and route telemetry to Kafka
- **Scaling**: Horizontal (add more instances as load increases)
- **Configuration**:
  ```yaml
  # Gateway collector - minimal processing, fast routing
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

  processors:
    memory_limiter:
      limit_mib: 1024
    batch:
      timeout: 1s
      send_batch_size: 10000

  exporters:
    kafka/traces:
      brokers: [kafka:9092]
      topic: otlp-traces
      encoding: otlp_proto
    kafka/metrics:
      brokers: [kafka:9092]
      topic: otlp-metrics
      encoding: otlp_proto
    kafka/logs:
      brokers: [kafka:9092]
      topic: otlp-logs
      encoding: otlp_proto

  service:
    pipelines:
      traces:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [kafka/traces]
      metrics:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [kafka/metrics]
      logs:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [kafka/logs]
  ```

### 2. Message Queue Layer (Kafka)

#### Why Kafka?
| Benefit | Description |
|---------|-------------|
| **Buffering** | Absorbs traffic spikes without data loss |
| **Decoupling** | Backends can be upgraded/restarted without losing data |
| **Replay** | Re-process historical data if needed |
| **Back-pressure** | Natural flow control when backends are slow |
| **Partitioning** | Parallel processing across consumers |
| **Durability** | Data persisted to disk, survives broker restarts |

#### Topic Design
```
otlp-traces     (partitions: 12, replication: 3, retention: 24h)
otlp-metrics    (partitions: 12, replication: 3, retention: 24h)
otlp-logs       (partitions: 12, replication: 3, retention: 24h)
```

#### Kafka Cluster Sizing
| Scale | Brokers | Partitions/Topic | Throughput |
|-------|---------|------------------|------------|
| Small | 3 | 6 | ~100K events/sec |
| Medium | 5 | 12 | ~500K events/sec |
| Large | 9+ | 24+ | 1M+ events/sec |

#### Alternative: Redis Streams (Simpler)
For smaller deployments, Redis Streams can replace Kafka:
- Simpler to operate
- Lower resource requirements
- Good for < 100K events/sec
- Less durable than Kafka

### 3. Processing Layer

#### OTel Collector Processing Pool
- **Role**: Consume from Kafka, apply transformations, export to storage
- **Scaling**: Scale consumers independently per telemetry type
- **Stateless**: Can be scaled up/down freely

```yaml
# Processing collector - consumes from Kafka
receivers:
  kafka/traces:
    brokers: [kafka:9092]
    topic: otlp-traces
    encoding: otlp_proto
    group_id: trace-processors

processors:
  memory_limiter:
    limit_mib: 2048
  batch:
    timeout: 5s
  tail_sampling:  # Only for traces
    decision_wait: 10s
    policies:
      - name: errors
        type: status_code
        status_code: {status_codes: [ERROR]}
      - name: slow-traces
        type: latency
        latency: {threshold_ms: 1000}
      - name: probabilistic
        type: probabilistic
        probabilistic: {sampling_percentage: 10}

exporters:
  otlp/tempo:
    endpoint: tempo-distributor:4317
    tls:
      insecure: true

service:
  pipelines:
    traces:
      receivers: [kafka/traces]
      processors: [memory_limiter, tail_sampling, batch]
      exporters: [otlp/tempo]
```

### 4. Storage Layer

#### Traces: Grafana Tempo

**Why Tempo over Jaeger?**
- Native object storage support (S3, GCS, Azure)
- Simpler architecture (no external database)
- Better Grafana integration
- Cost-effective at scale

**Architecture**:
```
┌─────────────────────────────────────────────┐
│              Tempo Cluster                   │
│  ┌───────────────┐    ┌───────────────┐     │
│  │  Distributor  │───▶│   Ingester    │     │
│  │   (stateless) │    │  (stateful)   │     │
│  └───────────────┘    └───────┬───────┘     │
│                               │              │
│  ┌───────────────┐    ┌───────▼───────┐     │
│  │   Querier     │◀───│   Compactor   │     │
│  │   (stateless) │    │  (stateless)  │     │
│  └───────────────┘    └───────────────┘     │
│           │                   │              │
│           └─────────┬─────────┘              │
│                     ▼                        │
│         ┌───────────────────┐               │
│         │   Object Storage  │               │
│         │   (S3 / MinIO)    │               │
│         └───────────────────┘               │
└─────────────────────────────────────────────┘
```

#### Metrics: Grafana Mimir (or VictoriaMetrics)

**Why Mimir?**
- Horizontally scalable Prometheus
- Multi-tenant support
- Long-term storage in object storage
- 100% Prometheus compatible

**Alternative: VictoriaMetrics**
- Simpler to operate
- Better single-node performance
- Good for medium scale
- Supports clustering

#### Logs: Grafana Loki (Microservices Mode)

**Loki Deployment Modes**:
| Mode | Use Case | Scale |
|------|----------|-------|
| Monolithic | Development | < 100GB/day |
| Simple Scalable | Small-Medium | 100GB-1TB/day |
| Microservices | Large | > 1TB/day |

### 5. Object Storage

All storage backends use object storage for durability:

| Provider | Service | Notes |
|----------|---------|-------|
| AWS | S3 | Most common |
| GCP | GCS | Good performance |
| Azure | Blob Storage | Enterprise |
| Self-hosted | MinIO | S3-compatible |

---

## Deployment Options

### Option 1: Docker Compose (Development/Small)

```
deploy/
├── docker-compose/
│   ├── single-node/         # Current setup (dev)
│   ├── scalable/            # Multi-container scalable
│   └── docker-compose.yml
```

**Best for**: Development, testing, small production (< 50K events/sec)

### Option 2: Kubernetes (Production)

```
deploy/
├── kubernetes/
│   ├── helm/
│   │   └── otel-stack/      # Umbrella Helm chart
│   ├── kustomize/
│   │   ├── base/
│   │   └── overlays/
│   │       ├── development/
│   │       ├── staging/
│   │       └── production/
│   └── manifests/           # Raw YAML (simple)
```

**Helm Chart Dependencies**:
```yaml
# Chart.yaml
dependencies:
  - name: opentelemetry-collector
    repository: https://open-telemetry.github.io/opentelemetry-helm-charts
  - name: kafka
    repository: https://charts.bitnami.com/bitnami
  - name: tempo
    repository: https://grafana.github.io/helm-charts
  - name: mimir-distributed
    repository: https://grafana.github.io/helm-charts
  - name: loki
    repository: https://grafana.github.io/helm-charts
  - name: grafana
    repository: https://grafana.github.io/helm-charts
```

### Option 3: Multi-VPS with Ansible

```
deploy/
├── ansible/
│   ├── inventory/
│   │   ├── development.yml
│   │   ├── staging.yml
│   │   └── production.yml
│   ├── playbooks/
│   │   ├── site.yml
│   │   ├── collectors.yml
│   │   ├── kafka.yml
│   │   ├── storage.yml
│   │   └── grafana.yml
│   └── roles/
│       ├── common/
│       ├── docker/
│       ├── otel-collector/
│       ├── kafka/
│       ├── tempo/
│       ├── mimir/
│       ├── loki/
│       └── grafana/
```

**Inventory Example**:
```yaml
# inventory/production.yml
all:
  children:
    collectors:
      hosts:
        collector-1: {ansible_host: 10.0.1.10}
        collector-2: {ansible_host: 10.0.1.11}
        collector-3: {ansible_host: 10.0.1.12}
    kafka:
      hosts:
        kafka-1: {ansible_host: 10.0.2.10}
        kafka-2: {ansible_host: 10.0.2.11}
        kafka-3: {ansible_host: 10.0.2.12}
    storage:
      hosts:
        storage-1: {ansible_host: 10.0.3.10}
        storage-2: {ansible_host: 10.0.3.11}
    grafana:
      hosts:
        grafana-1: {ansible_host: 10.0.4.10}
        grafana-2: {ansible_host: 10.0.4.11}
```

---

## Fault Tolerance & Error Handling

### Ingestion Layer
| Failure | Handling |
|---------|----------|
| Collector crash | Load balancer routes to healthy instances |
| Collector overload | Memory limiter drops data, alerts fired |
| Network partition | Kafka buffers, retry on reconnect |

### Kafka Layer
| Failure | Handling |
|---------|----------|
| Broker failure | Replication ensures no data loss |
| Consumer lag | Auto-scaling based on lag metrics |
| Disk full | Retention policy deletes old data |

### Storage Layer
| Failure | Handling |
|---------|----------|
| Ingester crash | WAL replay on restart |
| Query timeout | Circuit breaker, cached responses |
| Object storage unavailable | Local cache, retry with backoff |

### Alerting
```yaml
# Example Prometheus alerts
groups:
  - name: otel-stack
    rules:
      - alert: CollectorHighMemory
        expr: otelcol_process_memory_rss > 1e9
        for: 5m
        labels:
          severity: warning
          
      - alert: KafkaConsumerLag
        expr: kafka_consumer_group_lag > 100000
        for: 10m
        labels:
          severity: critical
          
      - alert: TempoIngesterUnhealthy
        expr: tempo_ingester_live_traces == 0
        for: 5m
        labels:
          severity: critical
```

---

## Scaling Guidelines

### When to Scale What

| Symptom | Solution |
|---------|----------|
| High collector CPU | Add more collector instances |
| Kafka consumer lag growing | Add more processing collectors |
| Slow queries | Add more queriers, increase cache |
| Storage growing fast | Adjust retention, add compactors |

### Capacity Planning

| Scale | Events/sec | Collectors | Kafka Brokers | Storage Nodes |
|-------|------------|------------|---------------|---------------|
| Small | < 50K | 2-3 | 3 | 2-3 |
| Medium | 50K-500K | 5-10 | 5 | 5-10 |
| Large | 500K-2M | 20+ | 9+ | 20+ |
| Enterprise | 2M+ | 50+ | 15+ | 50+ |

---

## Migration Path

### Phase 1: Add Kafka (Low Risk)
```
Current → Add Kafka → Collectors write to Kafka
                   → New processors read from Kafka
```

### Phase 2: Migrate Storage (Medium Risk)
```
Jaeger → Tempo (parallel run, then cutover)
Prometheus → Mimir (federation first, then full migration)
Loki single → Loki microservices
```

### Phase 3: Add HA (Low Risk)
```
Single Grafana → HA Grafana with shared DB
Add load balancers
Add monitoring and alerting
```

---

## Proposed Repository Structure

```
opensource-otel-setup/
├── README.md                    # Quick start, links to deployment guides
├── Makefile                     # Common commands
├── docs/
│   ├── getting-started.md      # Simple single-node setup
│   ├── architecture.md         # This document
│   ├── scaling.md              # When and how to scale
│   ├── integrations/           # Language-specific guides
│   │   ├── dotnet.md
│   │   ├── nodejs.md
│   │   ├── python.md
│   │   └── go.md
│   └── operations/
│       ├── monitoring.md       # Monitor the monitors
│       ├── backup-restore.md
│       └── troubleshooting.md
│
├── deploy/
│   ├── docker-compose/
│   │   ├── single-node/        # Current simple setup
│   │   │   ├── docker-compose.yml
│   │   │   └── configs/
│   │   └── scalable/           # Kafka + multiple collectors
│   │       ├── docker-compose.yml
│   │       └── configs/
│   │
│   ├── kubernetes/
│   │   ├── helm/
│   │   │   └── otel-stack/     # Umbrella chart
│   │   ├── kustomize/
│   │   │   ├── base/
│   │   │   └── overlays/
│   │   └── quickstart/         # Simple manifests
│   │
│   └── ansible/
│       ├── inventory/
│       ├── playbooks/
│       └── roles/
│
├── configs/
│   ├── otel-collector/
│   │   ├── gateway.yaml        # Ingestion config
│   │   └── processor.yaml      # Processing config
│   ├── kafka/
│   ├── tempo/
│   ├── mimir/
│   ├── loki/
│   └── grafana/
│
├── dashboards/                  # Grafana dashboards
│   ├── otel-collector.json
│   ├── kafka.json
│   ├── tempo.json
│   ├── mimir.json
│   └── loki.json
│
├── alerts/                      # Prometheus/Grafana alerts
│   ├── collector-alerts.yml
│   ├── kafka-alerts.yml
│   └── storage-alerts.yml
│
└── examples/
    ├── applications/           # Sample instrumented apps
    │   ├── dotnet/
    │   ├── nodejs/
    │   ├── python/
    │   └── go/
    └── load-testing/           # Performance testing
```

---

## Implementation Phases

### Phase 1: Foundation (Current + Improvements)
- [x] Single-node Docker Compose
- [x] Basic OTel Collector
- [x] Jaeger, Prometheus, Loki
- [x] Grafana with dashboards
- [ ] Add comprehensive alerting
- [ ] Add backup/restore scripts

### Phase 2: Scalable Docker Compose
- [ ] Add Kafka (single broker for dev, 3 for prod)
- [ ] Split collectors into gateway + processor
- [ ] Add Redis for caching
- [ ] Document scaling procedures

### Phase 3: Kubernetes Deployment
- [ ] Create Helm umbrella chart
- [ ] Create Kustomize overlays
- [ ] Add HPA configurations
- [ ] Add PodDisruptionBudgets
- [ ] Add NetworkPolicies

### Phase 4: Advanced Storage
- [ ] Replace Jaeger with Tempo
- [ ] Add Mimir or VictoriaMetrics
- [ ] Configure Loki microservices mode
- [ ] Add MinIO for local S3

### Phase 5: Multi-VPS Ansible
- [ ] Create Ansible roles
- [ ] Add inventory templates
- [ ] Add TLS/mTLS configuration
- [ ] Add Consul/etcd for service discovery

---

## Summary

### Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Message Queue | Kafka | Industry standard, proven scale, replay capability |
| Traces | Tempo | Native S3, simpler than Jaeger at scale |
| Metrics | Mimir | Prometheus-compatible, horizontal scale |
| Logs | Loki | Integrates with Grafana, cost-effective |
| Object Storage | S3/MinIO | Durable, cheap, scalable |

### Key Benefits

1. **No Single Points of Failure** - Every layer is redundant
2. **Horizontal Scaling** - Add instances as load grows
3. **Decoupled Components** - Upgrade/restart without data loss
4. **Cost Effective** - Object storage for long-term data
5. **Operationally Simple** - Standard tools, good observability

### Trade-offs

| Benefit | Cost |
|---------|------|
| High availability | More infrastructure |
| Horizontal scale | Operational complexity |
| Data durability | Storage costs |
| Query performance | Memory/cache requirements |

---

## Next Steps

1. **Review and approve this proposal**
2. **Prioritize deployment targets** (K8s vs VPS vs both)
3. **Start with Phase 2** - Add Kafka to existing setup
4. **Create Helm charts** for K8s deployment
5. **Document everything** as we build

---

## Appendix A: Alternative Architectures

### Simpler Scale (No Kafka)

If Kafka complexity is a concern, consider:

```
Apps → OTel Collectors (with persistent queue) → Storage
```

The OTel Collector has a `file_storage` extension that persists the sending queue to disk, providing some resilience without Kafka.

### Cloud-Native (Managed Services)

For teams preferring managed services:

| Component | AWS | GCP | Azure |
|-----------|-----|-----|-------|
| Traces | X-Ray / Managed Jaeger | Cloud Trace | App Insights |
| Metrics | Managed Prometheus | Cloud Monitoring | Azure Monitor |
| Logs | CloudWatch | Cloud Logging | Log Analytics |

OTel Collector can export to any of these.

---

## Appendix B: Resource Requirements

### Minimum Production (50K events/sec)

| Component | Instances | CPU | Memory | Storage |
|-----------|-----------|-----|--------|---------|
| OTel Gateway | 3 | 2 cores | 4 GB | - |
| OTel Processor | 3 | 4 cores | 8 GB | - |
| Kafka | 3 | 4 cores | 8 GB | 500 GB SSD |
| Tempo | 3 | 4 cores | 8 GB | - |
| Mimir | 3 | 4 cores | 16 GB | - |
| Loki | 3 | 4 cores | 8 GB | - |
| MinIO | 3 | 2 cores | 4 GB | 2 TB |
| Grafana | 2 | 2 cores | 4 GB | - |
| **Total** | **23** | **78 cores** | **168 GB** | **~8 TB** |

### Cost Estimate (Cloud)

| Provider | Monthly (Medium Scale) |
|----------|------------------------|
| AWS | $2,000 - $4,000 |
| GCP | $1,800 - $3,500 |
| Self-hosted | $800 - $1,500 (VPS) |

---

*Document prepared for review. Feedback welcome.*
