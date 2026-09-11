resource "aws_s3_bucket" "this" {
    bucket = var.bucket_name
}

resource "aws_s3_object" "assets_prefix" {
    bucket = aws_s3_bucket.this.id
    key    = "assets/"
    content_type = "application/x-directory"
}
resource "aws_s3_object" "archive_prefix" {
    bucket = aws_s3_bucket.this.id
    key    = "archive/"
    content_type = "application/x-directory"
}

resource "aws_s3_bucket_versioning" "this" {
    bucket = aws_s3_bucket.this.id
    versioning_configuration {
        status = "Enabled"
    }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
    bucket = aws_s3_bucket.this.id
    rule {
        apply_server_side_encryption_by_default {
            sse_algorithm = "aws:kms"
            kms_master_key_id = var.kms_key_arn
        }
            bucket_key_enabled = true
    }
}

resource "aws_s3_bucket_public_access_block" "this" {
    bucket = aws_s3_bucket.this.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
    bucket = aws_s3_bucket.this.id
    rule {
        id     = "HotContentAssets"
        status = "Enabled"

        filter{
            prefix = "assets/"
        }

        abort_incomplete_multipart_upload {
            days_after_initiation = 7
        }

        noncurrent_version_expiration {
            noncurrent_days = 30
        }
    }

    rule {
        id     = "ColdContentArchive"
        status = "Enabled"

        filter{
            prefix = "archive/"
        }

        transition {
            days          = 30
            storage_class = "STANDARD_IA"
        }

        transition {
            days          = 90
            storage_class = "GLACIER"
        }

        transition {
            days          = 365
            storage_class = "DEEP_ARCHIVE"
        }

        expiration {
            days = 2555
        }
    }
}
resource "aws_s3_bucket_policy" "this" {
    bucket = aws_s3_bucket.this.id
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Sid    = "AllowCloudFrontServicePrincipal"
                Effect = "Allow"
                Principal = {
                    Service = "cloudfront.amazonaws.com"
                }
                Action   = ["s3:GetObject"]
                Resource = "${aws_s3_bucket.this.arn}/*"
                Condition = {
                    StringEquals = {
                        "AWS:SourceArn" = var.cloudfront_distribution_arn
                    }
                }
            }
        ]
    })
}