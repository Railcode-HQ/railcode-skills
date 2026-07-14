# Railcode Organization CLI Reference

## Contents

- Setup and scope
- Apps and access
- Members and roles/grants
- Saved queries
- Data and service connectors
- Analytics and observability logs

## Setup and Scope

```bash
npm install -g railcode@latest
railcode --version
npm view railcode version
railcode login [--api-url <url>]
```

The CLI stores its selected instance, organization, and personal token at
`${RAILCODE_HOME:-~/.railcode}/config.json`. API URL resolution is `--api-url`, then
`RAILCODE_API_URL`, then saved config. `RAILCODE_API_TOKEN` overrides the saved token for CI.
On a `401`, the saved token is cleared and login must be repeated.

Management commands are org-scoped, work from any directory after login, and do not need an
app or `railcode.json`. Most references accept a human-readable name/slug/email or UUID. Use
`--json` for raw output and `railcode <command> --help` for the full current flag set.

## Apps and Access

```bash
railcode apps list
railcode apps show <app>
railcode apps access <app>
railcode apps set-access <app> --mode organization
railcode apps set-access <app> --mode private
railcode apps set-access <app> --mode restricted --members alice@example.com,bob@example.com
railcode apps transfer <app> --to <email|uuid>
railcode apps delete <app> [--yes]
```

`<app>` is a slug or UUID. Access modes are `organization` (every org member), `private`
(owners), and `restricted` (owners plus explicit members). Org admins/owners bypass per-app
access. `set-access`, `transfer`, and `delete` need app manage rights. Delete is irreversible,
removes deploys and app data, prompts on a TTY, and requires `--yes` non-interactively.

`apps access` includes direct policy grants and access conferred through roles/grants.

## Members and System Roles

```bash
railcode members list
railcode members set-role <email|uuid> --role admin|member
railcode members remove <email|uuid>
railcode members add --email <e> --name <n> --password <p> --role admin|member
railcode members add --email <e> --name <n> --password <p> --role member --no-password-change
```

Any member may list members. Mutations require admin authority. The owner tier is not
assignable through `set-role`. `members add` is for self-hosted provisioning; by default the
new user must change the supplied password.

## Custom Roles and Grants

```bash
railcode roles list
railcode roles create --name <name> [--description <text>]
railcode roles update <role> [--name <name>] [--description <text>]
railcode roles delete <role>
railcode roles add-member <role> <email|uuid>
railcode roles remove-member <role> <email|uuid>

railcode roles grants
railcode roles grant --subject <org|role:X|user:X> --resource <type> --ids <a,b>
railcode roles revoke <grant_id>
railcode roles materialize --subject <org|role:X|user:X> --resource <type>
railcode roles effective <email|uuid>
railcode roles catalog
```

`<role>` is a role name or UUID. Grant resource types are `app`, `llm`, `email`,
`sc_endpoint`, `connector`, `saved_query`, and `agent`. Grants are additive. `--ids` is a
comma-separated list and may use `*`; prefer explicit IDs. `materialize` expands wildcard
access into the resources that currently exist so future resources are not automatically
included.

Use `catalog` to discover grantable names and `effective` to verify a member's computed
access. App authority declared in `manifest.yaml` is ratified against this same grant model.

## Saved Queries

```bash
railcode query list
railcode query run my_orders --params '{"region":"emea","limit":5}'
railcode query create --name my_orders --connection analytics \
  --sql "select * from orders where region = :region limit :limit" \
  --params '[{"name":"region","type":"string"},{"name":"limit","type":"int","default":20}]'
railcode query update my_orders --sql-file my_orders.sql
railcode query delete my_orders
```

Create/update/delete are admin-only. Templates use `:name` placeholders with declared types
`string`, `int`, `float`, or `bool`. `run --params` is a JSON object; create/update `--params`
is an array of parameter declarations. SQL comes from `--sql` or `--sql-file`, never both.

`update` uses PATCH semantics: omitted fields stay unchanged; `--clear-params` declares no
params. SQL/param edits bump the version while preserving grants. Delete removes the saved
query and grants naming it.

The server injects `:_ctx_user_id`, `:_ctx_user_email`, and `:_ctx_org`; callers cannot
override `_ctx*` values. Use these binds for unforgeable caller row-scoping. `list` exposes
signatures, never SQL text.

## Data Connections

```bash
railcode connections list
railcode connections create --name <n> --kind postgres \
  --config-file connection.json --credentials-file credentials.json
railcode connections delete <name|uuid>
```

Create replaces a same-name connection and dials it before saving. Supported shapes:

- `postgres`: config `{host,database,username,port?,sslmode?}`, credentials `{password}`
- `bigquery`: config `{project_id,dataset}`, credentials `{service_account_json}`
- `turso`: config `{url}`, credentials `{auth_token}`

Inline `--config <json>` and `--credentials <json>` are supported, but file options reduce
shell-history exposure. Deleting a connection can break saved queries and apps; inspect
dependents first.

## Service Connectors

```bash
railcode connector list --admin
railcode connector native
railcode connector enable <key> --credentials-file credentials.json
railcode connector create --name <n> --base-url <url> --auth-type bearer \
  --auth-config-file auth.json --methods GET,POST --description <text>
railcode connector delete <name|uuid>
```

`list --admin` shows management fields such as base URL, credential state, enabled state, and
native key. `native` lists presets and their credential fields. `enable` creates or rotates a
native connector credential. Custom connector auth types and exact flags are shown by
`railcode connector --help`; use `--disabled` to create one disabled and restrict `--methods`
to the required HTTP verbs.

Member-facing `connector list`, `docs`, and `fetch` are invocation tools. Use them only as a
deliberate verification call because `fetch` can cause downstream side effects.

## Analytics

```bash
railcode analytics <app> [--range 7d|30d|90d]
```

The default range is `30d`. Output includes totals, uniques, daily values, top paths, and top
users. `<app>` is a slug or UUID; `--json` prints the raw object.

## Observability Logs

```bash
railcode logs <stream> [filters]
railcode logs <stream> <request_id>
```

Streams and required capabilities:

- `connector` — data-connection SQL (`connection:manage`)
- `service-connector` — proxied HTTP calls (`service-connector:manage`)
- `llm` — LLM gateway calls (`llm:manage`)
- `email` — email gateway sends (`email:manage`)
- `agent` — managed-agent runs (`agent:manage`)

Optional filters are validated per stream: `--app <slug|uuid>`, `--user <email|uuid>`,
`--connector <name>`, `--agent <uuid>`, `--source app|agent` (LLM only), `--status <value>`,
and `--limit <1..500>` (default 100). Use the request ID form for full JSON detail. Avoid
copying sensitive request/response bodies into handoffs.
