variable "aws_region" {
  type        = string
  description = "AWS region to deploy all resources"
  default     = "eu-west-1"
}

variable "environment" {
  type        = string
  description = "Deployment environment — must match lab-2.1-s3's environment so the bucket tag resolves to the same bucket"
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
  description = "Purpose tag applied to all resources (e.g. BatchIngestion)"
  default     = "BatchIngestion"
}

variable "cost_center" {
  type        = string
  description = "CostCenter tag used for billing allocation"
  default     = "Analytics"
}

variable "create_onprem_simulator" {
  type        = bool
  description = "Whether to create the on-prem simulator EC2 instance. Disabled by default because this account's AWS Organizations SCP explicitly denies ec2:RunInstances — enable only in an account without that restriction."
  default     = false
}

variable "datasync_schedule" {
  type        = string
  description = "Cron expression for the DataSync transfer schedule (UTC)"
  default     = "cron(0 3 * * ? *)"

  validation {
    condition     = can(regex("^cron\\(", var.datasync_schedule))
    error_message = "datasync_schedule must be a cron() expression, e.g. cron(0 3 * * ? *)"
  }
}
