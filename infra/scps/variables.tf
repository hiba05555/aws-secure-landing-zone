variable "aws_region" {
  type        = string
  description = "The AWS region to deploy resources in."
  default     = "eu-west-1"
}

variable "aws_profile" {
  type        = string
  description = "The AWS CLI profile to use for authentication."
  default     = "terraform-deployer"
}