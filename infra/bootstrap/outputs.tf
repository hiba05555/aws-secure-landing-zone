output "tfstate_bucket_name" {
  value       = aws_s3_bucket.tfstate.id
  description = "The id of the S3 bucket for Terraform state"
}

output "tfstate_s3_bucket_arn" {
  value       = aws_s3_bucket.tfstate.arn
  description = "The ARN of the S3 bucket for Terraform state"
}

output "tfstate_dynamodb_table_name" {
  value       = aws_dynamodb_table.tfstate_lock.name
  description = "The name of the DynamoDB table for Terraform state lock"
}