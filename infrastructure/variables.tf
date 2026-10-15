# ==============================================================================
# AegisTransit SD-WAN Infrastructure - Variables
# Target: AWS FinOps & Observability
# ==============================================================================

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Target deployment region for telecom lakehouse"
}

variable "environment" {
  type        = string
  default     = "production"
  description = "Operational environment tier (production, staging, dev)"
}

variable "retention_days_hot_tier" {
  type        = number
  default     = 90
  description = "Days before transitioning 5-minute telemetry from S3 Standard to Glacier Instant Retrieval"
}

variable "retention_days_glacier" {
  type        = number
  default     = 365
  description = "Total lifecycle days before archiving or expiring telemetry samples"
}

variable "burst_overage_alert_threshold_mbps" {
  type        = number
  default     = 500.0
  description = "Threshold in Mbps above CIR triggering proactive FinOps alert"
}

variable "notification_email" {
  type        = string
  default     = "finops-alerts@aegistransit.io"
  description = "Corporate recipient for critical burst and hazard threshold events"
}
