resource "aws_cloudfront_origin_access_control" "atlas_fintech_s3_oac" {
    name                              = "atlas-fintech-s3-oac"
    description                       = "OAC for Atlas FinTech S3 bucket"
    origin_access_control_origin_type = "s3"
    signing_behavior                  = "always"
    signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "atlas_fintech_cdn" {
    enabled         = true
    is_ipv6_enabled = true
    comment         = "CloudFront distribution for Atlas FinTech Platform"
    price_class     = "PriceClass_100"

    origin {
        domain_name              = var.s3_bucket_domain_name
        origin_id                = "S3-AtlasFinTechAssets"
        origin_access_control_id = aws_cloudfront_origin_access_control.atlas_fintech_s3_oac.id
    }

    origin {
        domain_name = var.alb_dns_name
        origin_id   = "ALB-AtlasFinTechApp"
        custom_origin_config {
            http_port              = 80
            https_port             = 443
            origin_protocol_policy = "http-only"
            origin_ssl_protocols   = ["TLSv1.2"]
        }
    }

    default_cache_behavior {
        target_origin_id       = "ALB-AtlasFinTechApp"
        viewer_protocol_policy = "redirect-to-https"
        allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
        cached_methods         = ["GET", "HEAD"]

        forwarded_values {
            query_string = true
            cookies {
                forward = "all"
            }
        }

        min_ttl     = 0
        default_ttl = 0
        max_ttl     = 0
    }

    ordered_cache_behavior {
        path_pattern           = "/assets/*"
        target_origin_id       = "S3-AtlasFinTechAssets"
        viewer_protocol_policy = "redirect-to-https"
        allowed_methods        = ["GET", "HEAD"]
        cached_methods         = ["GET", "HEAD"]

        forwarded_values {
            query_string = false
            cookies {
                forward = "none"
            }
        }

        min_ttl     = 0
        default_ttl = 3600
        max_ttl     = 86400
    }

    restrictions {
        geo_restriction {
            restriction_type = "none"
        }
    }

    viewer_certificate {
        cloudfront_default_certificate = true
    }
}