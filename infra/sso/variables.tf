variable "aws_region" {
        description = "AWS region to deploy resources"
        type        = string    
        default     = "eu-west-1"
}

variable "aws_profile" {
        description = "AWS profile to use for authentication"
        type        = string
        default     = "terraform-deployer"
}