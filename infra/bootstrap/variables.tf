variable "aws_region" {
  type        = string
  default     = "eu-west-1"
  description = "deployment region for the AWS resources"
}

variable "aws_profile" {
  type        = string
  default     = "terraform-deployer"
  description = "profile name for the AWS CLI to use when deploying resources"
}

variable "state_bucket_name" {
  type        = string
  description = "bucket name for the Terraform state file"
}

variable "state_lock_table_name" {
  type        = string
  default     = "atlas-fintech-tfstate-lock"
  description = "DynamoDB table name for the Terraform state lock"
} 