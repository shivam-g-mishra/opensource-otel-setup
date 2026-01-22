# Scalable Observability Stack - Configuration Files

This directory contains all configuration files needed to deploy the scalable observability platform.

## Directory Structure

```
configs/
├── docker/                         # Docker Compose deployments
│   ├── docker-compose-single.yaml  # Phase 1: Single-node setup
│   ├── docker-compose-scalable.yaml # Phase 2: Multi-node with Kafka
│   ├── otel-collector.yaml         # Single collector config
│   ├── otel-gateway.yaml           # Gateway collector config
│   ├── otel-processor.yaml         # Processor collector config
│   ├── haproxy.cfg                 # Load balancer config
│   ├── tempo.yaml                  # Tempo trace storage config
│   ├── mimir.yaml                  # Mimir metrics storage config
│   ├── mimir-runtime.yaml          # Mimir runtime overrides
│   ├── loki.yaml                   # Loki log storage config
│   ├── prometheus.yml              # Prometheus stack monitoring
│   ├── alertmanager-fallback.yaml  # Default alertmanager config
│   ├── grafana/                    # Grafana provisioning
│   │   └── provisioning/
│   │       ├── datasources/
│   │       │   └── datasources.yaml
│   │       └── dashboards/
│   │           └── dashboards.yaml
│   └── prometheus/
│       └── rules/
│           └── otel-stack-alerts.yml
│
├── kubernetes/                     # Kubernetes manifests (Phase 3)
│   ├── namespace.yaml              # Observability namespace
│   ├── otel-gateway.yaml           # Gateway deployment + HPA + PDB
│   ├── otel-processor.yaml         # Processor deployment + HPA + PDB
│   ├── kafka-cluster.yaml          # Strimzi Kafka cluster
│   ├── minio.yaml                  # MinIO object storage
│   ├── tempo.yaml                  # Tempo StatefulSet
│   ├── mimir.yaml                  # Mimir StatefulSet
│   ├── loki.yaml                   # Loki StatefulSet
│   ├── grafana.yaml                # Grafana deployment + Ingress
│   ├── postgresql.yaml             # PostgreSQL for Grafana HA
│   └── prometheus.yaml             # Prometheus for stack monitoring
│
└── scripts/                        # Operational scripts
    ├── backup.sh                   # Backup all volumes
    ├── restore.sh                  # Restore from backup
    └── health-check.sh             # Check stack health
```

## Quick Start

### Phase 1: Single-Node Docker

```bash
cd docker
docker compose -f docker-compose-single.yaml up -d
```

Access:
- Grafana: http://localhost:3000 (admin/admin)
- Jaeger: http://localhost:16686
- Prometheus: http://localhost:9090

### Phase 2: Scalable Docker with Kafka

```bash
cd docker
docker compose -f docker-compose-scalable.yaml up -d

# Scale gateways and processors
docker compose -f docker-compose-scalable.yaml up -d --scale otel-gateway=3 --scale otel-processor=3
```

Access:
- Grafana: http://localhost:3000 (admin/admin)
- HAProxy Stats: http://localhost:8404/stats
- Tempo: http://localhost:3200
- Mimir: http://localhost:9009
- Loki: http://localhost:3100
- Prometheus: http://localhost:9090

### Phase 3: Kubernetes

```bash
cd kubernetes

# 1. Create namespaces
kubectl apply -f namespace.yaml
kubectl create namespace kafka
kubectl create namespace minio

# 2. Install Strimzi Kafka Operator
kubectl apply -f 'https://strimzi.io/install/latest?namespace=kafka'

# 3. Deploy in order
kubectl apply -f minio.yaml
kubectl apply -f kafka-cluster.yaml
# Wait for Kafka to be ready
kubectl wait kafka/otel-kafka --for=condition=Ready --timeout=300s -n kafka

kubectl apply -f tempo.yaml
kubectl apply -f mimir.yaml
kubectl apply -f loki.yaml
kubectl apply -f prometheus.yaml
kubectl apply -f postgresql.yaml
kubectl apply -f grafana.yaml
kubectl apply -f otel-gateway.yaml
kubectl apply -f otel-processor.yaml
```

## Component Overview

| Component | Purpose | Docker Port | K8s Service |
|-----------|---------|-------------|-------------|
| HAProxy | Load balancer | 4317, 4318, 8404 | - |
| OTel Gateway | Receive telemetry | - | otel-gateway:4317 |
| OTel Processor | Process & export | - | otel-processor:8888 |
| Kafka | Message queue | 9092 | kafka-bootstrap:9092 |
| Tempo | Trace storage | 3200 | tempo:3200 |
| Mimir | Metrics storage | 9009 | mimir:9009 |
| Loki | Log storage | 3100 | loki:3100 |
| Prometheus | Stack monitoring | 9090 | prometheus:9090 |
| Grafana | Visualization | 3000 | grafana:3000 |
| MinIO | Object storage | - | minio:9000 |
| PostgreSQL | Grafana HA state | - | postgresql:5432 |

## Configuration Customization

### Credentials (CHANGE IN PRODUCTION)

Docker:
- Grafana: `admin/admin` (set in docker-compose)

Kubernetes:
- MinIO: `minio-credentials` secret
- Grafana: `grafana-credentials` secret
- PostgreSQL: `postgresql-credentials` secret
- S3 access: `tempo-s3-credentials`, `mimir-s3-credentials`, `loki-s3-credentials`

### Storage Classes

Kubernetes manifests use `storageClassName: standard`. Update to your cluster's storage class:
- GKE: `standard-rwo` or `premium-rwo`
- EKS: `gp2` or `gp3`
- AKS: `managed-premium`

### Resource Limits

All manifests include resource requests and limits. Adjust based on your workload:
- Gateway: CPU-bound, scale horizontally for throughput
- Processor: Memory-bound (tail sampling), scale for trace volume
- Storage backends: IO-bound, scale storage and memory for retention

## Monitoring the Stack

The stack monitors itself using Prometheus. Key metrics to watch:

```promql
# OTel Collector health
up{job=~"otel-.*"}

# Export queue size (should stay low)
otelcol_exporter_queue_size

# Export failures (should be zero)
rate(otelcol_exporter_send_failed_spans_total[5m])

# Kafka consumer lag
kafka_consumergroup_lag_sum
```

Pre-configured alerts are in:
- Docker: `prometheus/rules/otel-stack-alerts.yml`
- Kubernetes: `prometheus-config` ConfigMap

## Backup and Recovery

### Docker

```bash
# Backup
./scripts/backup.sh

# Restore
./scripts/restore.sh /path/to/backup/20240115_120000
```

### Kubernetes

```bash
# Backup PVCs using velero or similar tool
velero backup create observability-backup --include-namespaces observability,kafka,minio

# Restore
velero restore create --from-backup observability-backup
```

## Troubleshooting

### Common Issues

1. **Kafka not starting**
   ```bash
   # Check Kafka logs
   kubectl logs -n kafka otel-kafka-kafka-0
   # Ensure Strimzi operator is running
   kubectl get pods -n kafka
   ```

2. **MinIO buckets not created**
   ```bash
   # Run bucket creation job manually
   kubectl delete job minio-create-buckets -n minio
   kubectl apply -f minio.yaml
   ```

3. **Collectors not connecting to backends**
   ```bash
   # Check collector logs
   kubectl logs -l app=otel-processor -n observability
   # Verify service DNS resolution
   kubectl run test --rm -it --image=busybox -- nslookup tempo.observability.svc.cluster.local
   ```

4. **Grafana datasource errors**
   ```bash
   # Test datasource connectivity from Grafana pod
   kubectl exec -it deploy/grafana -n observability -- wget -qO- http://mimir:9009/ready
   ```

## Related Documentation

- [Architecture Overview](../architecture.md) - Design concepts and decisions
- [Implementation Guide](../implementation-guide.md) - Step-by-step deployment
- [Main README](../../../README.md) - Project overview
