output "budget_name" {
  description = "AWS Budget name"
  value       = aws_budgets_budget.monthly.name
}

output "budget_arn" {
  description = "AWS Budget ARN"
  value       = aws_budgets_budget.monthly.arn
}

output "dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "alerts_topic_arn" {
  description = "SNS alerts topic ARN"
  value       = aws_sns_topic.alerts.arn
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = var.enable_guardduty ? aws_guardduty_detector.main[0].id : null
}

output "cost_anomaly_detector_arn" {
  description = "Cost anomaly detector ARN"
  value       = aws_ce_anomaly_detector.sagemaker.arn
}

output "alarm_names" {
  description = "CloudWatch alarm names"
  value = {
    api_5xx_errors        = aws_cloudwatch_metric_alarm.api_gateway_5xx_errors.alarm_name
    lambda_errors         = aws_cloudwatch_metric_alarm.lambda_errors[*].alarm_name
    sagemaker_errors      = aws_cloudwatch_metric_alarm.sagemaker_invocation_errors.alarm_name
    sagemaker_latency     = aws_cloudwatch_metric_alarm.sagemaker_model_latency.alarm_name
  }
}