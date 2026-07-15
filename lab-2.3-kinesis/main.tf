# Looked up by the DataLakeRole tag Lab 2.1 sets on its bucket, rather than
# reconstructing Lab 2.1's naming convention here — decouples this lab from
# how Lab 2.1 names its bucket.
data "aws_resourcegroupstaggingapi_resources" "data_lake_bucket" {
  resource_type_filters = ["s3"]
  tag_filter {
    key    = "DataLakeRole"
    values = ["primary"]
  }
}

locals {
  data_lake_bucket_arn = data.aws_resourcegroupstaggingapi_resources.data_lake_bucket.resource_tag_mapping_list[0].resource_arn
}

resource "aws_kinesis_stream" "user_events" {
  name             = "user-events-stream"
  shard_count      = var.shard_count
  retention_period = 24

  shard_level_metrics = [
    "IncomingRecords",
    "IncomingBytes",
    "OutgoingRecords",
    "OutgoingBytes",
    "WriteProvisionedThroughputExceeded",
    "ReadProvisionedThroughputExceeded",
    "IteratorAgeMilliseconds"
  ]

  stream_mode_details { stream_mode = "PROVISIONED" }

  tags = { Name = "user-events-stream" }
}

# ---------------------------------------------------------------------------
# Firehose delivery role — not defined in Lab 1.1, created here for the
# Kinesis -> S3 delivery stream (read stream, write bucket, write logs)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "firehose" {
  name = "FirehoseToS3Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
    }]
  })
  description = "Role assumed by Kinesis Firehose to read the stream and write to S3"
}

resource "aws_iam_role_policy" "firehose" {
  name = "FirehoseS3Policy"
  role = aws_iam_role.firehose.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          local.data_lake_bucket_arn,
          "${local.data_lake_bucket_arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:PutLogEvents", "logs:CreateLogStream"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.user_events.arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/user-events-to-s3"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_stream" "firehose_s3" {
  name           = "s3-delivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_kinesis_firehose_delivery_stream" "to_s3" {
  name        = "user-events-to-s3"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.user_events.arn
    role_arn           = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = local.data_lake_bucket_arn
    prefix              = "streaming-data/"
    error_output_prefix = "streaming-data-errors/"
    buffering_size      = 5
    buffering_interval  = 300
    compression_format  = "GZIP"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = "s3-delivery"
    }
  }

  tags = { Name = "user-events-to-s3" }
}

# ---------------------------------------------------------------------------
# CloudWatch dashboard
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "kinesis_monitoring" {
  dashboard_name = "kinesis-monitoring"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [["AWS/Kinesis", "IncomingRecords", "StreamName", aws_kinesis_stream.user_events.name]]
          period  = 60
          stat    = "Sum"
          region  = var.aws_region
          title   = "Kinesis Incoming Records"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [["AWS/Kinesis", "IncomingBytes", "StreamName", aws_kinesis_stream.user_events.name]]
          period  = 60
          stat    = "Sum"
          region  = var.aws_region
          title   = "Kinesis Incoming Bytes"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [["AWS/Kinesis", "IteratorAgeMilliseconds", "StreamName", aws_kinesis_stream.user_events.name]]
          period  = 60
          stat    = "Average"
          region  = var.aws_region
          title   = "Kinesis Iterator Age"
          view    = "gauge"
        }
      }
    ]
  })
}
