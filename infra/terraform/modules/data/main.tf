# Data Module - S3 Buckets, DynamoDB Tables, and KMS Keys

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# KMS Key for encryption
resource "aws_kms_key" "main" {
  count = var.enable_kms_encryption ? 1 : 0
  
  description             = "KMS key for ${var.project_name}-${var.environment}"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow SageMaker Service"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow Lambda Service"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-kms-key"
  })
}

resource "aws_kms_alias" "main" {
  count = var.enable_kms_encryption ? 1 : 0
  
  name          = "alias/${var.project_name}-${var.environment}"
  target_key_id = aws_kms_key.main[0].key_id
}

# S3 Bucket for inference inputs
resource "aws_s3_bucket" "inference_input" {
  bucket = "${var.project_name}-${var.environment}-inference-input-${random_id.bucket_suffix.hex}"
  
  tags = merge(var.tags, {
    Name    = "${var.project_name}-${var.environment}-inference-input"
    Purpose = "SageMaker inference inputs"
  })
}

# S3 Bucket for inference outputs
resource "aws_s3_bucket" "inference_output" {
  bucket = "${var.project_name}-${var.environment}-inference-output-${random_id.bucket_suffix.hex}"
  
  tags = merge(var.tags, {
    Name    = "${var.project_name}-${var.environment}-inference-output"
    Purpose = "SageMaker inference outputs"
  })
}

# S3 Bucket for generated images (public via CloudFront)
resource "aws_s3_bucket" "images" {
  bucket = "${var.project_name}-${var.environment}-images-${random_id.bucket_suffix.hex}"
  
  tags = merge(var.tags, {
    Name    = "${var.project_name}-${var.environment}-images"
    Purpose = "Generated images for public access"
  })
}

# S3 Bucket for artifacts (models, configs, etc.)
resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project_name}-${var.environment}-artifacts-${random_id.bucket_suffix.hex}"
  
  tags = merge(var.tags, {
    Name    = "${var.project_name}-${var.environment}-artifacts"
    Purpose = "Model artifacts and configurations"
  })
}

# Random suffix for unique bucket names
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "inference_input" {
  bucket = aws_s3_bucket.inference_input.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_versioning" "inference_output" {
  bucket = aws_s3_bucket.inference_output.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

# S3 Bucket Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "inference_input" {
  bucket = aws_s3_bucket.inference_input.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.main[0].arn : null
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "inference_output" {
  bucket = aws_s3_bucket.inference_output.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.main[0].arn : null
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.main[0].arn : null
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.main[0].arn : null
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "inference_input" {
  bucket = aws_s3_bucket.inference_input.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "inference_output" {
  bucket = aws_s3_bucket.inference_output.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "inference_input" {
  bucket = aws_s3_bucket.inference_input.id
  
  rule {
    id     = "lifecycle"
    status = "Enabled"
    
    expiration {
      days = var.s3_lifecycle_delete_days
    }
    
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "inference_output" {
  bucket = aws_s3_bucket.inference_output.id
  
  rule {
    id     = "lifecycle"
    status = "Enabled"
    
    transition {
      days          = var.s3_lifecycle_ia_days
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = var.s3_lifecycle_glacier_days
      storage_class = "GLACIER"
    }
    
    expiration {
      days = var.s3_lifecycle_delete_days
    }
    
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }
    
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "images" {
  bucket = aws_s3_bucket.images.id
  
  rule {
    id     = "lifecycle"
    status = "Enabled"
    
    transition {
      days          = var.s3_lifecycle_ia_days
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = var.s3_lifecycle_glacier_days
      storage_class = "GLACIER"
    }
    
    # Don't auto-delete images - they're user-facing
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  
  rule {
    id     = "lifecycle"
    status = "Enabled"
    
    transition {
      days          = var.s3_lifecycle_ia_days
      storage_class = "STANDARD_IA"
    }
    
    # Keep artifacts longer
    noncurrent_version_expiration {
      noncurrent_days = 180
    }
  }
}

# DynamoDB Table for Jobs
resource "aws_dynamodb_table" "jobs" {
  name           = "${var.project_name}-${var.environment}-jobs"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "jobId"
  
  attribute {
    name = "jobId"
    type = "S"
  }
  
  attribute {
    name = "userId"
    type = "S"
  }
  
  attribute {
    name = "createdAt"
    type = "S"
  }
  
  attribute {
    name = "status"
    type = "S"
  }
  
  # GSI for querying jobs by user
  global_secondary_index {
    name     = "UserIndex"
    hash_key = "userId"
    range_key = "createdAt"
  }
  
  # GSI for querying jobs by status
  global_secondary_index {
    name     = "StatusIndex"
    hash_key = "status"
    range_key = "createdAt"
  }
  
  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }
  
  # Server-side encryption
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.enable_kms_encryption ? aws_kms_key.main[0].arn : null
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-jobs"
  })
}

# DynamoDB Table for Models (optional - for model metadata)
resource "aws_dynamodb_table" "models" {
  name           = "${var.project_name}-${var.environment}-models"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "modelId"
  
  attribute {
    name = "modelId"
    type = "S"
  }
  
  attribute {
    name = "category"
    type = "S"
  }
  
  # GSI for querying models by category
  global_secondary_index {
    name     = "CategoryIndex"
    hash_key = "category"
  }
  
  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }
  
  # Server-side encryption
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.enable_kms_encryption ? aws_kms_key.main[0].arn : null
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-models"
  })
}