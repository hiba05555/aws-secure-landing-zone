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