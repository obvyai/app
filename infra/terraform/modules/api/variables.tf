variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "enable_waf" {
  description = "Enable WAF for API Gateway"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "WAF rate limit (requests per 5 minutes)"
  type        = number
  default     = 2000
}

variable "api_rate_limit_per_minute" {
  description = "API rate limit per minute per user"
  type        = number
  default     = 60
}

variable "api_burst_limit" {
  description = "API burst limit"
  type        = number
  default     = 100
}

variable "enable_xray" {
  description = "Enable X-Ray tracing"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

# Dependencies
variable "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  type        = string
}

variable "cognito_user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  type        = string
}

variable "jobs_table_name" {
  description = "DynamoDB jobs table name"
  type        = string
}

variable "jobs_table_arn" {
  description = "DynamoDB jobs table ARN"
  type        = string
}

variable "inference_input_bucket" {
  description = "S3 bucket for inference inputs"
  type        = string
}

variable "inference_output_bucket" {
  description = "S3 bucket for inference outputs"
  type        = string
}

variable "images_bucket" {
  description = "S3 bucket for generated images"
  type        = string
}

variable "sagemaker_endpoint_name" {
  description = "SageMaker endpoint name"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}