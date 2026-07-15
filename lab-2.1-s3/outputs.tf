output "bucket_name" {
  value       = aws_s3_bucket.data_lake.id
  description = "Name of the data lake S3 bucket — tagged DataLakeRole=primary so Lab 2.2 and 2.3 can discover it without hardcoding"
}

output "bucket_arn" {
  value       = aws_s3_bucket.data_lake.arn
  description = "ARN of the data lake S3 bucket"
  sensitive   = true
}

output "logs_bucket" {
  value       = aws_s3_bucket.logs.id
  description = "Name of the S3 access-logs and CloudTrail bucket"
}

output "cloudtrail_trail_arn" {
  value       = aws_cloudtrail.audit.arn
  description = "ARN of the multi-region CloudTrail trail auditing S3 object-level events"
  sensitive   = true
}

output "glue_database_name" {
  value       = aws_glue_catalog_database.raw_data.name
  description = "Glue Catalog database — query via Athena: SELECT * FROM raw_data.test_customers"
}

output "glue_table_name" {
  value       = aws_glue_catalog_table.test_customers.name
  description = "Glue Catalog table pointing at s3://<bucket>/raw/test_customers/"
}
