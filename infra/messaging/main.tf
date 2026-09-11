resource "aws_sqs_queue" "dlq" {
    name = "atlas-fintech-guardduty-findings-dlq"
    message_retention_seconds = 1209600 # 14 days
}

resource "aws_sqs_queue" "this" {
    name = "atlas-fintech-guardduty-findings-queue"
    message_retention_seconds = 345600 # 4 days

    redrive_policy = jsonencode({
        deadLetterTargetArn = aws_sqs_queue.dlq.arn
        maxReceiveCount     = 3
    })
}

data "aws_iam_policy_document" "eventbridge_to_sqs" {
    statement {
        sid    = "AllowEventBridgeToSendMessages"
        effect = "Allow"
        actions = ["sqs:SendMessage" ]

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

resource "aws_cloudwatch_event_rule" "guardduty_findings" {
    name        = "atlas-fintech-guardduty-findings"
    description = "Routes GuardDuty findings to SQS for security triage"
    event_pattern = jsonencode({
        source = ["aws.guardduty"]
        detail-type = ["GuardDuty Finding"]
    })
}

resource "aws_cloudwatch_event_target" "sqs" {
    rule      = aws_cloudwatch_event_rule.guardduty_findings.name
    target_id = "SendToSecurityFindingsQueue"
    arn       = aws_sqs_queue.this.arn
}

data "aws_iam_policy_document" "lambda_assume_role" {
    statement {
        effect  = "Allow"
        actions = ["sts:AssumeRole"]

        principals {
            type        = "Service"
            identifiers = ["lambda.amazonaws.com"]
        }
    }
}

resource "aws_iam_role" "security_triage_lambda" {
    name               = "atlas-fintech-security-triage-role"
    assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_permissions" {
    statement {
        sid    = "SQSConsume"
        effect = "Allow"
        actions = [
            "sqs:ReceiveMessage",
            "sqs:DeleteMessage",
            "sqs:GetQueueAttributes"
        ]
        resources = [aws_sqs_queue.this.arn]
    }

    statement {
        sid    = "Logging"
        effect = "Allow"
        actions = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
        ]
        resources = ["*"]
    }
}

resource "aws_iam_role_policy" "security_triage_lambda" {
    name   = "atlas-fintech-security-triage-policy"
    role   = aws_iam_role.security_triage_lambda.id
    policy = data.aws_iam_policy_document.lambda_permissions.json
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