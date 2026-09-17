# ---------------------------------------------------------------------------
# Remote state on DigitalOcean Spaces (S3-compatible)   [scaffold copy]
#
# Spaces speaks S3 but is not AWS, so every AWS-specific preflight in the s3
# backend has to be switched off:
#
#   skip_credentials_validation  -- no STS endpoint on Spaces
#   skip_requesting_account_id   -- no IAM/STS account lookup
#   skip_metadata_api_check      -- no EC2 instance metadata service
#   skip_region_validation       -- "blr1" is not an AWS region name
#   skip_s3_checksum             -- Spaces rejects the trailing checksum
#                                   headers the AWS SDK adds by default
#
# `region` below is a *dummy AWS region* required by the SDK. The real
# placement is decided by the `endpoints.s3` hostname.
#
# LOCKING: DigitalOcean Spaces does not (at time of writing) guarantee support
# for the S3 conditional-write primitive that Terraform's `use_lockfile`
# locking relies on, and there is no DynamoDB equivalent. We therefore run
# WITHOUT backend locking and serialize applies in CI instead, via a per-stack
# `concurrency` group in the GitHub Actions workflows. Do not run apply from a
# laptop while CI may be applying the same stack. If you verify that
# conditional writes work on your Spaces region, add `use_lockfile = true`
# here and drop that caveat.
#
# Credentials come from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY set to your
# Spaces key pair -- never from this file.
#
# bucket/key are supplied per stack via `-backend-config`; see README.
#
# The state bucket lives in SGP1, not BLR1 like the workloads: on 17 Sep 2026
# the control panel reported "Creates in this datacenter region are disabled"
# for BLR1 Spaces, so imigrate-tfstate was created in Singapore. State holds
# no guest data, so residency is not a concern here. The per-wedding media
# bucket in modules/wedding-data still targets blr1 -- revisit before apply.
# ---------------------------------------------------------------------------

terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://sgp1.digitaloceanspaces.com"
    }

    region = "us-east-1"

    encrypt = true

    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true

    use_path_style = false
  }
}
