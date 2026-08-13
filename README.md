# AWS Secure Landing Zone — Atlas FinTech

> Production-grade AWS multi-account landing zone with DevSecOps pipeline,
> containerized workloads, and full observability. Built as a portfolio
> flagship demonstrating the 9 pillars of enterprise cloud architecture.

**Status:** 🚧 In Progress — Phase 1 of 8 complete
**Author:** Hiba Chagdaly ([GitHub](https://github.com/hiba05555))
**Started:** August 2026

---

## 🎯 The Scenario

**Atlas FinTech** is a fictional Moroccan payment processing startup:
- 55 employees, post-Series A
- Handles sensitive payment data
- Must achieve **SOC 2 compliance in 6 months**
- Zero existing cloud infrastructure

I play the role of the sole Cloud Security Engineer tasked with building
their entire AWS foundation from scratch — securely, cost-consciously,
and audit-ready.

---

## 🏛️ The 9 Pillars Framework

Every real company cloud architecture covers these pillars. This project
touches all 9:

| # | Pillar | Depth in This Project |
|---|--------|-----------------------|
| 1 | Identity & Access | 🟢 Deep |
| 2 | Networking | 🟡 Solid |
| 3 | Compute | 🟡 Solid |
| 4 | Data | 🟡 Solid |
| 5 | Observability | 🟠 Demonstrated |
| 6 | Security | 🟢 Deep |
| 7 | DevOps | 🟡 Solid |
| 8 | DevSecOps | 🟢 Deep |
| 9 | FinOps | 🟠 Demonstrated |

🟢 Deep = production-grade | 🟡 Solid = functional | 🟠 Demonstrated = proof of concept

---

## 📐 Current Architecture (Phase 1)

AWS Account (179236281274, eu-west-1)
─────────────────────────────────────
│
├── IAM
│ ├── hiba-admin (human console access)
│ └── terraform-deployer (automation, no console)
│
├── Terraform State Backend
│ ├── S3: atlas-fintech-tfstate-179236281274
│ │ ├── Versioning: enabled
│ │ ├── Encryption: AES256
│ │ └── Public access: blocked ×4
│ │
│ └── DynamoDB: atlas-fintech-tfstate-lock
│ ├── Billing: PAY_PER_REQUEST
│ └── Purpose: state locking
│
└── Budget: atlas-fintech-monthly-budget
├── $50/month cap
└── Alert @ 85%


---

## 🎯 Target Architecture (Phase 8)

AWS Organization (management account)
├── OU: Security
│ ├── log-archive account (centralized logs)
│ └── audit account (Security Hub, GuardDuty)
│
├── OU: Workloads
│ ├── dev account
│ │ └── VPC → ECS Fargate → RDS Aurora → ALB
│ │
│ └── prod account
│ └── VPC (Multi-AZ) → ECS → RDS (encrypted) → CloudFront
│
└── OU: Sandbox
└── experiments account (auto-cleanup)

Cross-cutting:
├── DevSecOps: GitHub Actions + Checkov + Trivy + tfsec
├── Observability: CloudWatch + X-Ray + centralized logs
├── Security: KMS + GuardDuty + Security Hub + AWS Config
└── FinOps: Cost Explorer + Budget alerts per account


---

## 📊 Project Status

### ✅ Completed Phases

#### Phase 0 — AWS Manual Bootstrap
Established the trust foundation before any code:
- IAM users (human + machine identity separation)
- AWS CLI configured with named profiles
- Budget guardrails ($50 cap, 85% alert)
- STS-verified authentication

**Key learning:** Free Tier is not a safety net. Explicit financial controls
must exist before any infrastructure is deployed.

#### Phase 1 — Terraform Backend
Built production-grade state management:
- S3 bucket with encryption, versioning, public access blocking
- DynamoDB table for state locking (prevents corruption)
- Solved the chicken-and-egg problem via state migration
- Established multi-folder state key convention for future phases

**Key learning:** State locking (DynamoDB) is separate from state storage
(S3). Without locking, concurrent applies corrupt state files silently —
a class of production failure eliminated at the foundation.

### 🔜 Upcoming Phases

- **Phase 2** — AWS Organizations & Multi-Account Structure
- **Phase 3** — Secure Networking (VPC, subnets, NAT gateway)
- **Phase 4** — Compute Layer (ECS Fargate, containerized workloads)
- **Phase 5** — Security Hardening (KMS, GuardDuty, least-privilege IAM)
- **Phase 6** — Observability (CloudWatch, X-Ray, centralized logs)
- **Phase 7** — DevSecOps Pipeline (GitHub Actions + Checkov + Trivy)
- **Phase 8** — FinOps & Cost Optimization

---

## 🛠️ Tech Stack

| Layer | Tools |
|-------|-------|
| Infrastructure | Terraform 1.5+, AWS Provider 5.x |
| Cloud | AWS (eu-west-1) |
| CI/CD | GitHub Actions (Phase 7) |
| Security | AWS IAM, KMS, GuardDuty, Security Hub |
| Containers | Docker, ECS Fargate |
| Data | RDS Aurora, S3 |
| Observability | CloudWatch, X-Ray |
| IaC Scanning | Checkov, tfsec, Trivy (Phase 7) |

---

## 📁 Repository Structure

.
├── infra/
│ ├── bootstrap/ ← Phase 1 (state backend)
│ │ ├── provider.tf
│ │ ├── variables.tf
│ │ ├── main.tf
│ │ └── outputs.tf
│ │
│ ├── modules/ ← Reusable modules (Phase 2+)
│ ├── environments/ ← Per-env configs (dev/prod)
│ └── global/ ← Cross-account resources
│
├── .gitignore ← Blocks secrets, state, credentials
└── README.md


---

## 🚀 How to Reproduce

**Prerequisites:**
- AWS account with programmatic access
- Terraform 1.5+ installed
- AWS CLI configured with a named profile

**Setup:**

```bash
# Clone
git clone https://github.com/hiba05555/aws-secure-landing-zone.git
cd aws-secure-landing-zone/infra/bootstrap

# Create your terraform.tfvars (see variables.tf for required inputs)
echo 'state_bucket_name = "your-unique-bucket-name"' > terraform.tfvars

# Deploy
terraform init
terraform plan
terraform apply
```

⚠️ **Important:** Add the `backend "s3" {}` block to `provider.tf` and run
`terraform init -migrate-state` AFTER the first apply. This is the
chicken-and-egg pattern for Terraform state.

---

## 🎓 What This Project Demonstrates

- **Infrastructure as Code discipline** — 100% Terraform, zero manual clicks post-bootstrap
- **Security-first mindset** — encryption, locking, public access blocking on day 1
- **Multi-account thinking** — designed for real enterprise isolation patterns
- **DevSecOps culture** — security integrated into pipelines, not bolted on
- **Documentation as code** — every decision recorded in ADRs, every phase logged
- **Cost consciousness** — budget alerts before infrastructure exists

---

## 📚 Learning Resources That Shaped This Project

- AWS Well-Architected Framework
- AWS Security Reference Architecture (SRA)
- HashiCorp Terraform documentation
- Manara Cloud Solutions Architect program

---

## 📬 Contact

**Hiba Chagdaly** — Cybersecurity Engineering Student, ENSA Marrakech
Building toward: **AWS Solutions Architect + DevSecOps Engineer**

- GitHub: [@hiba05555](https://github.com/hiba05555)
- Email: hibachagdaly19@gmail.com

---

## 📄 License

MIT License — feel free to reuse patterns for your own learning.