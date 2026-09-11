# Phase 9 — Storage & Lifecycle (S3 Bucket with Tiered Retention)

## 🎯 Overview

This phase introduces the platform's first dedicated static content store: a single S3 bucket serving two distinct purposes — live web assets served through CloudFront, and retired content kept only for compliance retention. Rather than split these into two buckets, one bucket with two logically separated prefixes was used, each governed by its own lifecycle policy matching its actual access pattern. The goal was proving that storage cost and retention behavior can be driven entirely by object location (prefix) rather than by bucket boundaries.

**What was built:**

- A new `infra/storage/` folder holding the S3 bucket and its supporting resources
- One S3 bucket (`atlas-fintech-assets-<account_id>`) with versioning, server-side encryption, and public access fully blocked
- Two logical prefixes inside the bucket: `assets/` (hot, live content) and `archive/` (cold, compliance retention)
- Two lifecycle rules, each scoped to one prefix via a `filter` block, each with a different cost/retention profile
- Terraform resource labels standardized to `this` across all 5 resources, following the Phase 5/6/8 convention of "label = role, not literal name"
-
___


## 🏗️ Why one bucket, two prefixes — not two buckets

The bucket name (`atlas-fintech-assets-<account_id>`) predates the decision to also store archived content in it, which made the name briefly ambiguous. Two buckets were considered and rejected:

- **Renaming or splitting would touch the KMS key policy**, whose `kms:EncryptionContext:aws:s3:arn` condition matches the bucket ARN exactly — an avoidable change with no functional benefit.
- **"Assets" in cloud/enterprise vocabulary reasonably covers any static file the org owns**, including retired ones — the ambiguity is a naming nuance, not a design flaw, and is resolved by documenting it explicitly here rather than by renaming infrastructure.
- **One bucket keeps IAM and bucket-policy surface area smaller** — one bucket to secure, encrypt, and block public access on, instead of two.

The distinction that actually matters — hot vs. cold, short-lived vs. long-retained — is expressed through prefixes and lifecycle rule `filter` blocks, not through bucket boundaries.

## 🛠️ Implementation

### New folder: `infra/storage/`

Same pattern as `cicd/`, `security/`, and `observability/` — its own state file, consistent tagging, resource labels standardized to `this`.

### Lifecycle configuration — two rules, one per prefix

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "this" {
    bucket = aws_s3_bucket.this.id

    rule {
        id     = "HotContentAssets"
        status = "Enabled"

        filter {
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

        filter {
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
```

**Rule 1 — `HotContentAssets`** (targets `assets/`): live web content stays in Standard indefinitely for fast, free retrieval. `abort_incomplete_multipart_upload` after 7 days cleans up stuck uploads that never completed — a zero-downside hygiene rule. `noncurrent_version_expiration` after 30 days controls the storage cost of old versions, since versioning keeps every overwritten copy by default.

**Rule 2 — `ColdContentArchive`** (targets `archive/`): a staged descent through storage classes as content ages — Standard-IA at 30 days (~45% cheaper, small retrieval fee), Glacier Flexible Retrieval at 90 days (~80% cheaper, retrieval in minutes–hours), Deep Archive at 365 days (cheapest tier, 12+ hour retrieval), then expiration at 2,555 days (~7 years, matching common SOC 2 / financial-regulation retention windows).

## 🐞 Debugging — the Deep Archive minimum-duration violation

The first version of Rule 2 transitioned to Deep Archive at day 180. This looked reasonable but violated an AWS-enforced minimum: a transition into Deep Archive must occur **at least 30 days after** the preceding transition — Glacier requires 90 days minimum residency, so the next transition value has to be ≥120, and even then AWS's own error message is explicit about the 30-day gap:

```
'Days' in Transition action must be greater than 'Days' in the previous
Transition action by at least 30 days for storage class 'DEEP_ARCHIVE'
```

At day 180, only 90 days had elapsed in Glacier — technically at the boundary, and rejected by `terraform apply` before any resources were touched. The fix was moving the Deep Archive transition to day 365, giving 275 days in Glacier — comfortably clear of the minimum. The full chain was re-verified against all three minimums:

- Standard → Standard-IA: 30-day minimum in Standard ✅ (exactly 30)
- Standard-IA → Glacier: 30-day minimum in IA ✅ (60 days in IA)
- Glacier → Deep Archive: 90-day minimum in Glacier ✅ (275 days in Glacier)

## ✅ Verifying the lifecycle rules apply correctly

`terraform apply` completed cleanly (5 resources added: bucket, versioning, encryption, public access block, lifecycle configuration). Dummy files were uploaded under both prefixes to confirm the rules attach to the objects they're meant to govern, and a file in `assets/` was overwritten to produce a noncurrent version — the object intended to demonstrate `noncurrent_version_expiration` once the 30-day window is observable.

## 📸 Evidence
![[1_bucket_name.png]]
_1 — Bucket overview, name and region._

![[2_bucket_prefixes.png]]
_2 — Bucket contents showing both `assets/` and `archive/` prefixes populated._

![[3_assets_prefix.png]]
_3 — Objects under the `assets/` prefix (hot content)._

![[4_bucket_archives.png]]
_4 — Objects under the `archive/` prefix (cold content, PDF)._

![[5_bucket_versioning.png]]
_5 — Bucket versioning enabled._

![[6_server_side_encryption.png]]
_6 — Default encryption: SSE-KMS with Phase 5 CMK, bucket key enabled._

![[7_block_public_access.png]]
_7 — Public access blocked (all 4 flags)._

![[8_lifecycle_configuration.png]]
_8 — Lifecycle rules: `HotContentAssets` and `ColdContentArchive`, both Enabled._

## 💰 A note on cost trade-offs

The archive lifecycle chain is designed for illustrative completeness rather than actual project need — this portfolio project holds a handful of dummy PDFs in `archive/`, not gigabytes of retired reports where Deep Archive would meaningfully reduce cost. Documented as the correct production pattern rather than the strictly cheapest one for this specific dataset, matching Phase 8's stance on the 3-NAT-Gateway trade-off.

## 💡 Lessons Learned

1. **A bucket's original name doesn't have to perfectly describe everything it later comes to hold.** Renaming to chase a purer name has a real cost (touching the KMS key policy); documenting the ambiguity is often the cheaper and equally effective fix.
2. **AWS's storage-class transition minimums are enforced at plan/apply time, not just as guidance** — a value that looks intuitively fine (180 days) can still violate a minimum-residency rule that only becomes visible in the error message.
3. **Lifecycle rules scoped by `filter { prefix = ... }` let one bucket safely host two very different retention policies** — the boundary that matters is the object's prefix, not the bucket it lives in.
4. **Terraform resource labels and real-world names are three independent concepts** — the bucket name, the Terraform label, and the prefix name inside the bucket can all differ without conflict, and standardizing labels to `this` keeps that distinction clear across the codebase.

## ✅ Completion Status

|Component|Status|
|---|---|
|`infra/storage/` folder + remote state pattern|✅ Complete|
|S3 bucket: versioning, encryption, public access blocked|✅ Complete|
|Terraform labels standardized to `this`|✅ Complete|
|Lifecycle rule — `HotContentAssets` (assets/)|✅ Complete|
|Lifecycle rule — `ColdContentArchive` (archive/)|✅ Complete|
|Dummy file upload + screenshot evidence|✅ Complete|

**Next:** Phase 10 — _(open)_

## 📚 References

- [Amazon S3 Lifecycle Configuration](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
- [S3 Storage Classes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html)
- [Terraform aws_s3_bucket_lifecycle_configuration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration)	