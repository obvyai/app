# Core Infrastructure Outputs
output "account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "AWS Region"
  value       = data.aws_region.current.name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# Network Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.network.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.network.public_subnet_ids
}

# Data Outputs
output "jobs_table_name" {
  description = "DynamoDB jobs table name"
  value       = module.data.jobs_table_name
}

output "inference_input_bucket" {
  description = "S3 bucket for inference inputs"
  value       = module.data.inference_input_bucket
}

output "inference_output_bucket" {
  description = "S3 bucket for inference outputs"
  value       = module.data.inference_output_bucket
}

output "images_bucket" {
  description = "S3 bucket for generated images"
  value       = module.data.images_bucket
}

output "artifacts_bucket" {
  description = "S3 bucket for artifacts"
  value       = module.data.artifacts_bucket
}

output "kms_key_id" {
  description = "KMS key ID"
  value       = module.data.kms_key_id
}

output "kms_key_arn" {
  description = "KMS key ARN"
  value       = module.data.kms_key_arn
}

# Authentication Outputs
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.auth.user_pool_id
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = module.auth.user_pool_arn
}

output "cognito_user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  value       = module.auth.user_pool_client_id
}

output "cognito_user_pool_domain" {
  description = "Cognito User Pool Domain"
  value       = module.auth.user_pool_domain
}

output "cognito_identity_pool_id" {
  description = "Cognito Identity Pool ID"
  value       = module.auth.identity_pool_id
}

# SageMaker Outputs
output "sagemaker_model_name" {
  description = "SageMaker model name"
  value       = module.sagemaker.model_name
}

output "sagemaker_endpoint_name" {
  description = "SageMaker endpoint name"
  value       = module.sagemaker.endpoint_name
}

output "sagemaker_endpoint_arn" {
  description = "SageMaker endpoint ARN"
  value       = module.sagemaker.endpoint_arn
}

output "sagemaker_execution_role_arn" {
  description = "SageMaker execution role ARN"
  value       = module.sagemaker.execution_role_arn
}

output "ecr_repository_uri" {
  description = "ECR repository URI for custom model"
  value       = module.sagemaker.ecr_repository_uri
}

# API Outputs
output "api_gateway_id" {
  description = "API Gateway ID"
  value       = module.api.api_gateway_id
}

output "api_gateway_domain" {
  description = "API Gateway domain"
  value       = module.api.api_gateway_domain
}

output "api_base_url" {
  description = "API base URL"
  value       = "https://${module.api.api_gateway_domain}/v1"
}

output "lambda_function_names" {
  description = "Lambda function names"
  value       = module.api.lambda_function_names
}

# Callback Outputs
output "sns_success_topic_arn" {
  description = "SNS success topic ARN"
  value       = module.callbacks.success_topic_arn
}

output "sns_error_topic_arn" {
  description = "SNS error topic ARN"
  value       = module.callbacks.error_topic_arn
}

output "callback_lambda_function_name" {
  description = "Callback Lambda function name"
  value       = module.callbacks.lambda_function_name
}

# Frontend Outputs
output "frontend_bucket_name" {
  description = "Frontend S3 bucket name"
  value       = module.frontend.bucket_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = module.frontend.cloudfront_distribution_id
}

output "cloudfront_domain" {
  description = "CloudFront domain name"
  value       = module.frontend.cloudfront_domain
}

output "frontend_url" {
  description = "Frontend URL"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "https://${module.frontend.cloudfront_domain}"
}

# Observability Outputs
output "cloudwatch_dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = module.observability.dashboard_url
}

output "budget_name" {
  description = "AWS Budget name"
  value       = module.observability.budget_name
}

# Configuration Summary
output "configuration_summary" {
  description = "Configuration summary"
  value = {
    project_name     = var.project_name
    environment      = var.environment
    region          = var.aws_region
    sagemaker_mode  = var.sagemaker_mode
    instance_type   = var.sagemaker_mode == "async" ? var.instance_type_async : var.instance_type_realtime
    use_jumpstart   = var.use_jumpstart
    model_id        = var.use_jumpstart ? var.jumpstart_model_id : "custom"
    monthly_budget  = var.monthly_budget_usd
    custom_domain   = var.domain_name != "" ? var.domain_name : "none"
  }
}

# Quick Access URLs
output "quick_access" {
  description = "Quick access URLs and commands"
  value = {
    frontend_url    = var.domain_name != "" ? "https://${var.domain_name}" : "https://${module.frontend.cloudfront_domain}"
    api_base_url    = "https://${module.api.api_gateway_domain}/v1"
    cognito_login   = "https://${module.auth.user_pool_domain}/login?client_id=${module.auth.user_pool_client_id}&response_type=code&scope=email+openid+profile&redirect_uri=https://${module.frontend.cloudfront_domain}/auth/callback"
    aws_console = {
      sagemaker_endpoint = "https://${var.aws_region}.console.aws.amazon.com/sagemaker/home?region=${var.aws_region}#/endpoints/${module.sagemaker.endpoint_name}"
      api_gateway       = "https://${var.aws_region}.console.aws.amazon.com/apigateway/home?region=${var.aws_region}#/apis/${module.api.api_gateway_id}"
      cloudwatch_logs   = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups"
      dynamodb_table    = "https://${var.aws_region}.console.aws.amazon.com/dynamodbv2/home?region=${var.aws_region}#table?name=${module.data.jobs_table_name}"
    }
  }
}