# ---------------------------------------------------------------------------
# Wedding stack: Muskan & Sourav
#
# One isolated DigitalOcean stack: its own Postgres cluster, its own Spaces
# bucket and CDN, its own App Platform app, its own DO project, and one CNAME
# under imigrate.com.
#
# Prerequisite: envs/_shared must be applied first (it owns the imigrate.com
# DNS zone and the shared VPC).
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
  description = "Identity of this wedding. Also the subdomain label under apex_domain."
  type        = string
  default     = "muskan-sourav"
}

variable "environment" {
  description = "Deployment environment for this stack."
  type        = string
  default     = "production"
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
  description = "Spaces region slug for the guest-media bucket."
  type        = string
  default     = "blr1"
}

variable "vpc_uuid" {
  description = "UUID of the shared VPC, from the envs/_shared stack output. Null falls back to the region's default VPC."
  type        = string
  default     = null
}

variable "github_repo" {
  description = "owner/name of the Next.js app repository."
  type        = string
  default     = "imigrate-apps/wedding-app"
}

variable "github_branch" {
  description = "Branch App Platform builds from."
  type        = string
  default     = "main"
}

variable "deploy_on_push" {
  description = "Auto-deploy on push. Set false in the run-up to the event."
  type        = bool
  default     = true
}

variable "instance_size_slug" {
  description = "App Platform instance size for the web service."
  type        = string
  default     = "apps-s-1vcpu-1gb"
}

variable "instance_count" {
  description = "App Platform instance count."
  type        = number
  default     = 1
}

variable "db_size" {
  description = "Managed Postgres node size."
  type        = string
  default     = "db-s-1vcpu-1gb"
}

variable "db_node_count" {
  description = "Managed Postgres node count."
  type        = number
  default     = 1
}

variable "custom_domains" {
  description = "Customer-owned domains to attach to the app. DNS for these stays at the customer's registrar."
  type = list(object({
    name     = string
    type     = optional(string, "ALIAS")
    wildcard = optional(bool, false)
  }))
  default = []
}

variable "trusted_ip_addresses" {
  description = "Extra IPv4 addresses/CIDRs allowed through the Postgres firewall, e.g. the office IP used for manual migrations."
  type        = list(string)
  default     = []
}

variable "bucket_force_destroy" {
  description = "Allow destroy of a bucket that still holds guest media."
  type        = bool
  default     = false
}

variable "jwt_secret" {
  description = "Session JWT signing secret. Generate with `openssl rand -base64 48`."
  type        = string
  sensitive   = true
}

variable "msg91_auth_key" {
  description = "MSG91 auth key for guest OTP delivery."
  type        = string
  sensitive   = true
}

variable "msg91_template_id" {
  description = "MSG91 OTP template id."
  type        = string
}

variable "admin_phones" {
  description = "Comma-separated E.164 numbers allowed into the admin console."
  type        = string
  default     = ""
}

variable "app_spaces_access_key_id" {
  description = <<-EOT
    Spaces key id injected into the running app as SPACES_KEY. Required, and
    deliberately separate from spaces_access_id: the app's key should be
    narrower and independently rotatable, and unlike Terraform's own
    credentials it cannot be supplied through the provider's environment
    variables -- the value has to be materialised into the app spec.
  EOT
  type        = string
  sensitive   = true
}

variable "app_spaces_secret_access_key" {
  description = "Spaces secret injected into the running app as SPACES_SECRET. Required; see app_spaces_access_key_id."
  type        = string
  sensitive   = true
}

# ===========================================================================
# Locals
# ===========================================================================

locals {
  site_fqdn = "${var.wedding_slug}.${var.apex_domain}"
  site_url  = "https://${local.site_fqdn}"

  # The bucket must accept browser uploads from the wedding site itself and
  # from any customer-owned domain pointed at the same app.
  cors_origins = distinct(concat(
    [local.site_url],
    [for d in var.custom_domains : "https://${d.name}"],
  ))
}

# ===========================================================================
# DigitalOcean project
#
# One project per wedding, so the DO billing page breaks costs down per
# wedding without any extra tooling.
#
# Resource membership is managed exclusively through
# digitalocean_project_resources: mixing it with the `resources` attribute on
# digitalocean_project makes the two fight over the same API field. For the
# same reason the modules' own `project_id` inputs are left null here.
# ===========================================================================

resource "digitalocean_project" "wedding" {
  name        = "wedding-${var.wedding_slug}-${var.environment}"
  description = "Isolated stack for the ${var.wedding_slug} wedding (${var.environment})."
  purpose     = "Web Application"
  environment = var.environment == "production" ? "Production" : "Staging"
}

resource "digitalocean_project_resources" "wedding" {
  project = digitalocean_project.wedding.id

  resources = [
    module.data.cluster_urn,
    module.data.bucket_urn,
    module.app.app_urn,
  ]
}

# ===========================================================================
# Data tier: Postgres + Spaces + CDN
# ===========================================================================

module "data" {
  source = "../../modules/wedding-data"

  wedding_slug = var.wedding_slug
  environment  = var.environment

  region        = var.region
  spaces_region = var.spaces_region
  vpc_uuid      = var.vpc_uuid

  db_size       = var.db_size
  db_node_count = var.db_node_count

  # Postgres accepts connections from the App Platform app and from nothing
  # else, unless trusted_ip_addresses is populated for a migration run.
  #
  # This creates no dependency cycle: the firewall resource depends on the
  # app, while the app depends on the CLUSTER. Terraform flattens modules, so
  # the graph is resolved per resource, not per module.
  allowed_app_ids      = [module.app.app_id]
  allowed_ip_addresses = var.trusted_ip_addresses

  cors_allowed_origins = local.cors_origins
  bucket_force_destroy = var.bucket_force_destroy
}

# ===========================================================================
# Application tier: App Platform
# ===========================================================================

module "app" {
  source = "../../modules/wedding-app"

  wedding_slug = var.wedding_slug
  environment  = var.environment
  app_region   = var.app_region

  github_repo    = var.github_repo
  github_branch  = var.github_branch
  deploy_on_push = var.deploy_on_push

  instance_size_slug = var.instance_size_slug
  instance_count     = var.instance_count

  primary_domain = local.site_fqdn
  custom_domains = var.custom_domains
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
}

# ===========================================================================
# DNS: one CNAME under imigrate.com
# ===========================================================================

module "dns" {
  source = "../../modules/wedding-dns"

  apex_domain  = var.apex_domain
  wedding_slug = var.wedding_slug

  # default_ingress, not live_url: live_url flips to the custom domain once
  # the certificate issues, which would point the record at itself.
  app_ingress_hostname = module.app.default_ingress

  record_ttl = 300
}

# ===========================================================================
# Outputs
# ===========================================================================

output "app_url" {
  description = "Live URL of the wedding site."
  value       = module.app.live_url
}

output "app_id" {
  description = "App Platform app UUID."
  value       = module.app.app_id
}

output "app_default_ingress" {
  description = "Permanent *.ondigitalocean.app hostname. This is the CNAME target to give a customer attaching their own domain."
  value       = module.app.default_ingress
}

output "site_fqdn" {
  description = "Wedding hostname under the apex domain."
  value       = module.dns.fqdn
}

output "database_uri" {
  description = "Postgres connection URI for the application role."
  value       = module.data.database_uri
  sensitive   = true
}

output "database_host" {
  description = "Public hostname of the Postgres cluster."
  value       = module.data.database_host
}

output "bucket_name" {
  description = "Guest-media Spaces bucket."
  value       = module.data.bucket_name
}

output "cdn_endpoint" {
  description = "Spaces CDN hostname serving guest media."
  value       = module.data.cdn_endpoint
}

output "cdn_url" {
  description = "https:// base URL for guest media."
  value       = module.data.cdn_url
}

output "project_id" {
  description = "UUID of this wedding's DigitalOcean project."
  value       = digitalocean_project.wedding.id
}
