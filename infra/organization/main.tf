resource "aws_organizations_organization" "org" {
    aws_service_access_principals = [
        "cloudtrail.amazonaws.com", 
        "config.amazonaws.com",
        "guardduty.amazonaws.com",
        "securityhub.amazonaws.com",
        "sso.amazonaws.com",
        "backup.amazonaws.com",
        ]
    feature_set = "ALL"
    enabled_policy_types = ["SERVICE_CONTROL_POLICY"]
}

resource "aws_organizations_organizational_unit" "security" {
    name = "Security"
    parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "infrastructure" {
    name = "Infrastructure"
    parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads" {
    name = "Workloads"
    parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "sandbox" {
    name = "Sandbox"
    parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "non_prod" {
    name = "Non-Prod"
    parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_organizational_unit" "prod" {
    name = "Prod"
    parent_id = aws_organizations_organizational_unit.workloads.id
}