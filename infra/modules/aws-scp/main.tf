resource "aws_organizations_policy" "this" {
  name        = var.name
  description = var.description
  content     = var.policy_content
  type        = "SERVICE_CONTROL_POLICY"
}

resource "aws_organizations_policy_attachment" "this" {
  for_each = toset(var.target_ids)

  policy_id = aws_organizations_policy.this.id
  target_id = each.value
}
