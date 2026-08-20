variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "AWS CLI profile"
  type        = string
  default     = "terraform-deployer"
}

variable "management_account_id" {
  description = "AWS management account ID"
  type        = string
  default     = "179236281274"
}