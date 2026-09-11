# Requirements — Atlas FinTech Cloud Platform

**Project:** AWS Enterprise-Grade Cloud Platform
**Client (fictional):** Atlas FinTech Solutions
**Author:** Hiba Chagdaly
**Date:** [YYYY-MM-DD]
**Version:** 1.0

---

## 1. Business Context

Atlas FinTech is a Moroccan payment processing startup. Post-Series A. 55 employees. Growing fast. Handles sensitive financial data.

Current AWS setup has serious problems:
- Everyone uses the root user
- Access keys hardcoded in GitHub repositories
- No audit trail
- No cost tracking
- No environment isolation (dev = prod)

**Business goals driving this project:**
- Pass SOC 2 audit in 6 months
- Support 3x employee growth without security breakdowns
- Enable enterprise sales (which require security due diligence)
- Prepare for future PCI-DSS compliance
- Control cloud costs while pre-profit

---

## 2. Stakeholders

| Stakeholder | Interest | Priority |
|-------------|----------|----------|
| CTO (Yasmine) | Overall security, cost, delivery speed | High |
| Engineering lead | Developer productivity | High |
| Security lead | Audit readiness, threat detection | High |
| SRE lead | Reliability, incident response | High |
| Finance director | Cost visibility, budget control | Medium |
| Compliance officer | SOC 2 evidence, audit trails | High |
| Data analysts | Read access to production data | Medium |
| Developers | Deploy code without waiting for approvals | High |

---

## 3. Functional Requirements

### 3.1 Identity & Access

**FR-IAM-01:** All human access MUST go through IAM Identity Center (no direct IAM users).
**FR-IAM-02:** IAM Identity Center MUST federate with Google Workspace via SAML.
**FR-IAM-03:** All human logins MUST require MFA.
**FR-IAM-04:** Root user MUST be locked (MFA, credentials stored offline, alerts on any use).
**FR-IAM-05:** Developers MUST have full access to dev, read-only to staging, no access to prod.
**FR-IAM-06:** SREs MUST have full access to prod under session-limited role assumption.
**FR-IAM-07:** Data analysts MUST have read-only access to production data with no PII exposure.
**FR-IAM-08:** Finance MUST have Cost Explorer + Billing access only.
**FR-IAM-09:** GitHub Actions MUST authenticate to AWS via OIDC (no static access keys).
**FR-IAM-10:** Every IAM identity MUST have a documented purpose.

### 3.2 Multi-Account Structure

**FR-ORG-01:** The organization MUST have at least 5 accounts: Management, Log Archive, Audit, Dev, Prod.
**FR-ORG-02:** Accounts MUST be organized in OUs (Security OU, Workloads OU).
**FR-ORG-03:** SCPs MUST enforce:
- No root user usage (except in Management)
- Deny leaving the Organization
- Region allow-list (eu-west-1 only initially)
- Require IMDSv2 on EC2
- Deny creation of long-lived access keys
**FR-ORG-04:** All accounts MUST have GuardDuty, Security Hub, Config, and CloudTrail enabled.

### 3.3 Networking

**FR-NET-01:** Each account MUST have its own VPC with public/private/isolated subnets across 2+ AZs.
**FR-NET-02:** Compute resources MUST run in private subnets (no public IPs on workloads).
**FR-NET-03:** All AWS service traffic MUST use VPC endpoints where possible (S3, DynamoDB, ECR, Secrets Manager).
**FR-NET-04:** ALB MUST be the only public-facing entry point.
**FR-NET-05:** WAF MUST protect the ALB with OWASP Top 10 rules.
**FR-NET-06:** Security groups MUST follow least privilege (no 0.0.0.0/0 except for public ALB).

### 3.4 Compute (Containerized Workload)

**FR-CMP-01:** Workload MUST run as containers on ECS Fargate (no EC2 servers to manage).
**FR-CMP-02:** MUST have at least 3 microservices demonstrating service-to-service communication.
**FR-CMP-03:** Container images MUST be stored in ECR with image scanning enabled.
**FR-CMP-04:** Task definitions MUST use least-privilege task roles (per service).
**FR-CMP-05:** Deployment MUST use blue/green strategy with automatic rollback.
**FR-CMP-06:** Auto Scaling MUST scale based on CPU/memory metrics.
**FR-CMP-07:** No secrets in container images or task definitions (must use Secrets Manager).

### 3.5 Data

**FR-DAT-01:** Primary database MUST be RDS PostgreSQL Multi-AZ.
**FR-DAT-02:** Database MUST be encrypted at rest with customer-managed KMS keys.
**FR-DAT-03:** Database credentials MUST be stored in Secrets Manager with automatic rotation.
**FR-DAT-04:** Automated backups MUST be enabled with 7-day retention minimum.
**FR-DAT-05:** All S3 buckets MUST have:
- Default encryption (KMS)
- Public access blocked
- Versioning enabled
- Access logging enabled

### 3.6 Security

**FR-SEC-01:** GuardDuty MUST be enabled in all accounts, with delegated administration to Audit account.
**FR-SEC-02:** Security Hub MUST aggregate findings from all accounts with CIS benchmark enabled.
**FR-SEC-03:** AWS Config MUST have CIS conformance pack applied.
**FR-SEC-04:** CloudTrail MUST log all events to a centralized bucket in Log Archive account.
**FR-SEC-05:** CloudTrail logs MUST be immutable (S3 Object Lock + bucket policy).
**FR-SEC-06:** All KMS keys MUST have automatic rotation enabled.
**FR-SEC-07:** Auto-remediation MUST exist for critical findings (public S3, disabled encryption).

### 3.7 DevOps & DevSecOps

**FR-DEV-01:** All infrastructure MUST be defined as Terraform code.
**FR-DEV-02:** Terraform state MUST be stored in S3 with DynamoDB locking.
**FR-DEV-03:** CI/CD MUST use GitHub Actions with OIDC (no static AWS credentials in secrets).
**FR-DEV-04:** Pipeline MUST include the following security scans and fail on high severity:
- Checkov (Terraform SAST)
- tfsec (Terraform SAST)
- Trivy (container images)
- TruffleHog / GitLeaks (secrets)
- Dependabot / Snyk (dependencies)
**FR-DEV-05:** Container images MUST be scanned in ECR on every push.
**FR-DEV-06:** Deployments MUST be automated end-to-end (no manual clicks).

### 3.8 Observability

**FR-OBS-01:** CloudWatch dashboards MUST exist per account showing key metrics.
**FR-OBS-02:** Critical alarms MUST notify via SNS → email (and Slack if possible).
**FR-OBS-03:** Application logs MUST be centralized in CloudWatch Logs.
**FR-OBS-04:** Log retention MUST be at least 90 days.
**FR-OBS-05:** Dashboards MUST include: cost, security findings, workload health.

### 3.9 Cost Management (FinOps)

**FR-COST-01:** All resources MUST be tagged with:
- Environment (dev/prod)
- Owner
- Project
- Cost Center
**FR-COST-02:** Tag enforcement MUST be applied via SCP.
**FR-COST-03:** AWS Budgets MUST alert at 50%, 80%, 100% of monthly budget.
**FR-COST-04:** Cost Anomaly Detection MUST be enabled.

---

## 4. Non-Functional Requirements

### 4.1 Security
**NFR-SEC-01:** Zero long-lived access keys in the environment.
**NFR-SEC-02:** All data encrypted at rest and in transit.
**NFR-SEC-03:** Blast radius of any single compromised credential must be limited (multi-account isolation).
**NFR-SEC-04:** Every action must be auditable and traceable to an identity.

### 4.2 Reliability
**NFR-REL-01:** Workload must survive single AZ failure.
**NFR-REL-02:** Database must have automated failover (Multi-AZ).
**NFR-REL-03:** Deployment must roll back automatically on failure.

### 4.3 Performance
**NFR-PERF-01:** ALB health checks < 30 seconds.
**NFR-PERF-02:** ECS task startup < 60 seconds.
**NFR-PERF-03:** Database queries < 100ms p95.

### 4.4 Cost
**NFR-COST-01:** Total infrastructure cost < $50/month during project.
**NFR-COST-02:** No idle resources beyond planned free tier usage.

### 4.5 Maintainability
**NFR-MAIN-01:** All Terraform modules must be reusable.
**NFR-MAIN-02:** All decisions must be documented as ADRs.
**NFR-MAIN-03:** Runbooks must exist for common operations.

### 4.6 Compliance
**NFR-COMP-01:** Design must map to SOC 2 controls.
**NFR-COMP-02:** Design must map to CIS AWS Foundations Benchmark.
**NFR-COMP-03:** Preparation for PCI-DSS compliance considered.

---

## 5. Constraints

- **Budget:** AWS Free Tier + max $50 for the entire project.
- **Region:** eu-west-1 (Ireland) as primary; secondary region only for DR extension (later).
- **Timeline:** 5-7 weeks at 8-10 hours/day.
- **Tools:** Terraform, GitHub Actions, Docker, Obsidian, draw.io.
- **Team size:** Solo developer (me).

---

## 6. Assumptions

- Google Workspace SAML federation is available (simulated).
- Free Tier is available for the AWS account.
- Docker and Terraform are installed on my machine.
- I have permissions to create sub-accounts under my AWS account.

---

## 7. Out of Scope (This Version)

Explicitly NOT included in v1:

- Multi-region disaster recovery (future extension)
- Kubernetes / EKS deployment
- Advanced APM (Datadog, New Relic)
- On-premise hybrid connectivity (VPN / Direct Connect)
- Data lake / analytics pipeline
- Machine learning workloads
- Third-party SIEM integration

These may become follow-up projects.

---

## 8. Definition of Done

The project is DONE when:

- [ ] All functional requirements are implemented
- [ ] All non-functional requirements are validated
- [ ] Terraform can deploy the entire platform from scratch
- [ ] Terraform can destroy the entire platform cleanly
- [ ] All ADRs are written (~15-20)
- [ ] Threat model is documented
- [ ] Compliance mapping document is complete
- [ ] Attack simulation is documented with results
- [ ] Full README is polished
- [ ] Blog post is drafted
- [ ] GitHub repo is public and clean
- [ ] Manara graduation submission is prepared

---

## 9. Success Metrics

Measurable indicators of a successful project:

| Metric | Target |
|--------|--------|
| Terraform deployment success | 100% (idempotent) |
| Security Hub compliance score | > 80% |
| GuardDuty findings resolved | 100% (or documented exceptions) |
| DevSecOps pipeline pass rate | > 95% |
| Monthly cost | < $50 |
| ADRs documented | 15-20 |
| Blog post published | Yes |
| Interview-ready explanations per pillar | 9 out of 9 |

---

## Related Documents

- [[00 - Project Overview]]
- [[Architecture design]]
- [[Decisions log]]
- [[Threat model]]
- [[The 9 Pillars of Real Company Cloud Architecture]]