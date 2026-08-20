output "guarduty_detector_id" {
    description = "Guarduty detector id in the management account"
    value       = aws_guardduty_detector.main.id
}

output "guarduty_detector_arn" {
    description = "Guarduty detector arn in the management account"
    value = aws_guardduty_detector.main.arn
}

output "securityhub_account_id" {
    description = "Security Hub account id"
    value = aws_securityhub_account.main.id
}

output "enabled_standards" {
    description = "list of enabled security hub standards"
    value = [
        aws_securityhub_standards_subscription.aws_foundational.standards_arn,
        aws_securityhub_standards_subscription.cis
    ]
}