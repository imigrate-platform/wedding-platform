# Deploy runbook — empty DigitalOcean account to live app

Ordered. Each step's output feeds the next, and three of them are things
Terraform cannot do, so they have to happen in the control panel first.

Budget about two hours for the first run. The second wedding takes twenty
minutes, because everything below that is one-time is genuinely one-time.

---

## Before you start: the credential rule

**Nobody should paste a DigitalOcean API token into a chat, a ticket, or a
commit.** Not to me, not to a colleague. Every command below reads its
credentials from your own shell environment, and the Terraform in this repo
deliberately has no variable to hold a DO token — that is why
`DIGITALOCEAN_TOKEN` is an environment variable and not a `.tfvars` entry.

A dashboard URL like `cloud.digitalocean.com/dashboard?i=a0957e` grants
nothing — the `i=` parameter is a UI reference, not a credential — so
sharing one is harmless. Tokens are different.

---

## Decide this first

The Terraform provisions **DO Managed Postgres and Spaces**. The current
app talks to **Supabase**. Applying the stack as-is means paying for a
database and a bucket that nothing connects to.

| | Apply now, migrate later | Migrate first, then apply |
|---|---|---|
| Cost until you migrate | ~$20/mo wasted | none |
| Work before 16 Nov | none | 2–3 days |
| Risk to the wedding | none | new auth path, first outing |

**If you are shipping November on Supabase**, apply only `envs/_shared`
(DNS and the project grouping — free) and deploy the app to App Platform
pointing at Supabase. Skip the `wedding-data` module until December.

**If you are migrating first**, do the migration, then apply the full
stack. Six weeks is enough, but the auth rewrite has to land before
1 November or it eats the staging window.

Either way steps 1–4 below are identical. Step 6 is where they diverge.

---

## Step 1 — control panel, one-time

Three things Terraform cannot create.

### 1a. API token

**API → Tokens → Generate New Token**

- Name: `terraform-imigrate`
- Scopes: **Custom**, with write on Apps, Databases, Domains, Projects, Spaces, VPCs
- Expiry: 90 days, and put the renewal in your calendar now

Full-access tokens work but there is no reason to hold one. Copy it into
your password manager. It is shown exactly once.

### 1b. Spaces access keys

**API → Spaces Keys → Generate New Key**

Generate **two** pairs, because they have different blast radii:

| Key | Used by | Scope |
|---|---|---|
| `terraform-state` | The Terraform S3 backend, and bucket management | All buckets |
| `wedding-app-media` | The running app, reading and writing guest media | The media bucket only, if per-bucket scoping is available to you |

The provider has no `digitalocean_spaces_key` resource in 2.43–2.48, which
is why these are made by hand rather than in code.

### 1c. Add the domain

**Networking → Domains → Add `imigrate.com`**

Then, at your registrar, point the nameservers at:

```
ns1.digitalocean.com
ns2.digitalocean.com
ns3.digitalocean.com
```

Propagation is usually under an hour, occasionally 24. **Do this today**
regardless of which path you took above — it is pure waiting time and
nothing else can be verified until it resolves.

Check it with:

```bash
dig +short NS imigrate.com
```

---

## Step 2 — GitHub, before any app apply

This is the sequencing mistake that makes a first `terraform apply` fail.

App Platform deploys **from a GitHub repository**. The Terraform references
`imigrate-apps/wedding-app`. Two things must be true before you apply the
wedding stack:

1. **The repo exists and has code on `main`.**

   ```bash
   cd wed
   git init && git add -A
   git commit -m "Initial import: wedding app"
   git branch -M main
   git remote add origin git@github.com:imigrate-apps/wedding-app.git
   git push -u origin main
   ```

2. **DigitalOcean is authorised on the `imigrate-apps` org.**

   In the control panel: **Apps → Create App → GitHub → Manage Access**,
   and install the DigitalOcean app on `imigrate-apps`, granting it
   `wedding-app`.

   Without this, the app resource fails with a repository-not-found error
   that reads like a typo but is a permissions problem.

You can cancel out of the Create App wizard once access is granted —
Terraform does the actual creation.

---

## Step 3 — bootstrap the state bucket

Chicken-and-egg: remote state needs a bucket, and the bucket is
infrastructure. This one piece is created by hand on purpose. A bootstrap
resource that manages its own manager is a trap, not a feature.

```bash
export DIGITALOCEAN_TOKEN='...'            # from 1a
export SPACES_ACCESS_KEY_ID='...'          # terraform-state pair, 1b
export SPACES_SECRET_ACCESS_KEY='...'
export AWS_ACCESS_KEY_ID="$SPACES_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$SPACES_SECRET_ACCESS_KEY"

# Bucket names are globally unique across every DigitalOcean customer,
# so 'imigrate-tfstate' may be taken. Add a suffix if so.
doctl spaces bucket create imigrate-tfstate --region blr1

aws s3api put-bucket-versioning \
  --bucket imigrate-tfstate \
  --versioning-configuration Status=Enabled \
  --endpoint-url https://blr1.digitaloceanspaces.com
```

**Versioning is not optional.** It is the entire recovery mechanism for a
truncated or corrupted state file, and the state file holds the Postgres
password, the JWT secret and the MSG91 key in cleartext. Treat this bucket
as production credentials.

Confirm it is not public:

```bash
aws s3api get-bucket-acl --bucket imigrate-tfstate \
  --endpoint-url https://blr1.digitaloceanspaces.com
```

---

## Step 4 — apply the shared stack

DNS zone, project grouping, VPC. Free, and every wedding depends on it.

```bash
cd envs/_shared
cp terraform.tfvars.example terraform.tfvars   # apex_domain, region

terraform init \
  -backend-config="bucket=imigrate-tfstate" \
  -backend-config="key=shared/terraform.tfstate"

terraform plan     # read this properly — it is your first real plan
terraform apply
```

Keep the VPC id:

```bash
terraform output -raw vpc_uuid
```

It goes into each wedding's `terraform.tfvars`.

---

## Step 5 — fill in the wedding tfvars

```bash
cd ../muskan-sourav
cp terraform.tfvars.example terraform.tfvars
```

What to change:

| Field | Value |
|---|---|
| `vpc_uuid` | From step 4 |
| `admin_phones` | Your real numbers, E.164, comma-separated |
| `msg91_template_id` | From MSG91 once DLT clears |
| `jwt_secret` | `openssl rand -base64 48` |
| `msg91_auth_key` | From MSG91 |
| `app_spaces_*` | The `wedding-app-media` key pair from 1b |

Better than putting secrets in the file at all:

```bash
export TF_VAR_jwt_secret="$(openssl rand -base64 48)"
export TF_VAR_msg91_auth_key='...'
export TF_VAR_app_spaces_access_key_id='...'
export TF_VAR_app_spaces_secret_access_key='...'
```

`terraform.tfvars` is git-ignored, but an environment variable cannot be
committed by accident at all.

---

## Step 6 — apply the wedding stack

### If shipping November on Supabase

Do not apply the whole stack. Comment out the `wedding-data` module in
`envs/muskan-sourav/main.tf`, and add the Supabase variables to the app's
`env` block instead. You get App Platform and DNS; you skip a Postgres
cluster and a bucket you are not using yet.

### If you have migrated to DO-native

```bash
terraform init \
  -backend-config="bucket=imigrate-tfstate" \
  -backend-config="key=weddings/muskan-sourav/terraform.tfstate"

terraform plan
terraform apply
```

First apply takes 5–10 minutes; the Postgres cluster is the slow part.

```bash
terraform output app_live_url
terraform output -raw database_uri     # sensitive
```

---

## Step 7 — verify before telling anyone

```bash
curl -sI https://muskan-sourav.imigrate.com | head -3
curl -s https://muskan-sourav.imigrate.com/api/rsvp \
  -X POST -H 'Content-Type: application/json' -d '{}' | head -c 200
```

Expect 200 on the first and a `400` with a JSON validation message on the
second. A 400 there is success — it means the route ran and validated.

Then, from a phone on mobile data, not office wifi:

- [ ] Home page loads under 3 seconds
- [ ] `/plan` returns sensible leave-by times
- [ ] An RSVP submits and appears in the database
- [ ] A photo uploads and appears in the admin queue
- [ ] `/admin` sends a real OTP to a real handset

---

## Cost

Per production wedding, at ₹88 = $1:

| Item | Monthly |
|---|---|
| App Platform `apps-s-1vcpu-1gb` | $12 |
| Managed Postgres `db-s-1vcpu-1gb` | $15 |
| Spaces 250 GiB + 1 TiB transfer | $5 |
| Spaces CDN | bundled |
| VPC, DNS, Projects | free |
| **Total** | **~$32 ≈ ₹2,820** (₹3,330 with 18% GST) |

Staging without the database is about $17. Verify App Platform and CDN
pricing on DigitalOcean's pricing page before you commit — Basic-tier
pricing has been restructured before, and those two lines are the ones I
am least confident are still current.

A wedding site runs for about six weeks, so the real cost per wedding is
roughly **₹4,200 to ₹5,000** including staging. That is the number for your
fixed-fee pricing, not the monthly.

---

## When the first apply fails

**`repository not found`** — step 2. The DigitalOcean GitHub app is not
installed on `imigrate-apps`, or the repo has no commit on `main`.

**`domain not found`** — step 1c. `imigrate.com` is not in DO DNS yet, or
nameservers have not propagated. `dig +short NS imigrate.com`.

**`bucket already exists`** — Spaces names are globally unique across all
DigitalOcean customers. Pick another.

**Backend init fails on credentials** — `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY` must be exported, not just the `SPACES_*` pair.
The S3 backend reads the AWS names.

**Plan wants to replace the database** — stop. Changing `region`, `size` or
engine version forces replacement and destroys the data. On a live wedding
that is unrecoverable. Read every `# forces replacement` line before typing
yes.

---

## A caveat on this Terraform

It was validated with **OpenTofu 1.10.6** against the real DigitalOcean
provider 2.48.0 — `fmt`, `validate` and `plan` all pass, and the plan
renders 10 resources cleanly per environment. It has **never been applied
against a real account**, and it was not run through HashiCorp's own
Terraform binary.

Nothing in the configs uses a feature that diverges between the two. But
read your first plan line by line rather than trusting that sentence.
