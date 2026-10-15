# ==============================================================================
# CommandLink SD-WAN Telemetry Lakehouse - Enterprise Infrastructure as Code
# Target: AWS / FinOps Cloud Architecture
# Role: Cost Optimization Analyst
# Strategy: S3 Lifecycle to Glacier Instant Retrieval, KMS, and Athena Data Catalog
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "sdwan-transit-cost-linear-optimizer"
      Company     = "CommandLink"
      TargetRole  = "Cost Optimization Analyst"
      ManagedBy   = "Terraform"
      Environment = "Production"
      FinOpsTier  = "Cost-Optimized-Storage"
    }
  }
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Target deployment region"
}

variable "environment" {
  type        = string
  default     = "production"
  description = "Target runtime environment"
}

# KMS Key with Key Rotation enabled for Telemetry at Rest
resource "aws_kms_key" "telemetry_key" {
  description             = "KMS Key for CommandLink SD-WAN transit telemetry encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

# Telemetry Lakehouse S3 Bucket
resource "aws_s3_bucket" "telemetry_lake" {
  bucket        = "commandlink-sdwan-telemetry-lake-${var.environment}"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "telemetry_lake_pab" {
  bucket = aws_s3_bucket.telemetry_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "telemetry_crypto" {
  bucket = aws_s3_bucket.telemetry_lake.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.telemetry_key.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# FinOps Automated Storage Tiering Policy: Transitions to Glacier after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "telemetry_lifecycle" {
  bucket = aws_s3_bucket.telemetry_lake.id

  rule {
    id     = "archive-cold-telemetry"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = 365
    }
  }
}

# AWS Glue Data Catalog Database for Athena/RDS Federated Queries
resource "aws_glue_catalog_database" "telemetry_catalog" {
  name        = "commandlink_telemetry_catalog"
  description = "Data catalog for SD-WAN multi-carrier transit samples and 95th percentile rollups"
}