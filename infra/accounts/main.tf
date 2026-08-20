data "terraform_remote_state" "organization" {
  backend = "s3"
  config = {
    bucket  = "atlas-fintech-tfstate-179236281274"
    key     = "organization/terraform.tfstate"
    region  = "eu-west-1"
  }
}

locals {
  accounts = {
    #"log-archive" = {email = "hibachagdaly19+aws-log-archive@gmail.com",ou    = data.terraform_remote_state.organization.outputs.security_ou_id}
    #"audit" = {email = "hibachagdaly19+aws-audit@gmail.com",ou    = data.terraform_remote_state.organization.outputs.security_ou_id}
    
    "backup" = {
      email = "hibachagdaly19+aws-backup@gmail.com"
      ou    = data.terraform_remote_state.organization.outputs.security_ou_id
    }

    "network" = {
      email = "hibachagdaly19+aws-network@gmail.com"
      ou    = data.terraform_remote_state.organization.outputs.infrastructure_ou_id
    }

    "shared-services" = {
      email = "hibachagdaly19+aws-shared@gmail.com"
      ou    = data.terraform_remote_state.organization.outputs.infrastructure_ou_id
    }

    "morocco-dev" = {
      email = "hibachagdaly19+aws-morocco-dev@gmail.com"
      ou    = data.terraform_remote_state.organization.outputs.non_prod_ou_id
    }
    
    #"morocco-staging" = {email = "hibachagdaly19+aws-morocco-staging@gmail.com",ou    = data.terraform_remote_state.organization.outputs.non_prod_ou_id}
    #"morocco-prod" = {email = "hibachagdaly19+aws-morocco-prod@gmail.com",ou    = data.terraform_remote_state.organization.outputs.prod_ou_id}
  }
}

module "accounts" {
  source   = "../modules/aws-account"
  for_each = local.accounts

  name  = each.key
  email = each.value.email
  parent_ou_id = each.value.ou
}