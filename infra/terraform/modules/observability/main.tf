# Observability Module - CloudWatch, Budgets, and Monitoring

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# AWS Budget for cost monitoring
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-${var.environment}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  time_period_start = formatdate("YYYY-MM-01_00:00", timestamp())
  
  cost_filters = {
    Service = [
      "Amazon SageMaker",
      "AWS Lambda",
      "Amazon S3",
      "Amazon CloudFront",
      "Amazon DynamoDB",
      "Amazon API Gateway",
      "Amazon Cognito"
    ]
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = var.budget_alert_threshold_1
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = var.budget_alert_threshold_2
    threshold_type            = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
  
  tags = var.tags
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}-dashboard"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", "${var.project_name}-${var.environment}-api"],
            [".", "4XXError", ".", "."],
            [".", "5XXError", ".", "."],
            [".", "Latency", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "API Gateway Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project_name}-${var.environment}-submit-job"],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."],
            [".", "Duration", "FunctionName", "${var.project_name}-${var.environment}-get-job"],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "Lambda Function Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/SageMaker", "InvocationsPerInstance", "EndpointName", var.sagemaker_endpoint_name],
            [".", "ModelLatency", ".", "."],
            [".", "OverheadLatency", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "SageMaker Endpoint Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", "${var.project_name}-${var.environment}-jobs"],
            [".", "ConsumedWriteCapacityUnits", ".", "."],
            [".", "ThrottledRequests", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "DynamoDB Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        
        properties = {
          metrics = [
            ["AWS/CloudFront", "Requests", "DistributionId", var.cloudfront_distribution_id],
            [".", "BytesDownloaded", ".", "."],
            [".", "4xxErrorRate", ".", "."],
            [".", "5xxErrorRate", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"  # CloudFront metrics are always in us-east-1
          title   = "CloudFront Metrics"
          period  = 300
        }
      }
    ]
  })
  
  tags = var.tags
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-api-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors API Gateway 5XX errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    ApiName = "${var.project_name}-${var.environment}-api"
  }
  
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = length(var.lambda_function_names)
  
  alarm_name          = "${var.project_name}-${var.environment}-lambda-errors-${keys(var.lambda_function_names)[count.index]}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "3"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    FunctionName = values(var.lambda_function_names)[count.index]
  }
  
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "sagemaker_invocation_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-sagemaker-invocation-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Invocation4XXErrors"
  namespace           = "AWS/SageMaker"
  period              = "300"
  statistic           = "Sum"
  threshold           = "2"
  alarm_description   = "This metric monitors SageMaker invocation errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    EndpointName = var.sagemaker_endpoint_name
  }
  
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "sagemaker_model_latency" {
  alarm_name          = "${var.project_name}-${var.environment}-sagemaker-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "ModelLatency"
  namespace           = "AWS/SageMaker"
  period              = "300"
  statistic           = "Average"
  threshold           = "120000"  # 2 minutes in milliseconds
  alarm_description   = "This metric monitors SageMaker model latency"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    EndpointName = var.sagemaker_endpoint_name
  }
  
  tags = var.tags
}

# SNS Topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"
  
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.budget_alert_email
}

# GuardDuty (if enabled)
resource "aws_guardduty_detector" "main" {
  count = var.enable_guardduty ? 1 : 0
  
  enable = true
  
  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = false
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = false
        }
      }
    }
  }
  
  tags = var.tags
}

# Cost Anomaly Detection
resource "aws_ce_anomaly_detector" "sagemaker" {
  name         = "${var.project_name}-${var.environment}-sagemaker-anomaly"
  monitor_type = "DIMENSIONAL"
  
  specification = jsonencode({
    Dimension = "SERVICE"
    MatchOptions = ["EQUALS"]
    Values = ["Amazon SageMaker"]
  })
  
  tags = var.tags
}

resource "aws_ce_anomaly_subscription" "sagemaker" {
  name      = "${var.project_name}-${var.environment}-sagemaker-anomaly-subscription"
  frequency = "DAILY"
  
  monitor_arn_list = [
    aws_ce_anomaly_detector.sagemaker.arn
  ]
  
  subscriber {
    type    = "EMAIL"
    address = var.budget_alert_email
  }
  
  threshold_expression {
    and {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
        values        = ["100"]
        match_options = ["GREATER_THAN_OR_EQUAL"]
      }
    }
  }
  
  tags = var.tags
}

# Custom Metrics (if enabled)
resource "aws_cloudwatch_log_metric_filter" "job_submissions" {
  count = var.enable_custom_metrics ? 1 : 0
  
  name           = "${var.project_name}-${var.environment}-job-submissions"
  log_group_name = "/aws/lambda/${var.project_name}-${var.environment}-submit-job"
  pattern        = "[timestamp, request_id, \"Job submitted successfully\"]"
  
  metric_transformation {
    name      = "JobSubmissions"
    namespace = "${var.project_name}/${var.environment}"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "job_completions" {
  count = var.enable_custom_metrics ? 1 : 0
  
  name           = "${var.project_name}-${var.environment}-job-completions"
  log_group_name = "/aws/lambda/${var.project_name}-${var.environment}-callback"
  pattern        = "[timestamp, request_id, \"Job\", job_id, \"marked as SUCCEEDED\"]"
  
  metric_transformation {
    name      = "JobCompletions"
    namespace = "${var.project_name}/${var.environment}"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "job_failures" {
  count = var.enable_custom_metrics ? 1 : 0
  
  name           = "${var.project_name}-${var.environment}-job-failures"
  log_group_name = "/aws/lambda/${var.project_name}-${var.environment}-callback"
  pattern        = "[timestamp, request_id, \"Job\", job_id, \"marked as FAILED\"]"
  
  metric_transformation {
    name      = "JobFailures"
    namespace = "${var.project_name}/${var.environment}"
    value     = "1"
  }
}