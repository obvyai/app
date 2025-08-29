output "api_gateway_id" {
  description = "API Gateway ID"
  value       = aws_apigatewayv2_api.main.id
}

output "api_gateway_domain" {
  description = "API Gateway domain"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "api_gateway_arn" {
  description = "API Gateway ARN"
  value       = aws_apigatewayv2_api.main.arn
}

output "api_gateway_execution_arn" {
  description = "API Gateway execution ARN"
  value       = aws_apigatewayv2_api.main.execution_arn
}

output "lambda_function_names" {
  description = "Lambda function names"
  value = {
    submit_job   = aws_lambda_function.submit_job.function_name
    get_job      = aws_lambda_function.get_job.function_name
    list_models  = aws_lambda_function.list_models.function_name
  }
}

output "lambda_function_arns" {
  description = "Lambda function ARNs"
  value = {
    submit_job   = aws_lambda_function.submit_job.arn
    get_job      = aws_lambda_function.get_job.arn
    list_models  = aws_lambda_function.list_models.arn
  }
}

output "lambda_execution_role_arn" {
  description = "Lambda execution role ARN"
  value       = aws_iam_role.lambda_execution.arn
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].arn : null
}

output "api_stage_arn" {
  description = "API Gateway stage ARN"
  value       = aws_apigatewayv2_stage.main.arn
}

output "cloudwatch_log_group_names" {
  description = "CloudWatch log group names"
  value = {
    api_gateway = aws_cloudwatch_log_group.api_gateway.name
    submit_job  = aws_cloudwatch_log_group.submit_job.name
    get_job     = aws_cloudwatch_log_group.get_job.name
    list_models = aws_cloudwatch_log_group.list_models.name
  }
}