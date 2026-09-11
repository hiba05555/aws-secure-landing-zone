# Phase 8 — FinOps (Budget Guardrails and Cost Visibility)

## 🎯 Overview

The final phase of the Atlas FinTech Secure Landing Zone project adds cost visibility and guardrails across the entire organization — closing the loop on a landing zone that until now had security, observability, and automation, but no mechanism to catch runaway spend. Built in the **management account** (179236281274) to take advantage of consolidated billing set up back in Phase 2, giving org-wide cost tracking rather than per-account visibility.

**What was built:**

- A new `infra/finops/` folder, deployed directly to the management account (no cross-account `assume_role` needed)
- An organization-wide monthly budget with dual-threshold SNS alerting
- Activated Cost Allocation Tags, enabling cost breakdowns by `Project`/`Component`/`Environment` in Cost Explorer

## 🏗️ Why the management account, not `network`

Every prior phase (`security/`, `observability/`, `cicd/`) deployed into the `network` member account via `assume_role`, since that's where the actual compute/networking resources live. FinOps is different: **AWS Budgets is account-scoped**, and the management account is the only one with visibility into **consolidated billing** across the whole Organization. A budget created in `network` would only see that one account's spend — deploying here instead means the budget reflects true total organizational cost, matching the actual FinOps goal.

## 🛠️ Implementation

### Provider — no assume_role

```hcl
provider "aws" {
    region  = var.aws_region
    profile = var.aws_profile

    default_tags {
        tags = {
            Project     = "atlas-fintech-landing-zone"
            ManagedBy   = "terraform"
            Environment = "shared"
            Component   = "finops"
        }
    }
}
```

Unlike every other folder in this project, there's no `assume_role` block — `terraform-deployer` is already authenticated directly into the management account, so no cross-account switch is needed here.

### SNS topic + org-wide budget

```hcl
resource "aws_sns_topic" "budget_alerts" {
    name = "atlas-fintech-budget-alerts"
}

resource "aws_sns_topic_subscription" "budget_alerts_email" {
    topic_arn = aws_sns_topic.budget_alerts.arn
    protocol  = "email"
    endpoint  = "hibachagdaly19@gmail.com"
}

resource "aws_budgets_budget" "monthly_org_budget" {
    name         = "atlas-fintech-monthly-budget"
    budget_type  = "COST"
    limit_amount = "20"
    limit_unit   = "USD"
    time_unit    = "MONTHLY"

    notification {
        comparison_operator       = "GREATER_THAN"
        threshold                 = 80
        threshold_type            = "PERCENTAGE"
        notification_type         = "ACTUAL"
        subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
    }

    notification {
        comparison_operator       = "GREATER_THAN"
        threshold                 = 100
        threshold_type            = "PERCENTAGE"
        notification_type         = "FORECASTED"
        subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
    }
}
```

**Design decisions:**

- **A dedicated SNS topic**, separate from the Phase 6 infrastructure-alerts topic — budget alerts are a different audience/urgency than infrastructure health, even if both currently land in the same inbox. Keeps the two cleanly separable if subscribers ever diverge.
- **Two notification types**: `ACTUAL` at 80% catches spend that's already close to the limit; `FORECASTED` at 100% catches a trend that AWS predicts will _exceed_ the limit by month's end even if actual spend hasn't yet — the difference between "you're close" and "you're on track to go over."
- **`limit_amount = "20"`** — a policy choice appropriate for a portfolio/demo project's expected spend, not a technical constraint.
- **`budget_type = "COST"`** in the management account, with consolidated billing active, means this budget tracks spend across **every linked account in the Organization** by default — exactly the org-wide visibility the project needed.

### Cost Allocation Tags

Activated in **Billing and Cost Management → Cost Allocation Tags**: `Project`, `Component`, `Environment`, `ManagedBy` — the same tags applied consistently via `default_tags` across every Terraform provider block in this project since Phase 5. Activation is a one-time console action (not a Terraform resource); until activated, tags exist on resources but Cost Explorer can't use them to break down spend. With them active, cost can now be filtered/grouped by `Component` — showing, for instance, exactly how much the `observability` layer costs per month versus `compute` or `security`.

## 🐞 A minor deployment wrinkle

The first `terraform apply` failed with `DuplicateRecordException: the budget already exists` — a budget with the intended name already existed in AWS but wasn't tracked in Terraform's state (likely from an earlier partial/retried attempt). Rather than delete and recreate:

```bash
terraform import aws_budgets_budget.monthly_org_budget 179236281274:atlas-fintech-monthly-budget
```

The subsequent `terraform plan` showed the imported budget was missing its `FORECASTED` notification block — a genuine drift between what existed in AWS and the intended configuration. `terraform apply` reconciled it in place (`0 added, 1 changed, 0 destroyed`), bringing the pre-existing resource fully under Terraform's management without any downtime or resource replacement.

## 💰 A note on cost trade-offs in this architecture

Worth stating plainly rather than optimizing away: this landing zone deliberately spends more than a minimal setup would, in service of demonstrating production-realistic patterns. The clearest example is **Phase 3's 3 NAT Gateways** (one per Availability Zone) — each NAT Gateway carries an hourly charge plus per-GB data processing cost, so 3 of them costs roughly 3x a single shared NAT Gateway. For a system serving real traffic, that redundancy is the correct call: if one AZ fails, the other two NAT Gateways keep private-subnet resources online. For a portfolio project with no production traffic, a single NAT Gateway would demonstrate the same pattern at a fraction of the cost. This project kept the 3-NAT design intentionally, to document the _production_ pattern rather than the _cheapest_ one — a trade-off worth naming explicitly rather than leaving implicit.

## 📸 Evidence

![[1 8.png]] _1 — `terraform state list`, finops/._
![[2 8.png]]
 _2 — AWS Budgets console, atlas-fintech-monthly-budget detail with both notification thresholds._

![[3 8.png]] _3 — Cost Allocation Tags page, Project/Component/Environment/ManagedBy activated._

![[4 8.png]] _4 — SNS subscription confirmation email for atlas-fintech-budget-alerts._

## 💡 Lessons Learned

1. **AWS Budgets is account-scoped, which directly shapes where FinOps infrastructure has to live.** Unlike the security/observability/CI-CD resources that all made sense in the `network` account, cost visibility genuinely required the management account — a reminder that architectural placement isn't always uniform across a project, even when a consistent Terraform pattern makes it tempting to keep everything in one place.
    
2. **`terraform import` is a practical everyday tool, not just an edge case.** A pre-existing resource outside Terraform's state is common in real environments (manual console changes, partial applies, migrations) — importing and reconciling drift in place is safer and faster than deleting and recreating.
    
3. **Cost allocation tags require explicit activation** — tagging resources consistently (done since Phase 5) is necessary but not sufficient; Cost Explorer only uses tags for breakdowns once each tag key is activated in Billing settings, a step easy to forget since it's not part of the Terraform workflow at all.
    
4. **Naming a cost trade-off explicitly is itself a FinOps deliverable.** Not every cost decision should be optimized away — documenting _why_ the 3-NAT-Gateway design was kept, and what the cheaper alternative would look like, demonstrates the same judgment a real cost review would produce, without requiring the project's actual usage pattern to justify the expense.
    

## ✅ Completion Status

|Component|Status|
|---|---|
|`infra/finops/` folder (management account, no assume_role)|✅ Complete|
|Org-wide monthly budget, dual-threshold alerting|✅ Complete|
|SNS topic + confirmed email subscription|✅ Complete|
|Cost Allocation Tags activated|✅ Complete|
|Cost trade-off (NAT Gateway HA vs. cost) documented|✅ Complete|

**This completes all 8 phases of the Atlas FinTech Secure Landing Zone project** — from multi-account Organizations foundation (Phase 2) through networking, compute, security hardening, observability, DevSecOps CI/CD, and finally cost governance. The project now demonstrates a security-first, observable, cost-aware, automated deployment pipeline across a real multi-account AWS Organization.

## 📚 References

- [AWS Budgets](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)
- [Cost Allocation Tags](https://docs.aws.amazon.com/cost-management/latest/userguide/cost-alloc-tags.html)
- [Consolidated Billing for AWS Organizations](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_org_consolidated_billing.html)
- [Terraform aws_budgets_budget](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget)