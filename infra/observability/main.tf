resource "aws_sns_topic" "alerts"{
    name = "atlas-fintech-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
    topic_arn = aws_sns_topic.alerts.arn
    protocol  = "email"
    endpoint  = "hibachagdaly19@gmail.com"
}

data "terraform_remote_state" "compute" {
    backend = "s3"

    config = {
        bucket = "atlas-fintech-tfstate-179236281274"
        key    = "compute/terraform.tfstate"
        region   = "eu-west-1"
    }
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high"{
    alarm_name          = "atlas-fintech-ecs-cpu-high"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods = 2
    metric_name         = "CPUUtilization"
    namespace           = "AWS/ECS"
    period              = 60
    statistic           = "Average"
    threshold           = 80
    alarm_description   = "ECS service average CPU above 80% for 2 consecutive minutes"
    alarm_actions       = [aws_sns_topic.alerts.arn]
    ok_actions         = [aws_sns_topic.alerts.arn]

    dimensions = {
        ClusterName = data.terraform_remote_state.compute.outputs.ecs_cluster_name
        ServiceName = data.terraform_remote_state.compute.outputs.ecs_service_name
    }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts"{
    alarm_name          = "atlas-fintech-alb-unhealthy-hosts"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods = 2
    metric_name         = "UnHealthyHostCount"
    namespace           = "AWS/ApplicationELB"
    period              = 60
    statistic           = "Maximum"
    threshold           = 0
    alarm_description   = "One or more ALB targets are unhealthy"
    alarm_actions       = [aws_sns_topic.alerts.arn]
    ok_actions         = [aws_sns_topic.alerts.arn]

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
    alarm_description   = "More than 5 backend 5xx errors in 1 minute"
    alarm_actions       = [aws_sns_topic.alerts.arn]
    treat_missing_data = "notBreaching"

    dimensions = {
        LoadBalancer = data.terraform_remote_state.compute.outputs.alb_arn_suffix
    }
}

resource "aws_cloudwatch_dashboard" "main" {
    dashboard_name = "atlas-fintech-observability"

    dashboard_body = jsonencode({
        widgets = [
            {
                type = "metric"
                x    = 0
                y    = 0
                width = 12
                height = 6
                properties = {
                    title   = "ECS CPU Utilization"
                    view    = "timeSeries"
                    region  = "eu-west-1"
                    metrics = [
                        [
                            "AWS/ECS",
                            "CPUUtilization",
                            "ClusterName",
                            data.terraform_remote_state.compute.outputs.ecs_cluster_name,
                            "ServiceName",
                            data.terraform_remote_state.compute.outputs.ecs_service_name
                        ]
                    ]
                    period = 60
                    stat = "Average"
                }
            },
            {
                type = "metric"
                x    = 12
                y    = 0
                width = 12
                height = 6
                properties = {
                    title   = "ECS Memory Utilization"
                    view    = "timeSeries"
                    region  = "eu-west-1"
                    metrics = [
                        [
                            "AWS/ECS",
                            "MemoryUtilization",
                            "ClusterName",
                            data.terraform_remote_state.compute.outputs.ecs_cluster_name,
                            "ServiceName",
                            data.terraform_remote_state.compute.outputs.ecs_service_name
                        ]
                    ]
                    period = 60
                    stat = "Average"
                }
            },
            {
                type = "metric"
                x    = 0
                y    = 6
                width = 12
                height = 6
                properties = {
                    title   = "ALB Target Health"
                    view    = "timeSeries"
                    region  = "eu-west-1"
                    metrics = [
                        [
                            "AWS/ApplicationELB",
                            "HealthyHostCount",
                            "LoadBalancer",
                            data.terraform_remote_state.compute.outputs.alb_arn_suffix,
                            "TargetGroup",
                            data.terraform_remote_state.compute.outputs.target_group_arn_suffix
                        ],
                        [
                            "AWS/ApplicationELB",
                            "UnHealthyHostCount",
                            "LoadBalancer",
                            data.terraform_remote_state.compute.outputs.alb_arn_suffix,
                            "TargetGroup",
                            data.terraform_remote_state.compute.outputs.target_group_arn_suffix
                        ]
                    ]
                    period  =60
                    stat    = "Average"
                }
            },
            {
                type = "metric"
                x    = 12
                y    = 6
                width = 12
                height = 6
                properties = {
                    title   = "ALB Request Count & 5xx Errors"
                    view    = "timeSeries"
                    region  = "eu-west-1"
                    metrics = [
                        [
                            "AWS/ApplicationELB",
                            "RequestCount",
                            "LoadBalancer",
                            data.terraform_remote_state.compute.outputs.alb_arn_suffix
                        ],
                        [
                            "AWS/ApplicationELB",
                            "HTTPCode_Target_5XX_Count",
                            "LoadBalancer",
                            data.terraform_remote_state.compute.outputs.alb_arn_suffix
                        ]
                    ]
                    period = 60
                    stat = "Sum"
                }
            }
        ]
    })
    
}