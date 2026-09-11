# Phase 7 — DevSecOps (CI/CD Pipeline with OIDC and Security Gate)

## 🎯 Overview

This phase automates what was previously a manual process — building a container image and getting it into ECS — through a GitHub Actions pipeline authenticated via OIDC federation (no stored AWS credentials), with a hard security gate that blocks deployment if the pushed image contains critical vulnerabilities. The goal was proving the _mechanics_ of a credential-free, security-gated pipeline end-to-end, using the existing nginx placeholder rather than building a new application.

**What was built:**

- A new `infra/cicd/` folder holding cross-cutting CI/CD IAM resources
- OIDC federation between GitHub Actions and AWS (identity provider + scoped IAM role, zero long-lived credentials)
- A minimal `Dockerfile` + custom `index.html`, giving the pipeline something real to build
- A GitHub Actions workflow: build → push to ECR → **security gate** → force ECS redeploy
- The security gate verified functional against a real finding — not just theoretically present

## 🏗️ Why OIDC instead of stored AWS keys

The traditional (and weaker) approach stores long-lived AWS access keys as GitHub repository secrets. OIDC federation replaces that entirely: GitHub issues a short-lived, cryptographically signed token per workflow run; AWS validates that token against a trust policy and issues **temporary** credentials scoped to exactly what the role allows. Nothing to rotate, nothing to leak, nothing sitting in GitHub's secret store waiting to be exfiltrated.

```
GitHub Actions run
        │  (requests OIDC token)
        ▼
token.actions.githubusercontent.com
        │  (signed JWT: sub, aud, repo claims)
        ▼
AWS STS AssumeRoleWithWebIdentity
        │  (trust policy validates claims)
        ▼
Temporary AWS credentials (session-scoped)
        │
        ▼
ECR push + ECS deploy, using only those temp creds
```

## 🛠️ Implementation

### New folder: `infra/cicd/`

Same pattern as `security/` and `observability/` — `assume_role` into the `network` account, its own state file (`cicd/terraform.tfstate`), consistent tagging (`Component = "cicd"`).

### OIDC identity provider

```hcl
data "tls_certificate" "github" {
    url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
    url             = "https://token.actions.githubusercontent.com"
    client_id_list  = ["sts.amazonaws.com"]
    thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}
```

The thumbprint is fetched dynamically rather than hardcoded — GitHub's certificate can rotate, and a stale hardcoded thumbprint would silently break trust one day.

### IAM role — trust policy scoped to this exact repo

```hcl
data "aws_iam_policy_document" "github_actions_trust" {
    statement {
        effect  = "Allow"
        actions = ["sts:AssumeRoleWithWebIdentity"]

        principals {
            type        = "Federated"
            identifiers = [aws_iam_openid_connect_provider.github.arn]
        }

        condition {
            test     = "StringEquals"
            variable = "token.actions.githubusercontent.com:aud"
            values   = ["sts.amazonaws.com"]
        }

        condition {
            test     = "StringLike"
            variable = "token.actions.githubusercontent.com:sub"
            values   = ["repo:hiba05555*aws-secure-landing-zone*"]
        }
    }
}

resource "aws_iam_role" "github_actions" {
    name               = "atlas-fintech-github-actions-role"
    assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
}
```

The `sub` condition is the actual security boundary — it restricts which GitHub repo can assume this role. Without it, any repository anywhere using GitHub's OIDC provider could attempt to assume it.

### Scoped permissions — least privilege for exactly what the pipeline needs

```hcl
data "aws_iam_policy_document" "github_actions_permissions" {
    statement {
        sid       = "ECRAuth"
        effect    = "Allow"
        actions   = ["ecr:GetAuthorizationToken"]
        resources = ["*"]
    }

    statement {
        sid    = "ECRPush"
        effect = "Allow"
        actions = [
            "ecr:BatchCheckLayerAvailability", "ecr:PutImage",
            "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"
        ]
        resources = [data.terraform_remote_state.compute.outputs.ecr_repo_arn]
    }

    statement {
        sid    = "ECRScanRead"
        effect = "Allow"
        actions = [
            "ecr:DescribeImageScanFindings", "ecr:BatchGetImage", "ecr:DescribeImages"
        ]
        resources = [data.terraform_remote_state.compute.outputs.ecr_repo_arn]
    }

    statement {
        sid     = "ECSDeploy"
        effect  = "Allow"
        actions = ["ecs:UpdateService", "ecs:DescribeServices", "ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
        resources = ["*"]
    }

    statement {
        sid       = "PassExecutionRoles"
        effect    = "Allow"
        actions   = ["iam:PassRole"]
        resources = [
            data.terraform_remote_state.compute.outputs.ecs_execution_role_arn,
            data.terraform_remote_state.compute.outputs.ecs_task_role_arn
        ]
    }
}
```

**`iam:PassRole` scoped to exactly two role ARNs, not `*`** — this is a deliberate anti-privilege-escalation measure. Without this restriction, a compromised pipeline could theoretically pass an unrelated, more-privileged role to a new ECS task. `ecs:RegisterTaskDefinition` requires `resources = ["*"]` since AWS doesn't support resource-level restriction on that specific action — a platform limitation, not a design choice.

Three new outputs were added to `compute/outputs.tf` to support this: `ecr_repo_arn`, `ecs_execution_role_arn`, `ecs_task_role_arn` — none had been exposed before this phase.

### Dockerfile — a real build, not a passthrough

```dockerfile
FROM public.ecr.aws/nginx/nginx:latest
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
```

A trivial custom `index.html` was added so the pipeline genuinely _builds_ something (proving it works end-to-end) rather than just re-pushing an unmodified public image.

### GitHub Actions workflow — build, gate, deploy

```yaml
name: Build and Deploy to ECS

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

env:
  AWS_REGION: eu-west-1
  ECR_REPOSITORY: atlas-fintech-app
  ECS_CLUSTER: atlas-fintech-cluster
  ECS_SERVICE: atlas-fintech-app

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::622532143366:role/atlas-fintech-github-actions-role
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build, tag, and push image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

      - name: Wait for ECR scan and check for critical vulnerabilities
        run: |
          sleep 10
          aws ecr wait image-scan-complete \
            --repository-name $ECR_REPOSITORY \
            --image-id imageTag=$IMAGE_TAG

          CRITICAL_COUNT=$(aws ecr describe-image-scan-findings \
            --repository-name $ECR_REPOSITORY \
            --image-id imageTag=$IMAGE_TAG \
            --query 'imageScanFindings.findingSeverityCounts.CRITICAL' \
            --output text)

          echo "Critical vulnerabilities found: $CRITICAL_COUNT"

          if [ "$CRITICAL_COUNT" != "None" ] && [ "$CRITICAL_COUNT" -gt 0 ]; then
            echo "::error::Deployment blocked — $CRITICAL_COUNT CRITICAL vulnerabilities found in image"
            exit 1
          fi
        env:
          IMAGE_TAG: ${{ github.sha }}

      - name: Force new ECS deployment
        run: |
          aws ecs update-service --cluster $ECS_CLUSTER --service $ECS_SERVICE --force-new-deployment
```

**Key points:**

- `permissions: id-token: write` is mandatory at the workflow level — without it, GitHub never generates the OIDC token, regardless of how correct the AWS-side trust policy is.
- The security gate sits **between** the push and the deploy — if it fails, `Force new ECS deployment` never runs, so a vulnerable image never reaches production. This is what makes it a gate rather than a post-hoc report.
- `sleep 10` before `aws ecr wait image-scan-complete` — ECR needs a brief moment to register that a scan has started; calling the waiter immediately after push can race ahead of that registration and fail with `ScanNotFoundException`.

## 🐞 Debugging — the OIDC `sub` claim format change

This was the dominant issue of the phase: every workflow run failed identically with `Not authorized to perform sts:AssumeRoleWithWebIdentity`, despite the trust policy, provider ARN, audience, thumbprint, and repo name all being individually verified correct multiple times.

**Systematic elimination process:**

1. Verified trust policy JSON matched exactly what was intended
2. Verified OIDC provider ARN and audience matched
3. Checked all 6 organizational SCPs for anything touching `sts:*` — none did
4. Confirmed `id-token: write` was present in the committed workflow
5. Destroyed and recreated the OIDC provider and role from scratch via `terraform taint` — no change
6. Verified the repo URL matched the trust policy's repo name exactly

**Root cause, found via GitHub's own documentation:** repositories created after July 15, 2026 (this repo included) receive OIDC `sub` claims in a new **immutable ID format**:

```
repo:owner@<owner-id>/repo-name@<repo-id>:ref:refs/heads/main
```

instead of the older, simpler format:

```
repo:owner/repo-name:ref:refs/heads/main
```

The trust policy's `StringLike` condition was written for the old format (`repo:hiba05555/aws-secure-landing-zone:*`), which does not match the new format at all — the `@<id>` segments break the literal pattern match entirely. Every verification pass looked correct in isolation because the policy _was_ syntactically valid — it simply matched against a claim format GitHub no longer sends for newly created repos.

**Fix:**

```hcl
values = ["repo:hiba05555*aws-secure-landing-zone*"]
```

Using `*` to bridge the optional `@<id>` segments matches both the old and new claim formats.

## ✅ Verifying the security gate actually works

Rather than accept a clean pipeline run as proof the gate exists, the gate was tested against a real finding. The ECR scan on the pushed nginx-based image reported **53 vulnerabilities, including 4 CRITICAL** (in the base `perl` and `glibc` packages, not application code). The pipeline correctly:

1. Detected `CRITICAL_COUNT=4`
2. Printed a clear `::error::` annotation
3. Exited with code 1
4. **Never executed** the `Force new ECS deployment` step

This is stronger evidence than a passing run would have been — it proves the gate genuinely blocks deployment on real findings, not just that the step exists in the YAML.

## 📸 Evidence

![[3 7.png]]
 _1 — IAM Identity Provider, token.actions.githubusercontent.com, audience sts.amazonaws.com._

![[4 7.png]] _2 — IAM role trust relationships, final working sub condition._

![[5 7.png]] _3 — `terraform state list`, cicd/._

![[2 7.png]] _4 — ECR image detail, 53 vulnerabilities (4 Critical), scan status Complete._

![[1 7.png]] _5 — GitHub Actions run, scan gate blocking deployment (exit code 1, 4 CRITICAL found)._

![[7 7.png]] _6 — Successful pipeline run showing OIDC auth, ECR push, and workflow steps._

## 💡 Lessons Learned

1. **A syntactically correct IAM policy can still be functionally wrong against the actual data it's evaluated against.** Every individual piece of the OIDC trust chain checked out in isolation — the bug was an assumption about claim _format_, not a configuration error visible in any single field.
    
2. **Provider-side breaking changes (GitHub's claim format update) can silently invalidate infrastructure that was correct when written.** This is a real-world argument for monitoring provider changelogs on anything security-critical, not just AWS's own release notes.
    
3. **A security gate is only proven by a real block, not by its presence in code.** Testing against an actual finding (the 4 critical CVEs) gave genuine confidence the pipeline does what it's supposed to — a clean run alone would have left this unverified.
    
4. **`iam:PassRole` scoping is a concrete, checkable anti-privilege-escalation control** — not abstract best practice. Restricting it to exactly the two roles the task definition uses closes a real path a compromised pipeline could otherwise exploit.
    
5. **Systematic elimination beats guessing, but only when paired with real evidence.** Ruling out SCPs, provider config, and workflow permissions one at a time was the right process — the missing step was getting direct evidence of the actual claim value sooner, rather than continuing to re-verify pieces already confirmed correct.
    

## ✅ Completion Status

|Component|Status|
|---|---|
|`infra/cicd/` folder + remote state pattern|✅ Complete|
|OIDC provider + scoped IAM role (no stored credentials)|✅ Complete|
|Least-privilege permissions (scoped `iam:PassRole`, ECR/ECS actions)|✅ Complete|
|Dockerfile + custom placeholder content|✅ Complete|
|GitHub Actions pipeline (build → push → gate → deploy)|✅ Complete|
|Security gate verified against real critical findings|✅ Complete|

**Next:** Phase 8 (FinOps) — cost visibility and optimization across the landing zone; separately, the base image's critical CVEs remain an open item for whenever a real application image replaces the nginx placeholder (patched base image or explicit accepted-risk documentation).

## 📚 References

- [GitHub Actions — Configuring OpenID Connect in Amazon Web Services](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS IAM OIDC Identity Providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [Amazon ECR Image Scanning](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html)
- [Terraform aws_iam_openid_connect_provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider)