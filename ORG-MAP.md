# The imigrate framework — orgs, repos and ownership

Seven GitHub organisations, each owning the repos its discipline actually
changes. The point is that a QA engineer can work without waiting on a
platform review, and a platform change cannot land without one.

---

## Where things live

| Org | Repos | Owns |
|---|---|---|
| [imigrate-apps](https://github.com/imigrate-apps) | `wedding-app` | The product. Next.js, all guest and admin surfaces. |
| [imigrate-platform](https://github.com/imigrate-platform) | `imigrate-platform`, `terraform-modules` | Terraform, DigitalOcean, DNS, environments. |
| [imigrate-devops](https://github.com/imigrate-devops) | `github-actions`, `deploy-runbooks` | Reusable workflows, release process, secrets rotation. |
| [imigrate-monitoring](https://github.com/imigrate-monitoring) | `imigrate-monitoring`, `runbooks` | Dashboards, alert rules, on-call, SLOs. |
| [imigrate-security](https://github.com/imigrate-security) | `policies`, `scanning` | Dependency and secret scanning, DPDP compliance, threat model. |
| [imigrate-quality-assurance](https://github.com/imigrate-quality-assurance) | `e2e-tests`, `load-tests` | Playwright suites, k6 scripts, release sign-off. |
| [imigrate-administration](https://github.com/imigrate-administration) | `org-config`, `customer-onboarding` | Org settings, access reviews, per-customer runbooks. |

A note on `wedding-app`: it is **one repo per product, not one per wedding**.
Each wedding is a deployment of it, configured by
`src/config/wedding.config.ts` and its own Terraform environment. Cloning the
repo per customer would mean applying every security fix N times.

---

## Why this is not microservices

You asked for microservices to let six teams contribute in parallel. The
repo and ownership boundaries above deliver that. Service boundaries would
not have — they would have split the system along the org chart, added
network hops between things that are one transaction today, and given you
six deploy pipelines to debug on a wedding night.

Revisit it when there is a real reason: a component with a genuinely
different scaling profile, a different release cadence, or a compliance
boundary that needs isolation. "Different team owns it" is a CODEOWNERS
problem, and CODEOWNERS is free.

---

## CODEOWNERS

In `imigrate-apps/wedding-app/.github/CODEOWNERS`:

```
# Default — the app team reviews everything not claimed below.
*                               @imigrate-apps/developers

# Anything that touches infrastructure needs platform eyes.
/Dockerfile                     @imigrate-platform/engineers
/next.config.ts                 @imigrate-platform/engineers @imigrate-apps/developers
/.do/                           @imigrate-platform/engineers

# Telemetry contract. Changing a log field name or a metric silently
# breaks a dashboard and an alert in another repo.
/src/lib/observability/         @imigrate-monitoring/engineers @imigrate-apps/developers
/src/instrumentation.ts         @imigrate-monitoring/engineers

# Auth, authorisation and anything holding guest personal data.
/src/lib/supabase/              @imigrate-security/reviewers @imigrate-apps/developers
/src/app/api/admin/             @imigrate-security/reviewers @imigrate-apps/developers
/supabase/schema.sql            @imigrate-security/reviewers @imigrate-platform/engineers

# Tests belong to the people who are accountable for them.
/e2e/                           @imigrate-quality-assurance/engineers
/.github/workflows/             @imigrate-devops/engineers
```

In `imigrate-platform/imigrate-platform/.github/CODEOWNERS`:

```
*                               @imigrate-platform/engineers
/envs/*/                        @imigrate-platform/engineers @imigrate-devops/engineers
/.github/workflows/             @imigrate-devops/engineers
```

The observability lines are the ones people forget. `log.ts` looks like
application code, but renaming a field there breaks an alert rule in
`imigrate-monitoring` that nobody will notice until it fails to fire.

---

## Branch protection

Same on every repo:

- `main` protected, no direct pushes, no force push
- One approving review, from a CODEOWNER
- Stale approvals dismissed on new commits
- Required checks: `build`, `typecheck`, `lint`, `test`, `terraform-plan` (platform repos)
- Signed commits on `imigrate-platform` and `imigrate-security` — infrastructure and policy changes should be attributable beyond a display name
- Linear history, squash merges only

---

## How a change reaches production

```
  Developer opens PR in imigrate-apps/wedding-app
            │
            ▼
  CI: build · typecheck · lint · unit tests        ← imigrate-devops owns
  CI: dependency + secret scan                     ← imigrate-security owns
  CI: Playwright against a preview deployment      ← imigrate-quality-assurance owns
            │
            ▼
  CODEOWNER review (whoever the paths pulled in)
            │
            ▼
  Merge to main ──► DigitalOcean App Platform auto-deploys staging
            │
            ▼
  QA sign-off on staging
            │
            ▼
  Tag a release ──► GitHub Environment gate ──► production apply
            │
            ▼
  Deploy annotation posted to Grafana             ← imigrate-monitoring owns
```

The Grafana deploy annotation is worth the twenty lines it costs. During an
incident, the first question is always "did something change?" and an
annotated deploy marker on the latency graph answers it in a second.

---

## Environments and who can approve

| Environment | Approvers | Auto-deploys |
|---|---|---|
| `preview` | none | every PR |
| `staging` | none | merge to `main` |
| `production-muskan-sourav` | platform + administration | tagged release only |
| `production-golu` | platform + administration | tagged release only |

Production environments are per wedding, not one shared "production". A
deploy to Golu's site in January must not be able to touch a site that is
still serving guests.

---

## Secrets

| Secret | Lives in | Rotated |
|---|---|---|
| `DIGITALOCEAN_ACCESS_TOKEN` | `imigrate-platform` org secret, environment-scoped | Quarterly |
| `GRAFANA_OTLP_TOKEN`, `LOKI_TOKEN` | Per-wedding environment | Per wedding |
| `SUPABASE_SERVICE_ROLE_KEY` | Per-wedding environment | Per wedding |
| `MSG91_AUTH_KEY` | Per-wedding environment | Quarterly |

No secret is an organisation-wide secret without an environment scope. An
org-wide secret is readable by every workflow in every repo in that org,
which is how a test workflow ends up holding production database
credentials.

`imigrate-administration` runs a quarterly access review: who is in each
org, which teams they are on, and which secrets those teams can reach.
Put it in a calendar, because nobody does it otherwise.

---

## Starting a new wedding

1. **administration** — create the GitHub Environment `production-<slug>`, add approvers.
2. **platform** — `cp -r envs/muskan-sourav envs/<slug>`, edit `terraform.tfvars`, PR, apply.
3. **apps** — rewrite `src/config/wedding.config.ts`, drop in the invitation cards.
4. **monitoring** — import the alert rules with `${WEDDING_SLUG}` substituted; confirm a test alert reaches the contact point.
5. **security** — review what personal data the new wedding collects; confirm redaction covers it.
6. **QA** — run the E2E suite against the new staging URL before it goes to the customer.
7. **devops** — tag the first release, walk the deploy, confirm the Grafana annotation lands.

Seven steps, seven teams, roughly a day. That is what the org split buys
you — the alternative is one person doing all seven and being the
bottleneck every time.
