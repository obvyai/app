# Core Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "obvy-imggen"
}

variable "environment" {
  description = "Environment name (dev, stage, prod)"
  type        = string
  
  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "Environment must be one of: dev, stage, prod."
  }
}

# SageMaker Configuration
variable "sagemaker_mode" {
  description = "SageMaker inference mode: async (scale-to-zero) or realtime (always-on)"
  type        = string
  default     = "async"
  
  validation {
    condition     = contains(["async", "realtime"], var.sagemaker_mode)
    error_message = "SageMaker mode must be either 'async' or 'realtime'."
  }
}

variable "instance_type_async" {
  description = "Instance type for async inference"
  type        = string
  default     = "ml.g5.xlarge"
}

variable "instance_type_realtime" {
  description = "Instance type for real-time inference"
  type        = string
  default     = "ml.g5.xlarge"
}

variable "max_concurrency" {
  description = "Maximum concurrent invocations per instance"
  type        = number
  default     = 10
}

variable "min_capacity_realtime" {
  description = "Minimum capacity for real-time endpoint"
  type        = number
  default     = 1
}

variable "max_capacity_realtime" {
  description = "Maximum capacity for real-time endpoint"
  type        = number
  default     = 5
}

variable "inference_timeout" {
  description = "Inference timeout in seconds"
  type        = number
  default     = 300
}

variable "async_timeout" {
  description = "Async inference timeout in seconds"
  type        = number
  default     = 3600
}

variable "scale_down_cooldown" {
  description = "Scale down cooldown period in seconds"
  type        = number
  default     = 300
}

variable "scale_up_cooldown" {
  description = "Scale up cooldown period in seconds"
  type        = number
  default     = 60
}

# Model Configuration
variable "use_jumpstart" {
  description = "Use SageMaker JumpStart model instead of custom container"
  type        = bool
  default     = true
}

variable "jumpstart_model_id" {
  description = "SageMaker JumpStart model ID"
  type        = string
  default     = "huggingface-txt2img-stable-diffusion-xl-base-1-0"
}

variable "ecr_repository_name" {
  description = "ECR repository name for custom model container"
  type        = string
  default     = "obvy-model"
}

variable "model_image_tag" {
  description = "Model container image tag"
  type        = string
  default     = "latest"
}

# Model Parameters
variable "default_steps" {
  description = "Default number of inference steps"
  type        = number
  default     = 20
}

variable "max_steps" {
  description = "Maximum number of inference steps"
  type        = number
  default     = 50
}

variable "default_guidance_scale" {
  description = "Default guidance scale"
  type        = number
  default     = 7.5
}

variable "max_guidance_scale" {
  description = "Maximum guidance scale"
  type        = number
  default     = 20.0
}

variable "default_width" {
  description = "Default image width"
  type        = number
  default     = 1024
}

variable "default_height" {
  description = "Default image height"
  type        = number
  default     = 1024
}

variable "max_resolution" {
  description = "Maximum image resolution (width or height)"
  type        = number
  default     = 1024
}

# Cost Controls
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
  default     = "admin@example.com"
}

variable "enable_keep_warm" {
  description = "Enable keep-warm scheduler to prevent cold starts"
  type        = bool
  default     = false
}

variable "keep_warm_interval_minutes" {
  description = "Keep-warm interval in minutes"
  type        = number
  default     = 10
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

# Networking
variable "use_custom_vpc" {
  description = "Use custom VPC instead of default VPC"
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones (leave empty for auto-selection)"
  type        = list(string)
  default     = []
}

# Domain & SSL
variable "domain_name" {
  description = "Custom domain name for the application"
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "ACM certificate ARN for custom domain"
  type        = string
  default     = ""
}

# Storage
variable "s3_lifecycle_ia_days" {
  description = "Days before transitioning to Infrequent Access"
  type        = number
  default     = 30
}

variable "s3_lifecycle_glacier_days" {
  description = "Days before transitioning to Glacier"
  type        = number
  default     = 90
}

variable "s3_lifecycle_delete_days" {
  description = "Days before deleting objects"
  type        = number
  default     = 365
}

variable "s3_versioning_enabled" {
  description = "Enable S3 versioning"
  type        = bool
  default     = false
}

# Security
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

variable "enable_kms_encryption" {
  description = "Enable KMS encryption for S3 and other services"
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = false
}

variable "enable_guardduty" {
  description = "Enable GuardDuty"
  type        = bool
  default     = false
}

# Observability
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

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring"
  type        = bool
  default     = true
}

variable "enable_custom_metrics" {
  description = "Enable custom metrics"
  type        = bool
  default     = true
}

# Authentication
variable "cognito_user_pool_name" {
  description = "Cognito User Pool name"
  type        = string
  default     = "obvy-imggen-users"
}

variable "cognito_domain_prefix" {
  description = "Cognito domain prefix"
  type        = string
  default     = "obvy-imggen"
}

variable "password_min_length" {
  description = "Minimum password length"
  type        = number
  default     = 8
}

variable "password_require_uppercase" {
  description = "Require uppercase letters in password"
  type        = bool
  default     = true
}

variable "password_require_lowercase" {
  description = "Require lowercase letters in password"
  type        = bool
  default     = true
}

variable "password_require_numbers" {
  description = "Require numbers in password"
  type        = bool
  default     = true
}

variable "password_require_symbols" {
  description = "Require symbols in password"
  type        = bool
  default     = false
}

variable "enable_mfa" {
  description = "Enable MFA for Cognito"
  type        = bool
  default     = false
}

variable "mfa_second_factor" {
  description = "MFA second factor method"
  type        = string
  default     = "SMS_TEXT"
  
  validation {
    condition     = contains(["SMS_TEXT", "SOFTWARE_TOKEN"], var.mfa_second_factor)
    error_message = "MFA second factor must be either 'SMS_TEXT' or 'SOFTWARE_TOKEN'."
  }
}

# Development Settings
variable "debug_logging" {
  description = "Enable debug logging"
  type        = bool
  default     = false
}

variable "enable_seed_data" {
  description = "Enable seed data creation"
  type        = bool
  default     = false
}

# Feature Flags
variable "enable_websockets" {
  description = "Enable WebSocket support"
  type        = bool
  default     = false
}

variable "enable_admin_ui" {
  description = "Enable admin UI"
  type        = bool
  default     = false
}

variable "enable_gallery" {
  description = "Enable image gallery"
  type        = bool
  default     = true
}

variable "enable_prompt_templates" {
  description = "Enable prompt templates"
  type        = bool
  default     = true
}

variable "enable_batch_processing" {
  description = "Enable batch processing"
  type        = bool
  default     = false
}