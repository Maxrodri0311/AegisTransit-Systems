# ==============================================================================
# AegisTransit SD-WAN Telemetry - CloudWatch & FinOps Monitoring
# Automates real-time burst penalty alerts and SLA violation tracking
# ==============================================================================

resource "aws_sns_topic" "finops_alerts" {
  name              = "aegistransit-finops-burst-alerts-${var.environment}"
  kms_master_key_id = aws_kms_key.telemetry_key.id
}

resource "aws_cloudwatch_log_group" "telemetry_ingestion_log" {
  name              = "/aegistransit/sdwan/telemetry-${var.environment}"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.telemetry_key.arn
}

resource "aws_cloudwatch_log_metric_filter" "burst_overage_filter" {
  name           = "carrier-burst-overage-metric"
  pattern        = "{ $.is_bursting = true }"
  log_group_name = aws_cloudwatch_log_group.telemetry_ingestion_log.name

  metric_transformation {
    name          = "CarrierBurstOverageCount"
    namespace     = "AegisTransit/FinOps"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "high_burst_penalty_alarm" {
  alarm_name          = "aegistransit-high-burst-penalty-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CarrierBurstOverageCount"
  namespace           = "AegisTransit/FinOps"
  period              = 300
  statistic           = "Sum"
  threshold           = 12 # 12 consecutive intervals (1 hour of continuous bursting)
  alarm_description   = "Triggers when carrier circuits burst continuously for > 1 hour, escalating monthly 95th percentile billing penalty risk."
  alarm_actions       = [aws_sns_topic.finops_alerts.arn]
}
