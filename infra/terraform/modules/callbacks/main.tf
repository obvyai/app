# Callbacks Module - SNS Topics and Lambda for SageMaker Async Results

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# SNS Topic for successful inference results
resource "aws_sns_topic" "success" {
  name = "${var.project_name}-${var.environment}-inference-success"
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-inference-success"
  })
}

# SNS Topic for failed inference results
resource "aws_sns_topic" "error" {
  name = "${var.project_name}-${var.environment}-inference-error"
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-inference-error"
  })
}

# Lambda function for processing callbacks
resource "aws_lambda_function" "callback" {
  filename         = data.archive_file.callback.output_path
  function_name    = "${var.project_name}-${var.environment}-callback"
  role            = aws_iam_role.callback_execution.arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.callback.output_base64sha256
  runtime         = "nodejs20.x"
  timeout         = 60
  memory_size     = 512
  
  environment {
    variables = {
      JOBS_TABLE_NAME           = var.jobs_table_name
      INFERENCE_OUTPUT_BUCKET   = var.inference_output_bucket
      IMAGES_BUCKET            = var.images_bucket
      REGION                   = local.region
      LOG_LEVEL                = var.enable_xray ? "DEBUG" : "INFO"
    }
  }
  
  dynamic "tracing_config" {
    for_each = var.enable_xray ? [1] : []
    content {
      mode = "Active"
    }
  }
  
  tags = var.tags
}

# Lambda execution role for callback function
resource "aws_iam_role" "callback_execution" {
  name = "${var.project_name}-${var.environment}-callback-execution-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.tags
}

# Lambda execution policy for callback function
resource "aws_iam_role_policy" "callback_execution" {
  name = "${var.project_name}-${var.environment}-callback-execution-policy"
  role = aws_iam_role.callback_execution.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Resource = var.jobs_table_arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:CopyObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.inference_output_bucket}/*",
          "arn:aws:s3:::${var.images_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.inference_output_bucket}",
          "arn:aws:s3:::${var.images_bucket}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

# KMS permissions for callback Lambda
resource "aws_iam_role_policy" "callback_kms" {
  count = var.kms_key_arn != null ? 1 : 0
  
  name = "${var.project_name}-${var.environment}-callback-kms-policy"
  role = aws_iam_role.callback_execution.id
  
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

# SNS subscriptions for Lambda
resource "aws_sns_topic_subscription" "success" {
  topic_arn = aws_sns_topic.success.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.callback.arn
}

resource "aws_sns_topic_subscription" "error" {
  topic_arn = aws_sns_topic.error.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.callback.arn
}

# Lambda permissions for SNS
resource "aws_lambda_permission" "sns_success" {
  statement_id  = "AllowExecutionFromSNSSuccess"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.callback.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.success.arn
}

resource "aws_lambda_permission" "sns_error" {
  statement_id  = "AllowExecutionFromSNSError"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.callback.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.error.arn
}

# CloudWatch Log Group for callback Lambda
resource "aws_cloudwatch_log_group" "callback" {
  name              = "/aws/lambda/${aws_lambda_function.callback.function_name}"
  retention_in_days = var.log_retention_days
  
  tags = var.tags
}

# Lambda function source code
data "archive_file" "callback" {
  type        = "zip"
  output_path = "/tmp/callback.zip"
  source {
    content = templatefile("${path.module}/lambda-src/callback.js", {
      region = local.region
    })
    filename = "index.js"
  }
}