variable "apex_domain" {
  description = <<-EOT
    Apex domain hosted in DigitalOcean DNS, e.g. imigrate.com. This module
    READS the zone with a data source and never creates it -- the zone is a
    singleton owned by envs/_shared. See the module README, "Why the apex is a
    data source".
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.apex_domain))
    error_message = "apex_domain must be a bare domain name -- no scheme, no trailing dot, no subdomain path."
  }
}

variable "wedding_slug" {
  description = "Subdomain label for the wedding, relative to apex_domain. \"muskan-sourav\" produces muskan-sourav.imigrate.com."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])$", var.wedding_slug))
    error_message = "wedding_slug must be a valid single DNS label: lowercase alphanumerics and hyphens, not starting or ending with a hyphen."
  }
}

variable "subdomain_override" {
  description = "DNS label to use instead of wedding_slug. Lets a non-production stack live at e.g. sandbox-staging.imigrate.com while keeping wedding_slug as the identity used everywhere else."
  type        = string
  default     = null

  validation {
    condition     = var.subdomain_override == null || can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])$", coalesce(var.subdomain_override, "xxx")))
    error_message = "subdomain_override must be a valid single DNS label: lowercase alphanumerics and hyphens, not starting or ending with a hyphen."
  }
}

variable "app_ingress_hostname" {
  description = <<-EOT
    The App Platform default ingress to point the wedding subdomain at, e.g.
    muskan-sourav-production-ab12c.ondigitalocean.app. A leading https:// and a
    trailing slash or dot are tolerated and stripped. Use the app's
    default_ingress, never its live_url: live_url flips to the custom domain
    once the certificate issues, which would make the record point at itself.
  EOT
  type        = string
}

variable "record_ttl" {
  description = "TTL in seconds for the wedding's records. Keep it low while a wedding is being set up so a cutover is fast; raise it once the site is stable."
  type        = number
  default     = 300

  validation {
    condition     = var.record_ttl >= 30 && var.record_ttl <= 604800
    error_message = "record_ttl must be between 30 and 604800 seconds."
  }
}

variable "create_wildcard" {
  description = "Also create *.<slug>.<apex> pointing at the same app. Needed only if the app serves per-guest or per-event subdomains."
  type        = bool
  default     = false
}

variable "media_subdomain" {
  description = "Optional label for a CDN vanity hostname under the wedding subdomain, e.g. \"media\" produces media.<slug>.<apex>. Requires media_cdn_endpoint."
  type        = string
  default     = null
}

variable "media_cdn_endpoint" {
  description = "Spaces CDN endpoint hostname the media subdomain should CNAME to. Required when media_subdomain is set."
  type        = string
  default     = null
}

variable "extra_records" {
  description = <<-EOT
    Additional records to create under the wedding subdomain, keyed by an
    arbitrary stable identifier (the map key becomes part of the Terraform
    resource address, so renaming a key destroys and recreates the record).
    `name` is relative to the apex, exactly as DigitalOcean expects it -- e.g.
    name = "mail.muskan-sourav".
  EOT
  type = map(object({
    name     = string
    type     = string
    value    = string
    ttl      = optional(number)
    priority = optional(number)
    weight   = optional(number)
    port     = optional(number)
    flags    = optional(number)
    tag      = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for r in var.extra_records :
      contains(["A", "AAAA", "CAA", "CNAME", "MX", "NS", "TXT", "SRV"], r.type)
    ])
    error_message = "extra_records[*].type must be one of A, AAAA, CAA, CNAME, MX, NS, TXT, SRV."
  }
}
