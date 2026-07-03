# CLI Workflow

Use this reference when an agent needs exact Railcode CLI behavior, local dev behavior, or
app deploy behavior on the **multi-tenant** Railcode platform.

The CLI ships as the npm package **`railcode`**. Its full command set is:

```
railcode login [--api-url <url>]              Sign in (browser) and mint a personal API token
railcode init <app> [--template static|react] Scaffold a new app directory
railcode dev [--port <n>] [--asset-port <n>] [--reset]   Run the app locally against an emulated /_api
railcode deploy                               Build (if configured) and deploy the app here
railcode design-system                        Print your org's design-system guidance (markdown)
railcode db <list|query> ...                  List data connectors / run ad-hoc SQL
railcode query <list|run|create|update|delete> ...   Saved queries: invoke by name / author (admin)
railcode connector <list|docs|fetch> ...      List service connectors / read API docs / proxy one HTTP call
railcode --version
railcode --help
```

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

- **`static`** (default) — a no-build app: `index.html` that loads `/_api/sdk.js` and demos
  `await me()` + `db.collection().put/get`, plus `railcode.json` with `{ "app": "<slug>",
  "dist": "." }`. No dependencies, no build step.
- **`react`** — a React 19 + Vite 7 + Zustand 5 + TypeScript starter that builds to `dist/`,
  with `railcode.json` `{ "app": "<slug>", "build": "pnpm run build", "dist": "dist" }`.
  Run `pnpm install` before `railcode dev`/`railcode deploy`.

Treat the starter as functional scaffolding, not a style guide.

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
  `node_modules` is missing it tells you to run `pnpm install` first.
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
- `/_api/connections`, `/_api/sql`, `/_api/llm/generate`, `/_api/llm/stream`,
  `/_api/service-connectors`, `/_api/service-connectors/request` — **proxied to the real
  instance** with your saved token (app-scoped under `/api/organizations/{org}/apps/{app}/…`).
  These hit the org's real provider, quota, databases, and connectors — **real spend and real
  data**. The first real compute call (`llm`/`sql`/a connector `request`) creates the app
  server-side if it doesn't exist yet; a load-time list (`GET /connections`,
  `/service-connectors`) only resolves an existing app, never creates one.

When you're **not logged in**, the list endpoints (`connections`, `service-connectors`)
degrade to empty and the call endpoints (`llm`, `sql`, a connector `request`) return `503`
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
Snowflake) and runs ad-hoc read-only SQL from the terminal — the same connectors and SQL the
in-app `dataConnectors()` / `data().runSQL()` use. Data connectors are **org-scoped**, so these
one-shot commands **work straight after `railcode login`** — **no app and no `railcode.json`
required**. They hit the app-less org data plane (`/api/organizations/{org}/data/*`) with your
login token; run them from any directory. (This is new in CLI 0.1.13 — earlier versions required
a deployed app.)

- `railcode db list` (aliases `ls`, `connections`) — prints each connector's `name` +
  `engine`; `--json` prints the raw array.
- `railcode db query "<sql>"` (alias `sql`) — runs the SQL and prints a table + row count.
  `--connection <name>` (default `default`), `--engine <postgres|bigquery|snowflake>` (inferred
  from the connector list when omitted), `--params '<json-array>'` binds positional
  placeholders (`$1, $2, …` on Postgres; `?` on BigQuery/Snowflake), `--file <path>` reads SQL
  from a file (mutually exclusive with the positional arg), `--json` prints the raw
  `{ columns, rows, rowcount, truncated }` envelope.

Treat SQL as read-only — always use placeholders + `--params`, never string interpolation.
(On Postgres the platform enforces this: every session is opened read-only. BigQuery and
Snowflake have no session-level read-only mode, so there the connection credential's
privileges are the boundary.)

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

## Deploy An App With The CLI

```bash
railcode deploy
```

Deploy behavior:

- Requires a `railcode.json` with an `"app"` slug in the current directory.
- Resolves the output directory, then runs a build command when needed (see resolution
  below), and uploads every file in the output dir (which must contain a root `index.html`)
  to the org-scoped multipart deploy API
  (`POST /api/organizations/{org}/apps/{appUuid}/deploy`).
- Skips `.git`, `node_modules`, `.DS_Store`, and (at the app root) `railcode.json`,
  `package.json`, `pnpm-lock.yaml`.
- The app is **created-or-resolved by slug in your saved org**; first deploy creates it with
  the default **`organization`** access mode.
- Uses the saved API token (or `RAILCODE_API_TOKEN`); clears the token and asks you to log in
  again on `401`.
- Prints the live URL `http://<app>.<org>.<serving-domain>/` after upload.

Deploy output resolution order:

1. `railcode.json` `"dist"` wins (use `"."` for a no-build static app). `"build"` still runs
   first if also set.
2. Otherwise `railcode.json` `"build"` runs and `dist/` is uploaded.
3. Otherwise a `package.json` with a `build` script runs `pnpm run build` and uploads
   `dist/`.
4. Otherwise a root `index.html` can be deployed interactively (a `y/N` prompt); for CI set
   `"dist": "."`.

The `railcode.json` schema is `{ app, build?, dist?, dev?: { root?, command?, port? } }`.

## App Access

A new app defaults to **`organization`** access — every member of your org may open it.
Access is set in the **admin UI**, or via the access API. The owner or an org admin changes
it:

```text
GET  /api/organizations/{org}/apps/{app}/access
PUT  /api/organizations/{org}/apps/{app}/access      { "mode": "...", ... }
```

Modes: `organization` (every org member, the default), `private` (owners only), `restricted`
(owners plus explicitly-granted members). Org admins/owners bypass per-app access entirely.
See [platform-magic.md](platform-magic.md) for the access model.
