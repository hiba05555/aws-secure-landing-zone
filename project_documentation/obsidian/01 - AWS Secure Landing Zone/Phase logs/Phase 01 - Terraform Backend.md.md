# Phase 1 — Terraform Backend Setup

**Duration:** 4 hours
**Status:** ✅ Complete
**Date:** 2026-08-12

> **Context:** Atlas FinTech is a fictional Moroccan payment processing
> startup building toward SOC 2 compliance. Full story →
> [[00 - Project Overview]]

---

## 1. Why This Phase Exists

Terraform tracks every resource it creates in a **state file** — a JSON
document mapping "code → real AWS resources." Lose this file and Terraform
"forgets" your infrastructure exists.

By default, state lives on the local laptop. That's fragile:
- Laptop crash → state lost → infrastructure orphaned
- No team collaboration possible
- Cannot run from CI/CD
- No versioning, no backup, no locking

**This phase builds a production-grade state backend** — encrypted, versioned,
locked, and shared. Every future phase will store its state here.

**Skip this phase = no safe collaboration, no CI/CD, no disaster recovery.**

---

## 2. What Gets Built

AWS Account (eu-west-1)  
───────────────────────  
│  
├── S3 Bucket: atlas-fintech-tfstate-179236281274  
│ ├── Versioning (recover from mistakes)  
│ ├── Encryption AES256 (protect secrets in state)  
│ └── Public access blocked × 4 flags  
│  
└── DynamoDB Table: atlas-fintech-tfstate-lock  
├── Billing: PAY_PER_REQUEST  
├── Hash key: LockID (String)  
└── Purpose: prevent concurrent state writes

The Chicken-and-Egg Solution  
─────────────────────────────  
Step 1: terraform apply → creates S3 + DynamoDB (state = local)  
Step 2: add backend block → migrate local state → S3  
Step 3: verify in S3 → future runs read/write from S3

---

## 3. Design Decisions

### Decision 1 — S3 + DynamoDB Instead of S3 Alone

**Q: Why do we need DynamoDB if S3 stores the file?**

S3 stores the state; DynamoDB coordinates who's editing it.

Without locking, two `terraform apply` runs at once = corrupted state file =
disaster. DynamoDB acts as a traffic light: "hiba is editing, wait your turn."

**Trade-off:** ~2 extra AWS resources vs. eliminating a class of production
failures. Non-negotiable in real teams.

---

### Decision 2 — Path A (Flat Bootstrap, Modules Later)

**Q: Why not use Terraform modules from day 1?**

Bootstrap has 5 resources, used exactly ONCE, never reused. Wrapping them in
a module adds folders and syntax without reuse benefit — like building a
factory to make one chair.

Modules will start in Phase 2 when repetition begins (VPC across dev/prod,
IAM roles per service, etc.).

**Trade-off documented in:** [[Decisions log#ADR-002]]

---

### Decision 3 — AES256 Encryption Instead of KMS

**Q: Why not KMS (customer-managed keys)?**

- KMS costs ~$1/month per key
- KMS adds key rotation complexity
- Bootstrap state has no compliance requirement forcing customer keys
- AES256 (S3-managed) is free and sufficient

**Rule:** KMS for production data (Phase 5+). AES256 for infrastructure state.

---

### Decision 4 — DynamoDB PAY_PER_REQUEST

**Q: Why not provisioned capacity?**

State locking is bursty — Terraform locks for seconds during apply, otherwise
nothing. Provisioned capacity would waste money on idle time.

PAY_PER_REQUEST costs pennies for actual usage. Free Tier friendly.

---

### Decision 5 — Backend Block Values Hardcoded (Not Variables)

**Q: Why can't we use `var.state_bucket_name` in the backend block?**

Terraform limitation: the `backend {}` block runs BEFORE variables are loaded
(it needs state to know what variables even exist — another chicken-and-egg).

**Workaround:** hardcode the bucket name, key, region in `backend "s3"`.
Ugly but universal — every Terraform project does this.

---

## 4. Build Steps

**Phase 1a — First apply (state stored locally):**
1. Wrote `provider.tf` — Terraform + AWS provider config
2. Wrote `variables.tf` — 4 input variables (region, profile, bucket, table)
3. Wrote `main.tf` — 5 resources (S3 bucket, versioning, encryption,
   public block, DynamoDB table)
4. Wrote `outputs.tf` — 3 outputs (bucket name, ARN, table name)
5. Wrote `terraform.tfvars` — actual bucket name with account ID appended
6. Ran `terraform init` → downloaded AWS provider
7. Ran `terraform apply` → resources created, state stored LOCALLY

**Phase 1b — State migration (local → S3):**
8. Added `backend "s3" {}` block to `provider.tf`
9. Ran `terraform init -migrate-state`
10. Confirmed "yes" at migration prompt → state copied to S3
11. Verified: `terraform state list` → 5 resources listed
12. Verified: S3 console → `bootstrap/terraform.tfstate` present
13. Cleaned up: removed leftover local `.tfstate` and `.tfstate.backup`

---

## 5. Screenshots (Proof of Work)


**Screenshot 1 — S3 bucket in console**
Bucket `atlas-fintech-tfstate-179236281274` visible in eu-west-1, with
versioning "Enabled" and encryption "SSE-S3". Proves the state storage
foundation exists before any real infrastructure is deployed.
![[1.png]]

![[3.png]]
**Screenshot 2 — S3 bucket public access block**
All 4 flags set to ON. Proves the state file (containing secrets like
future DB passwords) can never accidentally leak publicly — the single
most common cause of AWS breaches.

![[4.png]]
**Screenshot 3 — DynamoDB table active**
Table `atlas-fintech-tfstate-lock` with Status "Active", 0 items.
Proves the locking coordinator is ready. Empty because no apply is
currently running.

![[5.png]]

**Screenshot 4 — Terminal: terraform apply success**
Output showing "Apply complete! Resources: 5 added, 0 changed, 0
destroyed." with outputs displayed. Proves all 5 resources deployed
from code, not clicks.

![[6 1.png]]

**Screenshot 5 — Terminal: terraform init -migrate-state**
Prompt asking "Do you want to copy existing state to the new backend?"
followed by "Successfully configured the backend s3!" Proves the
chicken-and-egg migration technique worked.

![[7.png]]

**Screenshot 6 — S3 bucket showing bootstrap/terraform.tfstate**
File visible in the S3 console at the expected key. Proves state is
now S3-hosted, not laptop-hosted.

![[2.png]]

**Screenshot 7 — Terminal: terraform state list**
Output showing all 5 resources tracked. Proves Terraform successfully
reads state from S3 (not local file) after migration.

![[8.png]]

---

## 6. What This Phase Teaches (9 Pillars Alignment)

**Pillar 7 — DevOps:** Infrastructure-as-Code from day 1. Zero clicks
for the entire backend setup. Every resource reproducible.

**Pillar 6 — Security:** Defense-in-depth on the state file — encryption
at rest, public access blocked (×4), versioning for rollback. State
files contain secrets, so protecting them protects everything.

**Pillar 8 — DevSecOps:** Locking prevents corruption in team + CI/CD
scenarios. Not just about "does it work solo" but "does it work when
5 engineers + 3 pipelines apply concurrently."

**Cross-cutting:** The bootstrap pattern (build foundation → migrate
into it) is a technique that generalizes far beyond Terraform.

---

## 7. Q&A Learned During This Phase

**Q1: Why do we need DynamoDB when S3 already stores the file?**
S3 stores WHAT the infrastructure is. DynamoDB stores WHO is currently
editing it. Two different jobs — S3 can't do coordination, DynamoDB
can't store large state files.

**Q2: Is state locking enabled on S3 or DynamoDB?**
DynamoDB. The confusion comes from both being configured inside the
same `backend "s3" {}` block, but S3 is just storage; DynamoDB is
the actual lock coordinator.

**Q3: Do we always create S3+DynamoDB first, then add the backend block?**
Yes — always a two-step bootstrap. Terraform reads the backend block
FIRST during `init` and tries to connect to the bucket. If the bucket
doesn't exist yet, init fails. So: apply first (state local), then add
backend block, then migrate.

**Q4: After migration, does every apply re-migrate?**
No. Migration is one-time. After that, every apply reads/writes S3
directly. No local state file involved.

**Q5: What's the main purpose of the backend? Only for S3?**
Backend = where Terraform stores state. Not only S3 — also
`azurerm`, `gcs`, `remote` (Terraform Cloud), `local`, `http`, etc.
Choice depends on your cloud + team setup.

**Q6: Why must each Terraform folder have a UNIQUE key?**
Same key = same file in S3 = folders overwrite each other's state.
Match the key to the folder purpose:
`bootstrap/terraform.tfstate`, `networking/terraform.tfstate`, etc.

**Q7: Why split into multiple Terraform folders instead of one?**
Blast radius (one folder = one apply cycle = safer). Apply speed
(change 1 thing, apply only 1 folder). Team collaboration (parallel
work without lock conflicts). Different lifecycles (bootstrap runs
once, compute runs daily).

**Q8: Do all folders share ONE S3 bucket for state?**
Yes. One shared bucket + one shared DynamoDB table. Each folder
gets its own state FILE within the bucket (unique key). Bootstrap
is special because it builds the shared foundation everyone else
uses.

---

## 8. Known Risks (Being Honest)

| Risk | Status | Mitigation |
|------|--------|------------|
| Bucket name hardcoded in backend block | ⚠️ Terraform limitation | Universal issue, no workaround |
| Local `.tfstate.backup` may contain secrets | ✅ Cleaned up | Deleted after migration verified |
| No cross-region replication on state bucket | ⚠️ Accepted for now | Add in Phase 5 if SOC 2 requires |
| DynamoDB in single region | ⚠️ Accepted | Global tables considered overkill for solo dev |

---

## 9. What's Next

**Phase 02 — AWS Organizations & Multi-Account Structure**

Real companies isolate workloads by account, not by tag. Dev experiments
can't accidentally destroy production RDS. Compliance boundaries are
account-level in AWS.

Phase 2 will build:
- AWS Organization (root management account)
- Organizational Units (Security, Workloads, Sandbox)
- Member accounts (dev, prod, security-audit)
- Service Control Policies (guardrails)

Modules start here. First real Terraform module will be `aws-account`.

→ [[Phase 02 - AWS Organizations]]

---

## Related Notes

- [[00 - Project Overview]] — Full Atlas FinTech context
- [[Phase 00 - AWS Manual Bootstrap]] — What made this phase possible
- [[Requirements]] — NFRs ( Non Functionam Requirement) this phase satisfies
- [[Architecture design]] — Where state backend fits in the big picture
- [[Decisions log]] — Full ADR history