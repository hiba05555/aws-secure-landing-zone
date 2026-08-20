output "alb_dns_name" {
    description = "DNS name of the load balancer"
    value = aws_lb.app.dns_name
}

output "ecs_cluster_name" {
    description = "Name of the ECS cluster"
    value = aws_ecs_cluster.main.name
}

output "ecr_repo_url" {
    description = "URL of the ECR repository"
    value = aws_ecr_repository.app.repository_url
}

output "ecs_service_name" {
    value = aws_ecs_service.app.name
}

output "alb_arn_suffix" {
    value = aws_lb.app.arn_suffix
}

output "target_group_arn_suffix" {
    value = aws_lb_target_group.app.arn_suffix
}

output "ecr_repo_arn" {
    value = aws_ecr_repository.app.arn
}

output "ecs_execution_role_arn" {
    value = aws_iam_role.ecs_execution_role.arn
}

output "ecs_task_role_arn" {
    value = aws_iam_role.ecs_task_role.arn
}