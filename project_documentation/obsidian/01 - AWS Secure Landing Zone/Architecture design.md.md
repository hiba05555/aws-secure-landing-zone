# Architecture Design — Atlas FinTech Cloud Platform

**Author:** Hiba Chagdaly
**Date:** [YYYY-MM-DD]
**Version:** 1.0
**Status:** Draft (will evolve during build phases)

---

## 1. Design Principles

Every design decision in this project follows these principles. When in doubt, choose the option that best aligns with these:

1. **Least Privilege by Default** — start with zero access, grant only what's needed
2. **Defense in Depth** — multiple layers of security, no single point of failure
3. **Zero Long-Lived Credentials** — no static access keys anywhere
4. **Immutable Infrastructure** — everything as code, no manual changes
5. **Auditable by Design** — every action traceable to an identity
6. **Blast Radius Containment** — a breach in one account doesn't sprea
7. .d
8. **Cost-Aware** — every service justified against Free Tier / budget
9. **Compliance-Ready** — controls map to SOC 2, CIS, PCI-DSS

---

## 2. Multi-Account Structure

### Why Multi-Account?

**Blast radius containment.** If dev is compromised, prod is safe. If a bill spikes in one account, it's contained. Different security postures per environment.

### Account Layout
AWS Organization Root  
│  
├── Management Account  
│ └── Purpose: Org root, billing consolidation, IAM Identity Center  
│  
├── Security OU  
│ ├── Log Archive Account  
│ │ └── Purpose: Immutable CloudTrail + Config logs  
│ │  
│ └── Audit Account  
│ └── Purpose: Delegated admin for GuardDuty, Security Hub, Config  
│  
└── Workloads OU  
├── Dev Account  
│ └── Purpose: Development environment, safe experimentation  
│  
└── Prod Account  
└── Purpose: Production workload (containerized app)
### Trust & Access Flow
Human User  
│  
▼  
Google Workspace (SAML)  
│  
▼  
IAM Identity Center (in Management Account)  
│  
▼  
Permission Set (per role)  
│  
▼  
AssumeRole → Target Account
---

## 3. Identity & Access Design

### 3.1 Permission Sets

Defined in IAM Identity Center, assigned to users via Google Groups:

| Permission Set | Scope | Assigned To |
|----------------|-------|-------------|
| AdministratorAccess | Management account only | Cloud Architect (me) |
| DevFullAccess | Dev account | Developers |
| ProdReadOnly | Prod account | Developers |
| ProdSREAccess | Prod account | SREs (with session limits) |
| DataAnalystAccess | Prod (read-only, no PII) | Data Analysts |
| BillingViewer | Management (billing) | Finance |
| SecurityAudit | Audit account | Security Lead |

### 3.2 Session Duration Rules

- Developer sessions: 8 hours (workday)
- SRE prod sessions: 1 hour (must re-authenticate for extended access)
- Data analyst sessions: 4 hours
- Admin sessions: 1 hour (highest sensitivity)

### 3.3 Machine Identity (CI/CD)

GitHub Actions authenticates via OIDC:
GitHub Repo (hiba05555/atlas-fintech)  
│  
▼  
OIDC Token (JWT) signed by GitHub  
│  
▼  
AWS IAM OIDC Provider (in Management Account)  
│  
▼  
AssumeRole with trust condition:  
- repo: hiba05555/atlas-fintech  
- branch: main (for prod deploys)  
- branch: develop (for dev deploys)  
│  
▼  
Deployment role with least privilege
**No AWS access keys stored in GitHub secrets.**

---

## 4. Service Control Policies (SCPs)

Applied at OU level to enforce guardrails no user can override.

### SCP-1: Deny Root User Actions (except account setup)
Applied to: All OUs except Management
Purpose: Force use of IAM identities

### SCP-2: Deny Leaving Organization
Applied to: Root
Purpose: Prevent account takeover from removing itself from governance

### SCP-3: Region Restriction
Applied to: Workloads OU
Purpose: Allow only eu-west-1 (and eu-central-1 for DR later)

### SCP-4: Require IMDSv2 on EC2
Applied to: Workloads OU
Purpose: Prevent SSRF-based credential theft

### SCP-5: Deny Creation of IAM Users with Access Keys
Applied to: All accounts except Management
Purpose: Force OIDC/role-based access only

### SCP-6: Deny Public S3 Buckets
Applied to: All accounts
Purpose: Prevent accidental data exposure

### SCP-7: Require Encryption
Applied to: All accounts
Purpose: Deny unencrypted EBS, S3, RDS creation

### SCP-8: Deny Disabling Security Services
Applied to: All accounts
Purpose: Prevent tampering with GuardDuty, Config, CloudTrail

---

## 5. Network Architecture

### 5.1 VPC per Account

Each account gets its own VPC. No peering between dev and prod (isolation).

### 5.2 Subnet Design (per VPC)
VPC (10.0.0.0/16)  
│  
├── Public Subnet AZ-a (10.0.1.0/24) — ALB only  
├── Public Subnet AZ-b (10.0.2.0/24) — ALB only  
│  
├── Private Subnet AZ-a (10.0.11.0/24) — ECS tasks  
├── Private Subnet AZ-b (10.0.12.0/24) — ECS tasks  
│  
├── Isolated Subnet AZ-a (10.0.21.0/24) — RDS, ElastiCache  
└── Isolated Subnet AZ-b (10.0.22.0/24) — RDS, ElastiCache
### 5.3 Traffic Flow
Internet  
│  
▼  
Route 53 (DNS)  
│  
▼  
CloudFront + WAF (edge protection)  
│  
▼  
Application Load Balancer (public subnet)  
│  
▼  
ECS Fargate Tasks (private subnet)  
│  
├──▶ RDS (isolated subnet)  
├──▶ ElastiCache (isolated subnet)  
└──▶ VPC Endpoints (S3, ECR, Secrets Manager)
### 5.4 VPC Endpoints (No NAT Gateway)

**Why:** NAT Gateway costs ~$32/month. VPC endpoints are cheaper and more secure.

Endpoints created:
- S3 (Gateway endpoint — free)
- DynamoDB (Gateway endpoint — free)
- ECR (Interface endpoint)
- ECR Docker (Interface endpoint)
- Secrets Manager (Interface endpoint)
- CloudWatch Logs (Interface endpoint)
- KMS (Interface endpoint)

### 5.5 Security Groups

Follow the principle: **only allow what's needed, nothing more**.

| Security Group | Inbound | Outbound |
|----------------|---------|----------|
| ALB-SG | 443 from 0.0.0.0/0 | 80/443 to ECS-SG |
| ECS-SG | 80/443 from ALB-SG only | To RDS-SG (5432), ElastiCache-SG (6379), VPC endpoints |
| RDS-SG | 5432 from ECS-SG only | None |
| ElastiCache-SG | 6379 from ECS-SG only | None |

---

## 6. Compute Design (Containers)

### 6.1 ECS Fargate Cluster

**Why Fargate over EC2:**
- No servers to patch
- Better security (task-level isolation)
- Pay per task, not per instance
- Free Tier friendly for small workloads

### 6.2 Microservices

Three services demonstrating real-world patterns:

**Auth Service**
- Language: Node.js
- Handles user authentication
- Reads secrets from Secrets Manager
- Writes to RDS (users table)

**API Service**
- Language: Node.js
- Business logic (payment processing simulation)
- Reads/writes to RDS
- Publishes events to SNS

**Worker Service**
- Language: Node.js
- Consumes SQS messages
- Async processing (e.g., email notifications simulation)

### 6.3 Deployment Strategy

Blue/green via CodeDeploy:
1. New task definition created
2. New tasks launched (green)
3. ALB shifts traffic (10% → 50% → 100%)
4. Old tasks terminated (blue)
5. Auto-rollback on health check failure

---

## 7. Data Design

### 7.1 RDS PostgreSQL

**Configuration:**
- Multi-AZ (automatic failover)
- Encrypted at rest with customer-managed KMS key
- Automated backups (7-day retention)
- Deletion protection enabled
- Enhanced monitoring enabled
- IAM database authentication for admin access

### 7.2 ElastiCache Redis

**Purpose:** Session cache, rate limit counters, temporary data

**Configuration:**
- Single-node (Free Tier)
- Encryption in transit
- Auth token stored in Secrets Manager

### 7.3 S3 Buckets

Every bucket has:
- Default encryption (KMS or SSE-S3)
- Public access blocked
- Versioning enabled
- Access logging to Log Archive account
- Lifecycle policy (delete old versions after 90 days)

Buckets planned:
- `atlas-fintech-app-static` — static assets (CloudFront origin)
- `atlas-fintech-app-uploads` — user uploads
- `atlas-fintech-app-backups` — application backups
- `atlas-fintech-terraform-state` — Terraform state
- `atlas-fintech-logs-central` — centralized logs (in Log Archive account)

---

## 8. Security Architecture

### 8.1 Encryption Strategy

| Layer | Encryption | Key Type |
|-------|-----------|----------|
| S3 objects | SSE-KMS | Customer-managed (auto-rotation) |
| RDS storage | AWS-managed KMS | Customer-managed for prod |
| EBS volumes | KMS | AWS-managed |
| Secrets in Secrets Manager | KMS | Customer-managed |
| Data in transit | TLS 1.2+ | AWS Certificate Manager |
| ECR images | KMS | AWS-managed |

### 8.2 Detection Stack
┌────────────────────────────────────────────────────┐  
│ Audit Account │  
│ │  
│ ┌───────────────┐ ┌────────────────────────┐ │  
│ │ GuardDuty │ │ Security Hub │ │  
│ │ (delegated │ │ (delegated admin) │ │  
│ │ admin) │ │ - CIS benchmark │ │  
│ │ │ │ - AWS Foundational │ │  
│ └───────┬───────┘ └───────────┬────────────┘ │  
│ │ │ │  
│ └───────────┬───────────┘ │  
│ ▼ │  
│ ┌──────────────────┐ │  
│ │ Aggregated │ │  
│ │ Findings │ │  
│ └──────────────────┘ │  
└────────────────────────────────────────────────────┘  
│  
▼  
EventBridge Rules  
│  
┌─────────┴─────────┐  
│ │  
▼ ▼  
SNS Alert Lambda Auto-Remediation
### 8.3 Auto-Remediation Playbook

Critical findings trigger automated response:

| Finding | Auto-Action |
|---------|-------------|
| S3 bucket made public | Revoke public access, alert |
| Security group opens SSH to world | Remove rule, alert |
| KMS key scheduled for deletion | Cancel deletion, alert |
| IAM policy grants * on * | Alert (manual review, don't auto-fix) |
| GuardDuty: Compromised EC2 credential | Isolate instance (revoke SG), snapshot for forensics |

---

## 9. DevSecOps Pipeline

### 9.1 Pipeline Stages
Developer commits code  
│  
▼  
┌──────────────────────────────────────────────┐  
│ STAGE 1: Static Analysis │  
│ - Checkov (Terraform) │  
│ - tfsec (Terraform) │  
│ - TruffleHog (secrets scan) │  
│ - Snyk / Dependabot (dependencies) │  
│ FAIL ON: High/Critical severity │  
└──────────────────┬───────────────────────────┘  
│  
▼  
┌──────────────────────────────────────────────┐  
│ STAGE 2: Build │  
│ - Docker build │  
│ - Tag with git commit SHA │  
└──────────────────┬───────────────────────────┘  
│  
▼  
┌──────────────────────────────────────────────┐  
│ STAGE 3: Image Security │  
│ - Trivy scan │  
│ - Push to ECR (scan-on-push) │  
│ FAIL ON: Critical CVEs │  
└──────────────────┬───────────────────────────┘  
│  
▼  
┌──────────────────────────────────────────────┐  
│ STAGE 4: Deploy Infrastructure │  
│ - terraform plan (posted as PR comment) │  
│ - terraform apply (on merge to main) │  
└──────────────────┬───────────────────────────┘  
│  
▼  
┌──────────────────────────────────────────────┐  
│ STAGE 5: Deploy Application │  
│ - ECS service update │  
│ - Blue/green via CodeDeploy │  
│ - Health check validation │  
└──────────────────┬───────────────────────────┘  
│  
▼  
Deployment complete  
Slack notification sent
### 9.2 Pipeline Security Controls

- OIDC (no AWS access keys in GitHub secrets)
- Least-privilege deployment role per environment
- Required PR reviews for main branch
- Signed commits enforced
- Concurrency limits (prevent race conditions)
- Timeout limits per stage

---

## 10. Observability Design

### 10.1 Metrics

CloudWatch dashboards per account with:

**Workload dashboard:**
- ALB requests / errors
- ECS task count, CPU, memory
- RDS connections, CPU, storage
- ElastiCache hit rate

**Security dashboard:**
- GuardDuty findings by severity
- Security Hub compliance score
- CloudTrail failed API calls
- WAF blocked requests

**Cost dashboard:**
- Daily spend
- Cost by tag
- Anomalies detected

### 10.2 Logs

Centralized in CloudWatch Logs, aggregated in Log Archive account.

Log groups:
- `/aws/ecs/atlas-auth` — Auth service
- `/aws/ecs/atlas-api` — API service
- `/aws/ecs/atlas-worker` — Worker service
- `/aws/rds/instance/atlas-db/postgresql` — DB logs
- `/aws/waf/logs` — WAF logs
- `/aws/cloudtrail/logs` — Audit logs

Retention: 90 days for app logs, 1 year for security/audit logs.

### 10.3 Alarms

Critical alarms (page immediately):
- Any root user login
- CloudTrail disabled
- GuardDuty finding severity ≥ 7
- ECS service health < 50%
- RDS CPU > 90% for 15 minutes
- Monthly budget forecast > 100%

---

## 11. Cost Management Design

### 11.1 Cost Tags (Mandatory via SCP)

Every resource must have:
- `Environment` (dev/prod)
- `Project` (atlas-fintech)
- `Owner` (hiba)
- `CostCenter` (engineering)

### 11.2 Budgets

- Monthly budget: $50
- Alerts at: 50% ($25), 80% ($40), 100% ($50), 120% ($60 — forecasted)

### 11.3 Cost Optimization Strategies

- VPC endpoints (avoid NAT Gateway ~$32/mo)
- Fargate over EC2 (pay per use)
- Free Tier where possible
- S3 lifecycle policies (delete old versions)
- Turn off dev environment nights/weekends (automation)
- CloudWatch Logs retention limits

---

## 12. Regional & Availability Strategy

### 12.1 Primary Region: eu-west-1 (Ireland)

**Why:**
- Closest full-feature region to Morocco
- Cheapest EU region
- All AWS services available (including newer ones)

### 12.2 Multi-AZ (High Availability)

- RDS Multi-AZ (automatic failover)
- ECS tasks across 2 AZs
- ALB across 2 AZs
- Private subnets in 2 AZs

### 12.3 Multi-Region (Deferred)

Out of scope for v1. Documented as future extension:
- Pilot Light DR in eu-central-1 (Frankfurt)
- S3 Cross-Region Replication for critical data
- Route 53 failover routing

---

## 13. Terraform Module Structure

Modular design for reusability:
terraform/  
├── modules/  
│ ├── organization/ — Organizations + OUs + SCPs  
│ ├── identity-center/ — IAM Identity Center + permission sets  
│ ├── security-baseline/ — GuardDuty, Security Hub, Config, CloudTrail  
│ ├── networking/ — VPC, subnets, endpoints, security groups  
│ ├── ecr/ — Container registry  
│ ├── ecs-cluster/ — Fargate cluster  
│ ├── ecs-service/ — Individual service (reused per microservice)  
│ ├── rds/ — PostgreSQL Multi-AZ  
│ ├── elasticache/ — Redis  
│ ├── kms/ — Customer-managed keys  
│ ├── secrets/ — Secrets Manager entries  
│ ├── alb/ — Application Load Balancer + WAF  
│ ├── cloudfront/ — CloudFront distribution  
│ └── observability/ — CloudWatch dashboards, alarms  
│  
├── environments/  
│ ├── management/ — Management account resources  
│ ├── security/ — Audit + Log Archive accounts  
│ ├── dev/ — Dev account resources  
│ └── prod/ — Prod account resources  
│  
├── backend.tf — S3 + DynamoDB state backend  
└── providers.tf — AWS provider config
---

## 14. Deployment Order

The order matters — some things depend on others:

1. Management account setup (manual)
2. Terraform state backend (S3 + DynamoDB in Management)
3. AWS Organizations + OUs
4. Member accounts (Log Archive, Audit, Dev, Prod)
5. IAM Identity Center + permission sets
6. SCPs (attached to OUs)
7. Security baseline (GuardDuty, Config, Security Hub, CloudTrail)
8. Networking (VPCs in Dev + Prod)
9. KMS keys
10. Data layer (RDS, ElastiCache, S3)
11. Container infrastructure (ECR, ECS cluster)
12. Application deployment (microservices)
13. Edge layer (ALB, WAF, CloudFront, Route 53)
14. Observability (dashboards, alarms)
15. CI/CD pipeline (GitHub Actions + OIDC)

---

## 15. Diagrams

Diagrams will live in `Diagrams/` folder:

- `01-business-context.drawio` — Business flow
- `02-account-structure.drawio` — Multi-account layout
- `03-network-architecture.drawio` — VPC and traffic flow
- `04-security-architecture.drawio` — Security services and detection
- `05-devsecops-pipeline.drawio` — CI/CD flow
- `06-deployment-model.drawio` — Full deployment view

Each will be exported as PNG and referenced in the README.

---

## 16. Open Questions (Track As I Build)

Questions I haven't fully answered yet. Will be resolved and documented as ADRs:

- Should I use AWS Control Tower or manual Organizations setup? (ADR-002)
- Which auto-remediation actions should be automatic vs alert-only? (ADR-008)
- Should I include Cognito for user auth in the sample app? (out of scope for now)
- How to handle Terraform state for multi-account (one bucket or per account)? (ADR-005)

---

## Related Documents

- [[00 - Project Overview]]
- [[Requirements]]
- [[Threat model]]
- [[Decisions log]]
- [[The 9 Pillars of Real Company Cloud Architecture]]
-