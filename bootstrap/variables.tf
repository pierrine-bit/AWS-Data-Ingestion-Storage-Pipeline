variable "aws_region" {
  description = "AWS region to deploy bootstrap resources"
  type        = string
}

variable "github_org" {
  description = "GitHub username or organisation that owns the CDEM02 repository"
  type        = string
}

variable "github_repo" {
  description = "CDEM02 GitHub repository name (without the owner prefix)"
  type        = string
}

variable "data_lake_bucket_prefix" {
  description = "Naming prefix shared by the data lake buckets (must match the prefix used in lab-2.1-s3, e.g. \"data-lake-prod-<account_id>\")"
  type        = string
  default     = "data-lake"
}
