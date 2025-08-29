# API Module - API Gateway and Lambda Functions

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# API Gateway HTTP API
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-${var.environment}-api"
  protocol_type = "HTTP"
  description   = "Image Generation API"
  
  cors_configuration {
    allow_credentials = true
    allow_headers     = ["content-type", "x-amz-date", "authorization", "x-api-key", "x-amz-security-token", "x-amz-user-agent"]
    allow_methods     = ["*"]
    allow_origins     = ["*"]  # Will be restricted in production
    expose_headers    = ["date", "keep-alive"]
    max_age          = 86400
  }
  
  tags = var.tags
}

# Cognito Authorizer
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.project_name}-${var.environment}-cognito-authorizer"
  
  jwt_configuration {
    audience = [var.cognito_user_pool_client_id]
    issuer   = "https://cognito-idp.${local.region}.amazonaws.com/${var.cognito_user_pool_arn}"
  }
}

# Lambda Functions
# Submit Job Lambda
resource "aws_lambda_function" "submit_job" {
  filename         = data.archive_file.submit_job.output_path
  function_name    = "${var.project_name}-${var.environment}-submit-job"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.submit_job.output_base64sha256
  runtime         = "nodejs20.x"
  timeout         = 30
  memory_size     = 512
  
  environment {
    variables = {
      JOBS_TABLE_NAME           = var.jobs_table_name
      SAGEMAKER_ENDPOINT_NAME   = var.sagemaker_endpoint_name
      INFERENCE_INPUT_BUCKET    = var.inference_input_bucket
      INFERENCE_OUTPUT_BUCKET   = var.inference_output_bucket
      REGION                    = local.region
      LOG_LEVEL                 = var.enable_xray ? "DEBUG" : "INFO"
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

# Get Job Lambda
resource "aws_lambda_function" "get_job" {
  filename         = data.archive_file.get_job.output_path
  function_name    = "${var.project_name}-${var.environment}-get-job"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.get_job.output_base64sha256
  runtime         = "nodejs20.x"
  timeout         = 10
  memory_size     = 256
  
  environment {
    variables = {
      JOBS_TABLE_NAME = var.jobs_table_name
      IMAGES_BUCKET   = var.images_bucket
      REGION          = local.region
      LOG_LEVEL       = var.enable_xray ? "DEBUG" : "INFO"
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

# List Models Lambda
resource "aws_lambda_function" "list_models" {
  filename         = data.archive_file.list_models.output_path
  function_name    = "${var.project_name}-${var.environment}-list-models"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.list_models.output_base64sha256
  runtime         = "nodejs20.x"
  timeout         = 10
  memory_size     = 256
  
  environment {
    variables = {
      REGION    = local.region
      LOG_LEVEL = var.enable_xray ? "DEBUG" : "INFO"
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

# Lambda Execution Role
resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-${var.environment}-lambda-execution-role"
  
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

# Lambda Execution Policy
resource "aws_iam_role_policy" "lambda_execution" {
  name = "${var.project_name}-${var.environment}-lambda-execution-policy"
  role = aws_iam_role.lambda_execution.id
  
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
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          var.jobs_table_arn,
          "${var.jobs_table_arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.inference_input_bucket}/*",
          "arn:aws:s3:::${var.inference_output_bucket}/*",
          "arn:aws:s3:::${var.images_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sagemaker:InvokeEndpoint",
          "sagemaker:InvokeEndpointAsync"
        ]
        Resource = "arn:aws:sagemaker:${local.region}:${local.account_id}:endpoint/${var.sagemaker_endpoint_name}"
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

# KMS permissions for Lambda
resource "aws_iam_role_policy" "lambda_kms" {
  count = var.kms_key_arn != null ? 1 : 0
  
  name = "${var.project_name}-${var.environment}-lambda-kms-policy"
  role = aws_iam_role.lambda_execution.id
  
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

# Lambda function source code archives
data "archive_file" "submit_job" {
  type        = "zip"
  output_path = "/tmp/submit-job.zip"
  source {
    content = templatefile("${path.module}/lambda-src/submit-job.js", {
      region = local.region
    })
    filename = "index.js"
  }
}

data "archive_file" "get_job" {
  type        = "zip"
  output_path = "/tmp/get-job.zip"
  source {
    content = templatefile("${path.module}/lambda-src/get-job.js", {
      region = local.region
    })
    filename = "index.js"
  }
}

data "archive_file" "list_models" {
  type        = "zip"
  output_path = "/tmp/list-models.zip"
  source {
    content = templatefile("${path.module}/lambda-src/list-models.js", {
      region = local.region
    })
    filename = "index.js"
  }
}

# API Gateway Routes
resource "aws_apigatewayv2_route" "submit_job" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /v1/jobs"
  target    = "integrations/${aws_apigatewayv2_integration.submit_job.id}"
  
  authorization_type = "JWT"
  authorizer_id     = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "get_job" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /v1/jobs/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.get_job.id}"
  
  authorization_type = "JWT"
  authorizer_id     = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "list_models" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /v1/models"
  target    = "integrations/${aws_apigatewayv2_integration.list_models.id}"
  
  authorization_type = "JWT"
  authorizer_id     = aws_apigatewayv2_authorizer.cognito.id
}

# API Gateway Integrations
resource "aws_apigatewayv2_integration" "submit_job" {
  api_id           = aws_apigatewayv2_api.main.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.submit_job.invoke_arn
}

resource "aws_apigatewayv2_integration" "get_job" {
  api_id           = aws_apigatewayv2_api.main.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.get_job.invoke_arn
}

resource "aws_apigatewayv2_integration" "list_models" {
  api_id           = aws_apigatewayv2_api.main.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.list_models.invoke_arn
}

# Lambda Permissions
resource "aws_lambda_permission" "submit_job" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.submit_job.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "get_job" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_job.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "list_models" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_models.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# API Gateway Stage
resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
  
  default_route_settings {
    throttling_rate_limit  = var.api_rate_limit_per_minute
    throttling_burst_limit = var.api_burst_limit
  }
  
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip            = "$context.identity.sourceIp"
      requestTime   = "$context.requestTime"
      httpMethod    = "$context.httpMethod"
      routeKey      = "$context.routeKey"
      status        = "$context.status"
      protocol      = "$context.protocol"
      responseLength = "$context.responseLength"
      error         = "$context.error.message"
      integrationError = "$context.integration.error"
    })
  }
  
  tags = var.tags
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days
  
  tags = var.tags
}

# CloudWatch Log Groups for Lambda Functions
resource "aws_cloudwatch_log_group" "submit_job" {
  name              = "/aws/lambda/${aws_lambda_function.submit_job.function_name}"
  retention_in_days = var.log_retention_days
  
  tags = var.tags
}

resource "aws_cloudwatch_log_group" "get_job" {
  name              = "/aws/lambda/${aws_lambda_function.get_job.function_name}"
  retention_in_days = var.log_retention_days
  
  tags = var.tags
}

resource "aws_cloudwatch_log_group" "list_models" {
  name              = "/aws/lambda/${aws_lambda_function.list_models.function_name}"
  retention_in_days = var.log_retention_days
  
  tags = var.tags
}

# WAF Web ACL (if enabled)
resource "aws_wafv2_web_acl" "main" {
  count = var.enable_waf ? 1 : 0
  
  name  = "${var.project_name}-${var.environment}-waf"
  scope = "REGIONAL"
  
  default_action {
    allow {}
  }
  
  rule {
    name     = "RateLimitRule"
    priority = 1
    
    override_action {
      none {}
    }
    
    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-RateLimit"
      sampled_requests_enabled   = true
    }
    
    action {
      block {}
    }
  }
  
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2
    
    override_action {
      none {}
    }
    
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }
  
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-WAF"
    sampled_requests_enabled   = true
  }
  
  tags = var.tags
}

# Associate WAF with API Gateway
resource "aws_wafv2_web_acl_association" "main" {
  count = var.enable_waf ? 1 : 0
  
  resource_arn = aws_apigatewayv2_stage.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main[0].arn
}