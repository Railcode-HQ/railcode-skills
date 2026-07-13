# CLI Workflow

Use this reference when an agent needs exact Railcode CLI behavior, local dev behavior, or
app deploy behavior on the **multi-tenant** Railcode platform.

The CLI ships as the npm package **`railcode`**. Its full command set is:

```
railcode login [--api-url <url>]              Sign in (browser) and mint a personal API token
railcode login --setup-token <token>          Non-interactive onboarding login (one-time setup token)
railcode init <app> [--template static|react] Scaffold a new app directory
railcode dev [--port <n>] [--asset-port <n>] [--reset]   Run the app locally against an emulated /_api
railcode deploy [--private]                   Build (if configured) and deploy the app here
railcode design-system                        Print your org's design-system guidance (markdown)
railcode db <list|query> ...                  List data connectors / run ad-hoc SQL
railcode query <list|run|create|update|delete> ...   Saved queries: invoke by name / author (admin)
railcode connector <list|docs|fetch|native|enable|create|delete> ...   Call service connectors / manage them (admin)
railcode llm <providers|models>               List the LLM providers/models apps can call
railcode manifest <validate|show> ...         Validate manifest.yaml / show an app's ratified authority manifest
railcode agent <list|show|pull|create|update|delete|test|run> ...   Manage org-scoped managed agents
railcode agent schedule <show|set|add|update|pause|resume|delete|run-now> <agent>   The agent's one cron schedule
railcode apps <list|show|access|set-access|transfer|delete> ...   Apps + access policy (owner/admin)
railcode members <list|set-role|remove|add> ...   Org members + system roles (list: any member; mutations: admin)
railcode roles <list|create|update|delete|add-member|remove-member|grants|grant|revoke|materialize|effective|catalog> ...   Org roles + granular grants (admin)
railcode connections <list|create|delete> ... Manage org data connectors (admin)
railcode analytics <app> [--range 7d|30d|90d]  Per-app pageview analytics (owner/admin)
railcode logs <connector|service-connector|llm|email|agent> [filters]   Org observability logs (admin)
railcode --version
railcode --help
```

The `apps`, `members`, `roles`, `connections`, `analytics`, `logs`, and the `connector`
admin subcommands (`native`/`enable`/`create`/`delete`) mirror the web console's owner/admin
surfaces — see [Org Admin Console](#org-admin-console-cli). App-building rarely needs them;
they're documented so the command set above is complete.

Upgrade the CLI through your package manager (`npm install -g railcode@latest`) — it's a
regular npm package, not a self-updating binary.

## Install The CLI

Install the CLI globally:

```bash
npm install -g railcode@latest        # or: pnpm add -g railcode@latest
```

The CLI stores config at `${RAILCODE_HOME:-~/.railcode}/config.json` (dir `0700`, file
`0600`):

```json
{ "apiUrl": "...", "email": "...", "apiToken": "rc_...", "tokenPrefix": "rc_...",
  "orgUuid": "...", "orgSlug": "...", "appHostStrategy": "two_label" }
```

API-URL resolution for every command: `--api-url` flag > `RAILCODE_API_URL` env > saved
config > prompt (the prompt default is the dev URL `http://api.127.0.0.1.nip.io`). Set
`RAILCODE_API_TOKEN` to override the saved token in CI. On a `401`, the saved token is
cleared and you're told to `railcode login` again.

## Log In

```bash
railcode login [--api-url <url>]
```

Login is **browser-based** (not an email/password prompt). The CLI:

1. Starts a localhost HTTP callback, prints the authorization link, and **auto-opens your
   default browser** to it (new in CLI 0.1.14; paste the printed URL if it doesn't open).
2. The browser does normal dashboard auth and approves the CLI.
3. The CLI exchanges the one-time code for a long-lived, revocable **personal API token**,
   resolves your organization, and saves everything to `~/.railcode/config.json`.

Browser login needs a TTY. In non-interactive environments set `RAILCODE_API_TOKEN`
instead. If you have no organization yet, finish onboarding in the dashboard, then run
`railcode login` again so the org is saved (deploy needs it).

`railcode login --setup-token <rc_setup_...>` is the no-TTY, no-browser onboarding path: a
**one-time, ~10-minute** setup token (minted by the dashboard's copied CLI prompt) is
exchanged once for a personal API token and writes the same `config.json`. If it's expired
or already used, generate a fresh prompt from the dashboard.

## Create An App

```bash
railcode init <app> [--template static|react]
```

Behavior:

- Validates the app slug against `^[a-z0-9][a-z0-9-]{0,62}$` (a DNS label: lowercase
  letters, digits, dashes).
- Scaffolds a **single self-contained directory `./<app>/`** — there is no
  `apps/`/`app-bundles/` workspace split, and no template repo is copied.
- Refuses to scaffold into a non-empty directory.

Templates:

- **`react`** (default) — a React 19 + Vite 7 + Zustand 5 + TypeScript starter that builds to
  `dist/`, with `railcode.json` `{ "app": "<slug>", "build": "npm run build", "dist": "dist" }`.
  Run `npm install` before `railcode dev`/`railcode deploy`.
- **`static`** — a no-build app: `index.html` that loads `/_api/sdk.js` and demos
  `await me()` + `db.collection().put/get`, plus `railcode.json` with `{ "app": "<slug>",
  "dist": "." }`. No dependencies, no build step.

Treat the starter as functional scaffolding, not a style guide.

The CLI runs **your app's** package manager for builds and dev — detected from a
`packageManager` field or lockfile (pnpm/yarn/bun), defaulting to **`npm`** when there's no
lockfile (new in CLI 0.1.17; older CLIs hardcoded pnpm). Examples use `npm`; use whatever your
app declares.

## Local Dev

```bash
railcode dev [--port <n>] [--asset-port <n>] [--reset]
```

Run it from the app directory (any directory with a `railcode.json` that has an `"app"`
slug). Behavior:

- Serves the app on a single loopback origin, starting at `http://127.0.0.1:7331` and
  climbing (`7332`, …) when the port is busy. Print-and-open the URL it reports.
- **Static mode**: serves files straight from the app root (the deploy resolution mirrored).
- **Asset mode**: when `package.json` has a `dev` script (or `railcode.json` sets
  `dev.command`), the CLI runs the app's own dev server (Vite) and reverse-proxies it,
  tunnelling the HMR WebSocket. `--asset-port` / `railcode.json` `dev.port` set the starting
  Vite port (default `5173`). It does **not** install dependencies for you — if
  `node_modules` is missing it tells you to install them first (`npm install`, or your app's
  package manager).
- `--reset` wipes this app's local KV/files before starting.

`railcode dev` emulates the `/_api/*` data plane on local disk and proxies the rest to your
real instance:

- `GET /_api/sdk.js` — serves the bundled SDK.
- `GET /_api/me` — synthetic identity `{ user, app, org }` (user `dev@localhost`).
- `GET /_api/app-users` — a single synthetic member.
- `GET /_api/config/design-system` — your org's **real** configured markdown when logged in;
  empty otherwise (never errors).
- `/_api/kv/*` — JSON KV stored under `~/.railcode/dev/<instance>/<app>/kv.json`, queried by
  the same engine production uses.
- `/_api/files*` — bytes under `~/.railcode/dev/<instance>/<app>/files/`, metadata in
  `files.json`.
- `/_api/connections`, `/_api/sql`, `/_api/queries` + `/_api/queries/{name}`,
  `/_api/llm/generate`, `/_api/llm/stream`, `/_api/llm/providers`, `/_api/email` +
  `/_api/email/send`, `/_api/service-connectors` + `/_api/service-connectors/request` —
  **proxied to the real instance** with your saved token, invoked as the **signed-in user**
  on the org/user-scoped plane (`/api/organizations/{org}/data/*`, `…/llm/*`, `…/email/*`) —
  **not** a deployed app, so **no `railcode deploy` is needed first**. These hit the org's
  real provider, quota, databases, connectors, and mail — **real spend and real data**.
  Authority is your own grants (a deployed app is instead bound by its ratified manifest).
  Email forwarding is new in CLI 0.1.19; earlier CLIs 404 on `email.send()` in dev.

When you're **not logged in**, the list endpoints (`connections`, `service-connectors`,
`llm/providers`) degrade to empty and the call endpoints (`llm`, `sql`, `email/send`, a
connector `request`) return `503`
(never `401`, which the SDK would treat as a session lapse and reload-loop on). The startup
banner states which mode you're in.

The local state directory is namespaced by `(instance, org)` so two orgs' same-slug apps
never share KV/files. Concurrent `railcode dev` sessions for the same app/org share that
directory.

## Read The Design System

```bash
railcode design-system
```

Prints your org's configured design-system markdown straight to stdout (so it pipes/feeds
cleanly into an agent). Needs a logged-in CLI; resolves the server like every other command.
Returns empty when no admin has configured a design system for the org.

## Query Data Connectors

```bash
railcode db list                                   # list the org's data connectors
railcode db query "select 1"                       # read-only SQL against connection `default`
railcode db query "select * from orders where total > $1" --params '[100]'
railcode db query --file report.sql --connection analytics
```

`railcode db` inspects the org's **data connectors** (admin-configured Postgres, BigQuery, or
Turso) and runs ad-hoc read-only SQL from the terminal — the same connectors and SQL the
in-app `dataConnectors()` / `data().runSQL()` use. Data connectors are **org-scoped**, so these
one-shot commands **work straight after `railcode login`** — **no app and no `railcode.json`
required**. They hit the app-less org data plane (`/api/organizations/{org}/data/*`) with your
login token; run them from any directory. (This is new in CLI 0.1.13 — earlier versions required
a deployed app.)

- `railcode db list` (aliases `ls`, `connections`) — prints each connector's `name` +
  `engine`; `--json` prints the raw array.
- `railcode db query "<sql>"` (alias `sql`) — runs the SQL and prints a table + row count.
  `--connection <name>` (default `default`), `--engine <postgres|bigquery|turso>` (inferred
  from the connector list when omitted), `--params '<json-array>'` binds positional
  placeholders (`$1, $2, …` on Postgres; `?` on BigQuery/Turso), `--file <path>` reads SQL
  from a file (mutually exclusive with the positional arg), `--json` prints the raw
  `{ columns, rows, rowcount, truncated }` envelope.

Treat SQL as read-only — always use placeholders + `--params`, never string interpolation.
(On Postgres and Turso the platform enforces this with read-only sessions. BigQuery has no
session-level read-only mode, so its connection credential's privileges are the boundary.)

Note the two different `--params` shapes: `railcode db query` takes a positional **array**
(`'[100]'` binds `$1`); `railcode query run` takes a named **object** (see below).

## Saved Queries

*(New in CLI 0.1.14.)* A **saved query** is a named, versioned SQL template an org admin
publishes against one data connection. Members and apps invoke it **by name** with typed,
named params — the grant-gated alternative to ad-hoc SQL, and the same queries the in-app
`query('name', params)` / `savedQueries()` SDK globals use. Like `railcode db`, these are
org-scoped: they work straight after `railcode login`, no app required.

```bash
railcode query list                                # signatures: name, params, version, description
railcode query run my_orders --params '{"region":"emea","limit":5}'
railcode query create --name my_orders --connection analytics \
  --sql "select * from orders where region = :region limit :limit" \
  --params '[{"name":"region","type":"string"},{"name":"limit","type":"int","default":20}]'
railcode query update my_orders --sql-file my_orders.sql   # edit in place; version bumps
railcode query delete my_orders                            # removes the query AND grants naming it
```

- **Templates use `:name` placeholders** (not `$1`) matched to declared params, each typed
  `string | int | float | bool`. A param declared with a `"default"` is optional at invoke
  time — the server binds the default when the caller omits it.
- **`--params` is JSON on every subcommand**: `run` takes one JSON **object** (exactly what
  the API takes); `create`/`update` take a JSON **array** of
  `{"name","type","default"?}` declarations.
- **The SQL comes from `--sql` (inline) or `--sql-file`** — never both. Use the
  `--sql="..."` form if the template starts with a `--` comment (a bare `--sql` followed by
  a `--`-leading value is parsed as a flag).
- **`update` edits in place** with PATCH semantics: pass any of `--sql`/`--sql-file`,
  `--params` (replaces the declared list), `--clear-params` (declare none),
  `--connection`, `--description`; omitted fields keep their value. Editing SQL or params
  bumps the query's version; **grants naming the query survive** — unlike delete +
  recreate, which removes them.
- **Context binds**: templates may reference `:_ctx_user_id`, `:_ctx_user_email` and
  `:_ctx_org` — the server injects those from whoever invokes, and a caller-supplied
  `_ctx*` param is rejected with a 400. `where rep_email = :_ctx_user_email` is per-caller
  row scoping the caller cannot forge.
- `list`/`run` are member operations (invocation can be grant-gated per query by admins);
  `create`/`update`/`delete` are **admin-only** (403 otherwise). `list` returns signatures
  only, never the SQL text. Aliases: `query` = `queries`, `list` = `ls`, `run` = `invoke`;
  `--json` on `run` prints the raw `{ columns, rows, rowcount, truncated }` envelope.

## Call Service Connectors

```bash
railcode connector list                                          # list service connectors
railcode connector docs stripe                                   # how to call one connector's API
railcode connector docs stripe --openapi                         # just its OpenAPI spec (inline text, else URL)
railcode connector fetch "/v1/charges?limit=3" --connector stripe
railcode connector fetch "/v1/charges" --connector stripe --method POST --body "amount=500&currency=usd"
```

`railcode connector` lists, documents, and calls the org's **service connectors**
(admin-configured HTTP proxies to SaaS APIs) — the same surface the in-app
`serviceConnectors()` / `connector().fetch()` use. The connector holds the credential; you
control only method/path/body. Service connectors are **org-scoped**, so — like `railcode db` —
these commands **work straight after `railcode login`** with **no app or `railcode.json`
required**, hitting the same `/api/organizations/{org}/data/*` plane.

- `railcode connector list` (aliases `ls`, `connectors`) — prints `name`, `auth_type`, and
  `allowed_methods` (plus a `description` column, and a `docs` column reading `api` /
  `openapi` for the connectors that expose documentation); `--json` for the raw array.
- `railcode connector docs <name>` (alias `doc`) — prints one connector's documentation
  bundle so you know how to call it: usage instructions, the API-docs link (or inline text),
  and the OpenAPI spec (link or inline) when the admin configured them. `--openapi` prints
  only the spec (inline text if present, else its URL; exits non-zero when there is none);
  `--json` for the raw docs object. Use the `docs` column from `connector list` to see which
  connectors have anything to show.
- `railcode connector fetch <path>` (alias `request`) — proxies one HTTP call.
  `--connector <name>` (required), `--method <verb>` (default `GET`; must be allowed by the
  connector or the server returns 405), `--body <string>` / `--file <path>` (mutually
  exclusive), `--json` prints the raw `{ status, ok, headers, body, truncated }` envelope. A
  non-2xx upstream status is still printed, but the command exits non-zero.

## LLM Gateway

*(New in CLI 0.1.15.)*

```bash
railcode llm providers            # configured providers, each with its models
railcode llm models               # flat list of every callable model
railcode llm providers --json     # raw provider array
```

`railcode llm` shows the org's LLM gateway exactly as apps see it — the same catalog the
in-app `llmProviders()` SDK global returns. Like `railcode db`/`connector`, it's **org-scoped**
and works straight after `railcode login`, no app or `railcode.json` required
(`GET /api/organizations/{org}/llm/providers`).

- `railcode llm providers` (alias `provider`) — one row per provider (`provider`, whether it's
  the org default, and its models joined in a cell with the default model marked).
- `railcode llm models` (alias `model`) — one row per `(model, provider)` with the org default
  marked.
- Keys, LiteLLM strings, and cost rates are never shown.

An org can configure **many models across many providers**. In app code, calls route by
`(provider, model)`: pass `opts.model` (a catalog model name — its provider is implied) and/or
`opts.provider` (a provider name alone → that provider's default model) to `llm.generate()` /
`llm.stream()`, or pass neither to use the org default marked in the listing.

## Managed Agents

*(New in CLI 0.1.20.)* A **managed agent** is a server-side AI agent your org runs —
defined by a JSON manifest (model, system prompt, tools, optional input schema), stored
under `agent.manifest`, and invoked on demand or on a cron schedule. This is a distinct
surface from the static apps this skill mostly builds: agents live in the org, not in an
app directory. Like `railcode db`/`connector`/`llm`, the commands are **org-scoped** and
work straight after `railcode login` — **no app or `railcode.json` required** — hitting
`/api/organizations/{org}/agents`.

```bash
railcode agent list                                     # name, model, uuid, updated
railcode agent show <agent> [--manifest]                # one agent (or just its manifest JSON)
railcode agent pull <agent> [--output agent.json]       # write the manifest for editing (stdout by default)
railcode agent create --file agent.json                 # create from a JSON manifest
railcode agent update <agent> --file agent.json         # replace an existing agent's manifest
railcode agent delete <agent> [--yes]                   # archive it (run history is kept)
railcode agent test --file agent.json --input '{"k":"v"}'   # run a draft manifest without saving
railcode agent run <agent> --input '{"k":"v"}' [--trace]    # invoke a saved agent, print the result
```

- An `<agent>` reference is a **name or a UUID** (either resolves). Aliases: `list`=`ls`,
  `show`=`get`, `pull`=`export`, `update`=`edit`, `delete`=`rm`, `run`=`invoke`;
  `agent`=`agents`.
- **Manifests are JSON** in the exact `agent.manifest` shape the API stores (note the
  contrast with **app** manifests, which are YAML). `agent pull` writes the current
  manifest so you can edit and re-`update` it; `agent show --manifest` prints it to stdout.
- **`create`/`update`** print the agent name, UUID, and any ratification **warnings**;
  `--json` prints the raw response. `delete` **archives** the agent (its run history is
  kept) — it prompts unless you pass `--yes`, and requires `--yes` in a non-interactive
  session.
- **`run`/`test`** take input from `--input '<json>'` or `--input-file <path>` (default
  `null`; the two are mutually exclusive) and print `Status:`, the request id, and the
  output JSON. `--trace` appends the step trace (a table of each model/tool step);
  `--json` prints the raw run detail. `test` runs an unsaved draft manifest; `run` invokes
  a saved agent. Note the invocation exits **0** whenever the request itself succeeds — a
  run that *fails at runtime* (a limit or model error) still prints its failed `Status` and
  exits 0; only invalid input (schema mismatch) is a non-zero `422`. Check `Status:`/`--json`
  in scripts rather than relying solely on the exit code.
- **Permissions:** `list`/`show`/`pull` need agent-read; `run` also needs an
  agent-invoke grant for that agent; `create`/`update`/`delete`/`test` and every
  `schedule` mutation are **owner/admin** (403 otherwise).

### Agent Schedules

Each agent has **at most one** cron schedule (the poller fires it server-side). Schedules
are a resource *under* the agent, not part of the manifest.

```bash
railcode agent schedule show <agent>                                  # the one schedule (or "no schedule")
railcode agent schedule set <agent> --cron "0 9 * * *" --timezone UTC # create if missing, else update (upsert)
railcode agent schedule pause <agent>                                 # disable without deleting
railcode agent schedule resume <agent>                                # re-enable
railcode agent schedule run-now <agent> [--trace]                     # fire it immediately, print the run
railcode agent schedule delete <agent> [--yes]                        # remove the schedule
```

- **`set`** upserts the single schedule: it creates one when none exists (requires
  `--cron`; `--name` defaults to `default`, `--timezone` to `UTC`, enabled by default) and
  otherwise updates the existing one (pass any of `--name`, `--cron`, `--timezone`,
  `--enabled`/`--disabled`). `add`/`create` create-only (error if one already exists) and
  `update` update-only (error if none) are available when you want the stricter form.
- `--cron` (alias `--schedule`) is a five-field cron expression; `--timezone` is an IANA
  zone. `pause`/`resume` just toggle `enabled`. `run-now` (alias `run`) fires synchronously
  and prints the run detail like `agent run`. `delete` (alias `rm`) prompts unless `--yes`.

## Deploy An App With The CLI

```bash
railcode deploy [--private]
```

Deploy behavior:

- Requires a `railcode.json` with an `"app"` slug in the current directory.
- Resolves the output directory, then runs a build command when needed (see resolution
  below), and uploads every file in the output dir (which must contain a root `index.html`)
  to the org-scoped multipart deploy API
  (`POST /api/organizations/{org}/apps/{appUuid}/deploy`).
- Skips `.git`, `node_modules`, `.DS_Store`, and (at the app root) `railcode.json`,
  `package.json`, lockfiles (`package-lock.json` / `pnpm-lock.yaml` / `yarn.lock` /
  `bun.lockb`), `manifest.yaml`.
- The app is **created-or-resolved by slug in your saved org**. On the **first successful**
  deploy for a slug the server creates the app (default **`organization`** access); a failed
  first deploy leaves no phantom not-deployed app behind.
- `--private` is a **one-shot** flag that sets this app's access to `private` as part of this
  deploy only — it is never persisted (see [App Access](#app-access)). `railcode init` no
  longer accepts `--private`.
- The app directory should have a `manifest.yaml`; deploy sends it and prints the
  ratification outcome (see [App Manifest](#app-manifest-authority)).
- Uses the saved API token (or `RAILCODE_API_TOKEN`); clears the token and asks you to log in
  again on `401`.
- Prints the live URL `http://<app>.<org>.<serving-domain>/` after upload.

Deploy output resolution order:

1. `railcode.json` `"dist"` wins (use `"."` for a no-build static app). `"build"` still runs
   first if also set.
2. Otherwise `railcode.json` `"build"` runs and `dist/` is uploaded.
3. Otherwise a `package.json` with a `build` script runs `<pm> run build` — where `<pm>` is
   your app's package manager (pnpm/yarn/bun by lockfile, else `npm`) — and uploads `dist/`.
4. Otherwise a root `index.html` can be deployed interactively (a `y/N` prompt); for CI set
   `"dist": "."`.

The `railcode.json` schema is `{ app, build?, dist?, dev?: { root?, command?, port? } }`.

## App Access

A new app defaults to **`organization`** access — every member of your org may open it.
Access is otherwise managed in the **admin UI**, the `railcode apps` CLI commands (see
[Org Admin Console](#org-admin-console-cli)), or the access API. The owner or an org admin
changes it:

```bash
railcode apps access <app>                          # show the current mode + per-user grants
railcode apps set-access <app> --mode private       # or: organization | restricted
railcode apps set-access <app> --mode restricted --members alice@x.io,bob@x.io
```
```text
GET  /api/organizations/{org}/apps/{app}/access
PUT  /api/organizations/{org}/apps/{app}/access      { "mode": "...", ... }
```

Modes: `organization` (every org member, the default), `private` (owners only), `restricted`
(owners plus explicitly-granted members). Org admins/owners bypass per-app access entirely.
See [platform-magic.md](platform-magic.md) for the access model.

The only deploy-time control is `railcode deploy --private`: a **one-shot** action that sets
`mode: private` on that deploy and nothing more (it doesn't persist a flag anywhere, so a
later plain `railcode deploy` won't re-assert it — flip access back in the dashboard and it
stays flipped). There is no persisted `private` key in `railcode.json`.

## App Manifest (Authority)

*(New in CLI 0.1.15 — granular permissions.)* Always write a `manifest.yaml` beside
`railcode.json` for every app you build or materially change. It declares **which privileged
operations an app performs and whose authority they run under**. It's separate from
`railcode.json` (which stays `{ app, build?, dist?, dev? }`) and is uploaded on deploy.

For pass-through apps, write an explicit minimal manifest:

```yaml
run_as: user
```

`run_as: user` means every call runs as the signed-in caller with *their* grants; the app
borrows no authority and there is nothing to ratify.

A manifest with `run_as: app` makes the app run privileged operations under its own **ratified**
authority (so callers who lack those grants can still use the feature through the app). Shape:

```yaml
run_as: app                 # or: user for pass-through apps
saved_queries: [my_orders]  # saved queries the app may invoke
connectors:                 # service-connector endpoints, per connector
  stripe: ["POST /v1/charges", "GET /v1/charges"]
llm: true                   # LLM gateway access
email: true                 # transactional email gateway access (email.send)
adhoc_sql: [analytics]      # only when the user explicitly requested direct/ad-hoc SQL
```

Commands:

```bash
railcode manifest validate [path]   # strict local parse (default ./manifest.yaml)
railcode manifest show <app>        # the app's ratified doc + any pending diff (by slug); --json
```

- `manifest validate` parses the file with the **same strict YAML grammar the server uses**
  (spaces not tabs; PyYAML 1.1 scalar rules — e.g. a bare `yes`/`no`/`on`/`off`/`null`/number
  resolves to a non-string and is rejected where a name is expected). It prints a summary of
  the declared operations; resource **names** (queries, connectors, connections) are only
  checked against your org at deploy.
- **On deploy**, the manifest is ratified against the deployer's own grants: operations you
  already hold ratify immediately; operations you **don't** hold land as a **pending diff
  awaiting approval** by someone who does. Deploy prints the outcome (`ratified` / `unchanged`
  / `removed`, plus any pending additions). Deleting the file reverts the app to pass-through,
  but agents should keep an explicit `run_as: user` manifest unless the user asks to remove it.
- `manifest show` needs login and app access (403 otherwise); it prints who ratified the
  current doc, its content hash, and any pending additions.
- `adhoc_sql` grants raw SQL authority and is intentionally scarce. Do not add it unless the
  user explicitly requested direct/ad-hoc SQL; otherwise use `saved_queries`.

## Org Admin Console (CLI)

The CLI mirrors the web dashboard's owner/admin console, so an operator can do everything
from the terminal. These are **org-scoped** (they target your saved org and work straight
after `railcode login`, no app or `railcode.json`) and **gated server-side by the same
capabilities as the console** — a plain member gets a `403` (`apps list`/`show`/`access`
follow the per-app access policy, and `members list` is readable by any member). App-building
rarely needs these; they're documented so the command set is complete. Most refs accept a
**name/slug/email or UUID**; pass `--json` for raw output. Run `railcode <command> --help`
for the full flag set.

```bash
railcode apps list                                  # slug, name, status, access, your role, manage
railcode apps show <app>                             # one app's details
railcode apps set-access <app> --mode private        # organization | private | restricted (+ --members)
railcode apps transfer <app> --to <email|uuid>       # change ownership
railcode apps delete <app> [--yes]                   # irreversible; prompts on a TTY, --yes to skip

railcode members list                                # any member; set-role/remove/add are admin
railcode members add --email <e> --name <n> --password <p> --role admin|member   # self-hosted provisioning
railcode members set-role <email|uuid> --role admin|member
railcode members remove <email|uuid>

railcode roles list                                  # admin-defined org roles + member counts
railcode roles create --name <n> [--description <d>] # also: update/delete/add-member/remove-member
railcode roles grant --subject <org|role:X|user:X> --resource <type> --ids <a,b>   # additive grants
railcode roles grants                                # list grant rows; revoke <id>; materialize --subject/--resource
railcode roles effective <email|uuid>                # a member's computed effective access
railcode roles catalog                               # grantable resources (apps/connectors/queries/…)

railcode connections list                            # org data connectors (postgres|bigquery|turso)
railcode connections create --name <n> --kind postgres --config '{...}' --credentials '{...}'   # dials before saving
railcode connections delete <name|uuid>

railcode connector list [--admin]                    # --admin: base_url, credential + enabled state, native key
railcode connector native                            # native presets (stripe/resend/…) + enabled state
railcode connector enable <key> --credentials '{...}'    # one-click enable/rotate a native preset
railcode connector create --name <n> --base-url <url> [--auth-type <t>] [--auth-config '{...}']
railcode connector delete <name|uuid>

railcode analytics <app> [--range 7d|30d|90d]        # per-app pageviews: totals, daily, top paths/users (default 30d)

railcode logs <stream> [filters]                     # streams: connector|service-connector|llm|email|agent
railcode logs <stream> <request_id>                  # full JSON detail for one entry
```

- `roles` manage the **granular grants substrate** (`--resource` ∈
  `app|llm|email|sc_endpoint|connector|saved_query|agent`); this is the same model the app
  `manifest.yaml` ratifies against. `roles effective`/`apps access` show who can reach what
  (`apps access` also lists app access conferred via `roles grant --resource app`).
- `logs` filters are per-stream (`--app`, `--user`, `--connector`, `--agent`, `--source`,
  `--status`, `--limit 1..500`); unsupported filters are rejected with the valid set.
- Errors are actionable: unknown refs, bad enum values, and missing flags print the accepted
  values; destructive `apps delete` needs `--yes` in a non-interactive session.
