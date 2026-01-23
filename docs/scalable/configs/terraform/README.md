# Terraform Configuration for Observability Stack

This Terraform configuration provisions AWS infrastructure for running the scalable OpenTelemetry observability stack on Kubernetes (EKS).

## What Gets Created

| Resource | Description |
|----------|-------------|
| **VPC** | 3 AZs, public/private subnets, NAT gateway |
| **EKS Cluster** | Managed Kubernetes with IRSA enabled |
| **Node Groups** | System nodes + Observability nodes |
| **S3 Bucket** | Object storage for Tempo, Mimir, Loki |
| **IAM Roles** | IRSA roles for S3 access from pods |

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.0
3. **kubectl** for cluster access

```bash
# Verify AWS credentials
aws sts get-caller-identity

# Install Terraform (macOS)
brew install terraform
```

## Quick Start

```bash
# 1. Initialize Terraform
terraform init

# 2. Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Review the plan
terraform plan

# 4. Apply (creates resources)
terraform apply

# 5. Configure kubectl
$(terraform output -raw kubeconfig_command)
```

## Configuration

### Basic Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-west-2` | AWS region |
| `environment` | `dev` | Environment (dev/staging/production) |
| `cluster_name` | `observability` | EKS cluster name |
| `kubernetes_version` | `1.28` | Kubernetes version |

### Node Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `observability_node_instance_types` | `["t3.xlarge"]` | Instance types for observability workloads |
| `observability_node_min_size` | `2` | Minimum nodes |
| `observability_node_max_size` | `10` | Maximum nodes |
| `observability_node_desired_size` | `3` | Initial nodes |

### Retention Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `trace_retention_days` | `30` | Tempo trace retention |
| `metrics_retention_days` | `90` | Mimir metrics retention |
| `logs_retention_days` | `30` | Loki logs retention |

## After Deployment

### 1. Configure kubectl

```bash
# Get the kubeconfig command from outputs
terraform output kubeconfig_command

# Run it
aws eks update-kubeconfig --region us-west-2 --name observability
```

### 2. Install Strimzi (Kafka Operator)

```bash
kubectl create namespace kafka
kubectl apply -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka
```

### 3. Deploy Observability Stack

```bash
# Apply Kubernetes manifests
kubectl apply -f ../kubernetes/namespace.yaml
kubectl apply -f ../kubernetes/kafka-cluster.yaml
# ... apply other manifests
```

### 4. Update Kubernetes Configs for S3

The outputs provide S3 configuration snippets for Tempo, Mimir, and Loki. When using AWS S3 (instead of MinIO), update the Kubernetes configs:

1. Remove MinIO deployment (not needed with AWS S3)
2. Update storage configs to use AWS S3 endpoints
3. Add IRSA annotation to ServiceAccounts:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tempo
  namespace: observability
  annotations:
    eks.amazonaws.com/role-arn: <s3_irsa_role_arn from terraform output>
```

## Outputs

After `terraform apply`, these outputs are available:

```bash
# Get all outputs
terraform output

# Get specific output
terraform output s3_bucket_name
terraform output kubeconfig_command
terraform output service_account_annotation
```

## Cost Estimation

| Component | Monthly Cost (estimate) |
|-----------|------------------------|
| EKS Control Plane | ~$73 |
| 3x t3.xlarge nodes | ~$375 |
| NAT Gateway | ~$32 |
| S3 (100GB) | ~$2 |
| **Total** | **~$480/month** |

*Costs vary by region and usage. Use AWS Cost Calculator for accurate estimates.*

## Cleanup

```bash
# Destroy all resources
terraform destroy

# Note: S3 bucket must be empty before destruction
# Empty it first if needed:
aws s3 rm s3://$(terraform output -raw s3_bucket_name) --recursive
```

## Customization

### Using Different Instance Types

For memory-optimized workloads (recommended for production):

```hcl
observability_node_instance_types = ["r5.xlarge"]
```

For cost savings with Graviton:

```hcl
observability_node_instance_types = ["r6g.xlarge"]
```

### Multi-Region Setup

For multi-region deployments, create separate Terraform workspaces:

```bash
terraform workspace new us-east-1
terraform workspace new eu-west-1

terraform workspace select us-east-1
terraform apply -var="aws_region=us-east-1"
```

## Troubleshooting

### EKS Node Not Joining

```bash
# Check node group status
aws eks describe-nodegroup --cluster-name observability --nodegroup-name observability

# Check EC2 instances
aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=observability"
```

### S3 Access Denied

Ensure the ServiceAccount has the IRSA annotation:

```bash
kubectl describe sa tempo -n observability | grep -A1 Annotations
```

### Terraform State Issues

If using S3 backend, ensure the state bucket exists and DynamoDB table for locking is created.
