# ---------------------------------------------------------------------------
# Provider configuration (scaffold copy -- see versions.tf header)
#
# Credentials are NEVER committed. Supply them one of two ways:
#
#   1. Environment variables (preferred, and what CI uses):
#        export DIGITALOCEAN_TOKEN=...            # DO API token
#        export SPACES_ACCESS_KEY_ID=...          # Spaces key id
#        export SPACES_SECRET_ACCESS_KEY=...      # Spaces key secret
#      Leave the variables below unset (null) and the provider picks these up.
#
#   2. -var / TF_VAR_ inputs, for local one-off runs.
#
# The Spaces credentials are required because `digitalocean_spaces_bucket`
# talks to the S3-compatible Spaces API, not the DO REST API.
# ---------------------------------------------------------------------------

provider "digitalocean" {
  token             = var.do_token
  spaces_access_id  = var.spaces_access_id
  spaces_secret_key = var.spaces_secret_key

  # Managed Postgres and App Platform creates are slow and the DO API is
  # aggressively rate limited on larger accounts. Back off rather than fail.
  http_retry_max      = 5
  http_retry_wait_min = 1
  http_retry_wait_max = 30
  requests_per_second = 20
}
