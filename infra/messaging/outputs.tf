output "sqs_queue_arn" {
    value = aws_sqs_queue.this.arn
}

output "sqs_queue_url" {
    value = aws_sqs_queue.this.id
}

output "dlq_arn" {
    value = aws_sqs_queue.dlq.arn
}

output "lambda_function_arn" {
    value = aws_lambda_function.security_triage.arn
}