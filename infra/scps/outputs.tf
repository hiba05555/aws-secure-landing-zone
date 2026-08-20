output "scp_policies_ids" {
    description = "MAP f SCP name to ploicy ID."
    value = {
        deny_region_outside_eu = module.deny_region_outside_eu.policy_id
        deny_leave_organization = module.deny_leave_organization.policy_id
        deny_root_user_actions = module.deny_root_user_actions.policy_id
        deny_disable_security_servcies = module.deny_disable_security_services.policy_id
        deny_modify_cloudtrail = module.deny_modify_cloudtrail.policy_id
        deny_create_iam_users = module.deny_create_iam_users.policy_id
        prod_strict_rules = module.prod_strict_rules.policy_id
        sandbox_limits = module.sandbox_limits.policy_id
    }
}