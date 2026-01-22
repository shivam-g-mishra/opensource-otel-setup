# Scalable OpenTelemetry Stack

## Implementation Guide

**Version:** 1.0  
**Date:** January 2026

---

## What You Will Build

This guide walks you through implementing a **scalable, highly-available observability stack** using OpenTelemetry. By the end, you will have:

- Load-balanced telemetry ingestion (no single point of failure)
- Kafka message queue for durability and spike handling
- Horizontally scalable processing
- Production-grade storage backends (Tempo, Mimir, Loki)
- High-availability Grafana

**Prerequisites**: Familiarity with Docker, basic understanding of observability concepts. For architecture background, see [Architecture Overview](./architecture.md).

---

## Implementation Phases

| Phase | What You Get | Time |
|-------|--------------|------|
| [Phase 1](#phase-1-optimized-single-node) | Reliable single-node setup | 30 min |
| [Phase 2](#phase-2-add-message-queue) | Kafka + gateway/processor split | 1 hour |
| [Phase 3](#phase-3-kubernetes-deployment) | K8s deployment with auto-scaling | 2 hours |
| [Phase 4](#phase-4-advanced-storage) | Tempo, Mimir, object storage | 2 hours |

**Start with Phase 1** and progress as your needs grow.

---

## Phase 1: Optimized Single-Node

### Goal

A production-ready single-node setup with:
- Persistent queues (no data loss on restart)
- Resource limits (prevent OOM)
- Health checks (auto-recovery)
- Automated backups

### Step 1.1: Create Directory Structure

```bash
mkdir -p otel-stack/{configs,data,backups,scripts}
cd otel-stack
```

### Step 1.2: Configure OTel Collector with Persistence

Create the collector config with persistent queues.

**File**: `configs/otel-collector.yaml`

```yaml
# See full file: configs/docker/otel-collector.yaml

extensions:
  health_check:
    endpoint: 0.0.0.0:13133
  file_storage:
    directory: /var/lib/otelcol/storage
    timeout: 10s

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 5s
    send_batch_size: 10000
  memory_limiter:
    check_interval: 1s
    limit_mib: 1600
    spike_limit_mib: 400

exporters:
  otlp/jaeger:
    endpoint: jaeger:4317
    tls:
      insecure: true
    sending_queue:
      enabled: true
      storage: file_storage  # Persist to disk
    retry_on_failure:
      enabled: true
      max_elapsed_time: 300s

service:
  extensions: [health_check, file_storage]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlp/jaeger]
```

> **Full file**: [configs/docker/otel-collector.yaml](./configs/docker/otel-collector.yaml)

### Step 1.3: Create Docker Compose with Resource Limits

**File**: `docker-compose.yml`

```yaml
# See full file: configs/docker/docker-compose-single.yaml

services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.91.0
    volumes:
      - ./configs/otel-collector.yaml:/etc/otelcol/config.yaml:ro
      - otel-storage:/var/lib/otelcol
    ports:
      - "4317:4317"   # OTLP gRPC
      - "4318:4318"   # OTLP HTTP
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:13133/health"]
      interval: 10s
      retries: 5
    restart: unless-stopped

volumes:
  otel-storage:
```

> **Full file**: [configs/docker/docker-compose-single.yaml](./configs/docker/docker-compose-single.yaml)

### Step 1.4: Add Backup Script

**File**: `scripts/backup.sh`

```bash
#!/bin/bash
# Backup all data volumes
# See full file: configs/scripts/backup.sh

BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR/$TIMESTAMP"

for volume in prometheus-data grafana-data loki-data jaeger-data otel-storage; do
  docker run --rm \
    -v "${volume}:/source:ro" \
    -v "$BACKUP_DIR/$TIMESTAMP:/backup" \
    alpine tar czf "/backup/${volume}.tar.gz" -C /source .
done

echo "Backup complete: $BACKUP_DIR/$TIMESTAMP"
```

> **Full file**: [configs/scripts/backup.sh](./configs/scripts/backup.sh)

### Step 1.5: Start the Stack

```bash
docker compose up -d
```

### Step 1.6: Verify Health

```bash
# Check all services are healthy
docker compose ps

# Test collector endpoint
curl -s http://localhost:13133/health
```

### Phase 1 Checklist

- [ ] Collector has persistent storage volume
- [ ] All services have resource limits
- [ ] Health checks configured
- [ ] Backup script created and tested
- [ ] Stack starts without errors

---

## Phase 2: Add Message Queue

### Goal

Add Kafka to decouple ingestion from processing:
- Survive backend outages
- Handle traffic spikes
- Enable replay capability

### Architecture After Phase 2

```
Apps → [Gateway Collectors] → [Kafka] → [Processor Collectors] → Backends
```

### Step 2.1: Add Kafka to Docker Compose

**File**: `docker-compose.yml` (add to existing)

```yaml
# See full file: configs/docker/docker-compose-kafka.yaml

services:
  kafka:
    image: bitnami/kafka:3.6
    environment:
      - KAFKA_CFG_NODE_ID=0
      - KAFKA_CFG_PROCESS_ROLES=controller,broker
      - KAFKA_CFG_CONTROLLER_QUORUM_VOTERS=0@kafka:9093
      - KAFKA_CFG_LISTENERS=PLAINTEXT://:9092,CONTROLLER://:9093
      - KAFKA_CFG_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092
      - KAFKA_CFG_CONTROLLER_LISTENER_NAMES=CONTROLLER
    volumes:
      - kafka-data:/bitnami/kafka
    healthcheck:
      test: kafka-topics.sh --bootstrap-server localhost:9092 --list
      interval: 30s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G

volumes:
  kafka-data:
```

### Step 2.2: Create Gateway Collector Config

The gateway receives telemetry and forwards to Kafka.

**File**: `configs/otel-gateway.yaml`

```yaml
# See full file: configs/docker/otel-gateway.yaml

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 1s
    send_batch_size: 5000

exporters:
  kafka:
    brokers:
      - kafka:9092
    protocol_version: 3.0.0
    topic: otel-traces
    encoding: otlp_proto

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [kafka]
```

> **Full file**: [configs/docker/otel-gateway.yaml](./configs/docker/otel-gateway.yaml)

### Step 2.3: Create Processor Collector Config

The processor consumes from Kafka and writes to backends.

**File**: `configs/otel-processor.yaml`

```yaml
# See full file: configs/docker/otel-processor.yaml

receivers:
  kafka:
    brokers:
      - kafka:9092
    topic: otel-traces
    protocol_version: 3.0.0
    encoding: otlp_proto
    group_id: otel-processor

processors:
  batch:
    timeout: 5s
    send_batch_size: 10000
  memory_limiter:
    limit_mib: 1600

exporters:
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true

service:
  pipelines:
    traces:
      receivers: [kafka]
      processors: [memory_limiter, batch]
      exporters: [otlp/tempo]
```

> **Full file**: [configs/docker/otel-processor.yaml](./configs/docker/otel-processor.yaml)

### Step 2.4: Update Docker Compose

```yaml
# See full file: configs/docker/docker-compose-scalable.yaml

services:
  otel-gateway:
    image: otel/opentelemetry-collector-contrib:0.91.0
    command: ["--config=/etc/otelcol/config.yaml"]
    volumes:
      - ./configs/otel-gateway.yaml:/etc/otelcol/config.yaml:ro
    ports:
      - "4317:4317"
      - "4318:4318"
    depends_on:
      kafka:
        condition: service_healthy
    deploy:
      replicas: 2  # Multiple gateways

  otel-processor:
    image: otel/opentelemetry-collector-contrib:0.91.0
    command: ["--config=/etc/otelcol/config.yaml"]
    volumes:
      - ./configs/otel-processor.yaml:/etc/otelcol/config.yaml:ro
    depends_on:
      kafka:
        condition: service_healthy
    deploy:
      replicas: 2  # Multiple processors
```

### Step 2.5: Add Load Balancer

**File**: `configs/haproxy.cfg`

```
# See full file: configs/docker/haproxy.cfg

frontend otel_grpc
    bind *:4317
    mode tcp
    default_backend otel_gateways_grpc

backend otel_gateways_grpc
    mode tcp
    balance roundrobin
    server gateway1 otel-gateway-1:4317 check
    server gateway2 otel-gateway-2:4317 check
```

> **Full file**: [configs/docker/haproxy.cfg](./configs/docker/haproxy.cfg)

### Step 2.6: Deploy and Verify

```bash
# Start everything
docker compose up -d

# Verify Kafka topics created
docker compose exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --list

# Check consumer lag
docker compose exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group otel-processor
```

### Phase 2 Checklist

- [ ] Kafka running with persistent storage
- [ ] Gateway collectors publishing to Kafka
- [ ] Processor collectors consuming from Kafka
- [ ] Load balancer distributing traffic
- [ ] Can restart processors without data loss

---

## Phase 3: Kubernetes Deployment

### Goal

Deploy to Kubernetes with:
- Horizontal Pod Autoscaler (HPA)
- Pod Disruption Budgets (PDB)
- ConfigMaps for configuration
- Proper resource requests/limits

### Step 3.1: Create Namespace

```bash
kubectl create namespace observability
```

### Step 3.2: Deploy OTel Collector Gateway

**File**: `kubernetes/otel-gateway.yaml`

```yaml
# See full file: configs/kubernetes/otel-gateway.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: otel-gateway
  namespace: observability
spec:
  replicas: 3
  selector:
    matchLabels:
      app: otel-gateway
  template:
    metadata:
      labels:
        app: otel-gateway
    spec:
      containers:
      - name: collector
        image: otel/opentelemetry-collector-contrib:0.91.0
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "2"
            memory: "2Gi"
        ports:
        - containerPort: 4317
        - containerPort: 4318
        livenessProbe:
          httpGet:
            path: /health
            port: 13133
---
apiVersion: v1
kind: Service
metadata:
  name: otel-gateway
  namespace: observability
spec:
  type: LoadBalancer
  ports:
  - name: grpc
    port: 4317
  - name: http
    port: 4318
  selector:
    app: otel-gateway
```

> **Full file**: [configs/kubernetes/otel-gateway.yaml](./configs/kubernetes/otel-gateway.yaml)

### Step 3.3: Configure Horizontal Pod Autoscaler

**File**: `kubernetes/otel-gateway-hpa.yaml`

```yaml
# See full file: configs/kubernetes/otel-gateway-hpa.yaml

apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: otel-gateway
  namespace: observability
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: otel-gateway
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### Step 3.4: Add Pod Disruption Budget

**File**: `kubernetes/otel-gateway-pdb.yaml`

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: otel-gateway
  namespace: observability
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: otel-gateway
```

### Step 3.5: Deploy Kafka (using Strimzi)

```bash
# Install Strimzi operator
kubectl create namespace kafka
kubectl apply -f 'https://strimzi.io/install/latest?namespace=kafka'

# Deploy Kafka cluster
kubectl apply -f configs/kubernetes/kafka-cluster.yaml
```

> **Full file**: [configs/kubernetes/kafka-cluster.yaml](./configs/kubernetes/kafka-cluster.yaml)

### Step 3.6: Deploy All Components

```bash
# Apply all manifests
kubectl apply -f configs/kubernetes/

# Watch rollout
kubectl -n observability get pods -w
```

### Step 3.7: Verify Deployment

```bash
# Check HPA status
kubectl -n observability get hpa

# Check service endpoints
kubectl -n observability get svc

# Port-forward Grafana
kubectl -n observability port-forward svc/grafana 3000:3000
```

### Phase 3 Checklist

- [ ] All deployments running with 3+ replicas
- [ ] HPA configured and scaling works
- [ ] PDB prevents too many pods going down
- [ ] Services accessible
- [ ] Grafana dashboards loading

---

## Phase 4: Advanced Storage

### Goal

Replace single-node storage with scalable backends:
- Tempo for traces (with S3)
- Mimir for metrics (with S3)
- Loki microservices mode

### Step 4.1: Deploy MinIO (S3-compatible storage)

For on-premises S3-compatible storage:

**File**: `kubernetes/minio.yaml`

```yaml
# See full file: configs/kubernetes/minio.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: observability
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: minio
        image: minio/minio:latest
        args: ["server", "/data", "--console-address", ":9001"]
        env:
        - name: MINIO_ROOT_USER
          value: "admin"
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: minio-secret
              key: password
```

### Step 4.2: Deploy Tempo with S3

**File**: `kubernetes/tempo.yaml`

```yaml
# See full file: configs/kubernetes/tempo.yaml

# Tempo configuration
storage:
  trace:
    backend: s3
    s3:
      bucket: tempo-traces
      endpoint: minio:9000
      access_key: ${S3_ACCESS_KEY}
      secret_key: ${S3_SECRET_KEY}
      insecure: true
```

### Step 4.3: Deploy Mimir

**File**: `kubernetes/mimir.yaml`

```yaml
# See full file: configs/kubernetes/mimir.yaml

# Mimir configuration
blocks_storage:
  backend: s3
  s3:
    bucket_name: mimir-blocks
    endpoint: minio:9000

compactor:
  data_dir: /data/compactor

ruler_storage:
  backend: s3
  s3:
    bucket_name: mimir-ruler
```

### Step 4.4: Configure Prometheus Remote Write

Update Prometheus to write to Mimir:

```yaml
# prometheus.yml
remote_write:
  - url: http://mimir:9009/api/v1/push
```

### Step 4.5: Update Grafana Data Sources

```yaml
# grafana-datasources.yaml
datasources:
  - name: Tempo
    type: tempo
    url: http://tempo:3200
    
  - name: Mimir
    type: prometheus
    url: http://mimir:9009/prometheus
    
  - name: Loki
    type: loki
    url: http://loki:3100
```

### Phase 4 Checklist

- [ ] MinIO/S3 running with buckets created
- [ ] Tempo storing traces in S3
- [ ] Mimir receiving metrics via remote write
- [ ] Loki in microservices mode
- [ ] Grafana querying all data sources

---

## Troubleshooting

### Common Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| **Collector OOM** | Container restarts | Increase memory limit, add sampling |
| **Kafka lag** | Growing consumer lag | Add more processor replicas |
| **Slow queries** | Dashboard timeouts | Add caching, reduce retention |
| **Data gaps** | Missing telemetry | Check queue health, disk space |

### Useful Commands

```bash
# Check collector health
curl http://localhost:13133/health

# View Kafka consumer lag
kafka-consumer-groups.sh --bootstrap-server kafka:9092 \
  --describe --group otel-processor

# Check OTel Collector metrics
curl http://localhost:8888/metrics | grep otelcol

# Verify data in Tempo
curl http://tempo:3200/api/search?q={}
```

### Getting Help

- [OpenTelemetry Docs](https://opentelemetry.io/docs/)
- [Grafana Stack Docs](https://grafana.com/docs/)
- [Project Issues](https://github.com/your-repo/issues)

---

## Configuration Files Reference

All configuration files are in the [configs/](./configs/) directory:

```
configs/
├── docker/
│   ├── docker-compose-single.yaml    # Phase 1: Single-node
│   ├── docker-compose-scalable.yaml  # Phase 2: Multi-node
│   ├── otel-collector.yaml           # Single collector config
│   ├── otel-gateway.yaml             # Gateway collector config
│   ├── otel-processor.yaml           # Processor collector config
│   └── haproxy.cfg                   # Load balancer config
│
├── kubernetes/
│   ├── namespace.yaml
│   ├── otel-gateway.yaml
│   ├── otel-processor.yaml
│   ├── kafka-cluster.yaml
│   ├── tempo.yaml
│   ├── mimir.yaml
│   └── grafana.yaml
│
└── scripts/
    ├── backup.sh
    ├── restore.sh
    └── health-check.sh
```

---

## Next Steps

After completing the phases:

1. **Add alerting rules** - Configure Grafana alerts for SLOs
2. **Set up on-call** - Integrate with PagerDuty/Opsgenie
3. **Tune sampling** - Adjust rates based on actual volume
4. **Document runbooks** - Create ops guides for your team

For architecture details and design decisions, see [Architecture Overview](./architecture.md).
