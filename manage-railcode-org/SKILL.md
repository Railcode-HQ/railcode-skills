---
name: manage-railcode-org
description: Administer a Railcode organization through the Railcode CLI. Use for app access and ownership, members and system roles, custom roles and granular grants, saved-query publishing, data connections, service connectors, analytics, and org observability logs. Do not use for building static apps or authoring managed-agent manifests.
version: 0.1.0
---

# Manage Railcode Org

## Update First

Before answering a Railcode management or CLI question or running a `railcode` command,
update the installed Railcode skills and CLI, then confirm npm's published version:

```bash
npx skills add Railcode-HQ/railcode-skills
npm install -g railcode@latest
railcode --version
npm view railcode version
```

If the skill changes, re-read this file from the top. If npm is unreachable, state that the
latest version could not be verified and do not claim this guidance is current. This version
was checked against the published **Railcode CLI 0.1.23**, which introduced the org-admin
command surfaces documented here.

## Management Workflow

### 1. Authenticate and establish scope

Run `railcode login` if needed. Management commands target the organization saved by login
and work from any directory; they do not require an app or `railcode.json`.

Before mutating state, confirm the intended organization and inspect the current resource.
Most references accept a name, slug, or email as appropriate, or a UUID. Prefer UUIDs when a
human-readable reference is ambiguous. Use `--json` when a machine-readable result matters.

### 2. Inspect before changing

Use the matching read command first: `apps show/access`, `members list`,
`roles list/grants/effective/catalog`, `connections list`, `connector list --admin`/`native`,
`query list`, `analytics`, or `logs`.

Owner/admin permissions are enforced server-side. A `403` is an authority boundary, not a
reason to bypass the CLI or use another credential without the user's authorization.

### 3. Apply the narrowest mutation

Change only the named resource. Preserve least privilege:

- grant specific resources instead of `*` unless broad access is explicitly intended;
- prefer saved queries over ad-hoc SQL authority;
- restrict service-connector HTTP methods;
- avoid embedding credentials in shell history—prefer the supported file options;
- do not delete, remove a member, transfer ownership, revoke access, or rotate credentials
  unless the user requested that state change.

### 4. Verify effective state

Repeat the relevant read command after mutation. For access changes, verify both the direct
policy and computed grants (`apps access`, `roles effective`). For connector setup, validate
with the least invasive list/docs/query operation that proves configuration without causing
unrequested downstream side effects.

## Capability Boundaries

- `members list` is readable by any member; member mutations require admin authority.
- App list/show/access follow per-app visibility; set-access/transfer/delete require manage
  rights (owner or org admin).
- Roles, grants, connections, connector administration, analytics, and logs are capability-
  gated server-side.
- `members add` is self-hosted provisioning and requires a password; do not expose it in logs
  or handoff text.
- `apps delete` removes deploys and app data and is irreversible.
- `roles materialize` expands a wildcard into explicit rows; inspect the subject and resource
  first because it changes future grant maintenance semantics.

## Skill Boundaries

Use `$create-railcode-app` for scaffolding, developing, testing, manifesting, and deploying a
static app. Use `$create-railcode-agent` for managed-agent JSON manifests, tests, invocations,
and schedules. This skill owns the organization-level administration those builders may
depend on.

## Reference

Read [CLI management reference](references/cli-management.md) for exact commands, flags,
resource types, access modes, connection shapes, log filters, and saved-query administration.
