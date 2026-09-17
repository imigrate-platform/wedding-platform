# `wedding-app`

One App Platform app running the Next.js 15 wedding site for a single wedding:
a single `service` component built from `github.com/imigrate-apps/wedding-app`,
its domains, its full environment, and the two alerts that matter.

---

## Usage

```hcl
module "app" {
  source = "../../modules/wedding-app"

  wedding_slug = "muskan-sourav"
  environment  = "production"
  app_region   = "blr" # NOT "blr1" -- App Platform region slugs are short

  github_repo    = "imigrate-apps/wedding-app"
  github_branch  = "main"
  deploy_on_push = true

  instance_size_slug = "apps-s-1vcpu-1gb"
  instance_count     = 1

  primary_domain = "muskan-sourav.imigrate.com"
  site_url       = "https://muskan-sourav.imigrate.com"

  custom_domains = [
    { name = "muskanandsourav.in", type = "ALIAS" },
  ]

  database_url   = module.data.database_uri
  spaces_key     = var.app_spaces_access_key_id
  spaces_secret  = var.app_spaces_secret_access_key
  spaces_bucket  = module.data.bucket_name
  spaces_region  = module.data.bucket_region
  spaces_cdn_url = module.data.cdn_url

  jwt_secret        = var.jwt_secret
  msg91_auth_key    = var.msg91_auth_key
  msg91_template_id = var.msg91_template_id
  admin_phones      = "+919000000000"
}
```

---

## Next.js 15 standalone on App Platform

`next.config.ts` in the app repo must set `output: "standalone"`. Then:

```
build_command = "npm run build \
  && cp -r public .next/standalone/public \
  && cp -r .next/static .next/standalone/.next/static"

run_command   = "HOSTNAME=0.0.0.0 node .next/standalone/server.js"
http_port     = 3000
```

Three things bite people here and all three are handled by the defaults:

1. **`next build` does not copy `public/` or `.next/static/` into
   `.next/standalone/`.** This is documented Next.js behaviour, not a bug. Skip
   the copies and the site boots fine but every image, font and CSS chunk 404s.
2. **The standalone server binds to `HOSTNAME`, which defaults to
   `localhost`.** Inside a container that means App Platform's router and health
   checker cannot reach it and every deploy fails its health check. It must be
   `0.0.0.0`.
3. **`http_port` and `PORT` must agree.** `http_port` tells the App Platform
   router where to send traffic; `PORT` is what the standalone server listens
   on. The module sets both from `var.http_port`.

The buildpack install step (`npm ci`) still runs automatically — `build_command`
replaces only the build step, not the install step.

---

## Environment variables

| Key | Type | Scope | Source |
| --- | --- | --- | --- |
| `DATABASE_URL` | SECRET | RUN_TIME | `wedding-data` → `database_uri` |
| `SPACES_KEY` | SECRET | RUN_TIME | variable |
| `SPACES_SECRET` | SECRET | RUN_TIME | variable |
| `JWT_SECRET` | SECRET | RUN_TIME | variable |
| `MSG91_AUTH_KEY` | SECRET | RUN_TIME | variable |
| `SPACES_BUCKET` | GENERAL | RUN_TIME | `wedding-data` |
| `SPACES_REGION` | GENERAL | RUN_TIME | `wedding-data` |
| `SPACES_CDN_URL` | GENERAL | RUN_TIME | `wedding-data` |
| `SPACES_ENDPOINT` | GENERAL | RUN_TIME | derived from `spaces_region` |
| `MSG91_TEMPLATE_ID` | GENERAL | RUN_TIME | variable |
| `ADMIN_PHONES` | GENERAL | RUN_TIME | variable |
| `NEXT_PUBLIC_SITE_URL` | GENERAL | RUN_AND_BUILD_TIME | variable |
| `NEXT_PUBLIC_CDN_URL` | GENERAL | RUN_AND_BUILD_TIME | `wedding-data` |
| `PORT` | GENERAL | RUN_TIME | `http_port` |
| `NODE_ENV` | GENERAL | RUN_AND_BUILD_TIME | fixed `production` |
| `APP_ENV` | GENERAL | RUN_AND_BUILD_TIME | `environment` |
| `WEDDING_SLUG` | GENERAL | RUN_AND_BUILD_TIME | `wedding_slug` |
| `NEXT_TELEMETRY_DISABLED` | GENERAL | BUILD_TIME | fixed `1` |

**`NEXT_PUBLIC_*` must be `RUN_AND_BUILD_TIME`.** Next.js inlines those into the
client bundle at build time; a `RUN_TIME`-only value is simply absent from the
browser bundle and shows up as `undefined` in the UI.

`extra_env` (non-secret) and `extra_secret_env` (secret) extend this set.
`extra_env` is deliberately *not* marked sensitive because Terraform cannot
drive `for_each` from a sensitive value; put anything confidential in
`extra_secret_env`, whose values are sensitive and whose keys are not.

### The SECRET env perpetual-diff caveat

DigitalOcean stores `type = "SECRET"` values encrypted and returns them as
opaque `EV[1:...]` ciphertext. That never compares equal to the plaintext in
this configuration, so on some provider versions **every plan reports the whole
env set as changing** and every apply triggers a rebuild.

If you hit this, uncomment the `ignore_changes` line at the bottom of
`main.tf`. It is a reviewed edit rather than a variable because Terraform's
`ignore_changes` only accepts a static list. While it is on, **env var changes
stop applying** — you must comment it out again to ship one.

---

## Why we never set `zone`

`digitalocean_app`'s `domain` block accepts a `zone`. Setting it makes App
Platform create and manage the DNS record for you, inside that DO zone. This
module never sets it, for two reasons:

1. **DNS would then be managed twice.** The `wedding-dns` module creates an
   explicit `digitalocean_record` for the wedding subdomain. If App Platform
   also managed a record for the same name, Terraform and DigitalOcean would
   overwrite each other's work on every apply.
2. **It would not work for customer domains anyway.** A couple's own
   `muskanandsourav.in` lives at their registrar, which DigitalOcean cannot
   touch. Using one mechanism for both cases keeps the runbook identical: point
   a CNAME at `default_ingress`, wait for the certificate.

So: DNS for `*.imigrate.com` is Terraform's job via `wedding-dns`; DNS for a
customer domain is the customer's job, using the `default_ingress` output.

---

## Alerts

`alert_rules` defaults to the two app-scoped rules this platform actually needs:

- **`DEPLOYMENT_FAILED`** — a build that never shipped. Without this a failed
  deploy is silent and the site keeps serving the previous version, which looks
  fine right up until someone asks why their change is missing.
- **`DOMAIN_FAILED`** — the certificate or DNS validation for the wedding
  subdomain did not complete. This is the failure mode that presents as "the
  site is down" on the morning of the event.

`service_alerts` adds threshold alerts (`CPU_UTILIZATION`, `MEM_UTILIZATION`,
`RESTART_COUNT`), which need `operator`, `value` and `window`.

Alert *destinations* are account-level notification settings in the DO control
panel, not part of the app spec — the API gives Terraform no way to set them.

---

## Tagging & labelling

`digitalocean_app` has no `tags` argument. The wedding slug and environment are
therefore carried by:

1. the app **name**, `<slug>-<environment>`,
2. the `WEDDING_SLUG` and `APP_ENV` env vars visible to the running app,
3. **DO project membership**, which the calling stack sets up.

---

## Inputs

| Name | Type | Default | Required | Description |
| --- | --- | --- | :---: | --- |
| `wedding_slug` | `string` | — | yes | Wedding identifier. Validated as a DNS label. |
| `environment` | `string` | — | yes | `development`, `staging` or `production`. |
| `app_name_override` | `string` | `null` | no | Explicit app name. Null derives `<slug>-<environment>`. |
| `project_id` | `string` | `null` | no | DO project for the app. Leave null when the caller uses `digitalocean_project_resources`. |
| `app_region` | `string` | `"blr"` | no | App Platform region slug — short form. Validated. |
| `github_repo` | `string` | `"imigrate-apps/wedding-app"` | no | `owner/name`. The DO GitHub App must be authorised on it. |
| `github_branch` | `string` | `"main"` | no | Branch to build. |
| `deploy_on_push` | `bool` | `true` | no | Auto-deploy when the branch moves. Turn off once a wedding is live. |
| `source_dir` | `string` | `"/"` | no | Subdirectory containing the app. |
| `service_name` | `string` | `"web"` | no | Name of the service component. |
| `instance_size_slug` | `string` | `"apps-s-1vcpu-1gb"` | no | Instance size. |
| `instance_count` | `number` | `1` | no | Fixed instance count. Ignored when `autoscaling` is set. |
| `autoscaling` | `object({min_instance_count, max_instance_count, cpu_percent})` | `null` | no | CPU-target autoscaling. Not available on Basic (`apps-s-*`) sizes — enforced by a precondition. |
| `http_port` | `number` | `3000` | no | Container port. Also injected as `PORT`. |
| `build_command` | `string` | standalone build + static copies | no | See "Next.js 15 standalone" above. |
| `run_command` | `string` | `HOSTNAME=0.0.0.0 node .next/standalone/server.js` | no | Start command. |
| `health_check_path` | `string` | `"/api/health"` | no | Must return 2xx without touching Postgres. |
| `health_check` | `object({...})` | 20s delay / 10s period / 5s timeout / 1 / 5 | no | Health check tuning. |
| `primary_domain` | `string` | `null` | no | Primary hostname. Required for `environment = "production"` (precondition). |
| `custom_domains` | `list(object({name, type, wildcard}))` | `[]` | no | Customer-owned domains. `type` is `PRIMARY` or `ALIAS`. |
| `site_url` | `string` | — | yes | Public origin, baked in as `NEXT_PUBLIC_SITE_URL`. |
| `database_url` | `string` (sensitive) | — | yes | Postgres URI. |
| `spaces_key` | `string` (sensitive) | — | yes | Spaces access key id for the app. |
| `spaces_secret` | `string` (sensitive) | — | yes | Spaces secret for the app. |
| `spaces_bucket` | `string` | — | yes | Guest-media bucket name. |
| `spaces_region` | `string` | — | yes | Spaces region slug. |
| `spaces_cdn_url` | `string` | — | yes | CDN base URL. |
| `jwt_secret` | `string` (sensitive) | — | yes | Session JWT signing secret. |
| `msg91_auth_key` | `string` (sensitive) | — | yes | MSG91 auth key. |
| `msg91_template_id` | `string` | — | yes | MSG91 OTP template id. |
| `admin_phones` | `string` | `""` | no | Comma-separated E.164 admin numbers. |
| `extra_env` | `map(object({value, scope}))` | `{}` | no | Extra non-secret env vars. |
| `extra_secret_env` | `map(string)` (sensitive) | `{}` | no | Extra secret env vars. |
| `alert_rules` | `list(string)` | `["DEPLOYMENT_FAILED","DOMAIN_FAILED"]` | no | App-scoped alert rules. |
| `service_alerts` | `list(object({rule, operator, value, window, disabled}))` | `[]` | no | Threshold alerts on the service. |
| `app_features` | `list(string)` | `["buildpack-stack=ubuntu-22"]` | no | Pins the build image so a DO stack rollout cannot change Node under a live wedding. |
| `app_deploy_timeout` | `string` | `"30m"` | no | Create timeout. A cold Next.js build on Basic often takes 5–10 minutes. |

## Outputs

| Name | Description |
| --- | --- |
| `app_id` | App UUID. Feed to `wedding-data`'s `allowed_app_ids`. |
| `app_name` | App name in the DO control panel. |
| `app_urn` | URN, for DO project membership. |
| `live_url` | URL the app is actually serving on. Flips to the custom domain once its certificate issues. |
| `live_domain` | Hostname portion of `live_url`. |
| `default_ingress` | Permanent `*.ondigitalocean.app` URL. **This is the CNAME target** — it never changes. |
| `default_ingress_hostname` | `default_ingress` with scheme and trailing slash stripped. |
| `active_deployment_id` | Deployment currently serving traffic. |
| `domains` | Hostnames registered on the app. |

> Use `default_ingress`, never `live_url`, as a CNAME target. Once the custom
> domain's certificate issues, `live_url` becomes that custom domain — and a
> CNAME pointing at itself is a resolution loop.
