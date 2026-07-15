terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Bootstrap uses local state — DCE environment does not permit S3 bucket creation
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# The GitHub OIDC provider is a singleton per URL within an AWS account — CDEM01's
# bootstrap already created it. Reused here rather than re-created (a second
# aws_iam_openid_connect_provider for the same URL would conflict/fail).
data "aws_iam_openid_connect_provider" "github" {
  arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}
