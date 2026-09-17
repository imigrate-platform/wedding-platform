terraform {
  required_version = ">= 1.9"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.43"
    }
  }
}

locals {
  # Every resource carries the wedding slug and the environment. Only a few DO
  # resource types actually accept tags (see README "Tagging & labelling"), so
  # the same two facts are also baked into every resource NAME, which is the
  # only label Spaces, CDN and App Platform expose.
  name_prefix = "${var.wedding_slug}-${var.environment}"

  tags = distinct(concat(
    [
      "imigrate",
      "wedding:${var.wedding_slug}",
      "env:${var.environment}",
      "component:data",
    ],
    var.extra_tags,
  ))

  bucket_name = coalesce(var.bucket_name_override, "${var.wedding_slug}-media-${var.environment}")

  # App Platform reaches Managed Postgres over the PUBLIC endpoint and is
  # authorised by the `type = "app"` trusted-source rule below, so the public
  # host is the correct default. The private host is only reachable from inside
  # the VPC (droplets, Kubernetes nodes).
  db_host = var.use_private_host_for_app ? digitalocean_database_cluster.this.private_host : digitalocean_database_cluster.this.host

  # sslmode=require is mandatory: DigitalOcean Managed Postgres refuses
  # plaintext connections.
  database_uri = format(
    "postgresql://%s:%s@%s:%d/%s?sslmode=require",
    digitalocean_database_user.app.name,
    urlencode(digitalocean_database_user.app.password),
    local.db_host,
    digitalocean_database_cluster.this.port,
    digitalocean_database_db.app.name,
  )

  spaces_endpoint = "https://${var.spaces_region}.digitaloceanspaces.com"

  firewall_rules = concat(
    [for app_id in var.allowed_app_ids : { type = "app", value = app_id }],
    [for ip in var.allowed_ip_addresses : { type = "ip_addr", value = ip }],
    [for tag in var.allowed_tags : { type = "tag", value = tag }],
  )

  manage_firewall = var.enable_database_firewall && length(local.firewall_rules) > 0
}

# ---------------------------------------------------------------------------
# Managed Postgres
# ---------------------------------------------------------------------------

resource "digitalocean_database_cluster" "this" {
  name       = "${local.name_prefix}-pg"
  engine     = "pg"
  version    = var.db_engine_version
  size       = var.db_size
  region     = var.region
  node_count = var.db_node_count

  storage_size_mib     = var.db_storage_size_mib
  private_network_uuid = var.vpc_uuid
  project_id           = var.project_id

  tags = local.tags

  maintenance_window {
    day  = var.maintenance_window.day
    hour = var.maintenance_window.hour
  }

  lifecycle {
    # NOTE: `prevent_destroy` is deliberately NOT set here. It only accepts a
    # literal, so switching it on would also make `terraform destroy` of a
    # finished or staging wedding impossible. Protection instead comes from:
    #   - DigitalOcean's own daily backups + 7-day point-in-time recovery,
    #   - no destroy path in either GitHub Actions workflow,
    #   - the mandatory `terraform plan -destroy` review in README
    #     "Decommissioning a wedding".
    precondition {
      condition     = var.db_node_count == 1 || var.environment == "production"
      error_message = "Multi-node Postgres clusters are only justified for production stacks; staging should stay single node."
    }
  }
}

# The default `defaultdb` database that ships with every cluster is left alone;
# the application gets its own.
resource "digitalocean_database_db" "app" {
  cluster_id = digitalocean_database_cluster.this.id
  name       = var.database_name
}

# DigitalOcean generates and owns this password. Terraform never sets it, which
# keeps a chosen secret out of the configuration -- though the generated value
# does land in state (see README "Secrets and state").
resource "digitalocean_database_user" "app" {
  cluster_id = digitalocean_database_cluster.this.id
  name       = var.database_user
}

# Trusted sources. With this resource present the cluster accepts connections
# ONLY from the listed sources; without it, anything on the internet with the
# password can connect.
resource "digitalocean_database_firewall" "this" {
  count = local.manage_firewall ? 1 : 0

  cluster_id = digitalocean_database_cluster.this.id

  dynamic "rule" {
    for_each = local.firewall_rules
    content {
      type  = rule.value.type
      value = rule.value.value
    }
  }
}

# ---------------------------------------------------------------------------
# Spaces bucket for guest media
#
# ACL MODEL: the BUCKET is private; individual objects are made public at
# upload time by the application (S3 `x-amz-acl: public-read`). A public bucket
# would also expose ListObjects, which would let anyone enumerate every photo
# of every guest. See README "Bucket ACL model".
# ---------------------------------------------------------------------------

resource "digitalocean_spaces_bucket" "media" {
  name          = local.bucket_name
  region        = var.spaces_region
  acl           = "private"
  force_destroy = var.bucket_force_destroy

  versioning {
    enabled = var.bucket_versioning_enabled
  }

  lifecycle_rule {
    id      = "reap-incomplete-multipart-uploads"
    enabled = true

    abort_incomplete_multipart_upload_days = var.abort_incomplete_multipart_upload_days
  }

  dynamic "lifecycle_rule" {
    for_each = var.bucket_versioning_enabled ? [1] : []
    content {
      id      = "expire-noncurrent-versions"
      enabled = true

      noncurrent_version_expiration {
        days = var.noncurrent_version_expiration_days
      }
    }
  }
}

# The inline `cors_rule` block on digitalocean_spaces_bucket is deprecated and
# cannot express expose_headers, which browsers need in order to read ETag back
# from a multipart upload. Use the dedicated resource.
resource "digitalocean_spaces_bucket_cors_configuration" "media" {
  bucket = digitalocean_spaces_bucket.media.id
  region = var.spaces_region

  cors_rule {
    id              = "browser-uploads"
    allowed_headers = ["*"]
    allowed_methods = var.cors_allowed_methods
    allowed_origins = var.cors_allowed_origins
    expose_headers  = ["ETag", "Content-Length", "Content-Type"]
    max_age_seconds = var.cors_max_age_seconds
  }
}

# ---------------------------------------------------------------------------
# CDN in front of the bucket
#
# The Spaces CDN serves only objects that are themselves public-read, which is
# exactly the private-bucket / public-object model above. Bandwidth served here
# is billed against the Spaces transfer allowance, not separately.
# ---------------------------------------------------------------------------

resource "digitalocean_cdn" "media" {
  origin = digitalocean_spaces_bucket.media.bucket_domain_name
  ttl    = var.cdn_ttl

  custom_domain    = var.cdn_custom_domain
  certificate_name = var.cdn_certificate_name

  lifecycle {
    precondition {
      condition     = var.cdn_custom_domain == null || var.cdn_certificate_name != null
      error_message = "cdn_custom_domain requires cdn_certificate_name: DigitalOcean will not serve a vanity CDN hostname without a certificate."
    }
  }
}
