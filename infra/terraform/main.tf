terraform {
  required_version = ">= 1.8"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
  
  backend "s3" {
    bucket         = "obvy-imggen-terraform-state"
    region         = "us-east-1"
    dynamodb_table = "obvy-imggen-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "obvy-imggen"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  
  # Common naming
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Network module
module "network" {
  source = "./modules/network"
  
  project_name         = var.project_name
  environment         = var.environment
  use_custom_vpc      = var.use_custom_vpc
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  
  tags = local.common_tags
}

# Data module (S3, DynamoDB, KMS)
module "data" {
  source = "./modules/data"
  
  project_name              = var.project_name
  environment              = var.environment
  enable_kms_encryption    = var.enable_kms_encryption
  s3_lifecycle_ia_days     = var.s3_lifecycle_ia_days
  s3_lifecycle_glacier_days = var.s3_lifecycle_glacier_days
  s3_lifecycle_delete_days = var.s3_lifecycle_delete_days
  s3_versioning_enabled    = var.s3_versioning_enabled
  
  tags = local.common_tags
}

# Authentication module (Cognito)
module "auth" {
  source = "./modules/auth"
  
  project_name                = var.project_name
  environment                = var.environment
  cognito_user_pool_name     = var.cognito_user_pool_name
  cognito_domain_prefix      = var.cognito_domain_prefix
  password_min_length        = var.password_min_length
  password_require_uppercase = var.password_require_uppercase
  password_require_lowercase = var.password_require_lowercase
  password_require_numbers   = var.password_require_numbers
  password_require_symbols   = var.password_require_symbols
  enable_mfa                 = var.enable_mfa
  mfa_second_factor         = var.mfa_second_factor
  
  tags = local.common_tags
}

# SageMaker module
module "sagemaker" {
  source = "./modules/sagemaker"
  
  project_name                = var.project_name
  environment                = var.environment
  sagemaker_mode             = var.sagemaker_mode
  instance_type_async        = var.instance_type_async
  instance_type_realtime     = var.instance_type_realtime
  max_concurrency            = var.max_concurrency
  min_capacity_realtime      = var.min_capacity_realtime
  max_capacity_realtime      = var.max_capacity_realtime
  inference_timeout          = var.inference_timeout
  async_timeout              = var.async_timeout
  use_jumpstart              = var.use_jumpstart
  jumpstart_model_id         = var.jumpstart_model_id
  ecr_repository_name        = var.ecr_repository_name
  model_image_tag            = var.model_image_tag
  
  # Dependencies
  vpc_id                     = module.network.vpc_id
  private_subnet_ids         = module.network.private_subnet_ids
  inference_input_bucket     = module.data.inference_input_bucket
  inference_output_bucket    = module.data.inference_output_bucket
  kms_key_arn               = module.data.kms_key_arn
  
  tags = local.common_tags
}

# API module (API Gateway, Lambda)
module "api" {
  source = "./modules/api"
  
  project_name           = var.project_name
  environment           = var.environment
  enable_waf            = var.enable_waf
  waf_rate_limit        = var.waf_rate_limit
  api_rate_limit_per_minute = var.api_rate_limit_per_minute
  api_burst_limit       = var.api_burst_limit
  enable_xray           = var.enable_xray
  log_retention_days    = var.log_retention_days
  
  # Dependencies
  cognito_user_pool_arn     = module.auth.user_pool_arn
  cognito_user_pool_client_id = module.auth.user_pool_client_id
  jobs_table_name           = module.data.jobs_table_name
  jobs_table_arn            = module.data.jobs_table_arn
  inference_input_bucket    = module.data.inference_input_bucket
  inference_output_bucket   = module.data.inference_output_bucket
  images_bucket             = module.data.images_bucket
  sagemaker_endpoint_name   = module.sagemaker.endpoint_name
  kms_key_arn              = module.data.kms_key_arn
  
  tags = local.common_tags
}

# Callbacks module (SNS, Lambda)
module "callbacks" {
  source = "./modules/callbacks"
  
  project_name         = var.project_name
  environment         = var.environment
  enable_xray         = var.enable_xray
  log_retention_days  = var.log_retention_days
  
  # Dependencies
  jobs_table_name         = module.data.jobs_table_name
  jobs_table_arn          = module.data.jobs_table_arn
  inference_output_bucket = module.data.inference_output_bucket
  images_bucket           = module.data.images_bucket
  kms_key_arn            = module.data.kms_key_arn
  
  tags = local.common_tags
}

# Update SageMaker with SNS topic ARN
resource "aws_sagemaker_endpoint_configuration" "async_update" {
  count = var.sagemaker_mode == "async" ? 1 : 0
  
  name = "${local.name_prefix}-async-updated"
  
  production_variants {
    variant_name           = "primary"
    model_name            = module.sagemaker.model_name
    initial_instance_count = 0
    instance_type         = var.instance_type_async
  }
  
  async_inference_config {
    output_config {
      s3_output_path   = "s3://${module.data.inference_output_bucket}/"
      kms_key_id       = module.data.kms_key_arn
      notification_config {
        success_topic = module.callbacks.success_topic_arn
        error_topic   = module.callbacks.error_topic_arn
      }
    }
    
    client_config {
      max_concurrent_invocations_per_instance = var.max_concurrency
    }
  }
  
  tags = local.common_tags
}

# Frontend module (S3, CloudFront)
module "frontend" {
  source = "./modules/frontend"
  
  project_name    = var.project_name
  environment    = var.environment
  domain_name    = var.domain_name
  certificate_arn = var.certificate_arn
  
  # Dependencies
  api_gateway_domain = module.api.api_gateway_domain
  
  tags = local.common_tags
}

# Observability module (CloudWatch, Budgets)
module "observability" {
  source = "./modules/observability"
  
  project_name                = var.project_name
  environment                = var.environment
  monthly_budget_usd         = var.monthly_budget_usd
  budget_alert_threshold_1   = var.budget_alert_threshold_1
  budget_alert_threshold_2   = var.budget_alert_threshold_2
  budget_alert_email         = var.budget_alert_email
  enable_enhanced_monitoring = var.enable_enhanced_monitoring
  enable_guardduty          = var.enable_guardduty
  
  # Dependencies
  api_gateway_id            = module.api.api_gateway_id
  lambda_function_names     = module.api.lambda_function_names
  sagemaker_endpoint_name   = module.sagemaker.endpoint_name
  cloudfront_distribution_id = module.frontend.cloudfront_distribution_id
  
  tags = local.common_tags
}