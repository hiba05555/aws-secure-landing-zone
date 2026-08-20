output "cloudtrail_bucket_name" {
    description = "S3 bucker storing Cloudtrail logs"
    value       = aws_s3_bucket.cloudtrail.id
}

output "cloudtrail_bucket_arn" {
    description = "S3 bucket ARN storing Cloudtrail logs"
    value       = aws_s3_bucket.cloudtrail.arn
}

output "cloudtrail_trail_name" {
    description = "Name of the Organization Cloudtrail"
    value       = aws_cloudtrail.org_trail.name
}

output "cloudtrail_trail_arn" {
    description = "ARN of the Organization Cloudtrail"
    value       = aws_cloudtrail.org_trail.arn
}

output "cloudtrail_home_region" {
    description = "Home region of the Organization Cloudtrail"
    value       = aws_cloudtrail.org_trail.home_region
}