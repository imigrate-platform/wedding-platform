# ---------------------------------------------------------------------------
# Staging stack.
#
# The rehearsal environment for the platform itself: every module change lands
# here first. It is shaped identically to a real wedding stack -- same modules,
# same wiring -- so that a plan against staging is genuinely representative.
#
# Differences from a wedding stack, all of them deliberate:
#   * environment = "staging", which relaxes the module preconditions that
#     insist a production stack have a real domain,
#   * it lives at sandbox-staging.imigrate.com via subdomain_override, so it
#     never collides with a wedding slug,
#   * bucket_force_destroy defaults to true so it can actually be torn down,
#   * deploy_on_push follows a staging branch.
#
# Prerequisite: envs/_shared must be applied first.
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
  token             = var.do_token
  spaces_access_id  = var.spaces_access_id
  spaces_secret_key = var.spaces_secret_key

  http_retry_max      = 5
  http_retry_wait_min = 1
  http_retry_wait_max = 30
  requests_per_second = 20
}

# ===========================================================================
# Inputs
# ===========================================================================

variable "do_token" {
  description = "DigitalOcean API token. Leave null to read DIGITALOCEAN_TOKEN from the environment."
  type        = string
  default     = null
  sensitive   = true
}

variable "spaces_access_id" {
  description = "Spaces key id Terraform uses to manage the bucket. Leave null to read SPACES_ACCESS_KEY_ID from the environment."
  type        = string
  default     = null
  sensitive   = true
}

variable "spaces_secret_key" {
  description = "Spaces secret Terraform uses to manage the bucket. Leave null to read SPACES_SECRET_ACCESS_KEY from the environment."
  type        = string
  default     = null
  sensitive   = true
}

variable "wedding_slug" {
  description = "Identity of the staging stack. Not a real wedding."
  type        = string
  default     = "sandbox"
}

variable "subdomain" {
  description = "DNS label under apex_domain for the staging site."
  type        = string
  default     = "sandbox-staging"
}

variable "environment" {
  description = "Deployment environment for this stack."
  type        = string
  default     = "staging"
}

variable "apex_domain" {
  description = "Apex zone, created once by envs/_shared and only read here."
  type        = string
  default     = "imigrate.com"
}

variable "region" {
  description = "Datacenter slug for Postgres and the VPC."
  type        = string
  default     = "blr1"
}

variable "app_region" {
  description = "App Platform region slug (short form)."
  type        = string
  default     = "blr"
}

variable "spaces_region" {
  description = "Spaces region slug for the media bucket."
  type        = string
  default     = "blr1"
}

variable "vpc_uuid" {
  description = "UUID of the shared VPC, from the envs/_shared stack output."
  type        = string
  default     = null
}

variable "github_repo" {
  description = "owner/name of the Next.js app repository."
  type        = string
  default     = "imigrate-apps/wedding-app"
}

variable "github_branch" {
  description = "Branch App Platform builds from. Staging follows the integration branch."
  type        = string
  default     = "develop"
}

variable "deploy_on_push" {
  description = "Auto-deploy on push."
  type        = bool
  default     = true
}

variable "instance_size_slug" {
  description = "App Platform instance size. The smallest Basic size is enough for staging."
  type        = string
  default     = "apps-s-1vcpu-0.5gb"
}

variable "db_size" {
  description = "Managed Postgres node size."
  type        = string
  default     = "db-s-1vcpu-1gb"
}

variable "trusted_ip_addresses" {
  description = "Extra IPv4 addresses/CIDRs allowed through the Postgres firewall."
  type        = list(string)
  default     = []
}

variable "bucket_force_destroy" {
  description = "Allow destroy of a non-empty bucket. True by default here so staging can be recycled."
  type        = bool
  default     = true
}

variable "jwt_secret" {
  description = "Session JWT signing secret for staging. Must NOT be the same value as any production stack."
  type        = string
  sensitive   = true
}

variable "msg91_auth_key" {
  description = "MSG91 auth key. Use a sandbox key here so staging cannot message real guests."
  type        = string
  sensitive   = true
}

variable "msg91_template_id" {
  description = "MSG91 OTP template id."
  type        = string
}

variable "admin_phones" {
  description = "Comma-separated E.164 numbers allowed into the staging admin console."
  type        = string
  default     = ""
}

variable "app_spaces_access_key_id" {
  description = "Spaces key id injected into the running app as SPACES_KEY."
  type        = string
  sensitive   = true
}

variable "app_spaces_secret_access_key" {
  description = "Spaces secret injected into the running app as SPACES_SECRET."
  type        = string
  sensitive   = true
}

# ===========================================================================
# Locals
# ===========================================================================

locals {
  site_fqdn = "${var.subdomain}.${var.apex_domain}"
  site_url  = "https://${local.site_fqdn}"
}

# ===========================================================================
# DigitalOcean project
# ===========================================================================

resource "digitalocean_project" "staging" {
  name        = "wedding-${var.wedding_slug}-${var.environment}"
  description = "Staging stack for the imigrate wedding platform."
  purpose     = "Web Application"
  environment = "Staging"
}

resource "digitalocean_project_resources" "staging" {
  project = digitalocean_project.staging.id

  resources = [
    module.data.cluster_urn,
    module.data.bucket_urn,
    module.app.app_urn,
  ]
}

# ===========================================================================
# Modules
# ===========================================================================

module "data" {
  source = "../../modules/wedding-data"

  wedding_slug = var.wedding_slug
  environment  = var.environment

  region        = var.region
  spaces_region = var.spaces_region
  vpc_uuid      = var.vpc_uuid

  db_size       = var.db_size
  db_node_count = 1

  allowed_app_ids      = [module.app.app_id]
  allowed_ip_addresses = var.trusted_ip_addresses

  cors_allowed_origins = [local.site_url]
  bucket_force_destroy = var.bucket_force_destroy

  # Staging media is disposable; skip the versioning overhead.
  bucket_versioning_enabled = false

  # Shorter edge cache so a fixed upload pipeline can be verified quickly.
  cdn_ttl = 600
}

module "app" {
  source = "../../modules/wedding-app"

  wedding_slug      = var.wedding_slug
  environment       = var.environment
  app_name_override = "${var.wedding_slug}-${var.environment}"
  app_region        = var.app_region

  github_repo    = var.github_repo
  github_branch  = var.github_branch
  deploy_on_push = var.deploy_on_push

  instance_size_slug = var.instance_size_slug
  instance_count     = 1

  primary_domain = local.site_fqdn
  site_url       = local.site_url

  database_url = module.data.database_uri

  spaces_key     = var.app_spaces_access_key_id
  spaces_secret  = var.app_spaces_secret_access_key
  spaces_bucket  = module.data.bucket_name
  spaces_region  = module.data.bucket_region
  spaces_cdn_url = module.data.cdn_url

  jwt_secret        = var.jwt_secret
  msg91_auth_key    = var.msg91_auth_key
  msg91_template_id = var.msg91_template_id
  admin_phones      = var.admin_phones

  # Loud in staging: a failed deploy here is the signal that a module change
  # would have broken a real wedding.
  alert_rules = ["DEPLOYMENT_FAILED", "DOMAIN_FAILED"]
}

module "dns" {
  source = "../../modules/wedding-dns"

  apex_domain        = var.apex_domain
  wedding_slug       = var.wedding_slug
  subdomain_override = var.subdomain

  app_ingress_hostname = module.app.default_ingress

  # Low TTL: staging gets rebuilt from scratch often.
  record_ttl = 60
}

# ===========================================================================
# Outputs
# ===========================================================================

output "app_url" {
  description = "Live URL of the staging site."
  value       = module.app.live_url
}

output "app_id" {
  description = "App Platform app UUID."
  value       = module.app.app_id
}

output "app_default_ingress" {
  description = "Permanent *.ondigitalocean.app hostname."
  value       = module.app.default_ingress
}

output "site_fqdn" {
  description = "Staging hostname under the apex domain."
  value       = module.dns.fqdn
}

output "database_uri" {
  description = "Postgres connection URI for the application role."
  value       = module.data.database_uri
  sensitive   = true
}

output "bucket_name" {
  description = "Staging media bucket."
  value       = module.data.bucket_name
}

output "cdn_endpoint" {
  description = "Spaces CDN hostname."
  value       = module.data.cdn_endpoint
}

output "cdn_url" {
  description = "https:// base URL for staging media."
  value       = module.data.cdn_url
}

output "project_id" {
  description = "UUID of the staging DigitalOcean project."
  value       = digitalocean_project.staging.id
}
