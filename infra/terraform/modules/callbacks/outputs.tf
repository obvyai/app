output "success_topic_arn" {
  description = "SNS success topic ARN"
  value       = aws_sns_topic.success.arn
}

output "error_topic_arn" {
  description = "SNS error topic ARN"
  value       = aws_sns_topic.error.arn
}

output "success_topic_name" {
  description = "SNS success topic name"
  value       = aws_sns_topic.success.name
}

output "error_topic_name" {
  description = "SNS error topic name"
  value       = aws_sns_topic.error.name
}

output "lambda_function_name" {
  description = "Callback Lambda function name"
  value       = aws_lambda_function.callback.function_name
}

output "lambda_function_arn" {
  description = "Callback Lambda function ARN"
  value       = aws_lambda_function.callback.arn
}

output "lambda_execution_role_arn" {
  description = "Lambda execution role ARN"
  value       = aws_iam_role.callback_execution.arn
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.callback.name
}