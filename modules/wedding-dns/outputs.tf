output "fqdn" {
  description = "Fully qualified hostname for the wedding, e.g. muskan-sourav.imigrate.com."
  value       = local.fqdn
}

output "site_url" {
  description = "https:// origin for the wedding, ready to pass to the app as NEXT_PUBLIC_SITE_URL."
  value       = "https://${local.fqdn}"
}

output "apex_domain" {
  description = "Name of the apex zone the records were created in."
  value       = data.digitalocean_domain.apex.name
}

output "apex_domain_urn" {
  description = "URN of the apex zone, for attaching it to a DigitalOcean project."
  value       = data.digitalocean_domain.apex.urn
}

output "record_id" {
  description = "ID of the CNAME record pointing the wedding subdomain at App Platform."
  value       = digitalocean_record.app.id
}

output "record_fqdn" {
  description = "FQDN as reported back by DigitalOcean for the wedding's CNAME record."
  value       = digitalocean_record.app.fqdn
}

output "cname_target" {
  description = "The CNAME value the wedding subdomain points at. This is also the exact value to hand a customer who is attaching their own domain at their own registrar."
  value       = local.ingress_cname_value
}

output "media_fqdn" {
  description = "Vanity CDN hostname, or null when media_subdomain is not configured."
  value       = var.media_subdomain == null ? null : "${var.media_subdomain}.${local.fqdn}"
}

output "extra_record_fqdns" {
  description = "Map of extra_records key to the FQDN DigitalOcean created."
  value       = { for k, r in digitalocean_record.extra : k => r.fqdn }
}
