# ---------------------------------------------------------------------------
# Canonical variable contract for a wedding stack (scaffold copy).
# envs/<slug>/main.tf declares the same set. Keep them in sync when you add a
# new input -- `make new-wedding` (see README) copies this file.
# ---------------------------------------------------------------------------

# ----------------------------- credentials ---------------------------------

variable "do_token" {
  description = "DigitalOcean API token with read/write scope. Leave null to read DIGITALOCEAN_TOKEN from the environment."
  type        = string
  default     = null
  sensitive   = true
}

variable "spaces_access_id" {
  description = "Spaces (S3-compatible) access key id used by Terraform to manage buckets. Leave null to read SPACES_ACCESS_KEY_ID from the environment."
  type        = string
  default     = null
  sensitive   = true
}

variable "spaces_secret_key" {
  description = "Spaces (S3-compatible) secret key used by Terraform to manage buckets. Leave null to read SPACES_SECRET_ACCESS_KEY from the environment."
  type        = string
  default     = null
  sensitive   = true
}

# ----------------------------- identity ------------------------------------

variable "wedding_slug" {
  description = "Short DNS-safe identifier for this wedding. Becomes the subdomain, the resource name prefix and the DO tag suffix. Example: \"muskan-sourav\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{1,30}[a-z0-9])$", var.wedding_slug))
    error_message = "wedding_slug must be 3-32 chars, lowercase alphanumerics and hyphens, and must not start or end with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment for this stack. Drives DO project environment, tags and alerting posture."
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "environment must be one of: development, staging, production."
  }
}

# ----------------------------- placement -----------------------------------

variable "region" {
  description = "DigitalOcean datacenter slug for the Managed Postgres cluster and the VPC. Example: \"blr1\"."
  type        = string
  default     = "blr1"
}

variable "app_region" {
  description = "App Platform region slug. These are SHORTER than datacenter slugs (\"blr\", not \"blr1\")."
  type        = string
  default     = "blr"

  validation {
    condition     = contains(["ams", "blr", "fra", "lon", "nyc", "sfo", "sgp", "syd", "tor"], var.app_region)
    error_message = "app_region must be a valid App Platform region slug: ams, blr, fra, lon, nyc, sfo, sgp, syd, tor."
  }
}

variable "spaces_region" {
  description = "Spaces region slug for the guest-media bucket. Spaces is not available in every datacenter -- verify before changing."
  type        = string
  default     = "blr1"
}

variable "vpc_uuid" {
  description = "UUID of the shared VPC the Postgres cluster is placed in. Read from the envs/_shared stack output."
  type        = string
  default     = null
}

# ----------------------------- dns -----------------------------------------

variable "apex_domain" {
  description = "Apex domain hosted in DigitalOcean DNS. The zone itself is created once by envs/_shared; every wedding stack only reads it."
  type        = string
  default     = "imigrate.com"
}

variable "custom_domains" {
  description = <<-EOT
    Customer-owned domains to attach to the App Platform app, e.g. the couple's
    own muskansouravwedding.com. DNS for these lives at the customer's
    registrar, so Terraform only registers the domain with App Platform (which
    provisions the TLS certificate); the CNAME is the customer's job.
    `type` is one of PRIMARY or ALIAS.
  EOT
  type = list(object({
    name     = string
    type     = optional(string, "ALIAS")
    wildcard = optional(bool, false)
  }))
  default = []
}

# ----------------------------- application ---------------------------------

variable "github_repo" {
  description = "owner/name of the Next.js application repository deployed by App Platform."
  type        = string
  default     = "imigrate-apps/wedding-app"
}

variable "github_branch" {
  description = "Branch App Platform builds and auto-deploys from."
  type        = string
  default     = "main"
}

variable "deploy_on_push" {
  description = "Let App Platform rebuild automatically when github_branch moves. Disable for weddings that are live and frozen."
  type        = bool
  default     = true
}

variable "instance_size_slug" {
  description = "App Platform instance size for the web service. apps-s-1vcpu-1gb is the Basic tier default."
  type        = string
  default     = "apps-s-1vcpu-1gb"
}

variable "instance_count" {
  description = "Number of App Platform instances for the web service."
  type        = number
  default     = 1
}

# ----------------------------- database ------------------------------------

variable "db_size" {
  description = "Managed Postgres node size. db-s-1vcpu-1gb is the smallest single-node option."
  type        = string
  default     = "db-s-1vcpu-1gb"
}

variable "db_node_count" {
  description = "Managed Postgres node count. 1 = no standby (acceptable for a single wedding), 2+ adds HA and cost."
  type        = number
  default     = 1
}

# ----------------------------- app secrets ---------------------------------

variable "jwt_secret" {
  description = "Signing secret for the app's session JWTs. Generate with `openssl rand -base64 48`."
  type        = string
  sensitive   = true
}

variable "msg91_auth_key" {
  description = "MSG91 auth key used for guest OTP / WhatsApp notifications."
  type        = string
  sensitive   = true
}

variable "msg91_template_id" {
  description = "MSG91 template id for the OTP message. Not a secret, but environment specific."
  type        = string
}

variable "admin_phones" {
  description = "Comma-separated E.164 phone numbers allowed into the wedding admin console."
  type        = string
  default     = ""
}

variable "app_spaces_access_key_id" {
  description = "Spaces key id injected into the running app as SPACES_KEY. Required: unlike Terraform's own credentials this value has to be materialised into the app spec, so it cannot come from the provider's environment variables."
  type        = string
  sensitive   = true
}

variable "app_spaces_secret_access_key" {
  description = "Spaces secret injected into the running app as SPACES_SECRET. Required; see app_spaces_access_key_id."
  type        = string
  sensitive   = true
}

# ----------------------------- operations ----------------------------------

variable "trusted_ip_addresses" {
  description = "Additional IPv4 addresses/CIDRs allowed through the Postgres firewall, e.g. the office IP used for manual migrations."
  type        = list(string)
  default     = []
}

variable "bucket_force_destroy" {
  description = "Allow `terraform destroy` to delete a bucket that still holds guest media. Keep false for live weddings."
  type        = bool
  default     = false
}
