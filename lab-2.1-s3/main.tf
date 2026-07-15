data "aws_caller_identity" "current" {}

# Lab 1.1 roles, looked up by their literal names so this lab stays connected
# to Lab 1.1's state without duplicating or re-managing those resources.
data "aws_iam_role" "data_engineer" {
  name = "DataEngineerRole"
}

data "aws_iam_role" "glue_service" {
  name = "GlueServiceRole"
}

data "aws_iam_role" "redshift" {
  name = "RedshiftIAMRole"
}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "data-lake-${var.environment}-${local.account_id}"
  logs_bucket = "data-lake-${var.environment}-logs-${local.account_id}"
  allowed_role_arns = [
    data.aws_iam_role.data_engineer.arn,
    data.aws_iam_role.glue_service.arn,
    data.aws_iam_role.redshift.arn
  ]
}

# Main data lake bucket
resource "aws_s3_bucket" "data_lake" {
  bucket = local.bucket_name
  # DataLakeRole distinguishes this bucket from the logs bucket for other labs'
  # tag-based lookups (aws_resourcegroupstaggingapi_resources) — lets Lab 2.2/2.3
  # find this bucket without needing to know or reconstruct its naming convention.
  tags = { Name = local.bucket_name, DataLakeRole = "primary" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket                  = aws_s3_bucket.data_lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_policy" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceHTTPS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "arn:aws:s3:::${local.bucket_name}",
          "arn:aws:s3:::${local.bucket_name}/*"
        ]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "DenyUnencryptedUploads"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "arn:aws:s3:::${local.bucket_name}/*"
        # StringNotEqualsIfExists: only denies when the caller explicitly sets
        # an SSE algorithm other than AES256.  Requests with no SSE header
        # (AWS services, aws s3 cp) fall through to the bucket's default
        # AES256 encryption instead of being denied.
        Condition = {
          StringNotEqualsIfExists = { "s3:x-amz-server-side-encryption" = "AES256" }
        }
      },
      # Explicit allow-list for audit visibility — access is already governed by
      # each role's own IAM identity policy, this just makes the intended set of
      # accessing roles visible directly in the bucket's resource policy.
      {
        Sid       = "AllowPlatformRolesOnly"
        Effect    = "Allow"
        Principal = { AWS = local.allowed_role_arns }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject",
          "s3:GetBucketLocation",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = [
          "arn:aws:s3:::${local.bucket_name}",
          "arn:aws:s3:::${local.bucket_name}/*"
        ]
      }
    ]
  })
}

# Logs bucket
resource "aws_s3_bucket" "logs" {
  bucket = local.logs_bucket
  tags   = { Name = local.logs_bucket }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule { object_ownership = "BucketOwnerPreferred" }
}

resource "aws_s3_bucket_acl" "logs" {
  depends_on = [aws_s3_bucket_ownership_controls.logs]
  bucket     = aws_s3_bucket.logs.id
  acl        = "log-delivery-write"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "data_lake" {
  bucket        = aws_s3_bucket.data_lake.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access-logs/"
}

# Lifecycle policies
resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "processed-data-lifecycle"
    status = "Enabled"
    filter { prefix = "processed/" }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    transition {
      days          = 180
      storage_class = "DEEP_ARCHIVE"
    }
  }

  rule {
    id     = "temp-data-cleanup"
    status = "Enabled"
    filter { prefix = "temp/" }
    expiration { days = 1 }
  }

  rule {
    id     = "archive-data-lifecycle"
    status = "Enabled"
    filter { prefix = "archive/" }
    transition {
      days          = 30
      storage_class = "DEEP_ARCHIVE"
    }
    expiration { days = 2555 }
  }
}

# Folder structure
resource "aws_s3_object" "folders" {
  for_each               = toset(["raw/", "processed/", "curated/", "temp/", "archive/"])
  bucket                 = aws_s3_bucket.data_lake.id
  key                    = each.value
  content                = ""
  server_side_encryption = "AES256"
}

# Test data — lives in its own subfolder so the Glue table location
# (raw/test_customers/) doesn't also pick up other CSVs that land under raw/
# (e.g. Lab 2.2's on-prem simulator files), which have different schemas.
resource "aws_s3_object" "test_customers" {
  bucket                 = aws_s3_bucket.data_lake.id
  key                    = "raw/test_customers/test_customers.csv"
  content_type           = "text/csv"
  server_side_encryption = "AES256"
  # Content lines are indented to match the closing CSV marker so <<- strips
  # exactly 2 spaces and the resulting object has no leading whitespace per line.
  content = <<-CSV
  customer_id,name,email,signup_date,region
  C001,Alice Johnson,alice@example.com,2024-01-15,us-east
  C002,Bob Smith,bob@example.com,2024-02-20,us-west
  C003,Carol White,carol@example.com,2024-03-10,eu-west
  CSV
}

# CloudTrail
resource "aws_s3_bucket_policy" "logs_trail" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.logs.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/cloudtrail/AWSLogs/${local.account_id}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      }
    ]
  })
}

resource "aws_cloudtrail" "audit" {
  name                          = "data-lake-audit-trail"
  s3_bucket_name                = aws_s3_bucket.logs.id
  s3_key_prefix                 = "cloudtrail"
  enable_logging                = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  # Management events (bucket changes, IAM calls) are logged by default — this adds
  # S3 object-level data events so per-object reads/writes are also captured.
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.data_lake.arn}/"]
    }
  }

  depends_on = [aws_s3_bucket_policy.logs_trail]
}

# Glue Catalog — makes raw/test_customers/ queryable via Athena
resource "aws_glue_catalog_database" "raw_data" {
  name = "raw_data"
}

resource "aws_glue_catalog_table" "test_customers" {
  name          = "test_customers"
  database_name = aws_glue_catalog_database.raw_data.name
  table_type    = "EXTERNAL_TABLE"
  depends_on    = [aws_s3_object.test_customers]

  parameters = {
    "classification"         = "csv"
    "skip.header.line.count" = "1"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data_lake.id}/raw/test_customers/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
      parameters = {
        "field.delim" = ","
      }
    }

    columns {
      name = "customer_id"
      type = "string"
    }
    columns {
      name = "name"
      type = "string"
    }
    columns {
      name = "email"
      type = "string"
    }
    columns {
      name = "signup_date"
      type = "string"
    }
    columns {
      name = "region"
      type = "string"
    }
  }
}
