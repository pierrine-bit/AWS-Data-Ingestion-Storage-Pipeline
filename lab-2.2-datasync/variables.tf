variable "aws_region" {
  type        = string
  description = "AWS region to deploy all resources"
}

variable "environment" {
  type        = string
  description = "Deployment environment — must match lab-2.1-s3's environment so the bucket tag resolves to the same bucket"

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
  description = "Purpose tag applied to all resources (e.g. BatchIngestion)"
}

variable "cost_center" {
  type        = string
  description = "CostCenter tag used for billing allocation"
}

variable "datasync_schedule" {
  type        = string
  description = "Cron expression for the DataSync transfer schedule (UTC)"

  validation {
    condition     = can(regex("^cron\\(", var.datasync_schedule))
    error_message = "datasync_schedule must be a cron() expression, e.g. cron(0 3 * * ? *)"
  }
}
