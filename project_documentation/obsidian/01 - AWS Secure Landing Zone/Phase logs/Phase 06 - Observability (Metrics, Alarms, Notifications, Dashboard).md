# Phase 6 — Observability (Metrics, Alarms, Notifications, Dashboard)

## 🎯 Overview

This phase closes the loop on operational visibility: metrics were already being collected passively since Phase 4/5 (ECS, ALB, CloudWatch Logs), but nothing was watching them or alerting on abnormal conditions. Phase 6 adds the missing pieces — alerting and a single-pane-of-glass view — completing the standard observability chain: **Metrics → Alarms → Notifications → Dashboard**.

**What was built:**

- A new `infra/observability/` folder, following the same account/backend pattern as `network/`, `compute/`, and `security/`
- An SNS topic with a confirmed email subscription
- 3 CloudWatch Alarms covering the failure modes that actually matter for this architecture
- A CloudWatch Dashboard consolidating ECS and ALB metrics into one view
- An end-to-end test proving the full chain actually delivers a notification, not just that the resources exist

## 🧠 Concept: the three observability pillars

Before building, the distinction between **metrics**, **logs**, and **traces** was worth clarifying:

- **Metric** — a numerical value tracked over time (e.g. CPU utilization). Answers "how much / how many, right now."
- **Log** — a single, isolated event ("task started," "500 error at 12:04"). Answers "what happened."
- **Trace** — follows _one request_ across multiple services/hops with timing at each step (AWS X-Ray). Answers "where did the time go, for this specific request."

For the current architecture (a single containerized service behind an ALB, no service-to-service calls yet), traces add little value — they matter most once there are multiple services calling each other and pinpointing a slow hop becomes non-trivial. This phase focuses on metrics and logs, which is where the real operational value is today.

## 🏗️ Architecture

```
CloudWatch Metrics (ECS, ALB — collected automatically)
        │
        ▼
CloudWatch Alarms (3: CPU high, unhealthy hosts, 5xx errors)
        │
        ▼
   SNS Topic (atlas-fintech-alerts)
        │
        ▼
  Email Subscription (confirmed)
        │
        ▼
    Inbox notification
```

In parallel, all 4 metric families (ECS CPU/Memory, ALB target health, ALB traffic/errors) are also visualized together on one **CloudWatch Dashboard**.

## 🛠️ Implementation

### New folder: `infra/observability/`

Same pattern as `security/` — `assume_role` into the `network` account, backend key `observability/terraform.tfstate`, consistent tagging (`Component = "observability"`).

### SNS topic + email subscription

```hcl
resource "aws_sns_topic" "alerts" {
    name = "atlas-fintech-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
    topic_arn = aws_sns_topic.alerts.arn
    protocol  = "email"
    endpoint  = "hibachagdaly19@gmail.com"
}
```

**Operational detail:** subscriptions stay in `PendingConfirmation` until the recipient clicks the link in AWS's confirmation email — alarms fire regardless, but notifications silently drop until confirmed. Confirmed before proceeding to alarm testing.

### Remote state — pulling in compute's identifiers

```hcl
data "terraform_remote_state" "compute" {
    backend = "s3"
    config = {
        bucket = "atlas-fintech-tfstate-179236281274"
        key    = "compute/terraform.tfstate"
        region = "eu-west-1"
    }
}
```

This required adding three previously-missing outputs to `compute/outputs.tf`: `ecs_service_name`, `alb_arn_suffix`, `target_group_arn_suffix`. Only `alb_dns_name`, `ecr_repo_url`, and `ecs_cluster_name` existed before — not enough to build ALB/ECS alarms, since CloudWatch dimensions for ELB metrics require the ARN **suffix**, not the full ARN (an AWS-specific quirk worth remembering).

### Three CloudWatch Alarms

```hcl
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
    alarm_name          = "atlas-fintech-ecs-cpu-high"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods  = 2
    metric_name         = "CPUUtilization"
    namespace           = "AWS/ECS"
    period              = 60
    statistic           = "Average"
    threshold           = 80
    alarm_actions       = [aws_sns_topic.alerts.arn]
    ok_actions          = [aws_sns_topic.alerts.arn]

    dimensions = {
        ClusterName = data.terraform_remote_state.compute.outputs.ecs_cluster_name
        ServiceName = data.terraform_remote_state.compute.outputs.ecs_service_name
    }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
    alarm_name          = "atlas-fintech-alb-unhealthy-hosts"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods  = 2
    metric_name         = "UnHealthyHostCount"
    namespace           = "AWS/ApplicationELB"
    period              = 60
    statistic           = "Maximum"
    threshold           = 0
    alarm_actions       = [aws_sns_topic.alerts.arn]
    ok_actions          = [aws_sns_topic.alerts.arn]

    dimensions = {
        LoadBalancer = data.terraform_remote_state.compute.outputs.alb_arn_suffix
        TargetGroup  = data.terraform_remote_state.compute.outputs.target_group_arn_suffix
    }
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
    alarm_name          = "atlas-fintech-alb-5xx-errors"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods  = 1
    metric_name         = "HTTPCode_Target_5XX_Count"
    namespace           = "AWS/ApplicationELB"
    period              = 60
    statistic           = "Sum"
    threshold           = 5
    alarm_actions       = [aws_sns_topic.alerts.arn]
    treat_missing_data  = "notBreaching"

    dimensions = {
        LoadBalancer = data.terraform_remote_state.compute.outputs.alb_arn_suffix
    }
}
```

**Design decisions:**

- **`evaluation_periods = 2` on CPU/unhealthy-hosts, `1` on 5xx errors** — CPU spikes and brief unhealthy checks are common and often self-resolve; requiring 2 consecutive breaches avoids noisy false alarms. 5xx errors mean users are getting broken responses _right now_ — alerting on the first occurrence is deliberate.
- **`ok_actions` on the first two alarms** — notified both when something breaks and when it recovers, useful for confirming an issue actually resolved.
- **`treat_missing_data = "notBreaching"` on the 5xx alarm** — a quiet period with zero traffic shouldn't be treated as an alarm condition; without this, CloudWatch's default missing-data handling could trigger false "insufficient data" states during low-traffic windows.

### CloudWatch Dashboard

```hcl
resource "aws_cloudwatch_dashboard" "main" {
    dashboard_name = "atlas-fintech-observability"

    dashboard_body = jsonencode({
        widgets = [
            { /* ECS CPU Utilization — top-left */ },
            { /* ECS Memory Utilization — top-right */ },
            { /* ALB Target Health (healthy vs unhealthy) — bottom-left */ },
            { /* ALB Request Count & 5xx Errors — bottom-right */ }
        ]
    })
}
```

4 widgets in a 2×2 grid, each pulling the same metrics the alarms watch — so the dashboard and the alarms stay conceptually aligned (nothing on the dashboard that isn't also being actively monitored).

## 🐞 Debugging along the way

Several real issues surfaced while wiring this up — documented because they're the kind of thing that recurs in any multi-account Terraform setup:

1. **Missing compute outputs** — `compute/outputs.tf` didn't expose `ecs_service_name`, `alb_arn_suffix`, or `target_group_arn_suffix`, all required to build alarm dimensions. Had to go back and add them before `observability/` could reference anything meaningful.
    
2. **CLI role assumption gap** — the `terraform-deployer` AWS CLI profile holds direct access keys with no `role_arn` configured, so raw `aws` CLI commands (like manually testing an alarm) authenticate into the _management_ account, not the _network_ account where the alarm actually lives — even though Terraform itself works fine, because its `assume_role` block in `provider.tf` handles that switch automatically. Manual CLI testing required generating temporary credentials via `aws sts assume-role` and exporting them as environment variables for that terminal session.
    
3. **Leftover session-token environment variables broke a later `terraform plan`** — after finishing the manual CLI alarm test, the exported `AWS_ACCESS_KEY_ID`/`SECRET_ACCESS_KEY`/`SESSION_TOKEN` were still set in the same terminal, silently overriding Terraform's intended profile-based authentication on the next command, producing a confusing `DynamoDB ResourceNotFoundException` on the state lock table (Terraform was authenticating as the wrong identity/account). Clearing the env vars resolved it immediately.
    
4. **AWS console UI moved "Set alarm state"** — the expected `Actions → Set alarm state` menu item wasn't where documentation/older screenshots suggest; fell back to `aws cloudwatch set-alarm-state` via CLI instead, once properly authenticated.
    

## ✅ End-to-end verification

Rather than trust that "the resources exist" implies "the pipeline works," the alarm chain was manually forced into `ALARM` state:

```bash
aws cloudwatch set-alarm-state --alarm-name "atlas-fintech-alb-5xx-errors" --state-value ALARM --state-reason "Manual test of SNS chain" --region eu-west-1
```

Result: a real email arrived within seconds, containing the alarm name, threshold, dimensions, timestamp, and account ID — full proof the chain works end-to-end, not just that Terraform applied successfully. The alarm was then reset back to `OK` to avoid leaving a false trigger active.

## 📸 Evidence

![[1 6.png]] _1 — `terraform state list`, observability/._

![[2 6.png]] _2 — SNS topic atlas-fintech-alerts, email subscription confirmed._

![[3 6.png]] _3 — CloudWatch Alarms list, all 3 alarms in OK state._

![[4 6.png]] _4 — Alarm detail page (atlas-fintech-alb-5xx-errors), threshold and dimensions._

![[5 6.png]] _5 — Alarm History tab, OK → ALARM → OK transition from manual test._

![[6 7.png]] _6 — Test notification email received via SNS._

![[7 6.png]] _7 — CloudWatch Dashboard atlas-fintech-observability, all 4 widgets._

## 💡 Lessons Learned

1. **A deployed alarm is not the same as a working alarm.** Terraform reporting `apply complete` only proves the resource exists — it says nothing about whether the notification actually reaches anyone. Manually forcing the alarm state was the only way to get real confidence in the pipeline.
    
2. **CLI authentication and Terraform provider authentication are two separate paths**, even when pointed at the same AWS account. A `provider.tf` with `assume_role` handles cross-account auth transparently for Terraform, but the raw AWS CLI needs its own explicit role assumption — easy to forget when everything "just works" through Terraform.
    
3. **Leftover exported credentials in a terminal session are a silent trap.** Environment variables take priority over profile-based auth without any warning, so a temporary debugging session can quietly break the next unrelated command in the same shell.
    
4. **CloudWatch dimensions for ELB metrics use ARN suffixes, not full ARNs** — a small but easy-to-miss AWS convention that breaks alarm creation silently (wrong dimension = alarm never actually watches the right resource) if not caught in review.
    
5. **Alerting thresholds are a design decision, not a default.** Choosing `evaluation_periods = 1` vs `2`, and whether to attach `ok_actions`, reflects a judgment call about noise tolerance vs. responsiveness for each specific failure mode — not a one-size-fits-all setting.
    

## ✅ Completion Status

|Component|Status|
|---|---|
|`infra/observability/` folder + remote state pattern|✅ Complete|
|SNS topic + confirmed email subscription|✅ Complete|
|3 CloudWatch Alarms (CPU, unhealthy hosts, 5xx errors)|✅ Complete|
|CloudWatch Dashboard (4 widgets: CPU, memory, target health, traffic/errors)|✅ Complete|
|End-to-end notification test (real email confirmed)|✅ Complete|

**Next:** Phase 7 (DevSecOps) — CI/CD pipeline to build and push a real application image to the now-encrypted ECR repo, with automated security scanning before deployment.

## 📚 References

- [Amazon CloudWatch Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
- [Amazon SNS Email Notifications](https://docs.aws.amazon.com/sns/latest/dg/sns-email-notifications.html)
- [CloudWatch Metrics for Application Load Balancers](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-cloudwatch-metrics.html)
- [CloudWatch Dashboards](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Dashboards.html)
- [AWS X-Ray (for future tracing needs)](https://docs.aws.amazon.com/xray/latest/devguide/aws-xray.html)