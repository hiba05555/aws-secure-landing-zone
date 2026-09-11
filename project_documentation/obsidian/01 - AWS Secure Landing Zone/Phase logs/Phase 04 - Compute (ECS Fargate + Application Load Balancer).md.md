# Phase 4 — Compute (ECS Fargate + Application Load Balancer)

## 🎯 Overview

This phase deploys the compute layer into the `network` account (622532143366), running on top of the VPC built in Phase 3. The workload runs as **serverless containers on ECS Fargate** — no EC2 instances to patch or scale manually — fronted by an **Application Load Balancer** for public HTTP access.

**What was built:**

- ECS Cluster with Container Insights enabled
- ECR repository (placeholder — not yet consumed by the running task)
- Two separate IAM roles: execution role (ECS infrastructure) and task role (application permissions)
- ECS Task Definition running a public nginx image on Fargate
- ALB → Listener → Target Group → ECS Service chain, fully wired end-to-end
- ECS Service running 2 tasks across private-app subnets, behind the ALB

## 🏗️ Architecture

```
                    Internet
                        │
                        ▼
              ┌───────────────────┐
              │  ALB (public subnets) │   ALB-SG: ingress 80 (+ 443 future)
              └──────────┬────────┘
                         │ Listener :80 → forward
                         ▼
              ┌───────────────────┐
              │   Target Group     │   target_type = ip
              └──────────┬────────┘
                         │
        ┌────────────────┴────────────────┐
        ▼                                  ▼
┌───────────────┐                 ┌───────────────┐
│ Fargate Task 1 │                 │ Fargate Task 2 │   private-app subnets
│  nginx :80     │                 │  nginx :80     │   App-SG
└───────────────┘                 └───────────────┘
        ▲                                  ▲
        └──────────── ECS Service ─────────┘
              (desired_count = 2, cluster: atlas-fintech-cluster)
```

Tasks run in the **private-app** subnets (no public IP), reached only through the ALB — the same trust chain (Internet → ALB → App) enforced by the security groups from Phase 3.

## 🛠️ Implementation

### Remote state — consuming Phase 3's outputs

```hcl
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "atlas-fintech-tfstate-179236281274"
    key    = "network/terraform.tfstate"
    region = "eu-west-1"
  }
}

locals {
  vpc_id                  = data.terraform_remote_state.network.outputs.vpc_id
  private_app_subnet_ids  = data.terraform_remote_state.network.outputs.private_app_subnets_ids
  public_subnet_ids       = data.terraform_remote_state.network.outputs.public_subnet_ids
  security_groups_ids     = data.terraform_remote_state.network.outputs.security_groups_ids
}
```

This is the second phase deployed via `assume_role` into the `network` account — no new credentials, same pattern as Phase 3.

### ECS Cluster

```hcl
resource "aws_ecs_cluster" "main" {
  name = "atlas-fintech-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
```

A cluster is just a logical namespace — it holds no compute itself. With Fargate, AWS provisions capacity per-task on demand; there's no shared pool to size or manage (unlike the EC2 launch type).

### IAM — two roles, two different jobs

```hcl
resource "aws_iam_role" "ecs_execution_role" {
  name = "atlas-fintech-ecs-task-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
```

**Execution role** — used by the ECS agent itself, before the container even starts: pulling the image, writing logs. Attached via `execution_role_arn` in the task definition.

**Task role** — the _running application's_ own permissions (here: read-only S3 access via a customer-managed policy). Attached via `task_role_arn`. Kept deliberately separate from the execution role so the app's runtime permissions never inherit infrastructure-level access it doesn't need — least privilege applied at the task level.

### Task Definition

```hcl
resource "aws_ecs_task_definition" "app" {
  family                   = "my-app"
  requires_compatibilities = ["FARGATE"]
  network_mode              = "awsvpc"
  cpu                       = "256"
  memory                    = "512"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn
  task_role_arn       = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name  = "my-app"
    image = "public.ecr.aws/nginx/nginx:latest"
    essential = true
    portMappings = [{ containerPort = 80, protocol = "tcp" }]
  }])
}
```

`network_mode = "awsvpc"` is mandatory for Fargate — each task gets its own ENI and private IP inside the VPC, which is exactly what lets the target group register tasks by IP address rather than by instance.

The nginx image is a **temporary placeholder** — the ECR repo already exists for when a real application image replaces it.

### Load balancer chain

```hcl
resource "aws_lb" "app" {
  name               = "atlas-fintech-app"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [local.security_groups_ids["alb"]]
  subnets            = local.public_subnet_ids
}

resource "aws_lb_target_group" "app" {
  name        = "atlas-fintech-app"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"
  health_check { path = "/" }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
```

`target_type = "ip"` is required for Fargate — there are no EC2 instance IDs to register, only task ENI IPs. The listener is an independent resource that references both the ALB and target group ARNs; it's the piece that actually turns "an ALB exists" into "traffic gets forwarded somewhere."

### ECS Service — the piece that ties it together

```hcl
resource "aws_ecs_service" "app" {
  name            = "atlas-fintech-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip = false
    subnets           = local.private_app_subnet_ids
    security_groups   = [local.security_groups_ids["app"]]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name     = "my-app"
    container_port     = 80
  }
}
```

The service is the **scheduler** — it keeps `desired_count` tasks running, replaces failed ones, and registers/deregisters each task's IP with the target group automatically as tasks start and stop.

## 🐞 Debugging — two real deployment issues

Both bugs below were hit during actual deployment, not anticipated in advance — worth documenting because they're easy to reproduce and instructive.

### Bug 1 — service silently defaulted to EC2 launch type

**Symptom:** ECS Service showed `0/2 Tasks running` indefinitely. No stopped tasks to inspect — tasks never even attempted to launch. Cluster showed **0 EC2** container instances.

**Root cause:** the original `aws_ecs_service` block declared no `launch_type` and no `capacity_provider_strategy`. Terraform accepted this without error (both are optional arguments), but AWS silently defaulted the service to `EC2` launch type. With zero EC2 instances registered to the cluster, there was no capacity for the scheduler to place tasks on.

**Fix:** add `launch_type = "FARGATE"` explicitly to the service block.

**Why Terraform didn't catch it:** `launch_type` is optional in the resource schema — Terraform validates argument _types_, not cross-service business logic like "you probably want this set for a serverless workload." A missing optional argument is not a plan-time error; it just falls through to the provider's/AWS's own default.

### Bug 2 — ALB reachable from AWS's side, but browser times out

**Symptom:** after fixing Bug 1, tasks reached `Running`, but the ALB's listener showed **"Not reachable"** in the console, and the browser returned `ERR_CONNECTION_TIMED_OUT` on the ALB DNS name.

**Root cause:** `alb_sg` (built in Phase 3) only allowed inbound traffic on **port 443**. The listener is configured for HTTP on **port 80** — so the security group was silently dropping every incoming request before it reached the ALB at all.

**Fix:** add an inbound rule to `alb_sg` allowing port 80 from `0.0.0.0/0`.

**Takeaway:** the listener's port and the security group's allowed ports are two independent configurations that must agree — Terraform/AWS won't cross-validate that a listener you just created is actually reachable through the SG in front of it.

## 📸 Evidence

![[12 1.png]] _1 — `terraform state list`, compute/._

![[1 4.png]] _2 — ECS cluster list, 0 EC2 container instances (Fargate-only)._

![[2 4.png]] _3 — ECS Service, launch type Fargate._

![[3 4.png]] _4 — ECS Tasks tab, both tasks status Running._

![[4 4.png]] _5 — ECR repository atlas-fintech-app (placeholder, unused)._

![[5 4.png]] _6 — IAM execution role, AmazonECSTaskExecutionRolePolicy attached._

![[6 5.png]] _7 — IAM task role, customer-managed S3 permissions policy attached._

![[7 4.png]] _8 — Load balancer atlas-fintech-app, Active, internet-facing._

![[8 4.png]] _9 — Target group atlas-fintech-app, target type IP._

![[9 1.png]] _10 — Target group Targets tab, 2/2 Healthy, distinct AZs._

![[10 1.png]] _11 — Listener HTTP:80, reachable, forwarding to target group._

![[11 1.png]] _12 — nginx welcome page served through the ALB DNS name._

## 💡 Lessons Learned

1. **Optional Terraform arguments can hide critical defaults.** `launch_type` being optional doesn't mean it's safe to omit — AWS's fallback default (EC2) silently broke the whole deployment with zero plan-time warning.
    
2. **A "no stopped tasks" situation can mean the scheduler never got that far**, not that everything is fine. Absence of a stopped-task error was itself the diagnostic signal here — it pointed to a placement failure, not a container-level failure.
    
3. **Security groups and listener ports are two independent layers that must be manually kept in sync.** Nothing in Terraform's plan output flags a listener on a port the SG doesn't allow — this is exactly the kind of routing-vs-permission split drilled during SAA-C03 prep (route table = possible path, SG = permitted path), showing up as a real bug.
    
4. **Execution role vs. task role separation matters in practice, not just in theory** — keeping "can this task pull its image and write logs" separate from "what can this task's application code access" is what makes future least-privilege changes to app permissions safe without touching ECS infrastructure permissions.
    

## ✅ Completion Status

|Component|Status|
|---|---|
|ECS Cluster (Container Insights)|✅ Complete|
|ECR repository|✅ Complete (placeholder image)|
|IAM execution role + task role (separated)|✅ Complete|
|Task Definition (Fargate, awsvpc)|✅ Complete|
|ALB + Listener + Target Group (target_type=ip)|✅ Complete|
|ECS Service (2/2 tasks, Fargate, healthy targets)|✅ Complete|
|End-to-end browser test (nginx via ALB DNS)|✅ Complete|

**Next:** Phase 5 (Security hardening) — upgrading the ECR tag policy to `IMMUTABLE`, adding KMS encryption, and revisiting Auto Scaling policy types (Target Tracking, Step Scaling) on top of this base ECS Service.

## 📚 References

- [Amazon ECS on Fargate](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [ECS Task Execution IAM Role](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-execution-iam-role.html)
- [Application Load Balancer Target Groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html)
- [Terraform aws_ecs_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service)