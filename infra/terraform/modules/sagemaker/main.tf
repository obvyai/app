# SageMaker Module - Model, Endpoint Configuration, and Endpoint

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  
  # Model configuration
  model_name = var.use_jumpstart ? var.jumpstart_model_id : "${var.project_name}-${var.environment}-custom-model"
  
  # ECR repository URI for custom model
  ecr_repository_uri = var.use_jumpstart ? null : "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com/${var.ecr_repository_name}"
  
  # Container image URI
  image_uri = var.use_jumpstart ? null : "${local.ecr_repository_uri}:${var.model_image_tag}"
}

# ECR Repository for custom model (if not using JumpStart)
resource "aws_ecr_repository" "model" {
  count = var.use_jumpstart ? 0 : 1
  
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"
  
  image_scanning_configuration {
    scan_on_push = true
  }
  
  encryption_configuration {
    encryption_type = var.kms_key_arn != null ? "KMS" : "AES256"
    kms_key        = var.kms_key_arn
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-model-repo"
  })
}

# ECR Repository Policy
resource "aws_ecr_repository_policy" "model" {
  count = var.use_jumpstart ? 0 : 1
  
  repository = aws_ecr_repository.model[0].name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSageMakerPull"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
      }
    ]
  })
}

# SageMaker Execution Role
resource "aws_iam_role" "sagemaker_execution" {
  name = "${var.project_name}-${var.environment}-sagemaker-execution-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.tags
}

# SageMaker Execution Role Policy
resource "aws_iam_role_policy" "sagemaker_execution" {
  name = "${var.project_name}-${var.environment}-sagemaker-execution-policy"
  role = aws_iam_role.sagemaker_execution.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.inference_input_bucket}",
          "arn:aws:s3:::${var.inference_input_bucket}/*",
          "arn:aws:s3:::${var.inference_output_bucket}",
          "arn:aws:s3:::${var.inference_output_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/sagemaker/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach AWS managed policy for SageMaker
resource "aws_iam_role_policy_attachment" "sagemaker_execution" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# KMS permissions for SageMaker
resource "aws_iam_role_policy" "sagemaker_kms" {
  count = var.kms_key_arn != null ? 1 : 0
  
  name = "${var.project_name}-${var.environment}-sagemaker-kms-policy"
  role = aws_iam_role.sagemaker_execution.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# SageMaker Model
resource "aws_sagemaker_model" "main" {
  name               = "${var.project_name}-${var.environment}-model"
  execution_role_arn = aws_iam_role.sagemaker_execution.arn
  
  dynamic "primary_container" {
    for_each = var.use_jumpstart ? [] : [1]
    content {
      image          = local.image_uri
      model_data_url = "s3://${var.inference_input_bucket}/model.tar.gz"
      environment = {
        SAGEMAKER_PROGRAM                = "inference.py"
        SAGEMAKER_SUBMIT_DIRECTORY       = "/opt/ml/code"
        SAGEMAKER_CONTAINER_LOG_LEVEL    = "20"
        SAGEMAKER_REGION                 = local.region
        MODEL_CACHE_ROOT                 = "/opt/ml/model"
        TRANSFORMERS_CACHE              = "/tmp/transformers_cache"
        HF_HOME                         = "/tmp/huggingface_cache"
      }
    }
  }
  
  # For JumpStart models
  dynamic "primary_container" {
    for_each = var.use_jumpstart ? [1] : []
    content {
      image = data.aws_sagemaker_prebuilt_ecr_image.jumpstart[0].registry_path
      environment = {
        SAGEMAKER_PROGRAM                = "inference.py"
        SAGEMAKER_SUBMIT_DIRECTORY       = "/opt/ml/code"
        SAGEMAKER_CONTAINER_LOG_LEVEL    = "20"
        SAGEMAKER_REGION                 = local.region
      }
    }
  }
  
  # VPC configuration for custom VPC
  dynamic "vpc_config" {
    for_each = length(var.private_subnet_ids) > 0 ? [1] : []
    content {
      security_group_ids = [aws_security_group.sagemaker.id]
      subnets           = var.private_subnet_ids
    }
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-model"
  })
}

# Data source for JumpStart model image
data "aws_sagemaker_prebuilt_ecr_image" "jumpstart" {
  count = var.use_jumpstart ? 1 : 0
  
  repository_name = "huggingface-pytorch-inference"
  image_tag       = "1.13.1-transformers4.26.0-gpu-py39-cu117-ubuntu20.04"
}

# Security Group for SageMaker
resource "aws_security_group" "sagemaker" {
  name_prefix = "${var.project_name}-${var.environment}-sagemaker"
  vpc_id      = var.vpc_id
  
  # Allow HTTPS outbound
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Allow HTTP outbound
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Allow all outbound for model downloads
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-sagemaker-sg"
  })
}

# Async Endpoint Configuration
resource "aws_sagemaker_endpoint_configuration" "async" {
  count = var.sagemaker_mode == "async" ? 1 : 0
  
  name = "${var.project_name}-${var.environment}-async-config"
  
  production_variants {
    variant_name           = "primary"
    model_name            = aws_sagemaker_model.main.name
    initial_instance_count = 0  # Scale to zero
    instance_type         = var.instance_type_async
    
    serverless_config {
      max_concurrency   = var.max_concurrency
      memory_size_in_mb = 6144  # 6GB for GPU instances
    }
  }
  
  async_inference_config {
    output_config {
      s3_output_path = "s3://${var.inference_output_bucket}/"
      kms_key_id     = var.kms_key_arn
    }
    
    client_config {
      max_concurrent_invocations_per_instance = var.max_concurrency
    }
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-async-config"
  })
}

# Real-time Endpoint Configuration
resource "aws_sagemaker_endpoint_configuration" "realtime" {
  count = var.sagemaker_mode == "realtime" ? 1 : 0
  
  name = "${var.project_name}-${var.environment}-realtime-config"
  
  production_variants {
    variant_name           = "primary"
    model_name            = aws_sagemaker_model.main.name
    initial_instance_count = var.min_capacity_realtime
    instance_type         = var.instance_type_realtime
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-realtime-config"
  })
}

# SageMaker Endpoint
resource "aws_sagemaker_endpoint" "main" {
  name                 = "${var.project_name}-${var.environment}-${var.sagemaker_mode}"
  endpoint_config_name = var.sagemaker_mode == "async" ? aws_sagemaker_endpoint_configuration.async[0].name : aws_sagemaker_endpoint_configuration.realtime[0].name
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${var.sagemaker_mode}-endpoint"
    Mode = var.sagemaker_mode
  })
}

# Auto Scaling for Real-time Endpoint
resource "aws_appautoscaling_target" "sagemaker_target" {
  count = var.sagemaker_mode == "realtime" ? 1 : 0
  
  max_capacity       = var.max_capacity_realtime
  min_capacity       = var.min_capacity_realtime
  resource_id        = "endpoint/${aws_sagemaker_endpoint.main.name}/variant/primary"
  scalable_dimension = "sagemaker:variant:DesiredInstanceCount"
  service_namespace  = "sagemaker"
}

resource "aws_appautoscaling_policy" "sagemaker_policy" {
  count = var.sagemaker_mode == "realtime" ? 1 : 0
  
  name               = "${var.project_name}-${var.environment}-sagemaker-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.sagemaker_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.sagemaker_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.sagemaker_target[0].service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "SageMakerVariantInvocationsPerInstance"
    }
    target_value       = 70.0
    scale_in_cooldown  = var.scale_down_cooldown
    scale_out_cooldown = var.scale_up_cooldown
  }
}