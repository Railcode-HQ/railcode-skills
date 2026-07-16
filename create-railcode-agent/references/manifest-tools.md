# Agent Manifest Tools Reference

The manifest's `tools` object is a server-validated whitelist. The CLI has no
local schema — `agent create`/`update`/`test` send the JSON straight to the API —
so this list is a snapshot of the backend's current vocabulary, not a contract.
Confirm the live shape with `railcode agent pull` on an existing agent, and treat
every "Unknown ... key" or save-time error as authoritative over this file.

Top-level manifest keys: `kind`, `name`, `description`, `model`, `system`,
`input_schema`, `tools`, `limits`. Anything else is rejected. `triggers` (cron) is
**not** a manifest key — schedules are a separate resource, see
[cli-workflow.md](cli-workflow.md).

## `tools` keys

| Key | Type | Grants (runtime tool names) | Permission gate |
|---|---|---|---|
| `saved_queries` | `string[]` (query names) | `query(name, params)` | must be a ratified saved query in the org |
| `connectors` | `{connector: endpoint[]}` | `connector(name, method, path, body)` | each `connector:endpoint` must be ratified |
| `docs` | `string[]` (connector names) | `docs(connector)` — reads that connector's stored docs | connector must exist |
| `email` | `bool \| {emails: string[], domains: string[]}` | `email(to, subject, html/text, cc, bcc)` — recipients restricted to the allowlist when one is set | `email` grant (org default: `*`) |
| `adhoc_sql` | `string[]` (connection names) | `sql(connection, text, params)` — raw SQL, no firewall | `connector` grant; also a ratification **warning** ("prefer saved queries or read-only credentials") |
| `app_data` | `string[]` (app slugs) — **read** | `app_kv_get`, `app_kv_query`, `app_kv_count` against the app's shared KV | `can_access_app` — same bar as opening the app |
| `app_data_write` | `string[]` (app slugs) — **write**, new 2026-07-16 | `app_kv_set`, `app_kv_delete`, `publish_artifact_to_app(name, app)` | `can_manage_app` — the app's **owner, or an org admin, only**. Declaring it for an app you don't manage is a **hard save failure**, not a warning |
| `code_exec` | `bool` | the sandbox's own tool set (bash + read/write/edit/grep/find/ls), reported dynamically by the sandbox at boot — one all-or-nothing authority | a ratification **warning** ("may run arbitrary code... can reach PyPI and npm") |
| `agent_kv` | `bool` | `agent_kv_get/set/query/delete` against the agent's own private, cross-run store | none beyond holding the agent itself |

A save that adds authority you don't hold (any row in the table above, not just
`app_data_write`) fails with the missing operations named — grant it via the org's
roles/grants first (`$manage-railcode-org`), or drop it from the manifest.

## Draft/test caveats

`railcode agent test` runs a draft with no `Agent` row, so two capabilities are
silently unavailable even when declared — there's no persistent store to act on:

- `app_data_write`'s write tools (`app_kv_set`, `app_kv_delete`,
  `publish_artifact_to_app`) are omitted from a test run's tool list entirely.
- `agent_kv`'s tools are likewise omitted.

Both are a runtime omission, not a manifest error — a test run just won't offer
the tool, so an untouched app/KV after `test` isn't evidence of a bug. Verify
write behavior with `railcode agent create` + `railcode agent run` instead.

`publish_artifact_to_app` also needs `code_exec`: it publishes a file the agent
already wrote to the sandbox's output directory, so there's nothing to publish
without a sandbox to write it from.

## `limits`

| Field | Default | Max |
|---|---|---|
| `max_steps` | 50 | 100 |
| `timeout_seconds` | 60 | 300 |
| `max_tool_calls` | 100 | 200 |
| `max_tokens` | 50000 | 500000 |
