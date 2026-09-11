resource "aws_kms_key" "security" {
    description             = "Atlas FinTech shared KMS key for logs and ECR encryption"
    deletion_window_in_days = 30
    enable_key_rotation     = true

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Sid       = "EnableRootAccountAdmin"
                Effect    = "Allow"
                Principal = { AWS = "arn:aws:iam::622532143366:root" }
                Action    = "kms:*"
                Resource  = "*"
            },
            {
                Sid    = "AllowCloudWatchLogsUse"
                Effect = "Allow"
                Principal = {
                    Service = "logs.eu-west-1.amazonaws.com"
                }
                Action = [
                    "kms:Encrypt",
                    "kms:Decrypt",
                    "kms:ReEncrypt*",
                    "kms:GenerateDataKey*",
                    "kms:DescribeKey"
                ]
                Resource = "*"
                Condition = {
                    ArnLike = {
                        "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:eu-west-1:622532143366:*"
                    }
                }
            },
            {
                Sid    = "AllowECRUse"
                Effect = "Allow"
                Principal = {
                    Service = "ecr.amazonaws.com"
                }
                Action = [
                    "kms:Decrypt",
                    "kms:GenerateDataKey*",
                    "kms:CreateGrant"
                ]
                Resource = "*"
                Condition = {
                    Bool = {
                      "kms:GrantIsForAWSResource" = "true"
                    }
                }
            },
            {
                Sid    = "AllowS3Use"
                Effect = "Allow"
                Principal = {
                    Service = "s3.amazonaws.com"
                }
                Action =[
                    "kms:Decrypt",
                    "kms:GenerateDataKey*",
                    "kms:DescribeKey"
                ]
                Resource = "*"
                Condition = {
                    StringEquals = {
                        "kms:EncryptionContext:aws:s3:arn" = "arn:aws:s3:::atlas-fintech-assets-622532143366"
                    }
                }
            },
            {
                Sid    = "AllowCloudFrontServicePricnipal"
                Effect = "Allow"
                Principal = {
                    Service = "cloudfront.amazonaws.com"
                }
                Action = [
                    "kms:Decrypt",
                    "kms:GenerateDataKey*",
                    "kms:DescribeKey"
                ]
                Resource = "*"  
                Condition = {
                    StringEquals = {
                        "AWS:SourceArn" = "arn:aws:cloudfront::622532143366:distribution/ECQFVYBEI6XFU"
                    }
                }
            }
        ]
    })
}

resource "aws_kms_alias" "security" {
    name          = "alias/atlas-fintech-security-key"
    target_key_id = aws_kms_key.security.key_id
}

resource "aws_cloudwatch_log_group" "security" {
    name              = "/ecs/atlas-fintech-app"
    retention_in_days = 30
    kms_key_id        = aws_kms_key.security.arn
}