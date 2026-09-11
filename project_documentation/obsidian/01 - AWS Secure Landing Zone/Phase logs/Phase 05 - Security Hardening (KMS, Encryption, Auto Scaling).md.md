# Phase 5 — Security Hardening (KMS, Encryption, Auto Scaling)

## 🎯 Overview

This phase hardens the compute layer built in Phase 4 with encryption at rest, centralized log visibility, and elastic capacity — moving the workload from "functionally working" to "audit-ready." A new `infra/security/` folder was introduced to hold cross-cutting resources shared across the compute layer, following the same account/backend pattern as `network/` and `compute/`.

**What was built:**

- A customer-managed KMS key (`security/`) with a scoped key policy for CloudWatch Logs and ECR
- A KMS-encrypted CloudWatch log group wired into the ECS Task Definition via the `awslogs` driver
- ECR repository upgraded from `MUTABLE` (Phase 4) to `IMMUTABLE`, and from AWS-owned (AES256) to customer-managed KMS encryption
- Application Auto Scaling (Target Tracking) on the ECS Service, scaling 2–4 tasks on CPU utilization

## 🏗️ A new folder: `infra/security/`

Unlike Phase 4's changes (which modified existing resources directly in `compute/`), the KMS key and log group are **new, cross-cutting resources** that other phases will keep referencing (ECR encryption today; potentially RDS, Secrets Manager, or S3 buckets later). Splitting them into their own state file avoids coupling their lifecycle to the compute layer's, and lets `compute/` consume them read-only via `terraform_remote_state` — the same pattern `compute/` already uses to consume `network/`'s outputs.

```
infra/
├── network/    (Phase 3)
├── compute/    (Phase 4 + amendments)
└── security/   (Phase 5 — new)
```

## 🛠️ Implementation

### KMS key — one key, two consumers

```hcl
resource "aws_kms_key" "security" {
    description             = "Atlas FinTech shared KMS key for logs and ECR encryption"
    deletion_window_in_days = 30
    enable_key_rotation     = true

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Sid       = "EnableRootAccountAdmin"
                Effect    = "Allow"
                Principal = { AWS = "arn:aws:iam::622532143366:root" }
                Action    = "kms:*"
                Resource  = "*"
            },
            {
                Sid    = "AllowCloudWatchLogsUse"
                Effect = "Allow"
                Principal = { Service = "logs.eu-west-1.amazonaws.com" }
                Action = [
                    "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
                    "kms:GenerateDataKey*", "kms:DescribeKey"
                ]
                Resource = "*"
                Condition = {
                    ArnLike = {
                        "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:eu-west-1:622532143366:*"
                    }
                }
            },
            {
                Sid    = "AllowECRUse"
                Effect = "Allow"
                Principal = { Service = "ecr.amazonaws.com" }
                Action   = ["kms:Decrypt", "kms:GenerateDataKey*", "kms:CreateGrant"]
                Resource = "*"
                Condition = {
                    Bool = { "kms:GrantIsForAWSResource" = "true" }
                }
            }
        ]
    })
}

resource "aws_kms_alias" "security" {
    name          = "alias/atlas-fintech-security-key"
    target_key_id = aws_kms_key.security.key_id
}
```

**Design decisions:**

- **Root admin statement is non-negotiable** — KMS key policies require explicit access grants even for the account root; unlike most AWS services, IAM policies alone can't grant access to a key. Omitting this can permanently lock out key management.
- **`kms:EncryptionContext` condition** scopes the CloudWatch Logs statement so `logs.amazonaws.com` can only use the key for log groups in this exact account — not a blanket grant to any caller of that service.
- **`kms:CreateGrant` on the ECR statement, with a `Bool` condition** restricting it to AWS-internal resource grants — added after `terraform plan`/`apply` initially succeeded but before any image had been pushed, anticipating that ECR needs a grant (not just decrypt/generate) to actually use a customer-managed key during push/pull operations.
- **`enable_key_rotation = true`** — automatic annual key material rotation, transparent to every resource using the alias.

### CloudWatch log group — encrypted, wired to ECS

```hcl
resource "aws_cloudwatch_log_group" "security" {
    name              = "/ecs/atlas-fintech-app"
    retention_in_days = 30
    kms_key_id        = aws_kms_key.security.arn
}
```

Note the naming inconsistency worth remembering: `kms_key_id` on this resource actually expects the key **ARN**, not the bare key ID — despite the argument name.

In `compute/`, the Task Definition's container definition was updated to ship logs there:

```hcl
logConfiguration = {
    logDriver = "awslogs"
    options = {
        "awslogs-group"         = data.terraform_remote_state.security.outputs.ecs_log_group_name
        "awslogs-region"        = "eu-west-1"
        "awslogs-stream-prefix" = "ecs"
    }
}
```

Since Task Definitions are immutable, this change created a **new revision** (`my-app:2`) rather than modifying the existing one in place — visible in Terraform's plan as the old revision being destroyed and the new one created.

### Execution role — added KMS decrypt permission

The AWS-managed `AmazonECSTaskExecutionRolePolicy` covers `logs:CreateLogStream`/`PutLogEvents`, but not KMS access — required once the log group is encrypted with a customer-managed key:

```hcl
data "aws_iam_policy_document" "ecs_execution_kms" {
    statement {
        effect  = "Allow"
        actions = ["kms:Decrypt", "kms:GenerateDataKey*"]
        resources = [data.terraform_remote_state.security.outputs.kms_key_arn]
    }
}

resource "aws_iam_policy" "ecs_execution_kms_policy" {
    name   = "atlas-fintech-ecs-execution-kms-policy"
    policy = data.aws_iam_policy_document.ecs_execution_kms.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_kms" {
    role       = aws_iam_role.ecs_execution_role.name
    policy_arn = aws_iam_policy.ecs_execution_kms_policy.arn
}
```

### ECR — immutable tags + customer-managed encryption

```hcl
resource "aws_ecr_repository" "app" {
    name                  = "atlas-fintech-app"
    image_tag_mutability  = "IMMUTABLE"

    image_scanning_configuration {
        scan_on_push = true
    }

    encryption_configuration {
        encryption_type = "KMS"
        kms_key         = data.terraform_remote_state.security.outputs.kms_key_arn
    }
}
```

**Key operational note:** `encryption_configuration` cannot be changed in-place on an existing ECR repository — switching from AES256 to KMS forces a full destroy/recreate (`-/+` in the Terraform plan), confirmed and applied since the repo had no real images pushed yet (still holding the Phase 4 nginx placeholder architecture, not actual pushed images).

### Application Auto Scaling — Target Tracking on CPU

```hcl
resource "aws_appautoscaling_target" "ecs_app" {
    max_capacity       = 4
    min_capacity       = 2
    resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
    scalable_dimension = "ecs:service:DesiredCount"
    service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_app" {
    name               = "atlas-fintech-cpu-target-tracking"
    policy_type        = "TargetTrackingScaling"
    resource_id        = aws_appautoscaling_target.ecs_app.resource_id
    scalable_dimension = aws_appautoscaling_target.ecs_app.scalable_dimension
    service_namespace  = aws_appautoscaling_target.ecs_app.service_namespace

    target_tracking_scaling_policy_configuration {
        predefined_metric_specification {
            predefined_metric_type = "ECSServiceAverageCPUUtilization"
        }
        target_value       = 50.0
        scale_in_cooldown  = 300
        scale_out_cooldown = 60
    }
}
```

**Design decisions:**

- **Target Tracking** chosen over Step Scaling — AWS manages the underlying CloudWatch alarms and scaling math automatically toward a single target value (50% CPU), versus Step Scaling's manually-defined thresholds and step adjustments. Appropriate for a straightforward web workload with no unusual scaling behavior requirements.
- **`min_capacity = 2`** matches the service's original `desired_count` from Phase 4 — this becomes the new floor; `desired_count` on the service resource itself is now just the _initial_ value before Auto Scaling takes over.
- **Asymmetric cooldowns**: 60s scale-out (react fast to load) vs. 300s scale-in (avoid flapping capacity down during a brief dip in load).

## 📸 Evidence

![[1 5.png]] _1 — `terraform state list`, security/._

![[2 5.png]] _2 — `terraform state list`, compute/ (with KMS/Auto Scaling resources added)._

![[3 5.png]] _3 — KMS key overview, rotation enabled._

![[4 5.png]] _4 — CloudWatch log group /ecs/atlas-fintech-app, KMS key ID attached._

![[5 5.png]] _5 — Log stream open, nginx logs visible._

![[6 6.png]] _6 — ECR repository, encryption type KMS._

![[7 5.png]] _7 — ECS Service Auto Scaling tab, Target Tracking policy (min 2, max 4, target 50%)._

![[8 5.png]] _8 — IAM policy atlas-fintech-ecs-execution-kms-policy, attached to execution role._

## 💡 Lessons Learned

1. **Optional-looking config changes (encryption type) can force full resource replacement.** `encryption_configuration` on ECR isn't updatable in-place — Terraform's plan (`-/+`) is the signal to check before applying, especially on any resource holding real data.
    
2. **Customer-managed KMS keys need more than Decrypt/Encrypt for some AWS service integrations.** ECR specifically also needs `kms:CreateGrant` — a permission gap that wouldn't surface as an error until the first real `docker push`, making it easy to miss during initial setup and only catch when it's least convenient.
    
3. **KMS key policies are a different trust model than IAM policies.** The root-account admin statement isn't boilerplate — it's the only thing standing between "normal key management" and "permanently locked out," since KMS doesn't fall back to IAM permissions alone the way most AWS services do.
    
4. **Task Definition immutability means every config change creates a new revision**, not an edit — worth remembering when reading a Terraform plan that shows a task definition being "destroyed" (it's the old revision, not data loss).
    
5. **Target Tracking vs. Step Scaling is a real design decision, not just an API choice** — Target Tracking's simplicity (single target value, AWS-managed alarms) trades off configurability that Step Scaling offers; the right choice depends on whether the workload has non-uniform scaling behavior worth modeling explicitly.
    

## ✅ Completion Status

|Component|Status|
|---|---|
|`infra/security/` folder + remote state pattern|✅ Complete|
|Customer-managed KMS key (logs + ECR scoped policy)|✅ Complete|
|CloudWatch log group, KMS-encrypted, wired to ECS|✅ Complete|
|Execution role KMS decrypt permission|✅ Complete|
|ECR: IMMUTABLE tags + KMS encryption|✅ Complete|
|Application Auto Scaling (Target Tracking, CPU 50%, 2–4 tasks)|✅ Complete|

**Next:** Phase 6 (Observability) — deeper CloudWatch dashboards/alarms, and Phase 7 (DevSecOps) — CI/CD pipeline to actually push real application images to this now-encrypted ECR repo.

## 📚 References

- [AWS KMS Key Policies](https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html)
- [ECS awslogs Log Driver](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/using_awslogs.html)
- [Amazon ECR Encryption at Rest](https://docs.aws.amazon.com/AmazonECR/latest/userguide/encryption-at-rest.html)
- [Service Auto Scaling for Amazon ECS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-auto-scaling.html)
- [Terraform aws_appautoscaling_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy)