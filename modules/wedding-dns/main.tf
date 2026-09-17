terraform {
  required_version = ">= 1.9"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.43"
    }
  }
}

# ---------------------------------------------------------------------------
# The apex zone is read, never created.
#
# `digitalocean_domain` is a zone, and a zone is a singleton per account. If
# every wedding stack declared `resource "digitalocean_domain" "apex"` then:
#   - the second `terraform apply` would fail with "domain already exists", and
#   - if it were imported instead, a `terraform destroy` of ONE finished
#     wedding would delete the zone for imigrate.com and take every other
#     wedding offline with it.
#
# So the zone is created exactly once, by envs/_shared, and every wedding
# stack reads it here. The data source doubles as a guard: if someone points a
# stack at a domain that is not in DigitalOcean DNS, the plan fails at read
# time with a clear error instead of silently creating orphan records.
# ---------------------------------------------------------------------------
data "digitalocean_domain" "apex" {
  name = var.apex_domain
}

locals {
  subdomain = coalesce(var.subdomain_override, var.wedding_slug)
  fqdn      = "${local.subdomain}.${var.apex_domain}"

  # Tolerate being handed either a URL or a bare hostname, and normalise to the
  # trailing-dot FQDN that DigitalOcean requires in a CNAME value.
  ingress_host = trimsuffix(
    trimsuffix(
      replace(replace(var.app_ingress_hostname, "https://", ""), "http://", ""),
      "/",
    ),
    ".",
  )
  ingress_cname_value = "${local.ingress_host}."

  media_cname_value = var.media_cdn_endpoint == null ? null : "${trimsuffix(replace(var.media_cdn_endpoint, "https://", ""), ".")}."
}

# The wedding subdomain itself. CNAME rather than A: App Platform ingress IPs
# are not stable and are not documented as static.
resource "digitalocean_record" "app" {
  domain = data.digitalocean_domain.apex.name
  type   = "CNAME"
  name   = local.subdomain
  value  = local.ingress_cname_value
  ttl    = var.record_ttl

  lifecycle {
    precondition {
      condition     = length(local.ingress_host) > 0
      error_message = "app_ingress_hostname resolved to an empty hostname; pass the wedding-app module's default_ingress output."
    }

    precondition {
      condition     = !endswith(local.ingress_host, var.apex_domain)
      error_message = "app_ingress_hostname points back inside ${var.apex_domain}, which would create a CNAME loop. Pass the app's default_ingress (*.ondigitalocean.app), not its live_url."
    }
  }
}

resource "digitalocean_record" "wildcard" {
  count = var.create_wildcard ? 1 : 0

  domain = data.digitalocean_domain.apex.name
  type   = "CNAME"
  name   = "*.${local.subdomain}"
  value  = local.ingress_cname_value
  ttl    = var.record_ttl
}

# Vanity hostname for the Spaces CDN, e.g. media.muskan-sourav.imigrate.com.
# Only useful alongside wedding-data's cdn_custom_domain + cdn_certificate_name.
resource "digitalocean_record" "media" {
  count = var.media_subdomain == null ? 0 : 1

  domain = data.digitalocean_domain.apex.name
  type   = "CNAME"
  name   = "${var.media_subdomain}.${local.subdomain}"
  value  = local.media_cname_value
  ttl    = var.record_ttl

  lifecycle {
    precondition {
      condition     = var.media_cdn_endpoint != null
      error_message = "media_subdomain requires media_cdn_endpoint; pass the wedding-data module's cdn_endpoint output."
    }
  }
}

resource "digitalocean_record" "extra" {
  for_each = var.extra_records

  domain = data.digitalocean_domain.apex.name
  type   = each.value.type
  name   = each.value.name
  value  = each.value.value
  ttl    = coalesce(each.value.ttl, var.record_ttl)

  priority = each.value.priority
  weight   = each.value.weight
  port     = each.value.port
  flags    = each.value.flags
  tag      = each.value.tag
}
