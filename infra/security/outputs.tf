output "kms_key_arn" {
    description = "ARN of the shared KMS key for logs and ECR encryption"
    value       = aws_kms_key.security.arn
}

output "ecs_log_group_name" {
    description = "Name of the CloudWatch log group for ECS app logs"
    value       = aws_cloudwatch_log_group.security.name
}

output "ecs_log_group_arn" {
    description = "ARN of the CloudWatch log group for ECS app logs"
    value       = aws_cloudwatch_log_group.security.arn
}