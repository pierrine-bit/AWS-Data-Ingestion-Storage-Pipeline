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
  description = "Purpose tag applied to all resources (e.g. StreamingIngestion)"
  default     = "StreamingIngestion"
}

variable "cost_center" {
  type        = string
  description = "CostCenter tag used for billing allocation"
  default     = "Analytics"
}

variable "create_kinesis_stream" {
  type        = bool
  description = "Whether to create the Kinesis stream (and its dependent Firehose delivery stream). Disabled by default because this account's AWS Organizations SCP explicitly denies kinesis:CreateStream — enable only in an account without that restriction."
  default     = false
}

variable "shard_count" {
  type        = number
  description = "Number of provisioned Kinesis shards (each shard supports 1,000 records/sec or 1 MB/sec write throughput)"
  default     = 4

  validation {
    condition     = var.shard_count >= 1 && var.shard_count <= 500
    error_message = "shard_count must be between 1 and 500"
  }
}
