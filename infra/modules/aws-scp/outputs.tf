output "policy_id" {
  description = "The ID of the created AWS SCP."
  value       = aws_organizations_policy.this.id
}

output "policy_arn" {
    description = "The ARN of the created AWS SCP."
    value       = aws_organizations_policy.this.arn
}