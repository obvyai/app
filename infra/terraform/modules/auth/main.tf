# Authentication Module - Cognito User Pool and Identity Pool

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = var.cognito_user_pool_name
  
  # Password policy
  password_policy {
    minimum_length                   = var.password_min_length
    require_uppercase                = var.password_require_uppercase
    require_lowercase                = var.password_require_lowercase
    require_numbers                  = var.password_require_numbers
    require_symbols                  = var.password_require_symbols
    temporary_password_validity_days = 7
  }
  
  # Username configuration
  username_attributes = ["email"]
  
  # Auto-verified attributes
  auto_verified_attributes = ["email"]
  
  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
  
  # User pool add-ons
  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }
  
  # Device configuration
  device_configuration {
    challenge_required_on_new_device      = false
    device_only_remembered_on_user_prompt = true
  }
  
  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  
  # Verification message template
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your ${var.project_name} verification code"
    email_message        = "Your verification code is {####}"
  }
  
  # MFA configuration
  mfa_configuration = var.enable_mfa ? "ON" : "OFF"
  
  dynamic "software_token_mfa_configuration" {
    for_each = var.enable_mfa && var.mfa_second_factor == "SOFTWARE_TOKEN" ? [1] : []
    content {
      enabled = true
    }
  }
  
  dynamic "sms_configuration" {
    for_each = var.enable_mfa && var.mfa_second_factor == "SMS_TEXT" ? [1] : []
    content {
      external_id    = "${var.project_name}-${var.environment}-sms"
      sns_caller_arn = aws_iam_role.cognito_sms[0].arn
    }
  }
  
  # Schema
  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "email"
    required                 = true
    
    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }
  
  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "name"
    required                 = false
    
    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }
  
  tags = merge(var.tags, {
    Name = var.cognito_user_pool_name
  })
}

# IAM role for Cognito SMS
resource "aws_iam_role" "cognito_sms" {
  count = var.enable_mfa && var.mfa_second_factor == "SMS_TEXT" ? 1 : 0
  
  name = "${var.project_name}-${var.environment}-cognito-sms-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cognito-idp.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "${var.project_name}-${var.environment}-sms"
          }
        }
      }
    ]
  })
  
  tags = var.tags
}

resource "aws_iam_role_policy" "cognito_sms" {
  count = var.enable_mfa && var.mfa_second_factor == "SMS_TEXT" ? 1 : 0
  
  name = "${var.project_name}-${var.environment}-cognito-sms-policy"
  role = aws_iam_role.cognito_sms[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-${var.environment}-client"
  user_pool_id = aws_cognito_user_pool.main.id
  
  # Client settings
  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation             = true
  enable_propagate_additional_user_context_data = false
  
  # OAuth settings
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  
  # Callback URLs (will be updated with actual frontend URL)
  callback_urls = [
    "http://localhost:3000/auth/callback",
    "https://localhost:3000/auth/callback"
  ]
  
  logout_urls = [
    "http://localhost:3000/auth/logout",
    "https://localhost:3000/auth/logout"
  ]
  
  # Supported identity providers
  supported_identity_providers = ["COGNITO"]
  
  # Token validity
  access_token_validity  = 60    # 1 hour
  id_token_validity     = 60    # 1 hour
  refresh_token_validity = 30   # 30 days
  
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
  
  # Read and write attributes
  read_attributes = [
    "email",
    "email_verified",
    "name"
  ]
  
  write_attributes = [
    "email",
    "name"
  ]
  
  # Explicit auth flows
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.cognito_domain_prefix}-${random_id.domain_suffix.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "random_id" "domain_suffix" {
  byte_length = 4
}

# Cognito Identity Pool
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "${var.project_name}-${var.environment}-identity-pool"
  allow_unauthenticated_identities = false
  allow_classic_flow              = false
  
  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.main.id
    provider_name           = aws_cognito_user_pool.main.endpoint
    server_side_token_check = false
  }
  
  tags = var.tags
}

# IAM roles for authenticated users
resource "aws_iam_role" "authenticated" {
  name = "${var.project_name}-${var.environment}-cognito-authenticated-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })
  
  tags = var.tags
}

# IAM policy for authenticated users
resource "aws_iam_role_policy" "authenticated" {
  name = "${var.project_name}-${var.environment}-cognito-authenticated-policy"
  role = aws_iam_role.authenticated.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cognito-sync:*",
          "cognito-identity:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach roles to identity pool
resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id
  
  roles = {
    "authenticated" = aws_iam_role.authenticated.arn
  }
}