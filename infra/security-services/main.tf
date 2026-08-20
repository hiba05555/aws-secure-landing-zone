# ─────────────────────────────────────────────────────────
# PART 1 — GuardDuty (ML-based threat detection)
# ─────────────────────────────────────────────────────────

# Enable GuardDuty in the management account (delegated admin uses this)

resource "aws_guardduty_detector" "main" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = {
    Name = "atlas-fintech-guardduty"
  }
}

# Enable GuardDuty organization-wide (auto-enroll all member accounts)
resource "aws_guardduty_organization_configuration" "main" {
  auto_enable_organization_members = "ALL"
  detector_id                       = aws_guardduty_detector.main.id
}


# ─────────────────────────────────────────────────────────
# PART 2 — Security Hub (compliance + findings aggregator)
# ─────────────────────────────────────────────────────────

# Enable Security Hub in the management account

resource "aws_securityhub_account" "main" {
    enable_default_standards = false
}

# Enable Security Hub organization-wide (auto-enroll all members)
resource "aws_securityhub_organization_configuration" "main" {
    auto_enable = true

    depends_on = [
        aws_securityhub_account.main
    ]
}

# ── Compliance Standards ────────────────────────────────

# AWS Foundational Security Best Practices (recommended baseline)

resource "aws_securityhub_standards_subscription" "aws_foundational" {
    standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"

    depends_on = [aws_securityhub_account.main]
}

# CIS AWS Foundations Benchmark v1.4.0

resource "aws_securityhub_standards_subscription" "cis" {
    standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/cis-aws-foundations-benchmark/v/1.4.0"

    depends_on = [aws_securityhub_account.main]

}