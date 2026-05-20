---
title: "I audited my own credentials and found things I didn't expect"
description: "A practical walkthrough of scanning a homelab GitOps setup for exposed secrets — what I found, where I found it, and how I rotated everything without breaking anything."
pubDate: 2026-05-20
tags: ["security", "homelab", "GitOps", "credentials", "DevOps"]
---

I sat down to do a credential audit on my homelab and consulting infrastructure. I expected to find
a forgotten `.env` file. I found credentials in four different places I hadn't thought to check.

This is a walkthrough of what I found and how I fixed it. If you run your own infra — homelab,
consulting tooling, self-hosted SaaS stack — you probably have at least one of these too.

---

## The scan

Start with a grep across every repo. Cast wide, filter down:

```bash
grep -rn --include="*.env" --include="*.conf" \
  --include="*.yml" --include="*.yaml" \
  --include="*.json" --include="*.tf" \
  --include="*.sh" --include="*.py" --include="*.go" \
  -iE "(password|api_key|api_token|secret|token|private_key|access_key|webhook)\s*[=:]\s*['\"]?[A-Za-z0-9+/]{8,}" \
  ~/Workspace/ 2>/dev/null \
  | grep -v ".git/" | grep -v "node_modules/" | grep -v "_test\."
```

Most of the hits will be noise — vendor code, test fixtures, `.example` files with placeholder
strings. Filter those mentally and focus on anything that looks like a real value in a real config.

---

## Finding 1: The gitignore gap

The most obvious category — a file with real credentials that isn't in `.gitignore`.

In my case it was `shopstack/ansible/deploy-vars.yml`. Six credentials in plaintext:
a Cloudflare API token, three database passwords, an InvoiceNinja app key, another DB password.

The file had never been committed — `git log --all -- ansible/deploy-vars.yml` was empty. But
it wasn't gitignored either. One `git add .` away from being on GitHub.

The check that catches this:

```bash
git check-ignore -v path/to/suspect/file
```

If it returns nothing, the file isn't protected. Fix it before the next commit.

The fix is two parts. Add it to `.gitignore`:

```
# Ansible
ansible/deploy-vars.yml
```

And create a `.example` alongside it so the required variables are documented:

```yaml
# ansible/deploy-vars.yml.example
domain: your-client.example.com
cf_api_token: CLOUDFLARE_API_TOKEN_HERE
postgres_password: GENERATE_WITH_openssl_rand_-hex_16
# ... etc
```

The example file commits. The real file doesn't. Anyone cloning the repo knows exactly what
to create.

---

## Finding 2: Credentials baked into AI tool permissions

This one surprised me.

Claude Code (the AI coding tool I use) maintains a `settings.local.json` that tracks which
shell commands have been approved to run without prompting. When you approve a one-time
`ansible-playbook` command that includes `--extra-vars 'api_token=...'`, that full command
string — credentials and all — gets written into the allowlist permanently.

The file is globally gitignored, so it's not a git leak. But it's plaintext on disk, and it
persists indefinitely. Mine had accumulated:

- A Twilio SID and auth token from deploying an SMS alert service
- A Discord webhook URL
- An AWS IAM access key and secret from a one-time IAM setup session
- A Proxmox API token from a one-off curl command

None of these belong in a permissions file. They got there because I approved commands
that had the credentials inline rather than loading them from a file first.

The fix is to move the credentials to a gitignored env file and update the command to source it:

```bash
# Before (credentials baked in):
ansible-playbook setup-alert.yml \
  --extra-vars 'twilio_token=abc123 discord_webhook=https://...'

# After (credentials loaded from file):
set -a && source scripts/secrets/alert.env && make deploy-alert
```

The `scripts/secrets/` directory gets its own `.gitignore` that ignores everything except
`.example` files:

```
# scripts/secrets/.gitignore
*
!.gitignore
!*.example
```

This pattern means you can commit the directory structure and example templates, but the real
secret files never show up in `git status`.

---

## Finding 3: The same credential in two repos

The Cloudflare API token I use for Traefik's DNS-01 ACME challenge was also in the ShopStack
`deploy-vars.yml`. Same token, two repos.

This is a blast radius problem. If either repo's secrets are compromised, the attacker gets
credentials that work in both contexts. A token scoped to one purpose shouldn't be reused
for another.

The fix is to create a separate scoped token for each use case. Cloudflare's API supports
tokens scoped to a specific zone with specific permissions. The Traefik token gets DNS edit
rights for the homelab zone. The ShopStack token gets DNS edit rights for client zones only.

If I'm ever deploying for a paying client, I want to know that a credential leak in that
engagement can't pivot to my homelab.

---

## Rotating without breaking things

Once you've found the issues, rotation needs to happen carefully — especially for credentials
that are wired into running services.

**First: audit what's actually deployed.**

Before rotating anything, SSH into the services that use each credential and check what's
actually running. In my case, the Twilio token I found had never been deployed to the live
service (the fields were blank). Rotating it carried zero risk of breaking anything.

If the credential *is* live, you need to rotate in the right order: create new → deploy new →
verify → revoke old. Not: revoke old → scramble.

**Twilio auth token rotation:**

Twilio uses a secondary-token promotion model. You can't just generate a new primary token
directly. The flow is:

```bash
# Step 1: Generate a secondary token
curl -X POST "https://accounts.twilio.com/v1/AuthTokens/Secondary" \
  -u "$TWILIO_SID:$TWILIO_AUTH_TOKEN"

# Step 2: Promote it to primary using the *secondary* token as auth
# (this invalidates the old primary immediately)
curl -X POST "https://accounts.twilio.com/v1/AuthTokens/Promote" \
  -u "$TWILIO_SID:$SECONDARY_TOKEN"
```

After promotion, the old primary is dead. Verify your services are healthy before moving on.

**AWS IAM key rotation:**

The AWS key I found in the allowlist had already been deleted in a prior rotation — it didn't
show up in `aws iam list-access-keys` at all. But I rotated the currently active key anyway,
since the audit surfaced it:

```bash
# Create the new key first
aws iam create-access-key --user-name myuser

# Update ~/.aws/credentials with the new values, verify it works
aws iam get-user

# Then delete the old one
aws iam delete-access-key --user-name myuser --access-key-id AKIAOLD...
```

Always create before deleting. IAM accounts are limited to two active keys per user — if you
delete first and something goes wrong with the new key, you're locked out.

---

## The audit checklist

What I run now, periodically:

```bash
# 1. Grep for credential patterns
grep -rn --include="*.yml" --include="*.json" --include="*.env" --include="*.tf" \
  -iE "(password|token|secret|api_key|webhook)[=:]\s*['\"]?[A-Za-z0-9+/]{10,}" \
  ~/Workspace/ | grep -v ".git/" | grep -v "node_modules/"

# 2. Check gitignore status on any file containing credentials
git check-ignore -v path/to/file

# 3. Verify no credential files were ever committed
git log --all --full-history -- path/to/sensitive/file

# 4. Scan git history for accidental commits (adjust regex for your tools)
git log --all -p -- '*.env' '*.key' | grep "^\+" | grep -iE "(password|token|secret)=" | head -20

# 5. Check for stale allowlist entries
grep -iE "(password|token|secret|api_key|webhook)" .claude/settings.local.json
```

The last one is the new one. If you use Claude Code, LLM coding agents, or any AI tool that
builds up a local permissions file — check it. These files accumulate credential-bearing commands
over time and most people never think to look.

---

Running your own infrastructure means no security team is running these audits for you. The
blast radius of a credential leak in a homelab is usually small — but "usually" is doing a lot
of work in that sentence when the credentials in question touch your DNS, your SMS provider,
and your cloud account.

An hour of grep commands now is cheaper than an hour of incident response later.
