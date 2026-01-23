# Terraform Configuration for Observability Stack Infrastructure
#
# This configuration provisions AWS infrastructure for running
# the scalable OpenTelemetry observability stack.
#
# Components:
# - VPC with public/private subnets
# - EKS cluster for Kubernetes deployment
# - S3 bucket for object storage (Tempo, Mimir, Loki)
# - IAM roles and policies
#
# Usage:
#   terraform init
#   terraform plan -var-file="terraform.tfvars"
#   terraform apply -var-file="terraform.tfvars"

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  # Uncomment to use S3 backend for state
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "observability/terraform.tfstate"
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "observability-stack"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# =============================================================================
# Data Sources
# =============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# =============================================================================
# VPC Configuration
# =============================================================================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment != "production"
  enable_dns_hostnames   = true
  enable_dns_support     = true

  # Tags required for EKS
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = 1
    "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = 1
    "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
  }

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

# =============================================================================
# EKS Cluster
# =============================================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Cluster access
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # OIDC for IAM roles for service accounts
  enable_irsa = true

  # Cluster addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  # Node groups
  eks_managed_node_groups = {
    # System node group for core services
    system = {
      name            = "system"
      instance_types  = var.system_node_instance_types
      min_size        = var.system_node_min_size
      max_size        = var.system_node_max_size
      desired_size    = var.system_node_desired_size

      labels = {
        role = "system"
      }

      taints = []
    }

    # Observability node group for the stack
    observability = {
      name            = "observability"
      instance_types  = var.observability_node_instance_types
      min_size        = var.observability_node_min_size
      max_size        = var.observability_node_max_size
      desired_size    = var.observability_node_desired_size

      labels = {
        role = "observability"
      }

      taints = []
    }
  }

  # aws-auth configmap
  manage_aws_auth_configmap = true

  tags = {
    Name = var.cluster_name
  }
}

# =============================================================================
# IAM Role for EBS CSI Driver
# =============================================================================

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# =============================================================================
# S3 Bucket for Object Storage
# =============================================================================

resource "aws_s3_bucket" "observability" {
  bucket = "${var.cluster_name}-observability-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.cluster_name}-observability"
  }
}

resource "aws_s3_bucket_versioning" "observability" {
  bucket = aws_s3_bucket.observability.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "observability" {
  bucket = aws_s3_bucket.observability.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "observability" {
  bucket = aws_s3_bucket.observability.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "observability" {
  bucket = aws_s3_bucket.observability.id

  rule {
    id     = "tempo-traces"
    status = "Enabled"

    filter {
      prefix = "tempo/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = var.trace_retention_days
    }
  }

  rule {
    id     = "mimir-blocks"
    status = "Enabled"

    filter {
      prefix = "mimir/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = var.metrics_retention_days
    }
  }

  rule {
    id     = "loki-chunks"
    status = "Enabled"

    filter {
      prefix = "loki/"
    }

    transition {
      days          = 14
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = var.logs_retention_days
    }
  }
}

# =============================================================================
# IAM Role for S3 Access (IRSA)
# =============================================================================

module "s3_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-s3-access"

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "observability:tempo",
        "observability:mimir",
        "observability:loki",
      ]
    }
  }
}

resource "aws_iam_role_policy" "s3_access" {
  name = "${var.cluster_name}-s3-access"
  role = module.s3_irsa.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.observability.arn,
          "${aws_s3_bucket.observability.arn}/*"
        ]
      }
    ]
  })
}
