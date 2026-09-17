# ----------------------------- postgres ------------------------------------

output "cluster_id" {
  description = "UUID of the Managed Postgres cluster."
  value       = digitalocean_database_cluster.this.id
}

output "cluster_name" {
  description = "Name of the Managed Postgres cluster as shown in the DigitalOcean control panel."
  value       = digitalocean_database_cluster.this.name
}

output "cluster_urn" {
  description = "URN of the Postgres cluster, for attaching it to a DigitalOcean project."
  value       = digitalocean_database_cluster.this.urn
}

output "database_uri" {
  description = "Full libpq connection URI for the application role, including sslmode=require. Feed this straight into the app's DATABASE_URL."
  value       = local.database_uri
  sensitive   = true
}

output "database_host" {
  description = "Public hostname of the Postgres cluster."
  value       = digitalocean_database_cluster.this.host
}

output "database_private_host" {
  description = "VPC-private hostname of the Postgres cluster. Only resolvable from inside the VPC."
  value       = digitalocean_database_cluster.this.private_host
}

output "database_port" {
  description = "Postgres port."
  value       = digitalocean_database_cluster.this.port
}

output "database_name" {
  description = "Name of the logical database created for the application."
  value       = digitalocean_database_db.app.name
}

output "database_user" {
  description = "Name of the application role."
  value       = digitalocean_database_user.app.name
}

output "database_password" {
  description = "DigitalOcean-generated password for the application role. Exposed for migration tooling; prefer database_uri."
  value       = digitalocean_database_user.app.password
  sensitive   = true
}

output "firewall_managed" {
  description = "Whether a trusted-sources firewall is actually being managed on this cluster. False means the cluster accepts connections from anywhere."
  value       = local.manage_firewall
}

# ----------------------------- spaces --------------------------------------

output "bucket_name" {
  description = "Name of the Spaces bucket holding guest media."
  value       = digitalocean_spaces_bucket.media.name
}

output "bucket_region" {
  description = "Spaces region slug the bucket lives in."
  value       = var.spaces_region
}

output "bucket_domain_name" {
  description = "Origin hostname of the bucket, e.g. slug-media-production.blr1.digitaloceanspaces.com."
  value       = digitalocean_spaces_bucket.media.bucket_domain_name
}

output "bucket_endpoint" {
  description = "S3 API endpoint URL the application's S3 client should be configured with."
  value       = local.spaces_endpoint
}

output "bucket_urn" {
  description = "URN of the bucket, for attaching it to a DigitalOcean project."
  value       = digitalocean_spaces_bucket.media.urn
}

# ----------------------------- cdn -----------------------------------------

output "cdn_id" {
  description = "ID of the Spaces CDN endpoint."
  value       = digitalocean_cdn.media.id
}

output "cdn_endpoint" {
  description = "CDN hostname serving the bucket, e.g. slug-media-production.blr1.cdn.digitaloceanspaces.com."
  value       = digitalocean_cdn.media.endpoint
}

output "cdn_url" {
  description = "Fully qualified https:// base URL for guest media. Uses the vanity domain when one is configured."
  value       = "https://${coalesce(var.cdn_custom_domain, digitalocean_cdn.media.endpoint)}"
}
