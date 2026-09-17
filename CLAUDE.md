# CLAUDE.md — imigrate-platform

Terraform for the imigrate wedding-management platform on DigitalOcean.
One isolated stack per wedding under `imigrate.com`.

First deploy: `DEPLOY-RUNBOOK.md`. Repo and team layout: `ORG-MAP.md`.

---

## Status, read this first

**This Terraform has never been applied against a real account.**

It was validated with **OpenTofu 1.10.6** against the real
`digitalocean/digitalocean` provider 2.48.0 — `fmt`, `validate` and `plan`
all pass, 10 resources plan cleanly per environment, no dependency cycles.
It has not been run through HashiCorp's own binary, and nothing has ever
been created.

Say this plainly when reporting on it. "Validated" is not "working".

---

## Provider facts, verified against the 2.48.0 schema

Checked against the real binary, not remembered. Do not "fix" these.

- **`digitalocean_app` has no `tags` argument.** Nor do Spaces buckets,
  CDN endpoints, domains or records. Only `database_cluster` takes tags.
- **There is no `digitalocean_spaces_key` resource** in 2.43–2.48. Both
  Spaces key pairs are created by hand in the control panel. This is why
  `app_spaces_*` are required variables rather than defaulted.
- App-level `alert` is a set taking `rule`. Service-level `alert`
  additionally requires `operator`, `value` and `window`.
- `timeouts` on `digitalocean_app` accepts `create` only.
- `digitalocean_spaces_bucket_cors_configuration` is used instead of the
  inline `cors_rule` — the inline block is deprecated and cannot set
  `expose_headers`, which browsers need for multipart ETags.

---

## Design decisions, each with a reason

**Apex domain is created once in `envs/_shared`**, read via data source
everywhere else. Per-stack ownership would fail on the second apply, and
destroying one wedding would delete the DNS zone for all of them.

**Bucket private, objects public-read.** A public bucket also exposes
`ListObjects`, which lets anyone enumerate every guest photo. The
alternative is pre-signed URLs; that trade is documented in the module
README.

**No `prevent_destroy`.** It only accepts a literal, so it would make
staging undestroyable too. Protection is `force_destroy = false`, DO
backups, no destroy path in CI, and a `plan -destroy` review protocol.

**No state locking.** DO Spaces support for `use_lockfile` was not
assumed. Substitute is per-stack CI `concurrency` groups plus bucket
versioning. If you turn locking on, verify it actually works rather than
trusting the flag.

**No OIDC.** DigitalOcean's API does not support OIDC federation, so CI
uses an Environment-scoped `DIGITALOCEAN_ACCESS_TOKEN`. `id-token: write`
is requested anyway for a future federated backend.

**`zone` is never set on app domain blocks**, so DNS has exactly one
owner and the runbook is identical for `imigrate.com` subdomains and a
customer's own domain.

---

## Sequencing traps

**App Platform deploys from GitHub.** Before applying a wedding stack:
the repo must exist with a commit on `main`, **and** the DigitalOcean
GitHub app must be installed on the `imigrate-apps` org. Missing the
second gives `repository not found`, which reads like a typo but is a
permissions problem.

**Remote state bootstrap is deliberately manual.** The state bucket is
created by hand because a bootstrap resource that manages its own manager
is a trap. Versioning on that bucket is not optional — it is the only
recovery path for a corrupted state file.

**The state file holds secrets in cleartext** — Postgres password, JWT
signing secret, MSG91 key. Treat the bucket as production credentials.

**Never let a plan replace the database.** Changing `region`, `size` or
engine version forces replacement and destroys the data. On a live
wedding that is unrecoverable. Read every `# forces replacement` line.

---

## Credentials

Never accept, request, or write a DigitalOcean API token into a file, a
commit, or a chat. There is deliberately **no Terraform variable** for it
— `DIGITALOCEAN_TOKEN` is read from the environment so it cannot be
committed by accident.

The S3 backend reads the **AWS** names, so both must be exported:

```bash
export AWS_ACCESS_KEY_ID="$SPACES_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$SPACES_SECRET_ACCESS_KEY"
```

Prefer `TF_VAR_*` environment variables over `terraform.tfvars` for
secrets. The file is git-ignored; an environment variable cannot be
committed at all.

---

## Region

`blr1` (Bangalore) for everything, `blr` for App Platform. Verified: DO
supports Spaces, Managed Postgres and App Platform in BLR1. Guests are in
Delhi, so media serves from within India.

---

## Cost

~$32/month per wedding at ₹88 = $1 — App Platform $12, Managed Postgres
$15, Spaces $5. About ₹4,200–5,000 for a full six-week run including
staging; that is the figure for fixed-fee pricing, not the monthly.

The App Platform and CDN lines are **medium confidence** — DO has
restructured Basic-tier pricing before. Verify on the pricing page rather
than quoting these to a customer.

---

## Adding a wedding

```bash
cp -r envs/muskan-sourav envs/<slug>
```

Edit `terraform.tfvars`, new state key, new GitHub Environment. Full
sequence in `DEPLOY-RUNBOOK.md`; team-by-team version in `ORG-MAP.md`.

Separate deploy per wedding is deliberate: a January deploy for Golu must
not be able to touch a site still serving guests.

---

## On microservices

This was asked for, and pushed back on. Splitting a ~300-guest wedding app
into services would split the system along the org chart rather than
along anything the software does — network hops between things that are
one transaction, six deploy pipelines to debug on a wedding night, for no
scaling pressure that exists.

Parallel contribution is a **CODEOWNERS** problem, and CODEOWNERS is free.
`ORG-MAP.md` has the layout. Revisit when there is a real reason: a
different scaling profile, a different release cadence, or a compliance
boundary. "A different team owns it" is not one.
