# Terraform Outputs for Observability Stack
#
# These outputs provide information needed to configure
# the Kubernetes manifests and connect to the cluster.

# =============================================================================
# VPC Outputs
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.vpc.public_subnets
}

# =============================================================================
# EKS Outputs
# =============================================================================

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

# =============================================================================
# S3 Outputs
# =============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for observability data"
  value       = aws_s3_bucket.observability.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.observability.arn
}

output "s3_bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.observability.region
}

# =============================================================================
# IAM Outputs
# =============================================================================

output "s3_irsa_role_arn" {
  description = "ARN of the IAM role for S3 access (use in ServiceAccount annotations)"
  value       = module.s3_irsa.iam_role_arn
}

# =============================================================================
# Configuration Snippets
# =============================================================================

output "kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "tempo_s3_config" {
  description = "S3 configuration for Tempo (add to tempo config)"
  value       = <<-EOT
    storage:
      trace:
        backend: s3
        s3:
          bucket: ${aws_s3_bucket.observability.id}
          endpoint: s3.${var.aws_region}.amazonaws.com
          region: ${var.aws_region}
          # Using IRSA - no access_key/secret_key needed
  EOT
}

output "mimir_s3_config" {
  description = "S3 configuration for Mimir (add to mimir config)"
  value       = <<-EOT
    blocks_storage:
      backend: s3
      s3:
        bucket_name: ${aws_s3_bucket.observability.id}
        endpoint: s3.${var.aws_region}.amazonaws.com
        region: ${var.aws_region}
        # Using IRSA - no access_key_id/secret_access_key needed
  EOT
}

output "loki_s3_config" {
  description = "S3 configuration for Loki (add to loki config)"
  value       = <<-EOT
    storage_config:
      aws:
        bucketnames: ${aws_s3_bucket.observability.id}
        endpoint: s3.${var.aws_region}.amazonaws.com
        region: ${var.aws_region}
        # Using IRSA - no access_key_id/secret_access_key needed
  EOT
}

output "service_account_annotation" {
  description = "Annotation to add to ServiceAccounts for S3 access"
  value       = "eks.amazonaws.com/role-arn: ${module.s3_irsa.iam_role_arn}"
}
