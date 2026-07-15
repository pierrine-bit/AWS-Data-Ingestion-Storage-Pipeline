resource "aws_iam_role" "github_actions" {
  name        = "GitHubActionsRoleCDEM02"
  description = "Assumed by GitHub Actions via OIDC - scoped to ${var.github_org}/${var.github_repo}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }
        Action = ["sts:AssumeRoleWithWebIdentity", "sts:TagSession"]
        # AWS requires this trust policy to be scoped via "sub" or "job_workflow_ref"
        # (rejects anything it considers unscoped) — plain "repository" matching
        # alone isn't accepted. GitHub also now embeds numeric owner/repo IDs into
        # sub (e.g. "repo:org@123/repo@456:ref:..."), so the old literal
        # "repo:org/repo:*" pattern never matched; wildcarding around the IDs here
        # fixes that. "repository" is kept alongside as a clean, ID-free check.
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud"        = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:repository" = "${var.github_org}/${var.github_repo}"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}@*/${var.github_repo}@*:*"
          }
        }
      }
    ]
  })

  tags = {
    Name      = "GitHubActionsRoleCDEM02"
    ManagedBy = "Terraform"
    Project   = "DataPlatform"
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name = "GitHubActionsPolicyCDEM02"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3DataLakeLab21"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:PutBucketTagging",
          "s3:GetBucketTagging",
          "s3:PutBucketAcl",
          "s3:GetBucketAcl",
          "s3:PutBucketOwnershipControls",
          "s3:GetBucketOwnershipControls",
          "s3:PutBucketPolicy",
          "s3:GetBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutEncryptionConfiguration",
          "s3:GetEncryptionConfiguration",
          "s3:PutBucketVersioning",
          "s3:GetBucketVersioning",
          "s3:PutLifecycleConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:PutBucketLogging",
          "s3:GetBucketLogging",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::${var.data_lake_bucket_prefix}-*",
          "arn:${data.aws_partition.current.partition}:s3:::${var.data_lake_bucket_prefix}-*/*"
        ]
      },
      {
        Sid    = "GlueDataCatalogLab21"
        Effect = "Allow"
        Action = [
          "glue:CreateDatabase",
          "glue:DeleteDatabase",
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:CreateTable",
          "glue:DeleteTable",
          "glue:GetTable",
          "glue:GetTables",
          "glue:UpdateTable",
          "glue:TagResource",
          "glue:UntagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudTrailLab21"
        Effect = "Allow"
        Action = [
          "cloudtrail:CreateTrail",
          "cloudtrail:DeleteTrail",
          "cloudtrail:UpdateTrail",
          "cloudtrail:PutEventSelectors",
          "cloudtrail:GetEventSelectors",
          "cloudtrail:StartLogging",
          "cloudtrail:StopLogging",
          "cloudtrail:GetTrailStatus",
          "cloudtrail:DescribeTrails",
          "cloudtrail:ListTags",
          "cloudtrail:AddTags",
          "cloudtrail:RemoveTags"
        ]
        Resource = "*"
      },
      {
        # lab-2.1-s3 looks these up (via data "aws_iam_role") to build its bucket
        # policy's allowed-principals list — they're created by CDEM01's Lab 1.1.
        Sid    = "IAMRoleLookupLab21"
        Effect = "Allow"
        Action = ["iam:GetRole"]
        Resource = [
          "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/DataEngineerRole",
          "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/GlueServiceRole",
          "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/RedshiftIAMRole"
        ]
      }
    ]
  })
}
