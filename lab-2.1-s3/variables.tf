variable "aws_region" {
  type        = string
  description = "AWS region to deploy all resources"
}

variable "environment" {
  type        = string
  description = "Deployment environment — controls the Environment tag and is embedded in the S3 bucket name"

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "environment must be one of: prod, staging, dev"
  }
}

variable "project" {
  type        = string
  description = "Project name tag applied to all resources"
}

variable "owner" {
  type        = string
  description = "Owning team tag applied to all resources"
}

variable "purpose" {
  type        = string
  description = "Purpose tag applied to all resources"
}

variable "cost_center" {
  type        = string
  description = "CostCenter tag applied to all resources"
}
