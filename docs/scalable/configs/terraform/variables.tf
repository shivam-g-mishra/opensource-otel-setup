# Terraform Variables for Observability Stack
#
# Copy terraform.tfvars.example to terraform.tfvars and customize

# =============================================================================
# AWS Configuration
# =============================================================================

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

# =============================================================================
# VPC Configuration
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

# =============================================================================
# EKS Configuration
# =============================================================================

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "observability"
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.28"
}

# System Node Group
variable "system_node_instance_types" {
  description = "Instance types for system node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "system_node_min_size" {
  description = "Minimum number of system nodes"
  type        = number
  default     = 1
}

variable "system_node_max_size" {
  description = "Maximum number of system nodes"
  type        = number
  default     = 3
}

variable "system_node_desired_size" {
  description = "Desired number of system nodes"
  type        = number
  default     = 2
}

# Observability Node Group
variable "observability_node_instance_types" {
  description = "Instance types for observability node group"
  type        = list(string)
  default     = ["t3.xlarge"]
}

variable "observability_node_min_size" {
  description = "Minimum number of observability nodes"
  type        = number
  default     = 2
}

variable "observability_node_max_size" {
  description = "Maximum number of observability nodes"
  type        = number
  default     = 10
}

variable "observability_node_desired_size" {
  description = "Desired number of observability nodes"
  type        = number
  default     = 3
}

# =============================================================================
# Storage Retention
# =============================================================================

variable "trace_retention_days" {
  description = "Number of days to retain traces in S3"
  type        = number
  default     = 30
}

variable "metrics_retention_days" {
  description = "Number of days to retain metrics in S3"
  type        = number
  default     = 90
}

variable "logs_retention_days" {
  description = "Number of days to retain logs in S3"
  type        = number
  default     = 30
}
