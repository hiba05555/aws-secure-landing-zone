# AWS Enterprise-Grade Cloud Platform — Project Overview

**Status:** 🚧 Planning
**Started:** [YYYY-MM-DD]
**Target completion:** [YYYY-MM-DD]
**Time commitment:** 8-10 hours/day
**Estimated duration:** 5-7 weeks

---

## 1. What This Project Is

A production-grade AWS cloud platform simulating what a real cloud engineering team would deliver for a growing company. The project covers all 9 pillars of modern cloud architecture, with intentional depth choices based on career goals.

The workload is a containerized microservices application running inside a secure multi-account AWS Organization, deployed via a full DevSecOps pipeline with security scanning at every stage.

Everything is built as Infrastructure as Code (Terraform) — no clicks in the console for the final deliverable.

---

## 2. Why I'm Building It

**Career goal:** Position myself as a Cloud Security Engineer with strong DevSecOps and Solutions Architect skills.

**Certification goal:** Apply 95%+ of AWS SAA-C03 concepts hands-on.

**Portfolio goal:** Build ONE flagship project that tells a complete story to recruiters — covering every conversation an interviewer might start.

**Learning goal:** Move from "I know AWS services" to "I can design, defend, and secure a full cloud platform."

**Business alignment:** Build something that mirrors what real companies actually run — not toy tutorials.

---

## 3. The Fictional Client Scenario

**Company:** Atlas FinTech — a Moroccan fintech startup.
**Size:** 55 employees, growing fast.
**Product:** Payment processing platform.

**Current situation:**
- Just closed Series A funding
- Needs SOC 2 compliance in 6 months
- Existing AWS setup is a mess: shared root user, access keys in GitHub, no audit trail, no cost tracking
- Preparing for enterprise deals that require security due diligence

**My role:** Cloud Security Engineer / Architect designing their AWS foundation from scratch.

**Business requirements:**
- Separate dev, staging, production environments
- 12 developers, 3 SREs, 2 data analysts, 5 finance users — each with appropriate access
- CI/CD from GitHub Actions (no long-lived secrets)
- Full audit trail for compliance
- Cost control (pre-profit startup)
- Handles payment data (PCI-DSS aware for the future)

---

## 4. The 9 Pillars — Depth Strategy

Every real company relies on 9 pillars of cloud architecture. This project touches ALL 9, with intentional depth choices:

### 🔥 DEEP FOCUS (differentiators)
- **Pillar 1: Identity & Access Governance**
- **Pillar 6: Security & Compliance**
- **Pillar 8: DevSecOps**

### 💪 SOLID COVERAGE (proves full-stack architect skills)
- **Pillar 2: Network Architecture**
- **Pillar 3: Compute (containerized)**
- **Pillar 4: Data & Storage**
- **Pillar 7: DevOps CI/CD**

### 👀 DEMONSTRATED (proves awareness)
- **Pillar 5: Observability**
- **Pillar 9: FinOps**

**Rule I follow:** Every pillar has a minimum viable demonstration. If time runs short, I DEMOTE a pillar's depth rather than skip it entirely.

---

## 5. High-Level Architecture
┌───────────────────────────────────────────────────────────────┐  
│ AWS ORGANIZATION │  
│ │  
│ ┌──────────────────┐ ┌────────────────────────────────┐ │  
│ │ Management │ │ Security OU │ │  
│ │ Account │ │ ├─ Log Archive Account │ │  
│ │ (Root Org) │ │ └─ Audit Account │ │  
│ └──────────────────┘ └────────────────────────────────┘ │  
│ │  
│ ┌───────────────────────────────────────────────────────┐ │  
│ │ Workloads OU │ │  
│ │ ├─ Dev Account │ │  
│ │ └─ Prod Account (hosts containerized workload) │ │  
│ └───────────────────────────────────────────────────────┘ │  
│ │  
│ Guardrails: Service Control Policies (SCPs) │  
│ Identity: IAM Identity Center + Google Workspace SSO │  
└───────────────────────────────────────────────────────────────┘

PROD ACCOUNT WORKLOAD:  
┌───────────────────────────────────────────────────────────────┐  
│ [Route 53] → [CloudFront + WAF] → [ALB] │  
│ │ │  
│ ┌────────────────────────┴────────┐ │  
│ │ ECS FARGATE CLUSTER │ │  
│ │ ┌─────────┐ ┌─────────┐ │ │  
│ │ │ Auth │ │ API │ │ │  
│ │ │ Service │ │ Service │ │ │  
│ │ └─────────┘ └─────────┘ │ │  
│ │ ┌─────────────────────┐ │ │  
│ │ │ Worker Service │ │ │  
│ │ └─────────────────────┘ │ │  
│ └───────┬──────────────────┬──────┘ │  
│ │ │ │  
│ [ElastiCache] [RDS Multi-AZ] │  
│ [Secrets Mgr] [KMS encrypted] │  
└───────────────────────────────────────────────────────────────┘

DEVSECOPS PIPELINE:  
┌───────────────────────────────────────────────────────────────┐  
│ Developer pushes code │  
│ │ │  
│ ▼ │  
│ GitHub Actions (OIDC to AWS) │  
│ │ │  
│ ├─→ Checkov + tfsec (Terraform security scan) │  
│ ├─→ Snyk / Dependabot (dependency scan) │  
│ ├─→ Secret scanner (TruffleHog) │  
│ ├─→ Docker build │  
│ ├─→ Trivy (container image scan) │  
│ ├─→ Push to ECR (auto-scan on push) │  
│ ├─→ Terraform apply │  
│ └─→ ECS Fargate blue/green deploy │  
│ │  
│ Failure at any stage → block deployment + Slack alert │  
└───────────────────────────────────────────────────────────────┘

SECURITY EVERYWHERE (all accounts):  
==KMS== | ==GuardDuty== | ==Security Hub== | ==Config== | ==CloudTrail==  
==WAF== | ==Shield== | ==Secrets Manager== | ==Access Analyzer==

OBSERVABILITY (centralized):  
CloudWatch dashboards | Logs Insights | Alarms | SNS
---

## 6. AWS Services I'll Use

### Foundation & Identity
- AWS Organizations
- AWS Control Tower (optional)
- IAM Identity Center
- IAM (roles, policies, permission boundaries)
- Service Control Policies (SCPs)
- AWS STS

### Networking
- VPC (multi-account)
- Security Groups & NACLs
- VPC Endpoints (S3, DynamoDB, ECR, Secrets Manager)
- Route 53
- CloudFront
- Application Load Balancer

### Compute
- Amazon ECS on Fargate
- Amazon ECR
- Auto Scaling
- AWS CodeDeploy (blue/green)

### Data
- Amazon RDS Multi-AZ (PostgreSQL)
- Amazon ElastiCache (Redis)
- Amazon S3
- AWS Backup
- Amazon DynamoDB (optional)

### Security
- AWS KMS (customer-managed keys)
- AWS Secrets Manager
- Amazon GuardDuty
- AWS Security Hub
- AWS Config
- AWS CloudTrail
- AWS WAF
- AWS Shield (Standard)
- AWS Access Analyzer
- Amazon Inspector (optional)

### DevOps & DevSecOps
- Terraform (primary IaC)
- GitHub Actions (OIDC)
- Checkov (Terraform SAST)
- tfsec (Terraform SAST)
- Trivy (container scanning)
- Snyk / Dependabot (dependency scanning)
- TruffleHog / GitLeaks (secret scanning)

### Observability
- Amazon CloudWatch (metrics, logs, alarms, dashboards)
- CloudWatch Logs Insights
- Amazon SNS (alerting)
- AWS X-Ray (optional)

### FinOps
- AWS Budgets
- AWS Cost Explorer
- Cost Anomaly Detection
- Cost tags enforcement (via SCP)

---

## 7. Project Phases

### *Phase 1: Design & Documentation (Week 1)*
- Requirements document
- Threat model (STRIDE analysis)
- Architecture diagrams (business, network, security, deployment)
- ADRs for major decisions (~15-20 planned)
- Cost estimate
- Compliance mapping (SOC 2 controls)

### *Phase 2: Foundation (Week 2)*
- AWS Organizations setup
- Account structure creation (5 accounts)
- Base SCPs
- IAM Identity Center configuration
- Cross-account roles
- Terraform state backend (S3 + DynamoDB)
- OIDC provider for GitHub Actions

### *Phase 3: Security Baseline (Week 3)*
- KMS keys with automatic rotation
- Secrets Manager setup
- Centralized CloudTrail (in log archive account)
- GuardDuty (delegated admin in audit account)
- Security Hub (delegated admin, CIS benchmark enabled)
- AWS Config with CIS conformance pack
- Access Analyzer
- Auto-remediation via EventBridge + Lambda

### Phase 4: Networking & Workload (Week 4)
- VPC design across accounts
- Private subnets with VPC endpoints
- ALB + WAF setup
- ECR repositories
- Simple 3-microservice app (Auth, API, Worker)
- ECS Fargate cluster and services
- RDS Multi-AZ (encrypted)
- ElastiCache Redis
- Route 53 + CloudFront

### Phase 5: DevSecOps Pipeline (Week 5)
- GitHub Actions with OIDC
- Terraform CI pipeline (fmt, validate, plan)
- Checkov + tfsec integration
- Container build + Trivy scan
- Secret scanning
- Automated deployment to ECS
- Blue/green with CodeDeploy
- Failure alerting to Slack/email

### Phase 6: Observability & FinOps (Week 6)
- CloudWatch dashboards per account
- Centralized logging strategy
- Key alarms (CPU, errors, security events)
- AWS Budgets with alerts
- Cost anomaly detection
- Cost tags enforcement via SCP

### Phase 7: Testing, Documentation & Polish (Week 7)
- Attack simulation (deploy attacker EC2, test defenses)
- Validate GuardDuty findings
- Compliance mapping finalized
- Cost analysis writeup
- Full README with diagrams and screenshots
- Blog post draft (LinkedIn/Medium)
- Recruiter pitch document
- Manara graduation submission prep

---

## 8. Deliverables

### GitHub Repository
- Modular Terraform code (one module per component)
- Architecture diagrams (draw.io + PNG exports)
- 15-20 ADRs documenting decisions
- Runbooks (incident response, onboarding, break-glass)
- Cost analysis
- Compliance mapping (SOC 2 controls → AWS services)
- Threat model
- Attack simulation writeup

### Manara Graduation Submission
- Project 8 elements clearly presented
- Architecture diagram
- Documentation

### Portfolio README
- Business context and problem statement
- Architecture overview with diagrams
- Key design decisions summary
- Metrics and outcomes
- Screenshots of working system

### Blog Post
- Published on LinkedIn or Medium
- Story-driven walkthrough
- Lessons learned

---

## 9. Success Criteria

By the end of this project, I should be able to:

- [ ] Explain why every AWS service in the architecture is there
- [ ] Defend every design decision to a senior engineer
- [ ] Simulate an attack and demonstrate defenses working
- [ ] Deploy the entire environment from scratch with Terraform
- [ ] Tear it down cleanly to avoid costs
- [ ] Write a blog post that non-technical people can partially understand
- [ ] Answer interview questions across all 9 pillars
- [ ] Pass the SAA-C03 exam with confidence
- [ ] Speak fluently about DevSecOps in an interview
- [ ] Demonstrate Cloud Security Engineer readiness

---

## 10. Constraints

- **Budget:** AWS Free Tier + max $30-50 for the entire project
- **Region:** eu-west-1 (Ireland) — closest full-feature region to Morocco
- **Time:** ~5-7 weeks at 8-10 hours/day
- **Tools:** Terraform, GitHub Actions, Docker, draw.io, Obsidian, VS Code
- **Documentation language:** English

---

## 11. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Costs exceed Free Tier | Billing alarms; destroy resources when not testing |
| Scope creep | Stick to the phase plan; new ideas go to Extensions list |
| Overwhelm / burnout | One phase at a time; scheduled rest days |
| Terraform state loss | S3 backend with versioning + DynamoDB locking |
| Container complexity | Start with 1 simple service, add more only if time permits |
| DevSecOps tool overload | Pick 2-3 essential scanners, don't try all 10 |
| Manara submission mismatch | Confirm Project 8 elements are clearly identifiable |

---

## 12. Extensions (After Project Completion)

Ideas to add AFTER the main project is submitted:

- Multi-region DR (Pilot Light in eu-west-3)
- Kubernetes (EKS) version of the workload
- AI/ML component (Bedrock integration)
- Advanced observability (Datadog, Grafana)
- Cost automation (auto-shutdown of dev resources)
- Compliance automation (AWS Audit Manager)
- Chaos engineering (fault injection tests)

---

## 13. References I'll Use

- [AWS Security Reference Architecture](https://github.com/aws-samples/aws-security-reference-architecture-examples)
- [Muhammad Imad's Terraform Landing Zone](https://github.com/Muhammad-Imad/terraform-aws-landing-zone)
- [Brianbobbs' AWS Landing Zone](https://github.com/Brianbobbs/aws-landing-zone)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [CIS AWS Foundations Benchmark](https://www.cisecurity.org/benchmark/amazon_web_services)
- [The 9 Pillars document](../CERT-NOTES/01%20-%20Foundations/The%209%20Pillars%20of%20Real%20Company%20Cloud%20Architecture.md)

---

## 14. My Learning Journal

Where I capture aha moments, mistakes, and reflections:

- See `Lessons learned.md`
- See daily notes in `07 - Daily notes/`

---

## Related Notes

- [[Requirements]]
- [[Architecture design]]
- [[Decisions log]]
- [[Lessons learned]]
- [[Recruiter pitch]]
- [[The 9 Pillars of Real Company Cloud Architecture]]

---

**Next step:** Complete the `Requirements.md` document with detailed functional and non-functional requirements.