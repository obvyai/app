output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.main.arn
}

output "user_pool_endpoint" {
  description = "Cognito User Pool endpoint"
  value       = aws_cognito_user_pool.main.endpoint
}

output "user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.main.id
}

output "user_pool_domain" {
  description = "Cognito User Pool Domain"
  value       = aws_cognito_user_pool_domain.main.domain
}

output "user_pool_domain_url" {
  description = "Cognito User Pool Domain URL"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}

output "identity_pool_id" {
  description = "Cognito Identity Pool ID"
  value       = aws_cognito_identity_pool.main.id
}

output "authenticated_role_arn" {
  description = "IAM role ARN for authenticated users"
  value       = aws_iam_role.authenticated.arn
}

# Configuration for frontend
output "auth_config" {
  description = "Authentication configuration for frontend"
  value = {
    region          = data.aws_region.current.name
    userPoolId      = aws_cognito_user_pool.main.id
    userPoolWebClientId = aws_cognito_user_pool_client.main.id
    identityPoolId  = aws_cognito_identity_pool.main.id
    domain          = aws_cognito_user_pool_domain.main.domain
    redirectSignIn  = "http://localhost:3000/auth/callback"
    redirectSignOut = "http://localhost:3000/auth/logout"
  }
  sensitive = false
}