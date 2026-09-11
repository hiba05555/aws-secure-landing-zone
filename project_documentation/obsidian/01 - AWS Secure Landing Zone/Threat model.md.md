# Threat Model — Atlas FinTech Cloud Platform

**Framework:** STRIDE
**Author:** Hiba Chagdaly
**Date:** [YYYY-MM-DD]
**Version:** 1.0

---

## 1. What Is STRIDE?

STRIDE is a threat modeling framework created by Microsoft. It categorizes threats into 6 types:

| Letter | Threat                 | Violates        |
| ------ | ---------------------- | --------------- |
| **S**  | Spoofing               | Authentication  |
| **T**  | Tampering              | Integrity       |
| **R**  | Repudiation            | Non-repudiation |
| **I**  | Information Disclosure | Confidentiality |
| **D**  | Denial of Service      | Availability    |
| **E**  | Elevation of Privilege | Authorization   |

For every asset in the system, I ask: "Which of these 6 could hurt it, and how do I defend against each?"

---

## 2. Assets I'm Protecting

Before threats, I list what's valuable:

| Asset | Why It Matters |
|-------|----------------|
| Customer payment data | Legal liability, compliance (PCI-DSS) |
| AWS root credentials | Full account takeover risk |
| IAM Identity Center | Gateway to all human access |
| Database (RDS) | Contains business + customer data |
| Container images (ECR) | Supply chain attack vector |
| CI/CD pipeline (GitHub Actions) | Deploys to production |
| Terraform state | Contains infrastructure secrets |
| CloudTrail logs | Audit evidence (compliance) |
| KMS keys | Encryption foundation |
| Secrets Manager secrets | DB passwords, API keys |

---

## 3. Threat Actors

Who might attack us?

| Actor                             | Motivation                 | Sophistication |
| --------------------------------- | -------------------------- | -------------- |
| External attacker (opportunistic) | Financial gain, ransomware | Low-Medium     |
| External attacker (targeted)      | Payment data theft         | High           |
| Malicious insider                 | Data theft, sabotage       | Medium         |
| Compromised employee laptop       | Credential leak            | Low            |
| Automated bot / scanner           | Vulnerability exploitation | Low            |
| Supply chain attacker             | Backdoor via dependencies  | High           |
| Nation-state actor                | Espionage, disruption      | Very High      |

---

## 4. STRIDE Analysis Per Component

### 4.1 IAM Identity Center

| STRIDE | Threat | Mitigation |
|--------|--------|------------|
| **S** Spoofing | Attacker steals user credentials to impersonate them | MFA enforcement, SSO federation, short-lived sessions |
| **T** Tampering | Attacker modifies permission sets | CloudTrail audit, SCP guardrails, least privilege |
| **R** Repudiation | User denies performing an action | CloudTrail immutable logs, session duration limits |
| **I** Information Disclosure | Permission sets expose sensitive resources | Access reviews, Access Analyzer |
| **D** Denial of Service | Attacker locks out users via failed logins | Rate limiting via WAF, account recovery process |
| **E** Elevation of Privilege | User assumes role beyond their permissions | Permission boundaries, SCPs at OU level |

### 4.2 AWS Root User

| STRIDE | Threat | Mitigation |
|--------|--------|------------|
| **S** Spoofing | Attacker uses root credentials | MFA on root, credentials stored offline, alerts on root login |
| **T** Tampering | Root disables security controls | SCPs cannot restrict root but alerting exists |
| **R** Repudiation | Root actions untraceable | CloudTrail captures root events, alarms on any root action |
| **I** Information Disclosure | Root credentials leaked | Never used, no access keys created |
| **D** Denial of Service | Root closes the account | Alerting on billing changes |
| **E** Elevation of Privilege | Root is already max privilege | Locked away, only used for account setup |

### 4.3 RDS Database

| STRIDE | Threat | Mitigation |
|--------|--------|------------|
| **S** Spoofing | Attacker uses stolen DB credentials | Secrets Manager with rotation, IAM database auth |
| **T** Tampering | Attacker modifies data | Encryption at rest, database audit logs |
| **R** Repudiation | Unable to prove who changed data | Database audit logging enabled, CloudTrail for RDS API |
| **I** Information Disclosure | Data leak via SQL injection or misconfigured SG | WAF, parameterized queries, private subnet only |
| **D** Denial of Service | Resource exhaustion | Connection pooling, RDS Proxy, alarms |
| **E** Elevation of Privilege | App uses over-privileged DB user | Least-privilege DB users per service |

### 4.4 Container Images (ECR)

| STRIDE | Threat | Mitigation |
|--------|--------|------------|
| **S** Spoofing | Attacker pushes malicious image | IAM controls on ECR, signed images |
| **T** Tampering | Base image modified with backdoor | Trivy scanning, immutable tags, image signing |
| **R** Repudiation | Unclear who pushed a bad image | CloudTrail logs ECR events |
| **I** Information Disclosure | Secrets baked into image | Secret scanning in CI, .dockerignore, no build args for secrets |
| **D** Denial of Service | Malicious image consumes resources | Resource limits in ECS task definitions |
| **E** Elevation of Privilege | Container escapes to host | Fargate isolation, no privileged containers |

### 4.5 CI/CD Pipeline (GitHub Actions)

| STRIDE | Threat | Mitigation |
|--------|--------|------------|
| **S** Spoofing | Attacker forks repo and triggers pipeline | Branch protection, OIDC subject conditions |
| **T** Tampering | Malicious PR modifies pipeline | Required reviews, protected branches, CODEOWNERS |
| **R** Repudiation | Untraceable pipeline changes | Git history, GitHub audit logs |
| **I** Information Disclosure | Secrets in pipeline logs | GitHub secrets masking, OIDC (no long-lived keys) |
| **D** Denial of Service | Pipeline abuse (crypto mining) | Rate limits, concurrency controls |
| **E** Elevation of Privilege | Pipeline assumes over-privileged role | Least-privilege deployment roles per environment |

### 4.6 Terraform State

| STRIDE | Threat | Mitigation |
|--------|--------|------------|
| **S** Spoofing | Attacker impersonates Terraform user | OIDC-based access, MFA |
| **T** Tampering | State file modified maliciously | S3 versioning, DynamoDB locking |
| **R** Repudiation | Unknown who changed state | CloudTrail on S3, tf plan review in PRs |
| **I** Information Disclosure | State contains secrets in plaintext | S3 encryption at rest, block public access, no secrets in tfvars |
| **D** Denial of Service | State file corruption | Versioning + backups |
| **E** Elevation of Privilege | User with tf access has too much | Separate state per environment, least-privilege backend access |

### 4.7 Public-Facing Application (via ALB)

| STRIDE | Threat | Mitigation |
|--------|--------|------------|
| **S** Spoofing | Attacker impersonates users | JWT + Cognito, MFA on sensitive actions |
| **T** Tampering | Request tampering | HTTPS only, signed tokens, WAF |
| **R** Repudiation | User denies transaction | Application logs, CloudTrail |
| **I** Information Disclosure | XSS, SQLi, data leak | WAF rules (OWASP Top 10), input validation |
| **D** Denial of Service | DDoS, application-layer flood | Shield Standard, WAF rate limiting, Auto Scaling |
| **E** Elevation of Privilege | Broken authz in application | Least-privilege JWT scopes, tested authz logic |

---

## 5. Threats I'm Explicitly NOT Defending Against (Scope Boundaries)

Being honest about limits:

- **Nation-state persistent threats** — beyond a startup's realistic threat model
- **Physical attacks on AWS data centers** — AWS's responsibility (Shared Responsibility Model)
- **Zero-day exploits in AWS services** — patched by AWS
- **Social engineering of AWS support** — out of my direct control (partial mitigation via MFA on account)
- **Malicious AWS employees** — trust boundary, mitigated by AWS internal controls
- **Insider threats with legitimate admin access** — hard to fully prevent; mitigated by audit + separation of duties

---

## 6. Top 10 Most Critical Threats (Prioritized)

If I had to fix 10 things first, these are the priority:

1. **Root user credentials leak** → MFA + offline storage + alerts
2. **Long-lived access keys in CI/CD** → OIDC federation (no keys)
3. **Overly permissive IAM policies** → Access Analyzer + least privilege
4. **Public S3 buckets** → SCP denying public access + Config rule
5. **Unencrypted data at rest** → KMS everywhere, enforced by policy
6. **Missing audit trail** → Centralized CloudTrail in Log Archive
7. **Compromised container images** → Trivy scanning + immutable tags
8. **Insecure Terraform state** → S3 encryption + versioning + locking
9. **Application-layer attacks (SQLi, XSS)** → WAF with OWASP rules
10. **Lack of threat detection** → GuardDuty across all accounts

---

## 7. Attack Simulation Plan

To validate defenses work, I will simulate these attacks (during Phase 7 testing):

| Attack | Expected Detection | Where |
|--------|-------------------|-------|
| Launch EC2 with public IP + SSH open | GuardDuty finding: Recon:EC2/PortProbeUnprotectedPort | GuardDuty |
| Attempt root user login | CloudWatch alarm → SNS notification | CloudTrail alarm |
| Create S3 bucket without encryption | Config rule fails, auto-remediation triggers | Config |
| Push container image with known CVE | Pipeline fails at Trivy scan | GitHub Actions |
| Attempt SQL injection via ALB | WAF blocks request | WAF logs |
| Try to disable CloudTrail | SCP denies action, CloudTrail alarm fires | SCP + Alarm |
| Try to assume admin role from dev account | STS AssumeRole denied by trust policy | CloudTrail |

**Screenshots of each detection will be included in the portfolio.**

---

## 8. Compliance Mapping (Preview)

Each threat mitigation maps to compliance controls:

| Mitigation | SOC 2 | CIS | PCI-DSS |
|-----------|-------|-----|---------|
| MFA on root | CC6.1 | 1.13 | 8.3 |
| Centralized CloudTrail | CC7.2 | 3.1 | 10.2 |
| KMS encryption | CC6.7 | 2.7 | 3.4 |
| Least privilege IAM | CC6.1 | 1.16 | 7.1 |
| GuardDuty threat detection | CC7.2 | 4.1 | 10.6 |

(Full compliance mapping in a separate document at Phase 7.)

---

## 9. Living Document

This threat model is not static. It evolves as:

- New components are added
- New threats emerge
- New AWS services are adopted
- Attack simulations reveal gaps

**Review cadence:** Every 3 months (or after major architecture changes).

---

## Related Documents

- [[00 - Project Overview]]
- [[Requirements]]
- [[Architecture design]]
- [[Decisions log]]
- [[The 9 Pillars of Real Company Cloud Architecture]]