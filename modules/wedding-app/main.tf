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
  app_name = coalesce(var.app_name_override, "${var.wedding_slug}-${var.environment}")

  # digitalocean_app exposes no `tags` argument, so the wedding slug and
  # environment are carried by the app name and by the per-wedding DO project
  # the app is filed under. See the module README, "Tagging & labelling".

  # primary_domain first, then any customer-owned domains.
  domains = concat(
    var.primary_domain == null ? [] : [{
      name     = var.primary_domain
      type     = "PRIMARY"
      wildcard = false
    }],
    var.custom_domains,
  )

  # Names are safe to expose; only the values are sensitive. for_each cannot
  # consume a sensitive collection, so the keys are unwrapped explicitly.
  secret_env_keys = toset(nonsensitive(keys(var.extra_secret_env)))
}

resource "digitalocean_app" "this" {
  project_id = var.project_id

  spec {
    name     = local.app_name
    region   = var.app_region
    features = var.app_features

    # -------------------------------------------------------------------
    # Alerts. These are app-scoped (as opposed to the threshold alerts on
    # the service below) and are the two that matter for a wedding site:
    # a build that never shipped, and a domain whose certificate never
    # issued -- both of which otherwise present as "the site is down" on
    # the morning of the event.
    # -------------------------------------------------------------------
    dynamic "alert" {
      for_each = toset(var.alert_rules)
      content {
        rule = alert.value
      }
    }

    # -------------------------------------------------------------------
    # Domains. `zone` is never set: see README "Why we never set zone".
    # -------------------------------------------------------------------
    dynamic "domain" {
      for_each = local.domains
      content {
        name     = domain.value.name
        type     = domain.value.type
        wildcard = domain.value.wildcard
      }
    }

    service {
      name = var.service_name

      instance_size_slug = var.instance_size_slug
      instance_count     = var.autoscaling == null ? var.instance_count : null

      # Next.js standalone: `next build` emits .next/standalone/server.js and
      # the build_command default copies ./public and .next/static beside it.
      build_command = var.build_command
      run_command   = var.run_command
      source_dir    = var.source_dir
      http_port     = var.http_port

      environment_slug = "node-js"

      github {
        repo           = var.github_repo
        branch         = var.github_branch
        deploy_on_push = var.deploy_on_push
      }

      health_check {
        http_path             = var.health_check_path
        initial_delay_seconds = var.health_check.initial_delay_seconds
        period_seconds        = var.health_check.period_seconds
        timeout_seconds       = var.health_check.timeout_seconds
        success_threshold     = var.health_check.success_threshold
        failure_threshold     = var.health_check.failure_threshold
      }

      dynamic "autoscaling" {
        for_each = var.autoscaling == null ? [] : [var.autoscaling]
        content {
          min_instance_count = autoscaling.value.min_instance_count
          max_instance_count = autoscaling.value.max_instance_count

          metrics {
            cpu {
              percent = autoscaling.value.cpu_percent
            }
          }
        }
      }

      dynamic "alert" {
        for_each = var.service_alerts
        content {
          rule     = alert.value.rule
          operator = alert.value.operator
          value    = alert.value.value
          window   = alert.value.window
          disabled = alert.value.disabled
        }
      }

      routes {
        path = "/"
      }

      # =================================================================
      # ENVIRONMENT
      #
      # scope semantics:
      #   RUN_TIME            available to the running container only
      #   BUILD_TIME          available to the buildpack only
      #   RUN_AND_BUILD_TIME  both -- required for NEXT_PUBLIC_* because
      #                       Next.js inlines those at build time, and the
      #                       server runtime reads them again
      #
      # type semantics:
      #   SECRET   encrypted at rest by DigitalOcean, masked in the UI
      #   GENERAL  stored and displayed in cleartext
      # =================================================================

      # ---- secrets ----------------------------------------------------
      env {
        key   = "DATABASE_URL"
        value = var.database_url
        scope = "RUN_TIME"
        type  = "SECRET"
      }

      env {
        key   = "SPACES_KEY"
        value = var.spaces_key
        scope = "RUN_TIME"
        type  = "SECRET"
      }

      env {
        key   = "SPACES_SECRET"
        value = var.spaces_secret
        scope = "RUN_TIME"
        type  = "SECRET"
      }

      env {
        key   = "JWT_SECRET"
        value = var.jwt_secret
        scope = "RUN_TIME"
        type  = "SECRET"
      }

      env {
        key   = "MSG91_AUTH_KEY"
        value = var.msg91_auth_key
        scope = "RUN_TIME"
        type  = "SECRET"
      }

      # ---- non-secret runtime configuration ---------------------------
      env {
        key   = "SPACES_BUCKET"
        value = var.spaces_bucket
        scope = "RUN_TIME"
        type  = "GENERAL"
      }

      env {
        key   = "SPACES_REGION"
        value = var.spaces_region
        scope = "RUN_TIME"
        type  = "GENERAL"
      }

      env {
        key   = "SPACES_CDN_URL"
        value = var.spaces_cdn_url
        scope = "RUN_TIME"
        type  = "GENERAL"
      }

      env {
        key   = "SPACES_ENDPOINT"
        value = "https://${var.spaces_region}.digitaloceanspaces.com"
        scope = "RUN_TIME"
        type  = "GENERAL"
      }

      env {
        key   = "MSG91_TEMPLATE_ID"
        value = var.msg91_template_id
        scope = "RUN_TIME"
        type  = "GENERAL"
      }

      env {
        key   = "ADMIN_PHONES"
        value = var.admin_phones
        scope = "RUN_TIME"
        type  = "GENERAL"
      }

      # ---- baked into the client bundle at build time -----------------
      env {
        key   = "NEXT_PUBLIC_SITE_URL"
        value = var.site_url
        scope = "RUN_AND_BUILD_TIME"
        type  = "GENERAL"
      }

      env {
        key   = "NEXT_PUBLIC_CDN_URL"
        value = var.spaces_cdn_url
        scope = "RUN_AND_BUILD_TIME"
        type  = "GENERAL"
      }

      # ---- platform / build knobs -------------------------------------
      env {
        key   = "PORT"
        value = tostring(var.http_port)
        scope = "RUN_TIME"
        type  = "GENERAL"
      }

      env {
        key   = "NODE_ENV"
        value = "production"
        scope = "RUN_AND_BUILD_TIME"
        type  = "GENERAL"
      }

      # Deployment environment, distinct from NODE_ENV: a staging stack still
      # builds in production mode but must not, say, send real OTP messages.
      env {
        key   = "APP_ENV"
        value = var.environment
        scope = "RUN_AND_BUILD_TIME"
        type  = "GENERAL"
      }

      env {
        key   = "WEDDING_SLUG"
        value = var.wedding_slug
        scope = "RUN_AND_BUILD_TIME"
        type  = "GENERAL"
      }

      # Next.js phones home with anonymous build telemetry by default.
      env {
        key   = "NEXT_TELEMETRY_DISABLED"
        value = "1"
        scope = "BUILD_TIME"
        type  = "GENERAL"
      }

      # ---- caller-supplied extras -------------------------------------
      dynamic "env" {
        for_each = var.extra_env
        content {
          key   = env.key
          value = env.value.value
          scope = env.value.scope
          type  = "GENERAL"
        }
      }

      dynamic "env" {
        for_each = local.secret_env_keys
        content {
          key   = env.value
          value = var.extra_secret_env[env.value]
          scope = "RUN_TIME"
          type  = "SECRET"
        }
      }
    }
  }

  timeouts {
    create = var.app_deploy_timeout
  }

  lifecycle {
    precondition {
      condition     = var.primary_domain != null || length(var.custom_domains) > 0 || var.environment != "production"
      error_message = "A production wedding stack must have primary_domain set; leaving a live wedding on the *.ondigitalocean.app hostname is not acceptable."
    }

    precondition {
      condition     = var.autoscaling == null || !startswith(var.instance_size_slug, "apps-s-")
      error_message = "App Platform autoscaling is not available on Basic (apps-s-*) instance sizes; move to a Professional (apps-d-*) size or set autoscaling = null."
    }

    # ------------------------------------------------------------------
    # PERPETUAL-DIFF ESCAPE HATCH
    #
    # DigitalOcean returns SECRET env values as opaque `EV[1:...]` ciphertext,
    # which never compares equal to the plaintext in this configuration. On
    # some provider versions that makes every `plan` report the whole env set
    # as changing, and every `apply` trigger a rebuild.
    #
    # If you hit that, uncomment the line below. `ignore_changes` only accepts
    # a static list, so this cannot be driven by a variable -- it is a
    # deliberate, reviewed edit. While it is on, env var changes STOP being
    # applied: you must comment it out again to ship one.
    #
    # ignore_changes = [spec[0].service[0].env]
    # ------------------------------------------------------------------
  }
}
