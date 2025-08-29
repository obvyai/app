variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cognito_user_pool_name" {
  description = "Name of the Cognito User Pool"
  type        = string
}

variable "cognito_domain_prefix" {
  description = "Domain prefix for Cognito hosted UI"
  type        = string
}

variable "password_min_length" {
  description = "Minimum password length"
  type        = number
  default     = 8
}

variable "password_require_uppercase" {
  description = "Require uppercase letters in password"
  type        = bool
  default     = true
}

variable "password_require_lowercase" {
  description = "Require lowercase letters in password"
  type        = bool
  default     = true
}

variable "password_require_numbers" {
  description = "Require numbers in password"
  type        = bool
  default     = true
}

variable "password_require_symbols" {
  description = "Require symbols in password"
  type        = bool
  default     = false
}

variable "enable_mfa" {
  description = "Enable MFA for Cognito"
  type        = bool
  default     = false
}

variable "mfa_second_factor" {
  description = "MFA second factor method"
  type        = string
  default     = "SMS_TEXT"
  
  validation {
    condition     = contains(["SMS_TEXT", "SOFTWARE_TOKEN"], var.mfa_second_factor)
    error_message = "MFA second factor must be either 'SMS_TEXT' or 'SOFTWARE_TOKEN'."
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}