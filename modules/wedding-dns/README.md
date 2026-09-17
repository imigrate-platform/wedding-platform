# `wedding-dns`

Records for one wedding under the platform's apex zone. Creates a CNAME at
`<slug>.imigrate.com` pointing at the wedding's App Platform ingress, plus
optional wildcard, CDN vanity and arbitrary extra records.

**This module never creates the zone.** See below.

---

## Usage

```hcl
module "dns" {
  source = "../../modules/wedding-dns"

  apex_domain  = "imigrate.com"
  wedding_slug = "muskan-sourav"

  # default_ingress, NOT live_url.
  app_ingress_hostname = module.app.default_ingress

  record_ttl = 300
}
```

Staging, or anything that should not occupy a wedding-shaped label:

```hcl
module "dns" {
  source = "../../modules/wedding-dns"

  apex_domain          = "imigrate.com"
  wedding_slug         = "sandbox"
  subdomain_override   = "sandbox-staging"   # -> sandbox-staging.imigrate.com
  app_ingress_hostname = module.app.default_ingress
  record_ttl           = 60
}
```

With a CDN vanity hostname (requires `cdn_custom_domain` + `cdn_certificate_name`
on the `wedding-data` module):

```hcl
module "dns" {
  source = "../../modules/wedding-dns"

  apex_domain          = "imigrate.com"
  wedding_slug         = "muskan-sourav"
  app_ingress_hostname = module.app.default_ingress

  media_subdomain    = "media"                  # media.muskan-sourav.imigrate.com
  media_cdn_endpoint = module.data.cdn_endpoint
}
```

---

## Why the apex is a data source

`digitalocean_domain` is a **DNS zone**, and a zone is a singleton per account.
`imigrate.com` can exist exactly once.

If every wedding stack declared `resource "digitalocean_domain" "apex"`:

- the second `terraform apply` would fail outright with *domain already exists*;
- and if you worked around that by importing the zone into every stack, then
  `terraform destroy` on **one finished wedding** would delete the zone — taking
  every other wedding, and the marketing site, offline with it.

So the zone is created **exactly once**, by `envs/_shared`, and every wedding
stack reads it:

```hcl
data "digitalocean_domain" "apex" {
  name = var.apex_domain
}
```

That read doubles as a guard. Point a stack at a domain that is not in
DigitalOcean DNS and the plan fails immediately with a clear error, instead of
silently creating records in a zone nobody is serving.

Records are safe to own per wedding — a `digitalocean_record` is scoped to one
name, so destroying a wedding removes only that wedding's records.

---

## CNAME, not A

App Platform ingress addresses are not documented as static and DigitalOcean
does not commit to them. A CNAME to the `*.ondigitalocean.app` hostname survives
any address change; an A record does not.

Two preconditions protect the record:

- the ingress hostname must not resolve to an empty string (catches an unset
  or mis-wired variable);
- the ingress hostname must not itself be under `apex_domain` — which is what
  happens if someone passes `live_url` instead of `default_ingress` after the
  certificate has issued, and would create a CNAME pointing at itself.

The module tolerates being handed a full URL, a bare hostname, a trailing slash
or a trailing dot, and normalises all of them to the trailing-dot FQDN
DigitalOcean expects in a CNAME value.

---

## Inputs

| Name | Type | Default | Required | Description |
| --- | --- | --- | :---: | --- |
| `apex_domain` | `string` | — | yes | Apex zone, e.g. `imigrate.com`. Read, never created. Validated as a bare domain — no scheme, no trailing dot. |
| `wedding_slug` | `string` | — | yes | Subdomain label, unless overridden. Validated as a single DNS label. |
| `subdomain_override` | `string` | `null` | no | Use this label instead of `wedding_slug`. |
| `app_ingress_hostname` | `string` | — | yes | App Platform ingress to point at. Pass `module.app.default_ingress`. Scheme, trailing slash and trailing dot are tolerated. |
| `record_ttl` | `number` | `300` | no | TTL in seconds, 30–604800. Keep low during setup, raise once stable. |
| `create_wildcard` | `bool` | `false` | no | Also create `*.<label>.<apex>`. |
| `media_subdomain` | `string` | `null` | no | Label for a CDN vanity hostname, e.g. `media`. Requires `media_cdn_endpoint`. |
| `media_cdn_endpoint` | `string` | `null` | no | CDN endpoint hostname to CNAME to. |
| `extra_records` | `map(object({name, type, value, ttl, priority, weight, port, flags, tag}))` | `{}` | no | Arbitrary extra records. `name` is relative to the apex. The map key is part of the resource address — renaming a key destroys and recreates the record. |

## Outputs

| Name | Description |
| --- | --- |
| `fqdn` | `<label>.<apex>`. |
| `site_url` | `https://<fqdn>`, ready for `NEXT_PUBLIC_SITE_URL`. |
| `apex_domain` | Name of the apex zone the records were created in. |
| `apex_domain_urn` | URN of the apex zone. |
| `record_id` | ID of the app CNAME. |
| `record_fqdn` | FQDN as reported back by DigitalOcean. |
| `cname_target` | The CNAME value. Hand this verbatim to a customer attaching their own domain. |
| `media_fqdn` | Vanity CDN hostname, or null. |
| `extra_record_fqdns` | Map of `extra_records` key → created FQDN. |

---

## Customer-owned domains are deliberately out of scope

A couple's own domain lives at their registrar, which DigitalOcean cannot
manage. This module only touches the apex zone the platform owns. To attach a
customer domain, add it to the `wedding-app` module's `custom_domains` and send
the customer the `cname_target` output — see the top-level README, "Attaching a
customer's custom domain".
