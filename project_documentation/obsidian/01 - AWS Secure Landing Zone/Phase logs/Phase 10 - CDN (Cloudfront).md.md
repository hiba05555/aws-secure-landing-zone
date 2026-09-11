# Phase 10 — Content Delivery Network (CloudFront + OAC)

## 🎯 Overview

Phase 10 puts a **single edge layer** in front of the two Phase 4 / Phase 9 origins — the ALB serving dynamic content from ECS Fargate, and the S3 bucket holding the platform's static assets. Everything users hit now enters through **one CloudFront distribution**, terminated with HTTPS at the edge, and routed by path pattern to the appropriate origin.

Two origins, two cache behaviors:

- **Default (`*`)** → ALB origin (dynamic, minimal caching)
- **`/assets/*`** → S3 origin (static, aggressive caching), reached via **Origin Access Control (OAC)** signing requests with SigV4

Cross-service permissions were the hard part: the bucket policy trusts CloudFront via a `SourceArn` condition, and the Phase 5 KMS key policy was extended a second time to allow CloudFront to decrypt SSE-KMS objects on the fly.

The custom domain (`atlas-fintech.click`, Bloc 1) is deferred while a Route 53 domain registration support case is pending; the distribution uses the AWS-managed wildcard cert on `*.cloudfront.net` in the meantime, which is real, valid HTTPS — just not on a custom hostname.

---

## 🏗️ Why one distribution in front of both origins

The obvious alternative was to leave the ALB directly exposed and put CloudFront only in front of S3. That would have worked, but it splits the platform's entry point in two — dynamic content on one URL, static content on another — which is not how a real user-facing application is served. A single edge fronting both origins is the pattern that matches how production platforms actually route requests, and it's what SAA-C03 tests under D3 (Performing).

The path-based routing itself is what makes the two-origin design useful:

- **`/assets/*`** → S3, cached aggressively at the edge. Static files rarely change; hits from the edge are free after the first miss.
- **Default (`*`)** → ALB, TTL zero. Every request forwards to nginx, which is correct for dynamic content — caching HTML responses at the edge would serve stale application state.

Cookies, query strings, and all HTTP methods are forwarded to the ALB behavior; the S3 behavior forwards nothing (GET/HEAD only, no cookies, no query strings). That mirrors the intent of each origin: the ALB is an application, the S3 bucket is a file store.

---

## 🏗️ Why Origin Access Control (OAC), not Origin Access Identity (OAI)

S3 has all public access blocked (Phase 9). CloudFront needs a way to reach it that S3 will actually accept.

**OAI is the legacy pattern:** a special CloudFront-owned pseudo-user that S3 grants permission to. It works, but AWS documentation now labels it "legacy" and steers new distributions toward OAC.

**OAC is the current pattern:** the distribution signs every origin request to S3 using **SigV4** (AWS's standard signing protocol). S3 sees the signed request and checks a bucket policy condition on `AWS:SourceArn` — if the ARN matches the specific distribution, access is granted.

The reason this choice is _forced_ (not just recommended) in this project is the S3 bucket uses **SSE-KMS**, not SSE-S3. OAI does not fully support SSE-KMS — the signing model breaks down when the request has to go through KMS decryption. OAC + SigV4 signs the request end-to-end and works cleanly with KMS. So the decision was made for us the moment Phase 9 landed on SSE-KMS.

---

## 🏗️ Why PriceClass_100

CloudFront has ~450 edge locations globally, grouped into three price classes:

- **PriceClass_All** — every edge worldwide, most expensive
- **PriceClass_200** — everything except South America, Australia, Africa
- **PriceClass_100** — North America + Europe only, cheapest

For a portfolio project with no real user base and testing done from Morocco (served by a European edge either way — MAD53-P6 in Madrid, as the `X-Amz-Cf-Pop` header confirms), `PriceClass_100` covers the actual traffic and demonstrates awareness of the cost knob, which SAA-C03 tests under D4 (Cost).

---

## 🛠️ Implementation

Three folders were touched: a new `infra/cdn/` for the distribution and OAC, `infra/storage/` gained a bucket policy referencing the distribution ARN, and `infra/security/` gained a fifth statement on the Phase 5 KMS key policy.

### `infra/cdn/` — the distribution and its OAC

New folder, same pattern as Phases 3–9: dedicated backend state key (`cdn/terraform.tfstate`), provider assuming `OrganizationAccountAccessRole` into the network account, `default_tags` carrying `Component = "cdn"` for Cost Explorer breakdowns.

**The OAC — a standalone signing config:**

```hcl
resource "aws_cloudfront_origin_access_control" "atlas_fintech_s3_oac" {
    name                              = "atlas-fintech-s3-oac"
    description                       = "OAC for Atlas FinTech S3 bucket"
    origin_access_control_origin_type = "s3"
    signing_behavior                  = "always"
    signing_protocol                  = "sigv4"
}
```

The OAC is not attached to anything yet — it's just a config object CloudFront can reference. It becomes active only when an origin block cites it via `origin_access_control_id`.

**The distribution — two origins, two behaviors:**

```hcl
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
            cookies { forward = "all" }
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
            cookies { forward = "none" }
        }

        min_ttl     = 0
        default_ttl = 3600
        max_ttl     = 86400
    }

    restrictions {
        geo_restriction { restriction_type = "none" }
    }

    viewer_certificate {
        cloudfront_default_certificate = true
    }
}
```

The S3 origin has no `custom_origin_config` — that's only for HTTP origins. The OAC replaces what would have been `s3_origin_config { origin_access_identity = ... }` in the OAI-era syntax. The ALB origin uses `http-only` because the ALB listener is on port 80 (Phase 4); once Bloc 1 lands, this becomes `https-only` and the listener converts to port 443 with an ACM cert.

`viewer_certificate { cloudfront_default_certificate = true }` is what says _"serve HTTPS using AWS's own wildcard cert for `*.cloudfront.net`."_ AWS owns that domain and rotates the cert silently — users see a valid padlock, no custom domain required. When `atlas-fintech.click` unblocks, this line is replaced with `acm_certificate_arn = ...` pointing at a cert issued in us-east-1 (CloudFront's fixed cert region).

### `infra/storage/` — bucket policy trusting the distribution

The bucket had no explicit policy before Phase 10. The one added is intentionally minimal — one statement, one action, one condition:

```hcl
resource "aws_s3_bucket_policy" "this" {
    bucket = aws_s3_bucket.this.id

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Sid       = "AllowCloudFrontServicePrincipal"
                Effect    = "Allow"
                Principal = { Service = "cloudfront.amazonaws.com" }
                Action    = "s3:GetObject"
                Resource  = "${aws_s3_bucket.this.arn}/*"
                Condition = {
                    StringEquals = {
                        "AWS:SourceArn" = var.cloudfront_distribution_arn
                    }
                }
            }
        ]
    })
}
```

The `SourceArn` condition scopes trust to **one specific distribution**. Without it, any CloudFront distribution — including someone else's in a different AWS account — could pull from this bucket. With it, only distribution `ECQFVYBEI6XFU` in account `622532143366` is authorized. `Action = "s3:GetObject"` is the minimum needed — CloudFront doesn't list, doesn't write, doesn't delete.

The distribution ARN is passed in as a variable with its default hardcoded in `variables.tf`, following the same pattern as Phase 9's `kms_key_arn`. This creates a chicken-and-egg between `infra/cdn/` and `infra/storage/` — the distribution has to exist before its ARN can be referenced by the bucket policy — so Phase 10 is applied in two steps: `cdn/` first, capture the ARN from `terraform output`, then update `storage/variables.tf` and reapply `storage/`.

### `infra/security/` — extending the KMS key policy again

The Phase 5 key already allowed CloudWatch Logs, ECR, and S3 (added at the start of Phase 9). Phase 10 adds a fifth statement for CloudFront itself, because the OAC + SSE-KMS combination requires CloudFront to be able to decrypt objects it fetches from S3:

```hcl
{
    Sid    = "AllowCloudFrontServicePrincipal"
    Effect = "Allow"
    Principal = { Service = "cloudfront.amazonaws.com" }
    Action = [
        "kms:Decrypt",
        "kms:GenerateDataKey*"
    ]
    Resource = "*"
    Condition = {
        StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudfront::622532143366:distribution/ECQFVYBEI6XFU"
        }
    }
}
```

Same `SourceArn` scoping as the bucket policy — this key only decrypts for that specific distribution, nothing else.

---

## 🐞 Debugging

Three real bugs, all resolved during the phase.

### Bug 1 — CloudFront returned 504 Gateway Timeout on the default (ALB) path

After the distribution deployed, `https://d1w71vl5n8ghar.cloudfront.net/` returned:

```
504 Gateway Timeout ERROR
The request could not be satisfied.
```

CloudFront was reaching for the ALB origin and timing out. Bypassing CloudFront and hitting the ALB URL directly (`http://atlas-fintech-app-1754103518.eu-west-1.elb.amazonaws.com/`) also timed out — `ERR_CONNECTION_TIMED_OUT` — which localized the problem to the origin, not the CDN.

ECS was healthy (2 running tasks, 2 healthy targets in the target group), so the failure was network-level. The ALB overview page showed _"Reachability may be impacted"_ and the HTTP:80 listener showed _"Not reachable"_ — AWS's own diagnostic said the ALB was unreachable from the internet.

This was the **same class of bug as Phase 4**: the ALB security group had lost its port 80 ingress rule from `0.0.0.0/0`. Re-adding the rule restored reachability, and CloudFront started serving the nginx page correctly on the default path.

### Bug 2 — S3 path returned `<Error><Code>AccessDenied</Code></Error>`

With the ALB path working, the S3 path (`/assets/index.html`) returned an XML AccessDenied error from S3 — CloudFront was reaching S3 (that ruled out OAC misconfig at the CloudFront layer) but S3 was refusing to serve the object.

Bucket policy was in place and correct: `AllowCloudFrontServicePrincipal` with the right `SourceArn`. OAC was correctly attached to the S3 origin — the OAC's console page even showed distribution `ECQFVYBEI6XFU` in its "Distributions" section. Nothing at the S3 or CloudFront layer was wrong.

The failure was one layer deeper: **KMS decryption**. The bucket uses SSE-KMS, so S3 has to decrypt every object before returning it. The Phase 5 KMS key policy allowed `s3.amazonaws.com` (added at the start of Phase 9), but not `cloudfront.amazonaws.com`. When CloudFront fetched via OAC, the decrypt call was made in a context that required CloudFront to also be authorized on the key — and it wasn't.

Adding the `AllowCloudFrontServicePrincipal` statement to the KMS key policy (with `Decrypt` + `GenerateDataKey*` + `SourceArn` condition) fixed it. CloudFront could now decrypt objects it pulled from S3, and the browser started rendering the Atlas FinTech placeholder page from the `/assets/` prefix.

### Bug 3 — Silent KMS action typo

While patching the KMS policy for CloudFront, a typo in the existing `AllowS3Use` statement was discovered — `"kms:DesscribeKey"` (double _s_), not `"kms:DescribeKey"`. Terraform accepted it happily because the string is syntactically valid HCL, and AWS silently ignored the unknown action rather than failing the apply.

`DescribeKey` is what S3 calls to verify the key exists and is usable before doing any encrypt/decrypt operation. Missing this permission means S3 has to fall back on other means to discover key metadata, or fails opaquely. It didn't cause the AccessDenied in Bug 2 (that was the missing CloudFront principal), but it's the kind of silent config drift that shows up in unrelated failures later. Fixed at the same time as the CloudFront statement was added.

---

## ✅ Verifying the end-to-end chain

Three verifications, in order:

1. `https://d1w71vl5n8ghar.cloudfront.net/` returns the nginx welcome page — confirms default → ALB routing works, TLS at the edge is valid, ECS is serving.
2. `https://d1w71vl5n8ghar.cloudfront.net/assets/index.html` returns the Atlas FinTech placeholder HTML — confirms `/assets/*` → S3 routing works, OAC + bucket policy + KMS chain is complete.
3. Browser dev tools on the second load of the S3 path show `x-cache: Hit from cloudfront` and `x-amz-server-side-encryption: aws:kms` in the response headers — confirms edge caching works and that the object is being decrypted from KMS at the origin before caching at the edge.

The `X-Amz-Cf-Pop: MAD53-P6` header confirms the request was served from a Madrid edge — consistent with the `PriceClass_100` selection (Morocco is served by European edges).

---

## 💰 A note on cost trade-offs

Two conscious trade-offs are documented rather than optimized away:

**PriceClass_100 over PriceClass_All.** North America + Europe is a smaller footprint than a real global product would use, but it covers 100% of the actual test traffic (Morocco → Madrid edge) and cuts data transfer cost meaningfully at scale. For a portfolio project, this is the correct default; for a real global product, PriceClass_All would be justified.

**AWS-managed cert on `*.cloudfront.net` instead of a custom domain.** This isn't a cost trade-off but a deferred decision — Route 53 registration for `atlas-fintech.click` is currently blocked pending an AWS Support case on account verification for the network account. The distribution is fully functional on the auto-generated CloudFront URL; adding the custom domain later requires only two changes (an ACM cert issued in us-east-1, plus a Route 53 alias A record) and no rearchitecture.

---

## 📸 Evidence

![[1_terraform_state_list.png]] _1 — Terraform state list for `infra/cdn/`, showing the distribution and OAC._

![[2_distribution_list.png]] _2 — CloudFront Distributions page, showing distribution `ECQFVYBEI6XFU` enabled with domain `d1w71vl5n8ghar.cloudfront.net`._

![[3_distribution_origins.png]]

![[2_distribution_list 1.png]] _3 — Origins tab, showing both `S3-AtlasFinTechAssets` (with OAC `ENA2PSGZY3SBK` attached) and `ALB-AtlasFinTechApp` (Elastic Load Balancing)._

![[4_distribution_behaviors.png]] _4 — Behaviors tab, showing `/assets/*` → S3 origin and Default (`*`) → ALB origin, both redirecting HTTP to HTTPS._

![[5_oac_detail.png]] _5 — OAC `atlas-fintech-s3-oac` detail page: Signature V4, always sign, S3 origin type, linked to distribution `ECQFVYBEI6XFU`._

![[5_oac_detail 1.png]] _6 — Browser at `https://d1w71vl5n8ghar.cloudfront.net/` serving the nginx welcome page via the default behavior → ALB._

![[7_browser_assets_s3.png]] _7 — Browser at `https://d1w71vl5n8ghar.cloudfront.net/assets/index.html` serving the Atlas FinTech Platform placeholder via `/assets/*` → S3._

![[8_cloudfront_cache_hit.png]] _8 — Response headers on the `/assets/index.html` request: `x-cache: Hit from cloudfront`, `x-amz-server-side-encryption: aws:kms`, served from POP `MAD53-P6` (Madrid)._

![[9_s3_bucket_policy.png]] _9 — S3 bucket policy allowing `s3:GetObject` from the CloudFront service principal, scoped to distribution `ECQFVYBEI6XFU` via `AWS:SourceArn`._

![[10_kms_root_admin.png]] _10 — KMS key policy statement 1: `EnableRootAccountAdmin` (baseline root access, required on every customer-managed key)._

![[11_kms_cloudwatch_logs.png]] _11 — KMS key policy statement 2: `AllowCloudWatchLogsUse` (from Phase 5, encryption context scoped to the account's log group ARNs)._

![[12_kms_ecr.png]] _12 — KMS key policy statement 3: `AllowECRUse` (from Phase 5, with the AWS-resource grant condition)._

![[13_kms_s3.png]] _13 — KMS key policy statement 4: `AllowS3Use` (from Phase 9, scoped to the assets bucket via `kms:EncryptionContext:aws:s3:arn`)._

![[14_kms_cloudfront.png]] _14 — KMS key policy statement 5: `AllowCloudFrontServicePrincipal` (from Phase 10, scoped to the specific distribution via `AWS:SourceArn`)._

---

## 💡 Lessons Learned

1. **A missing security-group rule looks identical to a broken CDN.** The Phase 10 debugging started with a CloudFront 504 that felt like a CloudFront problem — origin protocol wrong, cache config broken, something at the edge. It was actually the ALB losing port 80 ingress, exactly the Phase 4 bug repeated in a new context. The lesson isn't "check the SG first" — it's that when CloudFront can't reach an origin, bypass CloudFront and test the origin directly before touching any CDN config. That test isolates the layer in 30 seconds.
    
2. **OAC + SSE-KMS needs TWO service principals on the key, not one.** S3 being allowed on the KMS key was necessary but not sufficient — when CloudFront fetched via OAC, the KMS decrypt call required CloudFront to also be authorized. This is not documented as a highlighted pattern anywhere obvious; it's an emergent property of how the OAC signs on behalf of the distribution rather than the S3 service principal chain. Any bucket fronted by CloudFront with SSE-KMS will hit this, and the fix is always the same shape: a second statement, same `SourceArn` scoping, `Decrypt` + `GenerateDataKey*` only.
    
3. **AWS silently accepts unknown KMS actions.** `kms:DesscribeKey` sat in the Phase 5 policy for two phases before being noticed. Terraform validated it as a string, AWS accepted it into the policy, and nothing failed loudly — the missing permission just meant one specific KMS call was denied under specific conditions, showing up as unrelated downstream errors. Policy content is not schema-validated against real AWS actions; the only real check is _does the runtime behavior actually work_. `terraform plan` will never catch this class of bug.
    
4. **Path-based routing to different origins is one of the cleanest patterns AWS offers, and it costs almost nothing to set up.** Two `origin` blocks, one `ordered_cache_behavior`, done. What made this Phase 10 interesting wasn't the CDN — it was the cross-service permission chain (bucket policy + KMS key policy + OAC) that the CDN implies. The CDN itself is simple; the identity and access boundaries around it are where the real work is. That's a general pattern in AWS: the fun service (CloudFront, ECS, Lambda) is often two hours of work, and the IAM / KMS / bucket policy plumbing around it is the other six.
    

---

## ✅ Completion Status

|Element|Status|
|:--|:--|
|CloudFront distribution deployed|✅ `ECQFVYBEI6XFU`, domain `d1w71vl5n8ghar.cloudfront.net`|
|Two origins configured|✅ S3 (`atlas-fintech-assets-622532143366`) + ALB (`atlas-fintech-app-1754103518`)|
|Path-based routing|✅ `/assets/*` → S3, Default (`*`) → ALB|
|Origin Access Control (OAC)|✅ SigV4, always sign, attached to S3 origin|
|S3 bucket policy trusting CloudFront|✅ `SourceArn`-scoped, `s3:GetObject` only|
|KMS key policy extended for CloudFront|✅ `Decrypt` + `GenerateDataKey*`, `SourceArn`-scoped|
|HTTPS at the edge|✅ AWS-managed wildcard cert on `*.cloudfront.net`|
|Price class|✅ `PriceClass_100` (North America + Europe)|
|End-to-end verification|✅ Both paths serve correctly, `x-cache: Hit from cloudfront` confirmed|
|Custom domain (`atlas-fintech.click`)|⏳ Deferred to Bloc 1 (Route 53 registration pending AWS Support case)|

**Next: Phase 11 — (open).**

---

## 📚 References

- [CloudFront Origin Access Control (OAC)](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [Restricting access to an S3 origin with OAC](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html#create-oac-overview-s3)
- [Using SSE-KMS encryption with CloudFront and S3](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-sse-kms-with-cloudfront.html)
- [Terraform: aws_cloudfront_distribution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution)
- [Terraform: aws_cloudfront_origin_access_control](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control)
- [CloudFront Price Classes](https://aws.amazon.com/cloudfront/pricing/)