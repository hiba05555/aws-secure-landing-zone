data "terraform_remote_state" "organization" {
  backend = "s3"
  config = {
    bucket = "atlas-fintech-tfstate-179236281274"
    key    = "organization/terraform.tfstate"
    region = "eu-west-1"
  }
}

locals {
  root_ou_id     = data.terraform_remote_state.organization.outputs.root_ou_id
  prod_ou_id     = data.terraform_remote_state.organization.outputs.prod_ou_id
  sandbox_ou_id  = data.terraform_remote_state.organization.outputs.sandbox_ou_id
}

module "deny_region_outside_eu" {
  source = "../modules/aws-scp"

  name           = "DenyRegionOutsideEU"
  description    = "Deny actions outside eu-west-1 and eu-west-3"
  policy_content = file("${path.module}/policies/deny_region_outside_eu.json")
  target_ids     = [local.root_ou_id]
}

module "deny_leave_organization" {
  source = "../modules/aws-scp"

  name           = "DenyLeaveOrganization"
  description    = "Prevent accounts from leaving the organization"
  policy_content = file("${path.module}/policies/deny_leave_organization.json")
  target_ids     = [local.root_ou_id]
}

module "deny_root_user_actions" {
  source = "../modules/aws-scp"

  name           = "DenyRootUserActions"
  description    = "Block root user of member accounts from any action"
  policy_content = file("${path.module}/policies/deny_root_user_actions.json")
  target_ids     = [local.root_ou_id]
}

module "deny_disable_security_services" {
  source = "../modules/aws-scp"

  name           = "DenyDisableSecurityServices"
  description    = "Block disabling CloudTrail, GuardDuty, Config, Security Hub"
  policy_content = file("${path.module}/policies/deny_disable_security_services.json")
  target_ids     = [local.root_ou_id]
}

module "deny_modify_cloudtrail" {
  source = "../modules/aws-scp"

  name           = "DenyModifyCloudTrailLogs"
  description    = "Block tampering with CloudTrail log buckets"
  policy_content = file("${path.module}/policies/deny_modify_cloudtrail.json")
  target_ids     = [local.root_ou_id]
}

module "deny_create_iam_users" {
  source = "../modules/aws-scp"

  name           = "DenyCreateIAMUsers"
  description    = "Force IAM Identity Center adoption by blocking IAM user creation"
  policy_content = file("${path.module}/policies/deny_create_iam_users.json")
  target_ids     = [local.root_ou_id]
}

module "prod_strict_rules" {
  source = "../modules/aws-scp"

  name           = "ProdStrictRules"
  description    = "Strict rules for production accounts"
  policy_content = file("${path.module}/policies/prod_strict_rules.json")
  target_ids     = [local.prod_ou_id]
}

module "sandbox_limits" {
  source = "../modules/aws-scp"

  name           = "SandboxLimits"
  description    = "Cost and resource limits for sandbox account"
  policy_content = file("${path.module}/policies/sandbox_limits.json")
  target_ids     = [local.sandbox_ou_id]
}