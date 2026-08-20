output "account_ids" {
  description = "Map of account name to account ID"
  value       = {for name, account in module.accounts : name => account.account_id}
}

output "account_arns" {
  description = "Map of account name to account ARN"
  value       = {for name, account in module.accounts : name => account.account_arn}
}

output "account_emails" {
  description = "Map of account name to account email"
  value       = {for name, account in module.accounts : name => account.account_email}
}