# ---------------------------------------------------------------------------
# imigrate-platform :: root scaffold
#
# NOTE ON THE REPO ROOT
# ---------------------
# The repository root is NOT applied directly. It is the canonical scaffold
# that every per-wedding root module under envs/<slug>/ is copied from, and it
# is kept as a valid (resource-free) Terraform module so that
# `terraform fmt -recursive` and `terraform validate` cover it in CI.
#
# The real root modules are:
#   envs/_shared/          -- apex DNS zone, shared VPC, platform project
#   envs/<wedding-slug>/   -- one isolated stack per wedding
#
# See README.md -> "Repository layout" for the rationale.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.9"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.43"
    }
  }
}
