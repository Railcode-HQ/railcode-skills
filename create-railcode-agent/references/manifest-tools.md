# Agent Manifest Tools Reference

The manifest's `tools` object is a server-validated whitelist. The CLI has no
local schema — `agent create`/`update`/`test` send the JSON straight to the API —
so this list is a snapshot of the backend's current vocabulary, not a contract.
Confirm the live shape with `railcode agent pull` on an existing agent, and treat
every "Unknown ... key" or save-time error as authoritative over this file.

Top-level manifest keys: `kind`, `name`, `description`, `model`, `system`,
`input_schema`, `tools`, `limits`. Anything else is rejected. `triggers` (cron) is
**not** a manifest key — schedules are a separate resource, see
[cli-workflow.md](cli-workflow.md). `visibility` (`org` | `personal`) is **not** inside
the manifest either — it's a sibling field the CLI sends alongside `manifest` via
`--visibility` on `create`/`update`/`test` (see [cli-workflow.md](cli-workflow.md)).

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
| `personal_connectors` | `string[]` — toolkit names or `toolkit:tool` pairs (e.g. `["gmail"]` or `["gmail:send_email"]`); in-house tool slugs are lowercase and case-sensitive, so copy discovery output exactly | `personal_tools(toolkit)` (list that toolkit's callable tools + schemas) and `personal_call(toolkit, tool, arguments)` (run one) | **`visibility: personal` only** — a save with this key on an `org` agent is a hard failure. No grant is checked at save time; execution runs against the agent's **owner's own** connected account (Gmail, Slack, ...) and 403s per-call if the owner hasn't connected that toolkit yet |

A save that adds authority you don't hold (any grant-backed row above — `saved_queries`,
`connectors`, `docs`, `email`, `adhoc_sql`, `app_data`, `app_data_write`) fails with the
missing operations named — grant it via the org's roles/grants first
(`$manage-railcode-org`), or drop it from the manifest. `personal_connectors` is the one
exception: it has no grant to hold or ratify (there is no resource for a third party to
be granted — the agent's owner's own connection is the whole authority), so the only save
gate is `visibility: personal`.

## Draft/test caveats

`railcode agent test` runs a draft with no `Agent` row, so persistent storage behaves
differently under `test` than under a saved `run`:

- **`app_data_write`'s write tools are offered and simulated, not persisted or omitted**
  (changed from "omitted entirely" — as of 2026-07-17). `app_kv_set`/`app_kv_delete` are
  validated exactly as a saved run would (`can_manage_app`, and the target app must
  exist), then recorded into a per-run, in-memory overlay instead of the app's real
  store. Within that **same test run**, `app_kv_get` reads the overlay first (so a
  `set` then `get` sees the write, and a `delete` reads as not-found) before falling
  back to the live store — read-your-writes, scoped to the one run.
  `app_kv_query`/`app_kv_count` still compile to SQL over the **live** store only and do
  **not** reflect this run's simulated writes; the tool result says so. Nothing here
  ever reaches the app's real KV — verify actual persistence with
  `railcode agent create` + `railcode agent run` instead of `test`.
- `publish_artifact_to_app` is likewise validated and accepted on a draft, but marks
  nothing — a draft has no run-end artifact sink to publish through.
- `agent_kv`'s tools remain fully **omitted** on a draft (unchanged): there is no
  `Agent` row yet to key that store on, so there's no overlay for it either.

Treat an untouched app/KV after `test` as inconclusive for `agent_kv`, but a `test` run's
own `app_kv_get`/output IS meaningful for `app_data_write` — just remember it isn't the
app's real data.

`publish_artifact_to_app` also needs `code_exec`: it publishes a file the agent
already wrote to the sandbox's output directory, so there's nothing to publish
without a sandbox to write it from.

## `limits`

| Field | Default | Max |
|---|---|---|
| `max_steps` | 50 | 100 |
| `timeout_seconds` | 60 | 300 |
| `max_tool_calls` | 100 | 200 |
| `max_tokens_total` | 50000 | 500000 |
| `max_tokens_turn` | 8192 | 100000 |

`max_tokens_total` is the cumulative run budget (input+output across all turns); `max_tokens_turn`
is the per-turn output ceiling. `max_tokens` is accepted as a **legacy alias** for
`max_tokens_total`.
