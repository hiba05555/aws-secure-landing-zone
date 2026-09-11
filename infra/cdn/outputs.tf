output "cloudfront_distribution_arn" {
    description = "ARN of the CloudFront distribution (used by S3 bucket policy)"
    value       = aws_cloudfront_distribution.atlas_fintech_cdn.arn
}

output "cloudfront_distribution_domain_name" {
    description = "Auto-generated CloudFront domain (e.g., d1a2b3c4.cloudfront.net)"
    value       = aws_cloudfront_distribution.atlas_fintech_cdn.domain_name
}