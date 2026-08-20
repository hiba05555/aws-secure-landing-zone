data "terraform_remote_state" "compute" {
    backend = "s3"
    config = {
        bucket = "atlas-fintech-tfstate-179236281274"
        key    = "compute/terraform.tfstate"
        region = "eu-west-1"
    }
}

data "tls_certificate" "github" {
    url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
    url             = "https://token.actions.githubusercontent.com"
    client_id_list  = ["sts.amazonaws.com"]
    thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "github_actions_trust" {
    statement {
        effect  = "Allow"
        actions = ["sts:AssumeRoleWithWebIdentity"]

        principals {
            type        = "Federated"
            identifiers = [aws_iam_openid_connect_provider.github.arn]
        }

        condition {
            test     = "StringEquals"
            variable = "token.actions.githubusercontent.com:aud"
            values   = ["sts.amazonaws.com"]
        }

        condition {
            test     = "StringLike"
            variable = "token.actions.githubusercontent.com:sub"
            values   = ["repo:hiba05555/aws-secure-landing-zone:*"]
        }
    }
}

resource "aws_iam_role" "github_actions" {
    name               = "atlas-fintech-github-actions-role"
    assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
}

data "aws_iam_policy_document" "github_actions_permissions" {
    statement {
        sid    = "ECRAuth"
        effect = "Allow"
        actions = [
            "ecr:GetAuthorizationToken"
        ]
        resources = ["*"]
    }

    statement {
        sid    = "ECRPush"
        effect = "Allow"
        actions = [
            "ecr:BatchCheckLayerAvailability",
            "ecr:PutImage",
            "ecr:InitiateLayerUpload",
            "ecr:UploadLayerPart",
            "ecr:CompleteLayerUpload"
        ]
        resources = [data.terraform_remote_state.compute.outputs.ecr_repo_arn]
    }

    statement {
        sid    = "ECSDeploy"
        effect = "Allow"
        actions = [
            "ecs:UpdateService",
            "ecs:DescribeServices",
            "ecs:DescribeTaskDefinition",
            "ecs:RegisterTaskDefinition"
        ]
        resources = ["*"]
    }

    statement {
        sid     = "PassExecutionRoles"
        effect  = "Allow"
        actions = ["iam:PassRole"]
        resources = [
            data.terraform_remote_state.compute.outputs.ecs_execution_role_arn,
            data.terraform_remote_state.compute.outputs.ecs_task_role_arn
        ]
    }
}

resource "aws_iam_policy" "github_actions_permissions" {
    name   = "atlas-fintech-github-actions-permissions"
    policy = data.aws_iam_policy_document.github_actions_permissions.json
}

resource "aws_iam_role_policy_attachment" "github_actions" {
    role       = aws_iam_role.github_actions.name
    policy_arn = aws_iam_policy.github_actions_permissions.arn
}