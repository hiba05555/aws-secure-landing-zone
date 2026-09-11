# Phase 2 — Secure Multi-Account Landing Zone

## 🎯 Overview

This phase builds the complete multi-account AWS foundation for **Atlas FinTech**, a fictional Moroccan payment processor targeting SOC 2 and PCI-DSS compliance. Everything is deployed via **Terraform**, following the **AWS Security Reference Architecture (SRA)** pattern.

**What was built:**

- An AWS Organization with a purpose-driven OU hierarchy
- 8 member accounts (4 deployed initially, remaining 4 unblocked after AWS quota approval)
- 8 Service Control Policies enforcing preventive guardrails
- IAM Identity Center for federated SSO with MFA
- An organization-wide CloudTrail trail for tamper-proof audit logging
- GuardDuty + Security Hub for threat detection and compliance monitoring

## 🏢 Client Context

|Attribute|Value|
|---|---|
|**Company**|Atlas FinTech — B2B payment gateway|
|**HQ**|Casablanca, Morocco|
|**Compliance targets**|SOC 2 Type II (12-month goal), PCI-DSS Level 4|
|**Drivers**|Regulatory pressure, Series A due diligence, team scaling (8→25 engineers)|
|**Data residency**|EU regions preferred (avoids US Cloud Act exposure)|

## 🚧 Constraints

- Student-owned personal AWS account — budget cap ~$50/month active, ~$10/month idle
- Paid security services (GuardDuty, Security Hub) destroyed after each work session
- IAM Identity Center cannot be enabled via Terraform (manual console bootstrap required)
- AWS default account quota for young personal accounts is **5**, not the advertised 10

---

## 📐 Target Architecture

```
                         AWS Organization (o-y2civ1d8c4)
                              Feature Set: ALL
                                     │
        ┌────────────────┬───────────────────┬────────────────┬────────────────┐
        ▼                ▼                   ▼                ▼
  ┌───────────┐    ┌────────────┐     ┌────────────┐    ┌────────────┐
  │MANAGEMENT │    │  SECURITY  │     │INFRASTRUCT.│    │  SANDBOX   │
  │           │    │     OU     │     │     OU     │    │     OU     │
  │ • Billing │    │ log-archive│     │ network    │    │ sandbox    │
  │ • Org mgmt│    │ audit      │     │ shared-svc │    │            │
  │ • SCPs    │    │ backup     │     └────────────┘    └────────────┘
  │ • SSO     │    └────────────┘
  │ • CT trail│
  │ • GD/SH   │           ┌────────────┐
  └───────────┘           │ WORKLOADS  │
                          │     OU     │
                          │ ┌────────┐ │
                          │ │Non-Prod│ │  dev, staging
                          │ └────────┘ │
                          │ ┌────────┐ │
                          │ │  Prod  │ │  morocco-prod
                          │ └────────┘ │
                          └────────────┘
```

**Why this structure?**

|OU|Purpose|
|---|---|
|Security|Isolated log aggregation, audit tooling, backups — auditors get scoped access here|
|Infrastructure|Shared platform services (network, DNS) — organization-wide blast radius|
|Workloads → Non-Prod / Prod|Split by environment lifecycle so SCPs get stricter toward Prod|
|Sandbox|Cost-capped experimentation, separate SCP intent from security guardrails|

---

## 🛠️ Terraform Project Structure

```
infra/
├── organization/        # AWS Organization + 6 OUs
├── accounts/             # 8 member accounts (module-driven)
├── scps/                 # 8 Service Control Policies
├── sso/                  # IAM Identity Center users, permission sets, assignments
├── cloudtrail/            # Organization trail + S3 + bucket policy
├── security-services/    # GuardDuty + Security Hub
└── modules/
    ├── aws-account/      # Reusable: creates one AWS account
    └── aws-scp/          # Reusable: creates one SCP + attachments
```

Each folder has its **own Terraform state** (isolated blast radius), connected via `terraform_remote_state` data sources for cross-folder references.

---

## 1️⃣ Organization & Organizational Units

**Resource:** `aws_organizations_organization` with `feature_set = "ALL"` and `enabled_policy_types = ["SERVICE_CONTROL_POLICY"]`.

Trusted access enabled for 6 services: CloudTrail, Config, GuardDuty, Security Hub, IAM Identity Center (SSO), AWS Backup — required before any of those services can operate across member accounts.

6 OUs created via `aws_organizations_organizational_unit`, nested to match the target hierarchy (Non-Prod and Prod nested inside Workloads).

**Deployed:**

```
Root                 r-bvxy
├── Security         ou-bvxy-2cas9oej
├── Infrastructure   ou-bvxy-souhdhma
├── Workloads        ou-bvxy-g4p2hj81
│   ├── Non-Prod     ou-bvxy-d0hl1tt0
│   └── Prod         ou-bvxy-967cewv7
└── Sandbox          ou-bvxy-wh4nnoup
```

**Gotcha hit:** `PolicyTypeNotEnabledException` on first SCP deployment attempt — `feature_set = "ALL"` does NOT automatically enable the SCP policy type. Had to add `enabled_policy_types` explicitly and re-apply.

**Evidence:**

![[2 1.png]] _1 — OU hierarchy in Identity Center._

![[3 1.png]]
 _2 — SCP policy type enabled._

![[4 1.png]]
 _3 — Trusted services enabled._

![[5 1.png]]
 _4 — `terraform state list`, organization/._

---

## 2️⃣ Member Accounts

Built the first reusable module, `modules/aws-account/`, invoked via `for_each` over a map of 8 account definitions (each with a unique email via Gmail `+alias` addressing, and a target OU).

```hcl
resource "aws_organizations_account" "this" {
  name              = var.name
  email             = var.email
  parent_id         = var.parent_ou_id
  role_name         = "OrganizationAccountAccessRole"
  close_on_deletion = false   # accounts survive terraform destroy
}
```

**What happened:** AWS rejected account creation after the 4th account:

```
ConstraintViolationException: You have exceeded the allowed number of AWS accounts.
```

**Root cause:** young personal AWS accounts have a hidden quota of **5 accounts** (not the marketed 10). Submitted an AWS Support quota increase request (5 → 15) with architectural justification.

**Accounts successfully created before the block:**

|Account|ID|OU|
|---|---|---|
|morocco-dev|674428977429|Non-Prod|
|network|622532143366|Infrastructure|
|shared-services|930628638898|Infrastructure|
|backup|991265480269|Security|

**Workaround:** commented out the 4 blocked accounts in Terraform so the module's `account_ids` output could still be written to remote state — unblocking Phase 2's SSO and CloudTrail work, which depend on that output. Quota was later approved, unblocking the remaining accounts.

**Evidence:**

![[6 2.png]]
 _5 — Accounts hierarchy, 4 created._

![[7 1.png]] _6 — `terraform state list`, accounts/._

---

## 3️⃣ Service Control Policies

Built a second module, `modules/aws-scp/`, and deployed **8 SCPs** in a tiered strategy:

**Tier 1 — Root OU baseline (applies everywhere):**

1. `DenyRegionOutsideEU` — restrict to eu-west-1 / eu-west-3
2. `DenyLeaveOrganization`
3. `DenyRootUserActions`
4. `DenyDisableSecurityServices` — protects CloudTrail/GuardDuty/Config/Security Hub
5. `DenyModifyCloudTrailLogs`
6. `DenyCreateIAMUsers` — forces Identity Center adoption

**Tier 2 — Prod OU only:** 7. `ProdStrictRules` — no RDS delete without snapshot, no prod-tagged bucket deletion

**Tier 3 — Sandbox OU only:** 8. `SandboxLimits` — blocks expensive EC2 types, large RDS, EKS

Example — the region-restriction SCP uses `NotAction` to exclude global services (IAM, STS, Route 53) from the region check, so administrative access isn't accidentally locked out:

```json
{
  "Effect": "Deny",
  "NotAction": ["iam:*", "organizations:*", "sts:*", "route53:*", "..."],
  "Resource": "*",
  "Condition": {
    "StringNotEquals": { "aws:RequestedRegion": ["eu-west-1", "eu-west-3"] }
  }
}
```

**Key concepts reinforced:** SCPs are deny-only and cascade downward; `FullAWSAccess` is the default SCP and must never be removed; the management account is always exempt from SCPs.

**Evidence:**

![[8 1.png]]
 _7 — All 8 SCPs listed._

![[9.png]] _8 — DenyRegionOutsideEU policy JSON._

![[10.png]] _9 — Root OU applied policies (7)._

![[11.png]] _10 — Prod OU applied policies (10, inheritance chain)._

---

## 4️⃣ IAM Identity Center (SSO)

Identity Center **cannot be created via Terraform** — required a manual console step first (single-region instance in eu-west-1, to avoid multi-region KMS charges). Once enabled, Terraform took over everything else via `data "aws_ssoadmin_instances"`.

Deployed:

- 1 SSO user (`hiba`) in the built-in identity store
- 2 permission sets: `Admin` (AdministratorAccess) and `ReadOnly` (ReadOnlyAccess), both with `session_duration = "PT8H"`
- 5 account assignments (management + the 4 created member accounts), generated dynamically via `for_each` over a merged map — new accounts auto-inherit assignments once created

```hcl
resource "aws_ssoadmin_account_assignment" "hiba_admin" {
  for_each            = local.all_accounts
  instance_arn        = local.sso_instance_arn
  permission_set_arn  = aws_ssoadmin_permission_set.admin.arn
  principal_id        = aws_identitystore_user.hiba.user_id   # NOT .id
  principal_type      = "USER"
  target_id           = each.value
  target_type         = "AWS_ACCOUNT"
}
```

**Gotcha hit:** `aws_identitystore_user` exposes both `.id` (composite Terraform-internal string) and `.user_id` (the plain UUID AWS APIs actually need) — using `.id` throws `InvalidRequestException`.

**Post-deploy:** invitation emails are NOT sent automatically for Terraform-created users (only console-created ones) — had to manually trigger "Send email verification link" from the console. MFA enrolled via Google Authenticator. End-to-end SSO login tested successfully.

**Evidence:**

![[12.png]] _11 — Identity Center dashboard._

![[13.png]] _12 — User hiba, MFA enrolled._

![[14.png]] _13 — Permission sets Admin + ReadOnly._

![[13 1.png]] _14 — Accounts hierarchy with Admin assignments._

![[16.png]] _15 — SSO login page._

![[17.png]] _16 — SSO portal, 5 accounts with Admin access._

---

## 5️⃣ CloudTrail Organization Trail

Deployed a fully encrypted, versioned, tamper-evident S3 bucket plus an organization-wide, multi-region CloudTrail trail.

**S3 bucket (`atlas-fintech-cloudtrail-179236281274`):**

- Versioning enabled
- SSE-S3 AES-256 encryption
- All 4 public-access-block layers enabled
- Lifecycle: Standard → Glacier at 90 days → expire at 2555 days (~7 years, SOC 2 requirement)

**Trail (`atlas-fintech-org-trail`):**

```hcl
resource "aws_cloudtrail" "org_trail" {
  name                            = "atlas-fintech-org-trail"
  s3_bucket_name                  = aws_s3_bucket.cloudtrail.id
  is_organization_trail           = true
  is_multi_region_trail           = true
  include_global_service_events   = true
  enable_log_file_validation      = true
  depends_on                      = [aws_s3_bucket_policy.cloudtrail]
}
```

**Gotcha hit:** organization trails write to **two different S3 path patterns** — `AWSLogs/<org_id>/<account_id>/...` for member accounts AND `AWSLogs/<management_account_id>/...` for the management account itself. The bucket policy initially only authorized the first path, causing `InsufficientS3BucketPolicyException` on trail creation. Fixed by adding both paths as authorized resources in the bucket policy's `s3:PutObject` statement, alongside an `aws:SourceArn` condition scoping writes to this specific trail only (confused-deputy prevention).


**Evidence:**

![[18.png]] _17 — CloudTrail trails list, Logging._


![[19.png]] _18 — Trail detail, all flags enabled._


![[19 1.png]] _19 — S3 buckets list._


![[21.png]] _21 — Bucket properties, versioning enabled._


![[22.png]] _22 — Bucket policy JSON._

---

## 6️⃣ GuardDuty & Security Hub

**GuardDuty** — ML-based threat detection, enabled organization-wide:

```hcl
resource "aws_guardduty_detector" "main" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

resource "aws_guardduty_organization_configuration" "main" {
  auto_enable_organization_members = "ALL"
  detector_id                      = aws_guardduty_detector.main.id
}
```

**Security Hub** — findings aggregator + compliance scoring, subscribed to 2 standards:

```hcl
resource "aws_securityhub_account" "main" {
  enable_default_standards = false
}

resource "aws_securityhub_standards_subscription" "aws_foundational" {
  standards_arn = "arn:aws:securityhub:eu-west-1::standards/aws-foundational-security-best-practices/v/1.0.0"
}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:eu-west-1::standards/cis-aws-foundations-benchmark/v/1.4.0"
}
```

**Design note (interim/tech debt):** both services are hosted and administered from the **management account** rather than a dedicated `audit` account, since `audit` was one of the accounts initially blocked by the quota issue. Migration to the delegated-administrator pattern is a follow-up item.

**Real-world validation:** within minutes of deployment, GuardDuty generated 2 genuine findings — `Policy:IAMUser/RootCredentialUsage` — flagging root-credential API calls (`ListObjects`, `ListPolicies`) made during the session. Confirms the detection pipeline is live, not just provisioned.

**Known issue:** the GuardDuty Accounts view showed member accounts with `Status: Left` rather than actively enrolled — likely a propagation timing issue. Documented as a follow-up item; does not block the management-account detector, which was active and generating findings.

**Evidence:**

![[23.png]] _23 — GuardDuty summary, 2 real findings._

![[24.png]] _24 — GuardDuty accounts, enrollment issue noted._

![[25.png]] _25 — GuardDuty settings, detector config._

![[26.png]] _26 — Security Hub summary dashboard._

![[27.png]] _27 — Security Hub standards, AWS Foundational + CIS enabled._

---

## 💡 Key Lessons From This Phase

1. **AWS quotas aren't what the docs say** — always verify actual applied quotas early, before architecture depends on account count.
2. **`feature_set = "ALL"` ≠ all policy types enabled** — SCPs need explicit `enabled_policy_types`.
3. **`.id` vs `.user_id` / `.arn`** — many AWS Terraform resources expose a Terraform-internal composite ID alongside the "real" AWS identifier other resources actually need. Always check which one an API expects.
4. **Organization trails need dual-path bucket policies** — one path for the management account, one for the org-wide member account structure.
5. **`aws:SourceArn` conditions** prevent confused-deputy attacks — a recurring, exam-relevant AWS security pattern.
6. **Reusable modules pay off fast** — `aws-account` and `aws-scp` modules turned 8+ near-identical resources into single, auditable definitions.
7. **Honest documentation of tech debt** (interim account placements, MFA deferral, quota blockers) is a portfolio strength, not a weakness — it shows real engineering judgment under real constraints.

---

## ✅ Completion Status

|Component|Status|
|---|---|
|Organization + OUs|✅ Complete|
|Member accounts|✅ Complete (initially 4/8, quota approved, remainder unblocked)|
|Service Control Policies|✅ Complete (8/8)|
|IAM Identity Center + MFA|✅ Complete|
|CloudTrail organization trail|✅ Complete|
|GuardDuty|✅ Complete (enrollment issue noted)|
|Security Hub|✅ Complete (2 standards active)|

## 📚 References

- [AWS Security Reference Architecture](https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/)
- [AWS Organizations — Service Control Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [IAM Identity Center Documentation](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html)
- [CloudTrail Organization Trails](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/creating-trail-organization.html)
- [Amazon GuardDuty](https://docs.aws.amazon.com/guardduty/latest/ug/what-is-guardduty.html)
- [AWS Security Hub](https://docs.aws.amazon.com/securityhub/latest/userguide/what-is-securityhub.html)