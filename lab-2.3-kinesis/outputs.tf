output "stream_name" {
  value       = one(aws_kinesis_stream.user_events[*].name)
  description = "Name of the Kinesis data stream — pass as KINESIS_STREAM_NAME env var to the producer/consumer scripts. Null when create_kinesis_stream is false."
}

output "stream_arn" {
  value       = one(aws_kinesis_stream.user_events[*].arn)
  description = "ARN of the Kinesis data stream. Null when create_kinesis_stream is false."
  sensitive   = true
}

output "firehose_name" {
  value       = one(aws_kinesis_firehose_delivery_stream.to_s3[*].name)
  description = "Name of the Firehose delivery stream — buffers stream records and writes GZIP files to s3://<bucket>/streaming-data/. Null when create_kinesis_stream is false."
}

output "firehose_log_group" {
  value       = aws_cloudwatch_log_group.firehose.name
  description = "CloudWatch log group for Firehose S3 delivery errors (/aws/kinesisfirehose/user-events-to-s3)"
}

output "dashboard_url" {
  value       = "https://console.aws.amazon.com/cloudwatch/home#dashboards:name=${aws_cloudwatch_dashboard.kinesis_monitoring.dashboard_name}"
  description = "Direct link to the kinesis-monitoring CloudWatch dashboard"
}
