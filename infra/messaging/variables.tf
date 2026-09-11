variable "aws_region" {
    default     = "eu-west-1"
    description = "AWS region for the storage bucket"
}

variable "aws_profile" {
    default     = "terraform-deployer"
    description = "AWS CLI profile for authentication"
}