variable "aws_region" {
  type        = string
  description = "AWS region to deploy all resources"
  default     = "eu-west-1"
}

variable "environment" {
  type        = string
  description = "Deployment environment — controls the Environment tag and is embedded in the S3 bucket name"
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "environment must be one of: prod, staging, dev"
  }
}

variable "project" {
  type        = string
  description = "Project name tag applied to all resources"
  default     = "data-platform"
}

variable "owner" {
  type        = string
  description = "Owning team tag applied to all resources"
  default     = "DataEngineering"
}

variable "purpose" {
  type        = string
  description = "Purpose tag applied to all resources"
  default     = "DataLake"
}

variable "cost_center" {
  type        = string
  description = "CostCenter tag applied to all resources"
  default     = "Analytics"
}
