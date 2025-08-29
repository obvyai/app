variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "sagemaker_mode" {
  description = "SageMaker inference mode: async or realtime"
  type        = string
  default     = "async"
  
  validation {
    condition     = contains(["async", "realtime"], var.sagemaker_mode)
    error_message = "SageMaker mode must be either 'async' or 'realtime'."
  }
}

variable "instance_type_async" {
  description = "Instance type for async inference"
  type        = string
  default     = "ml.g5.xlarge"
}

variable "instance_type_realtime" {
  description = "Instance type for real-time inference"
  type        = string
  default     = "ml.g5.xlarge"
}

variable "max_concurrency" {
  description = "Maximum concurrent invocations per instance"
  type        = number
  default     = 10
}

variable "min_capacity_realtime" {
  description = "Minimum capacity for real-time endpoint"
  type        = number
  default     = 1
}

variable "max_capacity_realtime" {
  description = "Maximum capacity for real-time endpoint"
  type        = number
  default     = 5
}

variable "inference_timeout" {
  description = "Inference timeout in seconds"
  type        = number
  default     = 300
}

variable "async_timeout" {
  description = "Async inference timeout in seconds"
  type        = number
  default     = 3600
}

variable "scale_down_cooldown" {
  description = "Scale down cooldown period in seconds"
  type        = number
  default     = 300
}

variable "scale_up_cooldown" {
  description = "Scale up cooldown period in seconds"
  type        = number
  default     = 60
}

variable "use_jumpstart" {
  description = "Use SageMaker JumpStart model instead of custom container"
  type        = bool
  default     = true
}

variable "jumpstart_model_id" {
  description = "SageMaker JumpStart model ID"
  type        = string
  default     = "huggingface-txt2img-stable-diffusion-xl-base-1-0"
}

variable "ecr_repository_name" {
  description = "ECR repository name for custom model container"
  type        = string
  default     = "obvy-model"
}

variable "model_image_tag" {
  description = "Model container image tag"
  type        = string
  default     = "latest"
}

# Dependencies
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "inference_input_bucket" {
  description = "S3 bucket for inference inputs"
  type        = string
}

variable "inference_output_bucket" {
  description = "S3 bucket for inference outputs"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}