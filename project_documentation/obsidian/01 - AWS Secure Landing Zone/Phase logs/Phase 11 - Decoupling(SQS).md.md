# Phase 11 — Security Findings Decoupling (SQS + DLQ)

## 🎯 Overview

This phase introduces asynchronous decoupling into the platform via a cybersecurity-flavored producer/consumer pipeline: GuardDuty security findings are routed through EventBridge into an SQS queue, picked up by a Lambda consumer for triage, with a dead-letter queue (DLQ) catching anything that repeatedly fails processing. The goal was proving the full decoupling mechanism end-to-end — including the failure path — rather than just a happy-path message flow.

**What was built:**

- A new `infra/messaging/` folder holding the SQS queues, EventBridge rule, and Lambda consumer
- Two SQS queues: a main queue (`atlas-fintech-guardduty-findings-queue`) and a DLQ (`atlas-fintech-guardduty-findings-dlq`)
- A redrive policy linking them, with `maxReceiveCount = 3`
- An EventBridge rule matching GuardDuty finding events, targeting the SQS queue, secured with a scoped queue access policy
- A Lambda function (`atlas-fintech-security-triage`) that logs each finding's details, wired to the queue via an event source mapping
- A deliberate poison-message test proving the DLQ redrive actually works, not just that it's configured

## 🏗️ Why this scenario — GuardDuty findings, not a generic demo queue

Rather than build an arbitrary producer/consumer pair, this phase reuses the GuardDuty/Security Hub delegation already in place from earlier work, giving the decoupling exercise a real purpose: buffering and triaging security findings instead of letting a burst of alerts hit a consumer directly.

- **Producer**: EventBridge, matching on `source: aws.guardduty` — this is how GuardDuty findings are natively surfaced in AWS, not a custom trigger.
- **Queue**: absorbs bursts of findings and decouples ingestion from processing, so a spike in alerts doesn't overwhelm — or get dropped by — the consumer.
- **Consumer**: a Lambda that logs each finding's id, type, and severity — standing in for a real triage/notification integration, which is out of scope for this phase.
- **DLQ**: represents findings that failed automated triage and need manual security-analyst review — a realistic outcome, not just a generic error queue.

**Standard vs FIFO**: Standard was chosen deliberately. Security findings don't require strict ordering or exactly-once delivery, and duplicate processing of a finding is harmless (the Lambda's logging is idempotent). FIFO would only be justified if processing order or exactly-once semantics mattered here.

## 🛠️ Implementation

### New folder: `infra/messaging/`

Same pattern as `cicd/`, `storage/`, `security/` — own state file, `assume_role` into account `622532143366`, consistent tagging.

### SQS queues with redrive policy

```hcl
resource "aws_sqs_queue" "dlq" {
    name                       = "atlas-fintech-guardduty-findings-dlq"
    message_retention_seconds = 1209600 # 14 days
}

resource "aws_sqs_queue" "this" {
    name                       = "atlas-fintech-guardduty-findings-queue"
    message_retention_seconds = 345600 # 4 days

    redrive_policy = jsonencode({
        deadLetterTargetArn = aws_sqs_queue.dlq.arn
        maxReceiveCount     = 3
    })
}
```

The DLQ retains messages for 14 days (the max) to give time for manual review; the main queue retains for 4 days since messages are expected to be processed quickly. `maxReceiveCount = 3` means a message is redriven to the DLQ after its 3rd failed processing attempt.

### EventBridge rule + scoped SQS access policy

```hcl
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
    name        = "atlas-fintech-guardduty-findings"
    description = "Routes GuardDuty findings to SQS for security triage"

    event_pattern = jsonencode({
        source      = ["aws.guardduty"]
        detail-type = ["GuardDuty Finding"]
    })
}

resource "aws_cloudwatch_event_target" "sqs" {
    rule      = aws_cloudwatch_event_rule.guardduty_findings.name
    target_id = "SendToSecurityFindingsQueue"
    arn       = aws_sqs_queue.this.arn
}

data "aws_iam_policy_document" "eventbridge_to_sqs" {
    statement {
        sid     = "AllowEventBridgeToSendMessages"
        effect  = "Allow"
        actions = ["sqs:SendMessage"]

        principals {
            type        = "Service"
            identifiers = ["events.amazonaws.com"]
        }

        resources = [aws_sqs_queue.this.arn]

        condition {
            test     = "ArnEquals"
            variable = "aws:SourceArn"
            values   = [aws_cloudwatch_event_rule.guardduty_findings.arn]
        }
    }
}

resource "aws_sqs_queue_policy" "this" {
    queue_url = aws_sqs_queue.this.id
    policy    = data.aws_iam_policy_document.eventbridge_to_sqs.json
}
```

The `aws:SourceArn` condition is the security boundary — same philosophy as the OIDC `sub` condition in Phase 7. Without it, any EventBridge rule with knowledge of the queue could target it; this restricts message delivery to exactly this one rule.

### Lambda consumer + execution role

```hcl
resource "aws_iam_role" "security_triage_lambda" {
    name               = "atlas-fintech-security-triage-role"
    assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_lambda_function" "security_triage" {
    function_name = "atlas-fintech-security-triage"
    role          = aws_iam_role.security_triage_lambda.arn
    handler       = "index.handler"
    runtime       = "python3.12"
    filename      = "lambda.zip"
}

resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
    event_source_arn = aws_sqs_queue.this.arn
    function_name    = aws_lambda_function.security_triage.arn
    batch_size       = 1
}
```

The execution role is scoped to exactly what's needed: `sqs:ReceiveMessage` / `DeleteMessage` / `GetQueueAttributes` on this queue only, plus basic CloudWatch Logs write permissions — no broader access.

```python
import json

POISON_FINDING_ID = "TEST-POISON-MESSAGE"

def handler(event, context):
    for record in event["Records"]:
        body = json.loads(record["body"])
        detail = body.get("detail", {})
        finding_id = detail.get("id", "unknown")
        severity = detail.get("severity", "unknown")
        finding_type = detail.get("type", "unknown")

        if finding_id == POISON_FINDING_ID:
            raise Exception(f"Simulated failure processing finding {finding_id}")

        print(f"Security finding triaged: id={finding_id} type={finding_type} severity={severity}")

    return {"statusCode": 200}
```

The `POISON_FINDING_ID` check is a deliberate failure trigger, used to prove the DLQ redrive mechanism actually works rather than just exists in configuration.

## ✅ Verifying the pipeline end-to-end

Both the normal and failure paths were tested directly via CLI, using temporary credentials from `sts assume-role` into account `622532143366` (the CLI's default identity was the management-account `terraform-deployer` user, which doesn't have direct access to this account's resources).

**Normal message:**

```powershell
aws sqs send-message --queue-url "<queue-url>" --message-body '{\"detail\":{\"id\":\"test-finding-001\",\"type\":\"UnauthorizedAccess:EC2/SSHBruteForce\",\"severity\":5.5}}'
```

Returned a `MessageId` immediately, and CloudWatch Logs confirmed the Lambda processed it: `Security finding triaged: id=test-finding-001 type=UnauthorizedAccess:EC2/SSHBruteForce severity=5.5`.

**Poison message (DLQ redrive test):**

```powershell
aws sqs send-message --queue-url "<queue-url>" --message-body '{\"detail\":{\"id\":\"TEST-POISON-MESSAGE\",\"type\":\"Test\",\"severity\":1}}'
```

CloudWatch Logs showed the Lambda raising the simulated exception on each delivery attempt. After the 3rd failed attempt (per `maxReceiveCount = 3`), the message was redriven to the DLQ — confirmed via `get-queue-attributes`, which returned `ApproximateNumberOfMessages: 1` on the DLQ.

## 🐞 Debugging — CLI signature errors from stale credentials

Running `aws sqs get-queue-url` initially failed with `IncompleteSignature: Invalid key=value pair (missing equal-sign) in Authorization header`. This looked like a malformed request, but the actual cause was leftover/corrupted AWS credential environment variables from a previous `assume-role` attempt still being picked up by the CLI, conflicting with valid credentials.

**Fix:** clear the stale environment variables, confirm the base identity resolves cleanly with `aws sts get-caller-identity`, then re-run `assume-role` — piping the JSON output directly into PowerShell variables via `ConvertFrom-Json` instead of manual copy-paste, which also removes the risk of a truncated or malformed session token from copy/paste errors.

## 📸 Evidence
![[1_terraform_state_list 1.png]] _1 — `terraform state list` for `infra/messaging/`, showing all 11 resources created._

![[2_sqs_main_queue.png]] _2 — Main queue detail page: type Standard, SSE-SQS encryption, dead-letter queue enabled._

![[3_sqs_dlq.png]] _3 — DLQ detail page: URL, ARN, no dead-letter queue of its own (terminal queue)._

![[4_sqs_redrive_config.png]] _4 — Main queue's Dead-letter queue tab, showing the DLQ target and Maximum receives = 3._

![[5_message_sent.png]] _5 — CLI `send-message` for the normal test finding, returning a MessageId._

![[5b_poison_message_sent.png]] _5b — CLI `send-message` for the poison test finding (`TEST-POISON-MESSAGE`)._

![[6_message_received.png]] _6 — Lambda CloudWatch logs: successful triage of the normal finding, followed by 2 of the 3 simulated failures on the poison finding._

![[7_dlq_poisoned_message.png]] _7 — `get-queue-attributes` on the DLQ showing `ApproximateNumberOfMessages: 1` — confirms the poison message was successfully redriven after its 3rd failed attempt._

## 💡 Lessons Learned

1. **Reusing an existing AWS-native event source (GuardDuty → EventBridge) makes a decoupling exercise more meaningful than an arbitrary demo queue** — the scenario ties directly into security operations already established in earlier phases, rather than existing in isolation.
2. **A redrive policy is only proven by an actual redrive, not by its presence in Terraform** — the poison-message test showing 3 real failed attempts followed by the message landing in the DLQ is materially stronger evidence than a queue configuration screenshot alone.
3. **CLI signature errors aren't always what they look like.** `IncompleteSignature` suggested a malformed request, but the real cause was stale environment variables from an earlier `assume-role` session — worth checking `get-caller-identity` first whenever cross-account CLI calls fail unexpectedly.
4. **Piping credential JSON directly into variables (`ConvertFrom-Json`) avoids an entire class of copy-paste errors** — long session tokens are easy to truncate or corrupt when copied manually from wrapped terminal output.
5. **Scoping the EventBridge → SQS access policy to one specific rule ARN (`aws:SourceArn`)** closes the same category of over-broad trust that the OIDC `sub` condition addressed in Phase 7 — a recurring theme across phases: service-to-service permissions should be pinned to the exact resource that needs them, never left open to "anything using this AWS service."

## ✅ Completion Status

|Component|Status|
|---|---|
|`infra/messaging/` folder + remote state pattern|✅ Complete|
|SQS main queue + DLQ with redrive policy|✅ Complete|
|EventBridge rule + scoped SQS access policy|✅ Complete|
|Lambda consumer + scoped execution role|✅ Complete|
|Event source mapping (SQS → Lambda)|✅ Complete|
|Normal message flow tested end-to-end|✅ Complete|
|Poison message → DLQ redrive tested and verified|✅ Complete|

**Next:** Bloc 6 — Finalization (README update, draw.io diagrams, final report). Bloc 5 (DR/Pilot Light, Phase 12) deferred for now to focus on SAA-C03 exam preparation.

## 📚 References

- [Amazon SQS Dead-Letter Queues](https://docs.aws.amazon.com/AmazonSQS/latest/dg/sqs-dead-letter-queues.html)
- [Amazon EventBridge and GuardDuty](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_findings_cloudwatch.html)
- [AWS Lambda Event Source Mapping for SQS](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)
- [Terraform aws_sqs_queue](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue)