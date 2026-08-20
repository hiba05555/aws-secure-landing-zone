terraform {
    required_version = ">= 1.5.0"

    required_providers {
        aws = {
            source  ="hashicorp/aws"
            version = "~> 5.0"
        }
    }

    backend "s3" {
        bucket = "atlas-fintech-tfstate-179236281274"
        key = "organization/terraform.tfstate"
        region = "eu-west-1"
        dynamodb_table = "atlas-fintech-tfstate-lock"
        encrypt = true
    }
}

provider "aws" {
    region = var.aws_region
    profile = var.aws_profile

    default_tags{
        tags = {
            Project = "atlas-fintech"
            Environment = "organization"
            ManagedBy = "terraform"
            Owner = "hiba"

        }
    }
}