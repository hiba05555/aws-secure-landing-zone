variable "aws_region" {
    description = "AWS region for the CDN"
    type        = string
    default     = "eu-west-1"
}

variable "aws_profile" {
    description = "AWS CLI profile for authentication"
    type        = string
    default     = "terraform-deployer"
}

variable "s3_bucket_domain_name" {
    description = "Regional domain name of the S3 origin bucket"
    type        = string
    default     = "atlas-fintech-assets-622532143366.s3.eu-west-1.amazonaws.com"
}

variable "s3_bucket_arn" {
    description = "ARN of the S3 origin bucket (needed for OAC bucket policy reference)"
    type        = string
    default     = "arn:aws:s3:::atlas-fintech-assets-622532143366"
}

variable "alb_dns_name" {
    description = "DNS name of the ALB from Phase 4 (dynamic content origin)"
    type        = string
    default     = "atlas-fintech-app-1754103518.eu-west-1.elb.amazonaws.com"
}