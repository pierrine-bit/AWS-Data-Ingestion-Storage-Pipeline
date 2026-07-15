provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project
      Owner       = var.owner
      Purpose     = var.purpose
      CostCenter  = var.cost_center
      ManagedBy   = "Terraform"
    }
  }
}
