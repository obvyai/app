output "kms_key_id" {
  description = "KMS key ID"
  value       = var.enable_kms_encryption ? aws_kms_key.main[0].key_id : null
}

output "kms_key_arn" {
  description = "KMS key ARN"
  value       = var.enable_kms_encryption ? aws_kms_key.main[0].arn : null
}

output "inference_input_bucket" {
  description = "S3 bucket name for inference inputs"
  value       = aws_s3_bucket.inference_input.bucket
}

output "inference_input_bucket_arn" {
  description = "S3 bucket ARN for inference inputs"
  value       = aws_s3_bucket.inference_input.arn
}

output "inference_output_bucket" {
  description = "S3 bucket name for inference outputs"
  value       = aws_s3_bucket.inference_output.bucket
}

output "inference_output_bucket_arn" {
  description = "S3 bucket ARN for inference outputs"
  value       = aws_s3_bucket.inference_output.arn
}

output "images_bucket" {
  description = "S3 bucket name for generated images"
  value       = aws_s3_bucket.images.bucket
}

output "images_bucket_arn" {
  description = "S3 bucket ARN for generated images"
  value       = aws_s3_bucket.images.arn
}

output "artifacts_bucket" {
  description = "S3 bucket name for artifacts"
  value       = aws_s3_bucket.artifacts.bucket
}

output "artifacts_bucket_arn" {
  description = "S3 bucket ARN for artifacts"
  value       = aws_s3_bucket.artifacts.arn
}

output "jobs_table_name" {
  description = "DynamoDB jobs table name"
  value       = aws_dynamodb_table.jobs.name
}

output "jobs_table_arn" {
  description = "DynamoDB jobs table ARN"
  value       = aws_dynamodb_table.jobs.arn
}

output "models_table_name" {
  description = "DynamoDB models table name"
  value       = aws_dynamodb_table.models.name
}

output "models_table_arn" {
  description = "DynamoDB models table ARN"
  value       = aws_dynamodb_table.models.arn
}