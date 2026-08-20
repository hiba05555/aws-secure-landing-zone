output "sso_instance_arn" {
    description = "The ARN of the AWS SSO instance."
    value       = local.sso_instance_arn
}

output "identity_store_id" {
    description = "The ID of the AWS SSO identity store."
    value       = local.identity_store_id
}

output "hiba_user_id" {
    description = "The ID of the Hiba user."
    value       = aws_identitystore_user.hiba.user_id
}

output "admin_permission_set_arn" {
    description = "The ARN of the Admin permission set."
    value       = aws_ssoadmin_permission_set.admin.arn
}

output "readonly_permission_set_arn" {
    description = "The ARN of the ReadOnly permission set."
    value       = aws_ssoadmin_permission_set.readonly.arn
}

output "all_accounts" {
  description = "Map of all AWS account names and their account IDs."
  value       = local.all_accounts
}