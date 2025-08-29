output "vpc_id" {
  description = "ID of the VPC"
  value       = local.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = var.use_custom_vpc ? aws_vpc.main[0].cidr_block : data.aws_vpc.default[0].cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = local.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = local.public_subnet_ids
}

output "availability_zones" {
  description = "Availability zones used"
  value       = local.availability_zones
}

output "sagemaker_security_group_id" {
  description = "Security group ID for SageMaker"
  value       = aws_security_group.sagemaker.id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = var.use_custom_vpc ? aws_internet_gateway.main[0].id : null
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = var.use_custom_vpc ? aws_nat_gateway.main[*].id : []
}

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 VPC Endpoint"
  value       = var.use_custom_vpc ? aws_vpc_endpoint.s3[0].id : null
}

output "sagemaker_vpc_endpoint_id" {
  description = "ID of the SageMaker VPC Endpoint"
  value       = var.use_custom_vpc ? aws_vpc_endpoint.sagemaker_runtime[0].id : null
}