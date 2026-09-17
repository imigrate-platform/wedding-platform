# ----------------------------- identity ------------------------------------

variable "wedding_slug" {
  description = "DNS-safe identifier for the wedding. Prefixes the app name and the service name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{1,30}[a-z0-9])$", var.wedding_slug))
    error_message = "wedding_slug must be 3-32 chars, lowercase alphanumerics and hyphens, and must not start or end with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment. Folded into the app name and surfaced to the running app as APP_ENV."
  type        = string

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "environment must be one of: development, staging, production."
  }
}

variable "app_name_override" {
  description = "Explicit App Platform app name. Null derives `<slug>-<environment>`. App names are unique per DO account."
  type        = string
  default     = null
}

variable "project_id" {
  description = "UUID of the DigitalOcean project the app is filed under. Null leaves it in the account default project."
  type        = string
  default     = null
}

variable "app_region" {
  description = "App Platform region slug. Shorter than datacenter slugs: \"blr\", not \"blr1\"."
  type        = string
  default     = "blr"

  validation {
    condition     = contains(["ams", "blr", "fra", "lon", "nyc", "sfo", "sgp", "syd", "tor"], var.app_region)
    error_message = "app_region must be a valid App Platform region slug: ams, blr, fra, lon, nyc, sfo, sgp, syd, tor."
  }
}

# ----------------------------- source --------------------------------------

variable "github_repo" {
  description = "owner/name of the Next.js repository App Platform builds. The DigitalOcean GitHub App must already be authorised on this repo."
  type        = string
  default     = "imigrate-apps/wedding-app"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.github_repo))
    error_message = "github_repo must be in owner/name form, without a URL scheme or a .git suffix."
  }
}

variable "github_branch" {
  description = "Branch App Platform builds from."
  type        = string
  default     = "main"
}

variable "deploy_on_push" {
  description = "Rebuild automatically when github_branch moves. Turn this off once a wedding is live so nobody ships to a running event by accident."
  type        = bool
  default     = true
}

variable "source_dir" {
  description = "Subdirectory of the repository containing the Next.js app. \"/\" for a single-app repo."
  type        = string
  default     = "/"
}

# ----------------------------- runtime -------------------------------------

variable "service_name" {
  description = "Name of the App Platform service component. Also the hostname other components would use to reach it."
  type        = string
  default     = "web"
}

variable "instance_size_slug" {
  description = "App Platform instance size for the web service. apps-s-1vcpu-1gb is the Basic tier default."
  type        = string
  default     = "apps-s-1vcpu-1gb"
}

variable "instance_count" {
  description = "Fixed instance count. Ignored when autoscaling is enabled."
  type        = number
  default     = 1

  validation {
    condition     = var.instance_count >= 1
    error_message = "instance_count must be at least 1."
  }
}

variable "autoscaling" {
  description = "Optional CPU-target autoscaling. Null pins the service to instance_count. Note: autoscaling is not offered on the Basic instance tiers."
  type = object({
    min_instance_count = number
    max_instance_count = number
    cpu_percent        = optional(number, 70)
  })
  default = null
}

variable "http_port" {
  description = "Port the Next.js standalone server listens on inside the container."
  type        = number
  default     = 3000
}

variable "build_command" {
  description = <<-EOT
    Build step for `output: "standalone"`. `next build` writes a self-contained
    server to .next/standalone but deliberately does NOT copy ./public or
    .next/static into it, so those have to be copied by hand or every image,
    font and CSS chunk 404s at runtime. Override only if the app repo's
    package.json already does this.
  EOT
  type        = string
  default     = "npm run build && cp -r public .next/standalone/public && cp -r .next/static .next/standalone/.next/static"
}

variable "run_command" {
  description = "Start command. The standalone server binds to HOSTNAME, which must be 0.0.0.0 for App Platform's health checks and router to reach it."
  type        = string
  default     = "HOSTNAME=0.0.0.0 node .next/standalone/server.js"
}

variable "health_check_path" {
  description = "HTTP path App Platform polls for readiness. Must return 2xx without touching Postgres, or a database blip will roll back a good deploy."
  type        = string
  default     = "/api/health"
}

variable "health_check" {
  description = "Health check tuning. initial_delay_seconds must exceed the app's cold-start time."
  type = object({
    initial_delay_seconds = optional(number, 20)
    period_seconds        = optional(number, 10)
    timeout_seconds       = optional(number, 5)
    success_threshold     = optional(number, 1)
    failure_threshold     = optional(number, 5)
  })
  default = {}
}

# ----------------------------- domains -------------------------------------

variable "primary_domain" {
  description = "Primary hostname for the app, e.g. muskan-sourav.imigrate.com. Null leaves the app on its *.ondigitalocean.app default ingress."
  type        = string
  default     = null
}

variable "custom_domains" {
  description = <<-EOT
    Customer-owned domains to attach in addition to primary_domain. `zone` is
    intentionally never set on any domain block: this platform manages DNS
    explicitly through the wedding-dns module (for imigrate.com) or hands the
    CNAME target to the customer (for their own registrar). See the module
    README, "Why we never set `zone`".
  EOT
  type = list(object({
    name     = string
    type     = optional(string, "ALIAS")
    wildcard = optional(bool, false)
  }))
  default = []

  validation {
    condition     = alltrue([for d in var.custom_domains : contains(["PRIMARY", "ALIAS"], d.type)])
    error_message = "custom_domains[*].type must be PRIMARY or ALIAS."
  }
}

# ----------------------------- app config ----------------------------------

variable "site_url" {
  description = "Public https:// origin the app serves itself from. Baked into the build as NEXT_PUBLIC_SITE_URL and used for absolute links in invitations and OTP messages."
  type        = string
}

variable "database_url" {
  description = "Postgres connection URI, from the wedding-data module. Injected as a SECRET env var."
  type        = string
  sensitive   = true
}

variable "spaces_key" {
  description = "Spaces access key id the app uses to upload guest media. Injected as a SECRET env var."
  type        = string
  sensitive   = true
}

variable "spaces_secret" {
  description = "Spaces secret access key the app uses to upload guest media. Injected as a SECRET env var."
  type        = string
  sensitive   = true
}

variable "spaces_bucket" {
  description = "Name of the guest-media bucket."
  type        = string
}

variable "spaces_region" {
  description = "Spaces region slug the bucket lives in."
  type        = string
}

variable "spaces_cdn_url" {
  description = "https:// base URL of the Spaces CDN endpoint serving guest media."
  type        = string
}

variable "jwt_secret" {
  description = "Signing secret for guest and admin session JWTs. Injected as a SECRET env var."
  type        = string
  sensitive   = true
}

variable "msg91_auth_key" {
  description = "MSG91 auth key for OTP and WhatsApp delivery. Injected as a SECRET env var."
  type        = string
  sensitive   = true
}

variable "msg91_template_id" {
  description = "MSG91 template id used for the guest OTP message."
  type        = string
}

variable "admin_phones" {
  description = "Comma-separated E.164 phone numbers permitted to sign in to the wedding admin console."
  type        = string
  default     = ""
}

variable "extra_env" {
  description = <<-EOT
    Additional NON-SECRET environment variables, keyed by env var name. This
    map is not marked sensitive because Terraform cannot iterate a sensitive
    value with `for_each`; put anything confidential in extra_secret_env
    instead.
  EOT
  type = map(object({
    value = string
    scope = optional(string, "RUN_TIME")
  }))
  default = {}

  validation {
    condition     = alltrue([for e in var.extra_env : contains(["RUN_TIME", "BUILD_TIME", "RUN_AND_BUILD_TIME"], e.scope)])
    error_message = "extra_env[*].scope must be RUN_TIME, BUILD_TIME or RUN_AND_BUILD_TIME."
  }
}

variable "extra_secret_env" {
  description = <<-EOT
    Additional SECRET environment variables, keyed by env var name. Rendered
    with `type = "SECRET"` so DigitalOcean encrypts them at rest and masks them
    in the control panel. Names are treated as non-sensitive (they have to be,
    to drive `for_each`); only the values are protected.
  EOT
  type        = map(string)
  default     = {}
  sensitive   = true
}

# ----------------------------- operations ----------------------------------

variable "alert_rules" {
  description = "App-level alert rules to enable. DEPLOYMENT_FAILED catches a broken build; DOMAIN_FAILED catches a certificate or DNS problem on the wedding subdomain."
  type        = list(string)
  default     = ["DEPLOYMENT_FAILED", "DOMAIN_FAILED"]
}

variable "service_alerts" {
  description = "Optional per-service threshold alerts, e.g. CPU_UTILIZATION above 80% for five minutes."
  type = list(object({
    rule     = string
    operator = string
    value    = number
    window   = string
    disabled = optional(bool, false)
  }))
  default = []
}

variable "app_features" {
  description = "App Platform feature flags. \"buildpack-stack=ubuntu-22\" pins the build image so a DigitalOcean stack rollout cannot silently change the Node version under a live wedding."
  type        = list(string)
  default     = ["buildpack-stack=ubuntu-22"]
}

variable "app_deploy_timeout" {
  description = "How long to wait for an App Platform deployment to go live before Terraform gives up. A cold Next.js build on the Basic tier regularly takes 5-10 minutes."
  type        = string
  default     = "30m"
}
