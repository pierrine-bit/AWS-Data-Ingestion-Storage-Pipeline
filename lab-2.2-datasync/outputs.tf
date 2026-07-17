output "instance_id" {
  value       = one(aws_instance.onprem_simulator[*].id)
  description = "EC2 instance ID of the on-premises data simulator — private subnet, connect via SSM: aws ssm start-session --target <id>. Null when create_onprem_simulator is false."
}

output "task_arn" {
  value       = aws_datasync_task.sync.arn
  description = "ARN of the DataSync task that syncs raw/ → processed/"
  sensitive   = true
}

output "task_id" {
  value       = aws_datasync_task.sync.id
  description = "ID of the DataSync task — referenced by the TaskExecutionsFailed CloudWatch alarm dimension"
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.datasync.name
  description = "CloudWatch log group receiving DataSync transfer logs (/aws/datasync/raw-to-processed)"
}

output "sns_topic_arn" {
  value       = aws_sns_topic.datasync_notifications.arn
  description = "ARN of the datasync-notifications SNS topic — subscribe an email endpoint to receive failure alerts"
  sensitive   = true
}
