resource "aws_organizations_account" "this" {
    name = var.name
    email = var.email
    parent_id = var.parent_ou_id
    role_name = "OrganizationAccountAccessRole"
    close_on_deletion = false
}