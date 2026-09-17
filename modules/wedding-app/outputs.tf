output "app_id" {
  description = "UUID of the App Platform app. Feed this into wedding-data's allowed_app_ids to open the Postgres firewall for it."
  value       = digitalocean_app.this.id
}

output "app_name" {
  description = "App Platform app name as shown in the DigitalOcean control panel."
  value       = digitalocean_app.this.spec[0].name
}

output "app_urn" {
  description = "URN of the app, for attaching it to a DigitalOcean project."
  value       = digitalocean_app.this.urn
}

output "live_url" {
  description = "The URL the app is actually serving on. Becomes the primary domain once its certificate has issued; until then, the default *.ondigitalocean.app ingress."
  value       = digitalocean_app.this.live_url
}

output "live_domain" {
  description = "Hostname portion of live_url."
  value       = digitalocean_app.this.live_domain
}

output "default_ingress" {
  description = "The permanent *.ondigitalocean.app URL. This is the CNAME target for any custom domain, and it never changes -- unlike live_url."
  value       = digitalocean_app.this.default_ingress
}

output "default_ingress_hostname" {
  description = "default_ingress with the scheme and any trailing slash stripped, ready to drop into a CNAME record value."
  value       = trimsuffix(replace(digitalocean_app.this.default_ingress, "https://", ""), "/")
}

output "active_deployment_id" {
  description = "ID of the deployment currently serving traffic. Useful for correlating an incident with a specific build."
  value       = digitalocean_app.this.active_deployment_id
}

output "domains" {
  description = "Hostnames registered on the app, in the order they were declared."
  value       = [for d in local.domains : d.name]
}
