resource "aws_sns_topic" "budget_alerts"{
    name = "atlas-fintech-budget-alerts"
}

resource "aws_sns_topic_subscription" "budget_alerts_email" {
    topic_arn = aws_sns_topic.budget_alerts.arn
    protocol  = "email"
    endpoint  = "hibachagdaly19@gmail.com"
}

resource "aws_budgets_budget" "monthly_org_budget" {
    name              = "atlas-fintech-monthly-budget"
    budget_type       = "COST"
    limit_amount      = "20"
    limit_unit        = "USD"
    time_unit         = "MONTHLY"
     
    notification {
        comparison_operator = "GREATER_THAN"
        threshold           = "80"
        threshold_type      = "PERCENTAGE"
        notification_type   = "ACTUAL"
        subscriber_sns_topic_arns    = [aws_sns_topic.budget_alerts.arn]
    }

    notification {
        comparison_operator = "GREATER_THAN"
        threshold           = "100"
        threshold_type      = "PERCENTAGE"
        notification_type   = "FORECASTED"
        subscriber_sns_topic_arns    = [aws_sns_topic.budget_alerts.arn]
    }
}