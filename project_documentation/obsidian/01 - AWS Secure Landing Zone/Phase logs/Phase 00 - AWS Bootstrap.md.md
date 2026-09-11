# Phase 0 — AWS Manual Bootstrap

**Duration:** 2 hours
**Status:** ✅ Complete
**Date:** 2026-08-08

> **Context:** Atlas FinTech is a fictional Moroccan payment processing
> startup building toward SOC 2 compliance. Full story →
> [[00 - Project Overview]]

---

## 1. Why This Phase Exists

Terraform automates infrastructure — but Terraform itself needs an AWS
identity to authenticate with. That identity cannot be created BY Terraform
(chicken-and-egg). It must be created manually, once, before code takes over.

This phase establishes the **trust foundation** every future phase depends on:
- Who is Terraform allowed to be? (identity)
- Where does it store its secrets? (credentials)
- What stops runaway costs? (budget)

**Skip this phase = no automation is possible.**

---

## 2. What Gets Built

AWS Account (179236281274)  
────────────────────────────  
│  
├── Root user ← Locked away, emergency only  
│  
├── IAM: hiba-admin ← For human console work  
│ └── AdministratorAccess  
│  
├── IAM: terraform-deployer ← For Terraform automation  
│ ├── AdministratorAccess  
│ └── Access keys (CSV, local)  
│  
└── Budget: atlas-fintech-monthly-budget  
├── $50/month cap  
└── Email alert @ 85%

Local Machine  
─────────────  
├── AWS CLI installed + configured  
├── Profile "terraform-deployer" → linked to service user  
└── Credentials at ~/.aws/credentials (outside project)

---

## 3. Design Decisions

### Decision 1 — Two IAM Users Instead of One

**Why not just use one admin account for everything?**

Separation of concerns:
- `hiba-admin` = **human identity** with password + console access
- `terraform-deployer` = **machine identity** with API keys only, no console

**Benefits:**
- Audit trail is clear (who did what: human or automation?)
- Compromised CLI keys don't grant console access
- Follows real-world enterprise pattern (SOC 2 requires this)

---

### Decision 2 — AdministratorAccess for Now

**Why not least-privilege from day 1?**

Bootstrap and early phases need broad permissions to experiment. Locking down
IAM now would create constant permission errors that slow learning.

**Mitigation:** Least-privilege policies will be introduced in Phase 5
(Security hardening) once the actual required permissions are known.

**Trade-off documented in:** [[Decisions log#ADR-001]]

---

### Decision 3 — Credentials Stored Outside Project

**Why not in the project folder?**

AWS credentials at `C:\Users\hiba\.aws\credentials` are:
- Automatically picked up by AWS CLI + Terraform
- Never accidentally committed to Git (outside repo)
- Standard convention across all AWS tooling

**Rule enforced:** `.gitignore` blocks `.aws/` and `credentials` even if
someone tries to add them.

---

### Decision 4 — $50 Budget Cap with 85% Alert

**Why $50 specifically?**

- Free Tier + AWS credits should cover the entire project
- $50 is high enough to allow occasional mistakes
- Low enough that a real leak (leaked keys → crypto mining) gets caught fast
- 85% threshold = warning before hitting cap, not after

---

## 4. Build Steps

**Console work (AWS UI):**
1. Root login → verified region eu-west-1
2. Created IAM user `hiba-admin` with console access + Admin policy
3. Switched to hiba-admin (retired root)
4. Created budget `atlas-fintech-monthly-budget`
5. Created IAM user `terraform-deployer` (no console, Admin policy)
6. Generated access keys → downloaded CSV → stored securely

**Local machine:**
7. `aws configure --profile terraform-deployer`
8. `aws sts get-caller-identity --profile terraform-deployer` → verified

---

## 5. Screenshots (Proof of Work)

![[1.png]]
*Figure 1: IAM user `hiba-admin` created successfully with AdministratorAccess.
This becomes the primary human identity — root is now reserved for
irreversible operations only.*

![[2.png]]
*Figure 2: Service user `terraform-deployer` created without console access.
This proves the machine/human identity separation is enforced at the account
level, not just by convention.*

![[3.png]]
*Figure 3: Budget creation flow — template selection screen showing "Monthly
cost budget" chosen for predictable financial guardrails.*

![[4.png]]
*Figure 4: Budget amount configured at $50 USD with billing scope covering
all AWS services. Cap is intentionally low to catch runaway usage early.*

![[5.png]]
*Figure 5: Alert threshold set at 85% ($42.50) with email notification to
hibachagdaly19@gmail.com. Warning arrives BEFORE hitting the cap, not after.*

![[6.png]]
*Figure 6: PowerShell output of `aws sts get-caller-identity --profile
terraform-deployer`. Confirms local CLI is authenticated as the service
account with Account ID 179236281274 and correct ARN. This is the proof
Terraform can now authenticate.*

![[7.png]]
*Figure 7: VS Code opened at project root. Folder structure ready for
Phase 1 Terraform code to begin.*

---

## 6. What This Phase Teaches (9 Pillars Alignment)

**Pillar 1 — Identity & Access:** Human/machine separation from day 1.
Root retirement pattern. Named profiles for CLI operations.

**Pillar 9 — FinOps:** Budget alerts before infrastructure exists. Reactive
billing = amateur mistake; proactive limits = production discipline.

**Cross-cutting:** Even "manual bootstrap" work is a security decision.
Every identity created here will be inherited by every future phase.

---

## 7. Known Risks (Being Honest)

| Risk | Status | Mitigation |
|------|--------|------------|
| MFA not enabled on hiba-admin | ⚠️ Open | Deadline: 2026-08-15 ([[Decisions log#ADR-000]]) |
| AdministratorAccess is too broad | ⚠️ Accepted for now | Refactor in Phase 5 |
| Credentials in plaintext CSV | ⚠️ Local only | Never committed; rotate after Phase 7 |

---

## 8. What's Next

**Phase 01 — Terraform Backend Setup**

Now that Terraform can authenticate, it needs a place to store its state
(the file that tracks what it created). This means building the S3 bucket +
DynamoDB table BEFORE any real infrastructure. Chicken-and-egg pattern is
solved via state migration.

→ [[Phase 01 - Terraform Backend]]

---

## Related Notes

- [[00 - Project Overview]] — Full Atlas FinTech context
- [[Requirements]] — Non-functional requirements this phase satisfies
- [[Threat model]] — Attack scenarios this phase mitigates
- [[Decisions log]] — Full ADR history

