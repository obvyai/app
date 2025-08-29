output "model_name" {
  description = "SageMaker model name"
  value       = aws_sagemaker_model.main.name
}

output "model_arn" {
  description = "SageMaker model ARN"
  value       = aws_sagemaker_model.main.arn
}

output "endpoint_name" {
  description = "SageMaker endpoint name"
  value       = aws_sagemaker_endpoint.main.name
}

output "endpoint_arn" {
  description = "SageMaker endpoint ARN"
  value       = aws_sagemaker_endpoint.main.arn
}

output "endpoint_config_name" {
  description = "SageMaker endpoint configuration name"
  value       = var.sagemaker_mode == "async" ? aws_sagemaker_endpoint_configuration.async[0].name : aws_sagemaker_endpoint_configuration.realtime[0].name
}

output "execution_role_arn" {
  description = "SageMaker execution role ARN"
  value       = aws_iam_role.sagemaker_execution.arn
}

output "execution_role_name" {
  description = "SageMaker execution role name"
  value       = aws_iam_role.sagemaker_execution.name
}

output "security_group_id" {
  description = "SageMaker security group ID"
  value       = aws_security_group.sagemaker.id
}

output "ecr_repository_uri" {
  description = "ECR repository URI for custom model"
  value       = var.use_jumpstart ? null : aws_ecr_repository.model[0].repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name"
  value       = var.use_jumpstart ? null : aws_ecr_repository.model[0].name
}

output "sagemaker_mode" {
  description = "SageMaker inference mode"
  value       = var.sagemaker_mode
}

output "instance_type" {
  description = "Instance type being used"
  value       = var.sagemaker_mode == "async" ? var.instance_type_async : var.instance_type_realtime
}