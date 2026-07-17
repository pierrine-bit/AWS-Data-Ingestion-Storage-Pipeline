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

# This account's AWS Organizations SCP explicitly denies kinesis:AddTagsToStream.
# default_tags merges into every taggable resource's API calls regardless of
# that resource's own tags block, so the only way to create the stream with
# zero tags (and avoid triggering the denied call) is a second provider alias
# with no default_tags, used only for aws_kinesis_stream.user_events.
provider "aws" {
  alias  = "no_default_tags"
  region = var.aws_region
}
