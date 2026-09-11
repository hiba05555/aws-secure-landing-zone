

output "aws_securityhub_organization_admin_account" {
    description = "Security Hub delegated admin account id"
    value = aws_securityhub_organization_admin_account.delegate.admin_account_id
}

output "enabled_standards" {
    description = "list of enabled security hub standards"
    value = [
        aws_securityhub_standards_subscription.aws_foundational.standards_arn,
        aws_securityhub_standards_subscription.cis
    ]
}