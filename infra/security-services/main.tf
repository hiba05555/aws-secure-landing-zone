data "aws_caller_identity" "current" {}

output "current_identity" {
  value = data.aws_caller_identity.current.account_id
}

# ─────────────────────────────────────────────────────────
# PART 1 — GuardDuty (ML-based threat detection)
# ─────────────────────────────────────────────────────────

# Enable GuardDuty in the management account (delegated admin uses this)



resource "aws_guardduty_organization_admin_account" "delegate" {
  admin_account_id = "930628638898" # GuardDuty delegated admin account ID
}

# Enable GuardDuty organization-wide (auto-enroll all member accounts)

resource "aws_guardduty_organization_configuration" "main" {
    provider                          = aws.delegated
    depends_on                        = [aws_guardduty_organization_admin_account.delegate]
    auto_enable_organization_members  = "ALL"
    detector_id                        = "ecd005aba33cc43f1b0d4b020a63b1d9"
}


# ─────────────────────────────────────────────────────────
# PART 2 — Security Hub (compliance + findings aggregator)
# ─────────────────────────────────────────────────────────

# Enable Security Hub in the management account

resource "aws_securityhub_organization_admin_account" "delegate" {
    admin_account_id = "930628638898" # Security Hub delegated admin account ID
}

# Enable Security Hub organization-wide (auto-enroll all members)
resource "aws_securityhub_organization_configuration" "main" {
    provider = aws.delegated
    auto_enable = true

    depends_on = [
        aws_securityhub_organization_admin_account.delegate
    ]
}

# ── Compliance Standards ────────────────────────────────

# AWS Foundational Security Best Practices (recommended baseline)
resource "aws_securityhub_standards_subscription" "aws_foundational" {
    provider      = aws.delegated
    standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
    depends_on    = [aws_securityhub_organization_admin_account.delegate]
}



# CIS AWS Foundations Benchmark v1.4.0
resource "aws_securityhub_standards_subscription" "cis" {
    provider      = aws.delegated
    standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/cis-aws-foundations-benchmark/v/1.4.0"
    depends_on    = [aws_securityhub_organization_admin_account.delegate]
}
