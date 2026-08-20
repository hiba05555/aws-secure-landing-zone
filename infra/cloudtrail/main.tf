# ─────────────────────────────────────────────────────────
# PART 1 — S3 Bucket for CloudTrail Logs
# ─────────────────────────────────────────────────────────


resource "aws_s3_bucket" "cloudtrail" {
    bucket = "atlas-fintech-cloudtrail-${var.management_account_id}"
    force_destroy = false

    tags = {
        Name ="atlas-fintech-cloudtrail"
        Purpose = "Cloudtrail organization logs"
    }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
    bucket = aws_s3_bucket.cloudtrail.id
    versioning_configuration {
        status = "Enabled"
    }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
    bucket = aws_s3_bucket.cloudtrail.id

    rule {
        apply_server_side_encryption_by_default {
            sse_algorithm = "AES256"
        }
    }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
    bucket = aws_s3_bucket.cloudtrail.id

    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
    bucket = aws_s3_bucket.cloudtrail.id

    rule {
        id     = "log"
        status = "Enabled"
        
        filter {}

        transition {
            days          = var.log_retention_days
            storage_class = "GLACIER"
        }

        expiration {
            days = 2555
        }

        noncurrent_version_expiration {
            noncurrent_days = 90
        }
    }
}

# ─────────────────────────────────────────────────────────
# PART 2 — Bucket Policy (allow CloudTrail service to write)
# ─────────────────────────────────────────────────────────

data "aws_organizations_organization" "current" {}

data "aws_iam_policy_document" "cloudtrail_bucket" {
    statement {
        sid = "AWSCloudTrailAclCheck"
        effect = "Allow"

        principals {
            type = "Service"
            identifiers = ["cloudtrail.amazonaws.com"]  
        }

        actions = ["s3:GetBucketAcl"]
        resources = [aws_s3_bucket.cloudtrail.arn]

        condition {
            test     = "StringEquals"
            variable = "aws:SourceArn"  
            values   = ["arn:aws:cloudtrail:${var.aws_region}:${var.management_account_id}:trail/atlas-fintech-org-trail"]
        }

    }

    statement {
        sid = "AWSCloudTrailWrite"
        effect = "Allow"

        principals {
            type = "Service"
            identifiers = ["cloudtrail.amazonaws.com"]  
        }

        actions = ["s3:PutObject"]
        resources = [
            "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_organizations_organization.current.id}/*",
            "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${var.management_account_id}/*"
        ]        
        
        condition {
            test     = "StringEquals"
            variable = "s3:x-amz-acl"  
            values   = ["bucket-owner-full-control"]
        }

        condition {
            test     = "StringEquals"
            variable = "aws:SourceArn"  
            values   = ["arn:aws:cloudtrail:${var.aws_region}:${var.management_account_id}:trail/atlas-fintech-org-trail"]
        }
    }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
    bucket = aws_s3_bucket.cloudtrail.id
    policy = data.aws_iam_policy_document.cloudtrail_bucket.json
}


# ─────────────────────────────────────────────────────────
# PART 3 — The CloudTrail Trail (the recorder)
# ─────────────────────────────────────────────────────────

resource "aws_cloudtrail" "org_trail" {
  name           = "atlas-fintech-org-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  # Organization-wide (captures ALL member accounts)
  is_organization_trail = true

  # All regions (not just eu-west-1)
  is_multi_region_trail = true

  # Include IAM, STS, CloudFront events (global services)
  include_global_service_events = true

  # Tamper detection — signs every log file with a hash
  enable_log_file_validation = true

  # Enable logging immediately
  enable_logging = true

  # Wait for bucket policy before creating (avoid race condition)
  depends_on = [
    aws_s3_bucket_policy.cloudtrail
  ]

  tags = {
    Name = "atlas-fintech-org-trail"
  }
}