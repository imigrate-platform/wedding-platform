# ---------------------------------------------------------------------------
# envs/_shared -- infrastructure that exists ONCE for the whole platform.
#
# Everything in here is a singleton: creating it per wedding would either fail
# outright (the DNS zone) or produce needless duplication (the VPC). Wedding
# stacks consume these by data source or by variable, never by managing them.
#
# Apply order: this stack FIRST, then any envs/<wedding-slug>/.
# Destroying this stack takes every wedding offline. It has no automated
# destroy path and is not wired into terraform-apply.yml's matrix by accident.
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

provider "digitalocean" {
  token = var.do_token

  http_retry_max      = 5
  http_retry_wait_min = 1
  http_retry_wait_max = 30
  requests_per_second = 20
}

# ----------------------------- variables -----------------------------------

variable "do_token" {
  description = "DigitalOcean API token. Leave null to read DIGITALOCEAN_TOKEN from the environment."
  type        = string
  default     = null
  sensitive   = true
}

variable "apex_domain" {
  description = "Apex domain for the whole platform. The zone is created here and only here."
  type        = string
  default     = "imigrate.com"
}

variable "region" {
  description = "Primary DigitalOcean datacenter slug for the shared VPC."
  type        = string
  default     = "blr1"
}

variable "vpc_ip_range" {
  description = "CIDR for the shared VPC. Null lets DigitalOcean pick a free /20."
  type        = string
  default     = null
}

# ----------------------------- DNS zone ------------------------------------

# The single source of truth for imigrate.com. Every wedding stack reads this
# zone through `data "digitalocean_domain"` in modules/wedding-dns and adds
# records to it; none of them may manage the zone itself.
#
# `ip_address` is deliberately omitted: setting it would make DigitalOcean
# create an apex A record pointing at a droplet we do not have. The apex record
# for the marketing site is managed below, explicitly.
resource "digitalocean_domain" "apex" {
  name = var.apex_domain
}

# ----------------------------- shared VPC ----------------------------------

# Managed Postgres clusters are placed in this VPC so that any future
# droplet-based or Kubernetes-based tooling (backup runners, admin bastion)
# can reach them over private networking instead of the public endpoint.
#
# VPCs are free and regional. One per region is plenty -- per-wedding VPCs
# would burn through the account's VPC quota for no isolation benefit, since
# per-wedding isolation is enforced by the database firewall and by separate
# credentials, not by network segmentation.
resource "digitalocean_vpc" "shared" {
  name        = "imigrate-shared-${var.region}"
  region      = var.region
  ip_range    = var.vpc_ip_range
  description = "Shared private network for imigrate wedding stacks in ${var.region}."
}

# ----------------------------- DO project ----------------------------------

# A DigitalOcean project is the closest thing the platform has to an account
# level label, and it is what the billing breakdown groups by. This one holds
# shared assets only; each wedding stack creates its own project so that a
# wedding's monthly cost can be read straight off the DO billing page.
#
# NOTE: `resources` here and a separate `digitalocean_project_resources`
# resource targeting the same project will fight each other -- DigitalOcean
# returns the full set on read, so each would try to remove the other's URNs.
# This stack uses `resources`; wedding stacks use digitalocean_project_resources.
resource "digitalocean_project" "platform" {
  name        = "imigrate-platform-shared"
  description = "Shared platform assets: the ${var.apex_domain} DNS zone. The Terraform state bucket is managed by hand outside this project."
  purpose     = "Web Application"
  environment = "Production"

  resources = [
    digitalocean_domain.apex.urn,
  ]
}

# ----------------------------- outputs -------------------------------------

output "apex_domain" {
  description = "Name of the apex DNS zone. Pass to each wedding stack's apex_domain variable."
  value       = digitalocean_domain.apex.name
}

output "apex_domain_urn" {
  description = "URN of the apex DNS zone."
  value       = digitalocean_domain.apex.urn
}

output "vpc_uuid" {
  description = "UUID of the shared VPC. Pass to each wedding stack's vpc_uuid variable."
  value       = digitalocean_vpc.shared.id
}

output "vpc_ip_range" {
  description = "CIDR DigitalOcean assigned to the shared VPC."
  value       = digitalocean_vpc.shared.ip_range
}

output "platform_project_id" {
  description = "UUID of the shared platform project."
  value       = digitalocean_project.platform.id
}

output "region" {
  description = "Region the shared VPC lives in."
  value       = var.region
}
