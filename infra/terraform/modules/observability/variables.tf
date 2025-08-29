variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly budget in USD"
  type        = number
  default     = 100
}

variable "budget_alert_threshold_1" {
  description = "First budget alert threshold (percentage)"
  type        = number
  default     = 80
}

variable "budget_alert_threshold_2" {
  description = "Second budget alert threshold (percentage)"
  type        = number
  default     = 100
}

variable "budget_alert_email" {
  description = "Email address for budget alerts"
  type        = string
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring"
  type        = bool
  default     = true
}

variable "enable_guardduty" {
  description = "Enable GuardDuty"
  type        = bool
  default     = false
}

variable "enable_custom_metrics" {
  description = "Enable custom metrics"
  type        = bool
  default     = true
}

# Dependencies
variable "api_gateway_id" {
  description = "API Gateway ID"
  type        = string
}

variable "lambda_function_names" {
  description = "Lambda function names"
  type        = map(string)
}

variable "sagemaker_endpoint_name" {
  description = "SageMaker endpoint name"
  type        = string
}

variable "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}