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
  description = "Purpose tag applied to all resources (e.g. StreamingIngestion)"
}

variable "cost_center" {
  type        = string
  description = "CostCenter tag used for billing allocation"
}

variable "shard_count" {
  type        = number
  description = "Number of provisioned Kinesis shards (each shard supports 1,000 records/sec or 1 MB/sec write throughput)"

  validation {
    condition     = var.shard_count >= 1 && var.shard_count <= 500
    error_message = "shard_count must be between 1 and 500"
  }
}
