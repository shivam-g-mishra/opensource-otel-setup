# Scalable OpenTelemetry Observability Stack

This directory contains documentation and configuration files for building a scalable, highly-available observability platform using OpenTelemetry.

## Documents

| Document | Description | Audience |
|----------|-------------|----------|
| [Architecture Overview](./architecture.md) | Design concepts, decisions, requirements | Leadership, Architects |
| [Implementation Guide](./implementation-guide.md) | Step-by-step deployment instructions | Engineers, DevOps |

## Quick Start

**Want to understand the architecture?**  
Start with [Architecture Overview](./architecture.md)

**Ready to implement?**  
Jump to [Implementation Guide](./implementation-guide.md)

## Configuration Files

All configuration files are in the [configs/](./configs/) directory:

```
configs/
├── docker/                         # Docker Compose deployments
│   ├── docker-compose-single.yaml  # Phase 1: Single-node setup
│   ├── docker-compose-scalable.yaml # Phase 2: Multi-node with Kafka
│   ├── otel-collector.yaml         # Single collector config
│   ├── otel-gateway.yaml           # Gateway collector config
│   ├── otel-processor.yaml         # Processor collector config
│   ├── haproxy.cfg                 # Load balancer config
│   ├── tempo.yaml                  # Trace storage config
│   ├── mimir.yaml                  # Metrics storage config
│   ├── loki.yaml                   # Log storage config
│   ├── prometheus.yml              # Stack self-monitoring
│   └── grafana/provisioning/       # Grafana datasources & dashboards
│
├── kubernetes/                     # Kubernetes manifests (Phase 3)
│   ├── namespace.yaml              # Observability namespace
│   ├── otel-gateway.yaml           # Gateway deployment + HPA + PDB
│   ├── otel-processor.yaml         # Processor deployment + HPA + PDB
│   ├── kafka-cluster.yaml          # Strimzi Kafka cluster
│   ├── minio.yaml                  # MinIO object storage
│   ├── tempo.yaml                  # Tempo trace storage
│   ├── mimir.yaml                  # Mimir metrics storage
│   ├── loki.yaml                   # Loki log storage
│   ├── grafana.yaml                # Grafana HA + Ingress
│   ├── postgresql.yaml             # PostgreSQL for Grafana HA
│   └── prometheus.yaml             # Stack self-monitoring
│
└── scripts/                        # Operational scripts
    ├── backup.sh                   # Backup all volumes
    ├── restore.sh                  # Restore from backup
    └── health-check.sh             # Check stack health
```

For detailed configuration documentation, see [configs/README.md](./configs/README.md).

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                         Applications                             │
└─────────────────────────────┬───────────────────────────────────┘
                              │ OTLP
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Layer 1: Ingestion                            │
│    Load Balancer → [Gateway 1] [Gateway 2] [Gateway N]          │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Layer 2: Buffering                            │
│                      Kafka / Redis                               │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Layer 3: Processing                           │
│           [Processor 1] [Processor 2] [Processor N]             │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Layer 4: Storage                              │
│              Tempo (Traces) | Mimir (Metrics) | Loki (Logs)     │
│                          Object Storage (S3)                     │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Layer 5: Visualization                        │
│                         Grafana HA                               │
└─────────────────────────────────────────────────────────────────┘
```

## When to Scale

| Scenario | Recommended Setup |
|----------|-------------------|
| <10K events/sec, Dev/Test | Single-node Docker |
| 10K-50K events/sec | Multi-node + Kafka |
| >50K events/sec or 99.9% SLA | Kubernetes cluster |
| Multi-region requirements | Multiple K8s clusters |

## Cost Comparison

| Events/sec | Self-Hosted | Commercial (Datadog) | Savings |
|------------|-------------|----------------------|---------|
| 10K | ~$150/mo | ~$5,000/mo | 97% |
| 50K | ~$800/mo | ~$25,000/mo | 97% |
| 200K | ~$4,000/mo | ~$100,000/mo | 96% |

## Related Documentation

- [Main Project README](../../README.md) - Project overview
- [.NET Integration Guide](../dotnet-integration.md) - SDK setup for .NET apps
