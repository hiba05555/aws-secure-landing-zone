terraform {
    required_version = ">= 1.5"

    required_providers {
        aws = {
            source ="hashicorp/aws"
            version = "~> 5.0"
        }
    }

    backend "s3" {
        bucket = "atlas-fintech-tfstate-179236281274"
        key    = "observability/terraform.tfstate"
        region = "eu-west-1"
        dynamodb_table = "atlas-fintech-tfstate-lock"
        encrypt = true
    }
}

provider "aws" {
    region = var.aws_region
    profile = var.aws_profile

    assume_role {
        role_arn = "arn:aws:iam::622532143366:role/OrganizationAccountAccessRole"
    }

    default_tags {
        tags = {
            Project     = "atlas-fintech-landing-zone"
            ManagedBy   = "terraform"
            Environment = "shared"
            Component = "observability"
        }
    }
}