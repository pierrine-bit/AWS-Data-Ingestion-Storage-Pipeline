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
        # AWS requires this trust policy to be scoped via "sub" or "job_workflow_ref".
        # GitHub now embeds numeric owner/repo IDs into sub (e.g.
        # "repo:org@123/repo@456:ref:..."), so the old literal "repo:org/repo:*"
        # pattern never matched; wildcarding around the IDs here fixes that.
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
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
        Sid    = "StateBackend"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::cdem01-tfstate",
          "arn:${data.aws_partition.current.partition}:s3:::cdem01-tfstate/*"
        ]
      },
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
          "s3:PutBucketCORS",
          "s3:GetBucketCORS",
          "s3:PutBucketWebsite",
          "s3:GetBucketWebsite",
          "s3:PutBucketRequestPayment",
          "s3:GetBucketRequestPayment",
          "s3:PutAccelerateConfiguration",
          "s3:GetAccelerateConfiguration",
          "s3:PutReplicationConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:PutBucketObjectLockConfiguration",
          "s3:GetBucketObjectLockConfiguration",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:PutObjectTagging",
          "s3:GetObjectTagging"
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
          "glue:GetTags",
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
      },
      {
        # lab-2.2-datasync looks up Lab 1.2's private subnet/security group by tag,
        # Lab 2.1's data lake bucket via the tagging API, and the latest Amazon
        # Linux 2 AMI for the on-prem simulator EC2 instance.
        Sid    = "ReadOnlyLookupsLab22"
        Effect = "Allow"
        Action = [
          "tag:GetResources",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeInstanceAttribute",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "PassDataEngineerRoleLab22"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/DataEngineerRole"
      },
      {
        Sid    = "IAMManageLab22"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:UntagInstanceProfile"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2SimulatorLab22"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:ModifyInstanceAttribute",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "DataSyncLab22"
        Effect = "Allow"
        Action = [
          "datasync:CreateLocationS3",
          "datasync:DeleteLocation",
          "datasync:DescribeLocationS3",
          "datasync:CreateTask",
          "datasync:DeleteTask",
          "datasync:DescribeTask",
          "datasync:UpdateTask",
          "datasync:TagResource",
          "datasync:UntagResource",
          "datasync:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "LogsLab22"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:CreateLogStream",
          "logs:DeleteLogStream",
          "logs:DescribeLogStreams",
          "logs:PutRetentionPolicy",
          "logs:TagLogGroup",
          "logs:TagResource",
          "logs:UntagResource",
          "logs:ListTagsForResource",
          "logs:ListTagsLogGroup",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DeleteResourcePolicy"
        ]
        Resource = "*"
      },
      {
        Sid    = "SNSLab22"
        Effect = "Allow"
        Action = [
          "sns:CreateTopic",
          "sns:DeleteTopic",
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:TagResource",
          "sns:UntagResource",
          "sns:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchAlarmLab22"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:DeleteAlarms",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:TagResource",
          "cloudwatch:UntagResource",
          "cloudwatch:ListTagsForResource",
          "cloudwatch:PutDashboard",
          "cloudwatch:DeleteDashboards",
          "cloudwatch:GetDashboard",
          "cloudwatch:ListDashboards"
        ]
        Resource = "*"
      },
      {
        Sid    = "KinesisLab23"
        Effect = "Allow"
        Action = [
          "kinesis:CreateStream",
          "kinesis:DeleteStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:DescribeStream",
          "kinesis:EnableEnhancedMonitoring",
          "kinesis:DisableEnhancedMonitoring",
          "kinesis:IncreaseStreamRetentionPeriod",
          "kinesis:DecreaseStreamRetentionPeriod",
          "kinesis:AddTagsToStream",
          "kinesis:RemoveTagsFromStream",
          "kinesis:ListTagsForStream"
        ]
        Resource = "*"
      },
      {
        Sid    = "FirehoseLab23"
        Effect = "Allow"
        Action = [
          "firehose:CreateDeliveryStream",
          "firehose:DeleteDeliveryStream",
          "firehose:DescribeDeliveryStream",
          "firehose:UpdateDestination",
          "firehose:TagDeliveryStream",
          "firehose:UntagDeliveryStream",
          "firehose:ListTagsForDeliveryStream"
        ]
        Resource = "*"
      }
    ]
  })
}
