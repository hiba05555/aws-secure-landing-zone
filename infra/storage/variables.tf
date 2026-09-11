variable "aws_region" {
    description = "AWS region for the storage bucket"
    type        = string
    default     = "eu-west-1"
}

variable "aws_profile" {
    description = "AWS CLI profile for authentication"
    type        = string
    default     = "terraform-deployer"
}

variable "bucket_name" {
    description = "Name of the S3 bucket for static assets"
    type        = string
    default     = "atlas-fintech-assets-622532143366"
}

variable "kms_key_arn" {
    description = "ARN of the Phase 5 KMS key used for bucket encryption"
    type        = string
    default     = "arn:aws:kms:eu-west-1:622532143366:key/a80f37d4-4955-4616-b6bf-48d508ff294c"
}

variable "cloudfront_distribution_arn" {
  type        = string
  default     = "arn:aws:cloudfront::622532143366:distribution/ECQFVYBEI6XFU"
  description = "ARN of the CloudFront distribution allowed to read from this bucket"
}
