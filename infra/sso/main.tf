data "aws_ssoadmin_instances" "main" {}

locals {
    sso_instance_arn = tolist(data.aws_ssoadmin_instances.main.arns)[0]
    identity_store_id = tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]
}

resource "aws_identitystore_user" "hiba" {
  identity_store_id = local.identity_store_id
  user_name         = "hiba"
  display_name      = "Hiba Chagdaly"

  name {
    given_name  = "Hiba"
    family_name = "Chagdaly"
  }

  emails {
    value   = "hibachagdaly19@gmail.com"
    type    = "work"
    primary = true
  }
}

resource "aws_ssoadmin_permission_set" "admin" {
    name = "Admin"
    description = "Admin permission set"
    instance_arn = local.sso_instance_arn
    session_duration = "PT8H"
}

resource "aws_ssoadmin_managed_policy_attachment" "admin" {
    instance_arn = local.sso_instance_arn
    permission_set_arn = aws_ssoadmin_permission_set.admin.arn
    managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssoadmin_permission_set" "readonly" {
    name = "ReadOnly"
    description = "ReadOnly permission set"
    instance_arn = local.sso_instance_arn
    session_duration = "PT8H"
}

resource "aws_ssoadmin_managed_policy_attachment" "readonly" {
    instance_arn = local.sso_instance_arn
    permission_set_arn = aws_ssoadmin_permission_set.readonly.arn
    managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "terraform_remote_state" "accounts" {
    backend = "s3"
    config = {
        bucket  = "atlas-fintech-tfstate-179236281274"
        key     = "accounts/terraform.tfstate"
        region  = "eu-west-1"
    }
}

locals {
  all_accounts = merge(
    data.terraform_remote_state.accounts.outputs.account_ids,
    { management = "179236281274" }
  )
}

resource "aws_ssoadmin_account_assignment" "hibaRootAdmin" {
    for_each = local.all_accounts

    instance_arn = local.sso_instance_arn
    permission_set_arn = aws_ssoadmin_permission_set.admin.arn

    principal_id = aws_identitystore_user.hiba.user_id
    principal_type = "USER"

    target_id = each.value
    target_type = "AWS_ACCOUNT"
    
}