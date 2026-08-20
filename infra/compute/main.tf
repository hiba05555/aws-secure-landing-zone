data "terraform_remote_state" "network" {
    backend = "s3"

    config = {
        bucket = "atlas-fintech-tfstate-179236281274" 
        key = "network/terraform.tfstate"
        region = "eu-west-1"
    }
}

data "terraform_remote_state" "security" {
    backend = "s3"

    config = {
        bucket = "atlas-fintech-tfstate-179236281274" 
        key = "security/terraform.tfstate"
        region = "eu-west-1"
    }
}

locals {
    vpc_id = data.terraform_remote_state.network.outputs.vpc_id
    private_app_subnet_ids = data.terraform_remote_state.network.outputs.private_app_subnets_ids
    private_data_subnet_ids = data.terraform_remote_state.network.outputs.private_data_subnets_ids
    public_subnet_ids = data.terraform_remote_state.network.outputs.public_subnet_ids
    security_groups_ids = data.terraform_remote_state.network.outputs.security_groups_ids
}

resource "aws_ecs_cluster" "main" {
    name = "atlas-fintech-cluster"

    setting {
        name  = "containerInsights"
        value = "enabled"
    }
}

resource "aws_ecr_repository" "app" {
    name = "atlas-fintech-app"
    image_tag_mutability = "IMMUTABLE"

    image_scanning_configuration {
        scan_on_push = true
    }

    encryption_configuration {
        encryption_type = "KMS"
        kms_key = data.terraform_remote_state.security.outputs.kms_key_arn
    }
}

resource "aws_iam_role" "ecs_execution_role" {
    name = "atlas-fintech-ecs-task-execution-role"
    assume_role_policy = jsonencode({
        Version = "2012-10-17",
        
        Statement = [
            {
                Effect = "Allow"
                Principal = {
                    Service = "ecs-tasks.amazonaws.com"
                }
                Action = "sts:AssumeRole"
            }
        ]
    })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
    role = aws_iam_role.ecs_execution_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_execution_kms" {
    statement {
        effect = "Allow"
        actions = [
            "kms:Decrypt",
            "kms:GenerateDataKey*"
        ]
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

resource "aws_ecs_task_definition" "app" {
    family = "my-app"
    requires_compatibilities = ["FARGATE"]
    network_mode = "awsvpc"

    cpu = "256"
    memory = "512"

    execution_role_arn = aws_iam_role.ecs_execution_role.arn
    task_role_arn = aws_iam_role.ecs_task_role.arn

    container_definitions = jsonencode([
        {
            name = "my-app"
            image = "public.ecr.aws/nginx/nginx:latest"
            essential = true
            portMappings = [
                {
                    containerPort = 80
                    protocol = "tcp"
                }
            ]
            logConfiguration = {
               logDriver = "awslogs"
               options = {
                   "awslogs-group"         = data.terraform_remote_state.security.outputs.ecs_log_group_name
                   "awslogs-region"        = "eu-west-1"
                   "awslogs-stream-prefix" = "ecs"
               }
            }
        }
    ])
}

resource "aws_ecs_service" "app" {
    name = "atlas-fintech-app"
    cluster = aws_ecs_cluster.main.id
    task_definition = aws_ecs_task_definition.app.arn
    desired_count = 2
    launch_type     = "FARGATE"

    network_configuration {
        assign_public_ip = false
        subnets = local.private_app_subnet_ids
        security_groups = [local.security_groups_ids["app"]]
    }

    load_balancer {
        target_group_arn = aws_lb_target_group.app.arn
        container_name = "my-app"
        container_port = 80
    }
}

data "aws_iam_policy_document" "ecs_task_trust" {
    statement {
        effect = "Allow"

        actions = ["sts:AssumeRole"]

        principals {
            type        = "Service"
            identifiers = ["ecs-tasks.amazonaws.com"]
        }
    }
}

resource "aws_iam_role" "ecs_task_role" {
    name = "atlas-fintech-ecs-task-role"
    assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json
}

data "aws_iam_policy_document" "ecs_task_permissions"{
    statement {
        effect = "Allow"

        actions = [
          "s3:GetObject",
          "s3:ListBucket"
        ]

        resources = [
          "arn:aws:s3:::my-application-bucket",
          "arn:aws:s3:::my-application-bucket/*"
        ]
    }
}

resource "aws_iam_policy" "ecs_task_role_permissions_policy" {
    name = "atlas-fintech-ecs-task-role-permissions-policy"
    policy = data.aws_iam_policy_document.ecs_task_permissions.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_policy" {
    role = aws_iam_role.ecs_task_role.name
    policy_arn = aws_iam_policy.ecs_task_role_permissions_policy.arn
}

resource "aws_lb" "app"{
    name = "atlas-fintech-app"
    internal = false
    load_balancer_type = "application"
    security_groups = [local.security_groups_ids["alb"]]
    subnets = local.public_subnet_ids

    idle_timeout = 60
}

resource "aws_lb_target_group" "app" {
    name = "atlas-fintech-app"
    port = 80
    protocol = "HTTP"
    vpc_id = local.vpc_id
    target_type  = "ip"
    health_check {
        path = "/"
    }
}

resource "aws_lb_listener" "app" {
    load_balancer_arn = aws_lb.app.arn
    port = "80"
    protocol = "HTTP"

    default_action {
        type = "forward"
        target_group_arn = aws_lb_target_group.app.arn
    }
}

resource "aws_appautoscaling_target" "ecs_app"{
    max_capacity = 4
    min_capacity = 2
    resource_id = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
    scalable_dimension = "ecs:service:DesiredCount"
    service_namespace = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_app" {
    name = "atlas-fintech-cpu-target-tracking"
    policy_type = "TargetTrackingScaling"
    resource_id = aws_appautoscaling_target.ecs_app.resource_id
    scalable_dimension = aws_appautoscaling_target.ecs_app.scalable_dimension
    service_namespace = aws_appautoscaling_target.ecs_app.service_namespace

    target_tracking_scaling_policy_configuration {
        predefined_metric_specification {
            predefined_metric_type = "ECSServiceAverageCPUUtilization"
        }
        target_value = 50.0
        scale_in_cooldown = 300
        scale_out_cooldown = 60
    }
} 