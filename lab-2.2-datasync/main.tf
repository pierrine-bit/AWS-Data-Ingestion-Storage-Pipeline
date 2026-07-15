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
  data_lake_bucket_arn  = data.aws_resourcegroupstaggingapi_resources.data_lake_bucket.resource_tag_mapping_list[0].resource_arn
  data_lake_bucket_name = element(split(":::", local.data_lake_bucket_arn), 1)
}

# Lab 1.2's private subnet + security group, looked up by their literal names.
data "aws_subnet" "private_1b" {
  filter {
    name   = "tag:Name"
    values = ["private-subnet-1b"]
  }
}

data "aws_security_group" "private_compute" {
  filter {
    name   = "tag:Name"
    values = ["sg-private-compute"]
  }
}

# Lab 1.1's DataEngineerRole, reused as the on-prem simulator's instance role
# (the lab doc doesn't create a dedicated EC2 role for this instance).
data "aws_iam_role" "data_engineer" {
  name = "DataEngineerRole"
}

resource "aws_iam_instance_profile" "onprem_simulator" {
  name = "onprem-simulator-profile"
  role = data.aws_iam_role.data_engineer.name
}

# ---------------------------------------------------------------------------
# DataSyncS3Role — full S3 access, used by both DataSync locations
# ---------------------------------------------------------------------------
resource "aws_iam_role" "datasync_s3" {
  name = "DataSyncS3Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "datasync.amazonaws.com" }
    }]
  })
  description = "Full S3 access role assumed by AWS DataSync"
}

resource "aws_iam_role_policy_attachment" "datasync_s3" {
  role       = aws_iam_role.datasync_s3.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# ---------------------------------------------------------------------------
# On-premises simulator EC2 — pushes sample files to raw/ on boot
# ---------------------------------------------------------------------------
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "onprem_simulator" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t2.micro"
  subnet_id              = data.aws_subnet.private_1b.id
  vpc_security_group_ids = [data.aws_security_group.private_compute.id]
  iam_instance_profile   = aws_iam_instance_profile.onprem_simulator.name

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y awscli
    mkdir -p /opt/onprem-data

    cat > /opt/onprem-data/customer_master.csv << 'CSV'
customer_id,name,email,signup_date,region
C001,Alice Johnson,alice@example.com,2024-01-15,us-east
C002,Bob Smith,bob@example.com,2024-02-20,us-west
C003,Carol White,carol@example.com,2024-03-10,eu-west
CSV

    cat > /opt/onprem-data/sales_history.csv << 'CSV'
transaction_id,customer_id,amount,product,date
T001,C001,99.99,Premium Plan,2024-06-01
T002,C002,49.99,Basic Plan,2024-06-02
T003,C003,149.99,Enterprise Plan,2024-06-03
CSV

    cat > /opt/onprem-data/transaction_log.csv << 'CSV'
log_id,transaction_id,action,timestamp,status
L001,T001,created,2024-06-01T10:00:00Z,completed
L002,T002,created,2024-06-02T11:30:00Z,completed
L003,T003,created,2024-06-03T14:15:00Z,completed
CSV

    # Push on-premises data to S3 raw/ so DataSync can process it.
    # --sse AES256 satisfies the bucket policy's DenyUnencryptedUploads condition.
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    aws s3 cp /opt/onprem-data/ s3://${local.data_lake_bucket_name}/raw/ \
      --recursive --sse AES256 --region $REGION
  EOF

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "datasync-test-server"
    Role = "simulated-on-premises"
  }
}

# ---------------------------------------------------------------------------
# DataSync locations + task
# ---------------------------------------------------------------------------
resource "aws_datasync_location_s3" "source" {
  s3_bucket_arn = local.data_lake_bucket_arn
  subdirectory  = "/raw/"
  s3_config { bucket_access_role_arn = aws_iam_role.datasync_s3.arn }
  tags = { Name = "onprem-s3-raw-location" }
}

resource "aws_datasync_location_s3" "destination" {
  s3_bucket_arn = local.data_lake_bucket_arn
  subdirectory  = "/processed/"
  s3_config { bucket_access_role_arn = aws_iam_role.datasync_s3.arn }
  tags = { Name = "aws-s3-processed-location" }
}

resource "aws_cloudwatch_log_group" "datasync" {
  name              = "/aws/datasync/raw-to-processed"
  retention_in_days = 30
  tags              = { Name = "DataSyncLogs" }
}

# DataSync writes logs as the datasync.amazonaws.com service principal, not via
# the location's IAM role — it needs a resource policy on the log group itself,
# not an identity policy on any role, or task logging silently never appears.
data "aws_iam_policy_document" "datasync_logs" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.datasync.arn}:*"]

    principals {
      type        = "Service"
      identifiers = ["datasync.amazonaws.com"]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "datasync" {
  policy_name     = "datasync-logs-policy"
  policy_document = data.aws_iam_policy_document.datasync_logs.json
}

resource "aws_datasync_task" "sync" {
  name                     = "raw-to-processed-sync"
  source_location_arn      = aws_datasync_location_s3.source.arn
  destination_location_arn = aws_datasync_location_s3.destination.arn

  schedule { schedule_expression = var.datasync_schedule }

  options {
    bytes_per_second       = -1
    verify_mode            = "ONLY_FILES_TRANSFERRED"
    overwrite_mode         = "ALWAYS"
    log_level              = "TRANSFER"
    preserve_deleted_files = "PRESERVE"
    posix_permissions      = "NONE"
    uid                    = "NONE"
    gid                    = "NONE"
  }

  cloudwatch_log_group_arn = aws_cloudwatch_log_group.datasync.arn

  tags = {
    Name        = "raw-to-processed-sync"
    Description = "Daily sync from raw to processed"
  }

  depends_on = [aws_cloudwatch_log_resource_policy.datasync]
}

# ---------------------------------------------------------------------------
# CloudWatch alerting
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "datasync_notifications" {
  name              = "datasync-notifications"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_cloudwatch_metric_alarm" "datasync_failure" {
  alarm_name                = "datasync-task-executions-failed"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = 1
  metric_name               = "TaskExecutionsFailed"
  namespace                 = "AWS/DataSync"
  period                    = 300
  statistic                 = "Sum"
  threshold                 = 0
  alarm_description         = "One or more DataSync task executions failed"
  alarm_actions             = [aws_sns_topic.datasync_notifications.arn]
  ok_actions                = [aws_sns_topic.datasync_notifications.arn]
  insufficient_data_actions = [aws_sns_topic.datasync_notifications.arn]
  dimensions                = { TaskId = aws_datasync_task.sync.id }
}
