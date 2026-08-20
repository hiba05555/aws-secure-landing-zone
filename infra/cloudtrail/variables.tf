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

variable "management_account_id" {
        description = "AWS Management Account ID"
        type        = string
        default     = "179236281274"
}  

variable "log_retention_days" {
        description = "Number of days to retain CloudTrail logs"
        type        = number
        default     = 90
}   