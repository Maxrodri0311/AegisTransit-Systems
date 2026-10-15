# ==============================================================================
# AegisTransit SD-WAN Telemetry Lakehouse - Outputs
# ==============================================================================

output "telemetry_bucket_arn" {
  description = "ARN of the AegisTransit telemetry S3 bucket"
  value       = aws_s3_bucket.telemetry_lake.arn
}

output "telemetry_bucket_id" {
  description = "Name ID of the telemetry storage bucket"
  value       = aws_s3_bucket.telemetry_lake.id
}

output "kms_key_arn" {
  description = "ARN of the customer managed KMS key"
  value       = aws_kms_key.telemetry_key.arn
}

output "glue_database_name" {
  description = "Glue Catalog database name for Athena queries"
  value       = aws_glue_catalog_database.telemetry_catalog.name
}