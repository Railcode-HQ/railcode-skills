# CLI Workflow

## Contents

- Install and login
- Create and develop an app (apps v2)
- Per-app secrets, worker logs, and the migration gate
- Use org-facing data, saved-query, connector, and LLM commands
- Deploy and set app access
- Deploy from CI with an app-scoped deploy token
- Validate the app authority manifest

Use this reference for exact Railcode CLI behavior relevant to building, testing, and
deploying an app on the **multi-tenant** Railcode platform. Written against **CLI 0.3.9**. For managed agents use
`$create-railcode-agent`; for organization administration use `$manage-railcode-org`.

The CLI ships as the npm package **`railcode`**. The app-building subset is:

```
railcode login [--api-url <url>] [--paste|--no-browser]   Sign in and mint a personal API token
railcode login --setup-token <token>          Non-interactive onboarding login (one-time setup token)
railcode init <app> [dir] [--template hono+vite|hono+static|tanstack|next|static] [--force]   Scaffold an app
railcode dev [--port <n>] [--reset]           Run the frontend AND the worker locally
railcode deploy [--private] [--no-source] [--force]   Build + deploy the static tree and worker
railcode pull [<deploy>] [--app <slug>] [--dir <path>] [--force]   Download a deploy's stored source
railcode secrets <set|import|ls|rm> ... [--app <slug|uuid>]   Per-app worker secrets — write-only (apps v2)
railcode logs app [<invocation_id>] [--app <slug>] [--limit <n>] [--follow]   Worker invocations + traces (apps v2)
railcode migrate [--app <slug>] [--yes]       Move a v1 app to apps v2 (ONE-WAY)
railcode manifest <validate|show> ...         Validate manifest.yaml / show the ratified authority
railcode design-system [get|set] ...          Print the org's design-system guidance
railcode db <list|query> ...                  List data connectors / run read-only SQL
railcode query <list|run|create|update|delete> ...  Invoke saved queries by name / author (admin)
railcode connector <list|catalog|link|add-mcp|tools|call|docs|fetch|access|share|...> ...
                                              Link your own accounts or custom APIs/MCP servers,
                                              call them, share them; admins manage every row
railcode llm <providers|models|default>       List models, or set the org default
railcode app kv <collections|list|get|set|delete|drop> ...   Read/write the deployed app's KV (owner)
railcode app files <list|download|upload|delete> ...   Read/write the deployed app's files (owner)
railcode apps show <app> [--json]             App details, incl. your rights and its generation
railcode apps access <app>                    Inspect the access policy
railcode apps set-access <app> ...            Set mode/members/editors (manage rights)
railcode apps add-editor|remove-editor <app> <email|uuid>   Grant/revoke co-deploy rights
railcode apps add-viewer|remove-viewer <app> <email|uuid>   Grant/revoke view rights (restricted, or an external user)
railcode ci github [--repo <owner/name>] [--branch <name>] [--yes]   Deploy from GitHub Actions
railcode token <create|list|revoke> ...       App-scoped deploy tokens for CI (edit tier)
railcode --version
railcode --help
```

Organization-level commands are intentionally excluded. Load `$manage-railcode-org` when the
task is to administer apps, members, roles/grants, connections, service connectors, saved
queries, analytics, or logs.

## Install The CLI

Install the CLI globally:

```bash
npm install -g railcode@latest        # or: pnpm add -g railcode@latest
```

Auto-update runs only on an interactive terminal (at most every 6 hours, never across a
major); off-TTY — every agent-driven session — run `npm install -g railcode@latest`
yourself. `RAILCODE_NO_UPDATE=1` disables it.

**How every command resolves its target.** API URL: `--api-url` flag > `RAILCODE_API_URL`
env > saved config > `https://api.railcode.app`. Token: `RAILCODE_API_TOKEN` overrides the
saved one; on a `401` the saved token is cleared and you're told to `railcode login` again.
A CI runner has **no `~/.railcode/config.json` at all**, so the token alone is not enough
there — the org uuid has nowhere to come from either. Set all three: `RAILCODE_API_TOKEN`,
`RAILCODE_API_URL` and `RAILCODE_ORG_UUID`. Without the last one the command stops at
*"No organization on file"* despite a perfectly valid token. Only the token is a secret;
the other two are identifiers. See [Deploy From CI](#deploy-from-ci-github-actions).

## Log In

```bash
railcode login [--api-url <url>] [--paste|--no-browser]
```

Login is **browser-based** (not an email/password prompt). The CLI:

1. Starts a localhost HTTP callback, prints the authorization link, and **auto-opens your
   default browser** to it; paste the printed URL if it doesn't open. The authorize page can
   also show a one-time code with a copy button, and the CLI accepts either the localhost
   callback or a pasted code — whichever happens first. `--paste` (or `--no-browser`) skips
   the localhost server entirely, for SSH/headless machines.
2. The browser does normal dashboard auth and approves the CLI.
3. The CLI exchanges the one-time code for a long-lived, revocable **personal API token**,
   resolves your organization, and saves everything to `~/.railcode/config.json`.

Browser login needs a TTY. In non-interactive environments set the env vars listed under
[Install The CLI](#install-the-cli) instead. If you have no organization yet, finish
onboarding in the dashboard, then run `railcode login` again so the org is saved (deploy
needs it).

`railcode login --setup-token <rc_setup_...>` is the no-TTY, no-browser onboarding path: a
**one-time, ~10-minute** setup token (minted by the dashboard's copied CLI prompt) is
exchanged once for a personal API token and writes the same `config.json`. If it's expired
or already used, generate a fresh prompt from the dashboard.

## Create An App

```bash
railcode init <app> [dir] [--template hono+vite|hono+static|tanstack|next|static]
```

- Validates the app slug against `^[a-z0-9][a-z0-9-]{0,62}$` (a DNS label).
- Scaffolds a **single self-contained directory** — `./<app>/` by default, or the optional
  `[dir]` (`railcode init foo .` scaffolds into the current directory). A non-empty target is
  fine, but an existing `railcode.json` is refused unless `--force`.
- **Every app created is generation 2 (apps v2).** There is no v1 template and no downgrade.

The five stacks — and **the CLI owns the build for all of them**, so the app declares no
bundler, no `wrangler`, no Cloudflare package, and no worker build script (`next` builds
through the `@railcode/next` dev dependency, which the template installs):

| Template | Frontend | Worker | Layout |
|---|---|---|---|
| **`hono+vite`** (default) | Vite + React | Hono | `frontend/` + `server/index.ts` |
| `hono+static` | one `index.html`, no build | Hono | `frontend/index.html` + `server/index.ts` |
| `tanstack` | TanStack Start (SPA mode) | server fns + `/api/*` | file routes; data routes need `ssr: false` |
| `next` | Next.js App Router, rendered by the worker | the Next app itself: Server Components, Server Actions, Route Handlers | `app/`; every path reaches the worker. See [Next.js and worker-first routing](#nextjs-and-worker-first-routing) |
| `static` | static tree | **none** | pure hosting; no server code |

The `hono+static` and `tanstack` templates scaffold a small **platform tour** — identity
(`ctx.user` + `appUsers`), a todo list on `db`, files, and the read-only org surfaces — over a
frontend that only fetches the worker's `/api` routes; the default `hono+vite` scaffolds the
onboarding welcome app instead. Read it, then delete it. Treat it as functional scaffolding,
not a style guide.

`railcode.json` keys:

```json
{
  "app": "my-app",
  "type": "hono+vite",
  "dist": "dist/client",
  "server": "dist/server/index.js"
}
```

`type` drives build, dev, and deploy. `server` names the built worker module; `dist` the static
output. **Never add `"server"` to a generation-1 app** — the deploy is refused with `422`.

### Next.js and worker-first routing

By default only `/api/*` and `/_serverFn/*` reach the worker; every other path is a static file
or the root `index.html`. Two things change that, for apps whose worker renders the pages:

- **`railcode init <app> --template next`** scaffolds a Next.js App Router app: `"type": "next"`,
  built by the `@railcode/next` dev dependency, served at its normal URLs. Server Components,
  Server Actions and Route Handlers call `@railcode/sdk` directly; there is no separate
  `server/index.ts`, and no `wrangler` or OpenNext config in the project.
- **`"routes": "all"`** in `railcode.json` is for a bring-your-own stack whose worker renders
  pages. A `GET` or `HEAD` for a file in `dist` is still served as that file; every other
  request, on any method, goes to the worker, and there is no `index.html` fallback (a root
  `index.html` is not required). `"type": "next"` implies it. Reverting a deploy restores
  its routing with it.

Signed-out requests are redirected to login before they reach the worker in both modes.

The `migrate-to-railcode` skill's Next.js guide has the full porting rules, the gotchas table
and what has been proven; they apply to a new app as much as to a migrated one.

**If a `routes: all` or `type: next` deploy is refused**, check the server:

```bash
curl -s <api-url>/api/config               # is "worker_routes" in deploy_capabilities?
```

`<api-url>` is the server the CLI is logged in to (`https://api.railcode.app` unless the user
logged in with `--api-url`); `api.railcode.app` has `worker_routes`. The CLI refuses a
`routes: all` or `type: next` deploy against a server without it, so a wrong guess fails at
deploy rather than shipping a broken app. Until the server is upgraded, Next.js still runs
through the fallback in the `migrate-to-railcode` skill (the app mounted under `/api`).

### A minimum-CLI floor gates NEW apps

Creating an app requires a CLI at or above the floor the server enforces
(`APPS_MIN_CLI_VERSION_FOR_CREATE`). **Deploys to existing apps are never gated** — a v1 app
keeps deploying from any CLI.

## Local Dev

```bash
railcode dev [--port <n>] [--reset]
```

Run it from the directory containing `railcode.json`. It serves the frontend **and the worker**,
carving exactly the paths production carves (`/api/*`, `/_serverFn/*`; every path without a
static file for `"routes": "all"`).

- **`tanstack`** — the Vite preset runs the worker in embedded workerd; the CLI proxies `/api`
  and `/_serverFn` to Vite.
- **`next`** — the CLI runs `next dev` with the SDK's dev credentials in its environment. Next
  renders the pages and runs the server code itself, in Node, at every path.
- **`hono+vite` / `hono+static` / bring-your-own** — the CLI bundles the worker with esbuild
  (watched), runs it **in-process**, and serves the same paths. A rebuild re-imports the worker
  on the next request.

Either way the worker calls the CLI's local data plane over HTTP with the **same wire shape as
production**, so "works in `railcode dev`" means "works deployed." The one exception is
`next`: the data plane is the same, but the runtime is Node locally and the worker runtime when
deployed, so the first deploy is the real compatibility test.

What is local vs forwarded:

| Surface | Under `railcode dev` |
|---|---|
| `db`, `files` | **Local scratch store** on disk. Flat scope. `--reset` seeds fresh. Never touches live data |
| SQL, saved queries, LLM, email, connectors, **agents** | **Forwarded to the real instance** under a CLI-minted dev token carrying your identity |
| `secrets` | Read from your local environment |
| Cron | Not scheduled — trigger the route by hand (remember: **POST**) |

Forwarded calls hit real providers, real data, and real spend — including sending email and
starting real agent runs. Authority for them is manifest-bounded exactly as in production, so
authority failures reproduce locally.

Local dev storage is separate from the deployed app's: `railcode app kv` / `railcode app files`
read and write the **live** app, never the local emulation.

## Per-App Secrets (apps v2)

```bash
railcode secrets set NAME          # hidden prompt, or piped on stdin — never inline
railcode secrets import [.env]     # every NAME=value line of an env file
railcode secrets ls                # names + set-at + value digest, never values
railcode secrets rm NAME
```

Values are **write-only**: they can be replaced or removed, never read back. The worker reads
them ambiently as `secrets.NAME`.

Secrets are **live app state, not part of a deploy**. Every activation — deploy, revert, cold
revert — re-applies the **current** set before the flip is observable, so a revert can never
resurrect a rotated value. Writes serialize with deploys.

Caps: 64 per app, 5 KB per value.

## Worker Logs (apps v2)

The v2 debugging surface. There is no generation-1 equivalent.

```bash
railcode logs app --app <slug>              # invocations: time, outcome, status, method, path, who
railcode logs app --app <slug> --follow     # tail
railcode logs app <invocation_id> --app <slug>   # ONE full trace, as JSON
```

Every invocation — http or cron — produces a record: who called, which path, which deploy,
outcome, duration. A single trace additionally carries the worker's `console` lines, any uncaught
error, and **every governed operation with its verdict**, so a refusal appears as `denied` with
the resource name instead of a silent failure.

`invocation_id` joins the gate record, the logs, and every data-plane audit row — one request
reads as one trace. Invocation records and logs are retained indefinitely for now.

## The Migration Gate (v1 → v2)

```bash
railcode migrate [--app <slug>] [--yes]
```

**One-way and irreversible.** It flips the app's `generation` from 1 to 2. Immediately:

- the browser SDK stops working for that app — `/_api` data calls refuse;
- the app's user/role-scoped browser data **freezes** (readable by the new worker through
  `db.scoped()` / `db.scopedRole()`, writable by nothing);
- unscoped data is untouched — the v2 flat store **is** that same app scope.

Reverting a deploy never un-migrates. It prompts on a TTY; `--yes` is required
non-interactively.

**Do not run this until the v2 build is finished and validated.** Between `migrate` and the next
`deploy` the app is down for its users, and that window cannot be rehearsed — a worker deploy is
refused (`422`) while the app is still generation 1. See
[migration.md](migration.md) for the full procedure and the new-slug alternative.

## Check An App's Generation

```bash
railcode apps show <app> --json | grep generation      # 1 = legacy, 2 = apps v2
```

The plain-text output does not print it; use `--json`.

## Read The Design System

```bash
railcode design-system
```

Prints your org's configured design-system markdown straight to stdout (so it pipes/feeds
cleanly into an agent). Needs a logged-in CLI; resolves the server like every other command.
Returns empty when no admin has configured a design system for the org. `railcode
design-system get` is the explicit spelling of the same read.

An admin with **design-system manage** can also replace the guidance:

```bash
railcode design-system set --file brand.md          # from a file
cat brand.md | railcode design-system set           # from stdin
railcode design-system set --markdown "# Brand ..."  # inline
```

`set` reads the markdown from exactly one source, preferred in that order: `--file`, then
`--markdown`, then piped stdin. An empty file or empty pipe is **refused** rather than
silently wiping the guidance; clear it deliberately with `--markdown=""`.

Optionally record which dashboard template and brand pair produced the markdown, so the
picker can restore itself — `--template <slug> --primary <hex> --accent <hex>`. Pass all
three or none; provenance is replaced wholesale on every `set`, never merged. Omitting the
trio marks the guidance hand-written ("custom").

## Query Data Connectors

```bash
railcode db list                                   # list the org's data connectors
railcode db query "select 1"                       # read-only SQL against connection `default`
railcode db query "select * from orders where total > $1" --params '[100]'
railcode db query --file report.sql --connection analytics
```

`railcode db` inspects the org's **data connectors** (admin-configured Postgres, BigQuery,
Turso, or MotherDuck) and runs ad-hoc read-only SQL from the terminal — the same connectors and SQL the
in-app `dataConnectors()` / `data().runSQL()` use. Data connectors are **org-scoped**, so these
one-shot commands **work straight after `railcode login`** — **no app and no `railcode.json`
required**. They use your login token and run from any directory.

- `railcode db list` (aliases `ls`, `connections`) — prints each connector's `name` +
  `engine`; `--json` prints the raw array.
- `railcode db query "<sql>"` (alias `sql`) — runs the SQL and prints a table + row count.
  `--connection <name>` (default `default`), `--engine <postgres|bigquery|turso|motherduck>` (inferred
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

A **saved query** is a named, versioned SQL template an org admin
publishes against one data connection. Members and apps invoke it **by name** with typed,
named params — the grant-gated alternative to ad-hoc SQL, and the same queries the in-app
`query('name', params)` / `savedQueries()` SDK globals use. Like `railcode db`, these are
org-scoped: they work straight after `railcode login`, no app required.

```bash
railcode query list                                # signatures: name, params, version, description
railcode query run my_orders --params '{"region":"emea","limit":5}'
```

- **Templates use `:name` placeholders** (not `$1`) matched to declared params, each typed
  `string | int | float | bool`. A param declared with a `"default"` is optional at invoke
  time — the server binds the default when the caller omits it.
- **`--params` for `run` is one JSON object**, exactly matching the SDK/API call.
- **No context binds**: `:_ctx_user_id`, `:_ctx_user_email` and `:_ctx_org` have been
  **removed**. A placeholder or param named `_ctx*` is rejected at create and at run time
  with `_ctx binds are no longer supported`. The caller's identity drives the grant check
  and the audit trail, never the binding — per-caller row scoping is the author's job:
  declare a typed param and have the caller pass the value.
- `list`/`run` are member operations (invocation can be grant-gated per query by admins).
  `list` returns signatures only, never SQL text. Aliases: `query` = `queries`, `list` =
  `ls`, `run` = `invoke`; `--json` on `run` prints the raw
  `{ columns, rows, rowcount, truncated }` envelope.

Publishing or changing a saved query is organization administration. Use
`$manage-railcode-org` for `query create`/`update`/`delete` rather than expanding the app
builder's scope.

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
required**.

- `railcode connector list` (aliases `ls`, `connectors`) — prints `name`, `kind`, `tools`
  (whether the row exposes callable tools), `auth`, `owner`, `access`, and `account`; a `mode`
  column (`per-user` / `shared`) appears when any per-user row exists, and a `status` column
  when a row is not yet approved (an OAuth link still in flight). `--json` for the raw array.
  To see what documentation a connector has, run `connector docs <name>`.
- `railcode connector docs <name>` (alias `doc`) — prints one connector's documentation
  bundle so you know how to call it: usage instructions, the API-docs link (or inline text),
  and the OpenAPI spec (link or inline) when the admin configured them. `--openapi` prints
  only the spec (inline text if present, else its URL; exits non-zero when there is none);
  `--json` for the raw docs object.
- `railcode connector fetch <path>` (alias `request`) — proxies one HTTP call.
  `--connector <name>` (required), `--method <verb>` (default `GET`; must be allowed by the
  connector or the server returns 405), `--body <string>` / `--file <path>` (mutually
  exclusive), `--json` prints the raw `{ status, ok, headers, body, truncated }` envelope. A
  non-2xx upstream status is still printed, but the command exits non-zero.

## Link A Connector You Own

There is no separate `personal-connectors` command: `railcode connector` is one command for a
shared team credential and for an account you link yourself.

```bash
railcode connector catalog                     # providers you can link + their connect methods
railcode connector link gmail                  # link your own account; you own the row
railcode connector add-mcp notion https://mcp.notion.com/mcp   # any remote MCP server (alias: mcp)
railcode connector list                        # what you can see: owned, shared, org-mode
railcode connector tools gmail-jp              # callable tools + input schemas
railcode connector call gmail-jp send_email --args '{"to":"a@b.com","subject":"hi"}'
```

- **You own what you link, and it starts `restricted`** — visible to you, admins, and anyone you
  `share` it with. `railcode connector access <name> organization` opens it to the org;
  `railcode connector share <name> --user <email>` or `--role <name>` grants it narrowly.
- **The name is not the provider id.** The default is `<provider>-<your email's local part>`
  (`gmail-jp`, `slack-harshsharma`); when that is taken the server counts up (`gmail-jp-2`,
  `-3`, …). A name you pass with `--name` that is already taken is a `409`. Always read the
  name from `connector list` before writing it into a manifest.
- `link` waits for the OAuth round trip by default; `--no-wait` prints the URL and returns.
  `relink <name>` re-authorizes an expired row without disturbing what names it.
- `call` runs a tool **as you, under your grants** — an identity op with no app manifest bound,
  the same thing you could do by hand. The app-plane equivalent, `connector(name).call()` in the
  SDK, **is** bound by the calling app's ratified manifest — see
  [App Manifest](#app-manifest-authority) below.
- Two kinds behave differently: **http** rows are a method/path proxy (`connector fetch`), **mcp**
  rows are tools called by name (`connector tools` / `call`). Linked providers such as Gmail
  expose tools as well.

### Per-user connectors

A per-user connector is one name under which **each member connects their own
account**; it holds no credential itself, and an app calling it runs on the caller's account
(after they approve that app once). OAuth providers only — `catalog` shows `oauth` / `mcp_oauth`.

```bash
railcode connector link granola --per-user [--name <n>] [--method oauth|mcp_oauth]   # create the definition (org-wide, you own it)
railcode connector connect granola                        # connect YOUR account (prints the URL, waits)
railcode connector connect granola --no-wait              # print the URL and return
railcode connector status granola                         # your link: not connected | linking | connected as … (alias: connection)
railcode connector status granola --app meetings          # + what that app declares and whether you approved it
railcode connector disconnect granola                     # remove your account and every app approval
```

- `connector list` grows a **`mode`** column (`per-user` / `shared`) when any per-user row exists;
  on a per-user row `auth` is how members sign in and `account` is *your* link, not a shared one.
- **`link <provider>` refuses when a per-user definition for that provider exists** and points
  you at `connect` — a separate row of your own would not make the apps built on the definition
  work, and on providers that rotate refresh tokens the two grants can invalidate each other.
  `--own` links the separate row anyway.
- **Approval has no CLI command.** The member approves an app on the platform's connect page,
  where they see the operations the app declares. The app gets there through
  `ApiError.connectionRequired.connectUrl` — see [worker-sdk.md](worker-sdk.md#per-user-connectors).
- `connect` on a connector you already connected says so instead of re-running OAuth. A
  **shared** connector has no connection to make: `connect` on one answers 404.
- Under **`railcode dev`**, `connector(name).connection()` / `checkHealth()` forward to the
  **deployed** app's ratified manifest, so deploy once before testing them; the dev proxy answers
  409 "Deploy this app once" otherwise. Ordinary dev connector calls keep using your own member
  authority — and your own link.
- Admins can disable or delete a definition (which removes every member's link) but cannot edit
  its host, headers or body logging, cannot see whose accounts are linked, and cannot connect on
  someone's behalf; impersonated sessions are refused on every write.

## LLM Gateway

```bash
railcode llm providers            # configured providers, each with its models
railcode llm models               # flat list of every callable model
railcode llm providers --json     # raw provider array
railcode llm default <model>      # set the model used when a call names none
```

`railcode llm` shows the org's LLM gateway exactly as apps see it — the same catalog the
in-app `llmProviders()` SDK global returns. Like `railcode db`/`connector`, it works after
`railcode login`, with no app or `railcode.json` required.

- `railcode llm providers` (alias `provider`) — one row per provider (`provider`, whether it's
  the org default, and its models joined in a cell with the default model marked).
- `railcode llm models` (alias `model`) — one row per `(model, provider)` with the org default
  marked.
- Keys, LiteLLM strings, and cost rates are never shown.

An org can configure **many models across many providers**. In app code, calls route by
`(provider, model)`: pass `opts.model` (a catalog model name — its provider is implied) and/or
`opts.provider` (a provider name alone → that provider's default model) to `llm.generate()` /
`llm.stream()`, or pass neither to use the org default marked in the listing.

LLM **tool calling** (`opts.tools`) rides this same plane: the wire
carries only each tool's `{ name, description, schema }` — `run`/`summarize` execute in the
page — and under `railcode dev` the calls forward to the real instance like every other LLM
call.

## Deploy An App With The CLI

```bash
railcode deploy [--private] [--no-source] [--force]
```

Deploy behavior:

- Requires a `railcode.json` with an `"app"` slug in the current directory.
- Resolves the output directory, then runs a build command when needed (see resolution
  below), and uploads every file in the output dir (which must contain a root `index.html`
  unless `routes` is `all`) to the selected organization.
- Skips `.git`, `node_modules`, `.DS_Store` and `.railcode` at any depth, and (at the app
  root) `.gitignore`, `railcode.json`, `package.json`, and lockfiles (`package-lock.json` /
  `pnpm-lock.yaml` / `yarn.lock` / `bun.lockb` / `bun.lock`). `manifest.yaml` is **not**
  skipped — it is copied into the bundle root.
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
- Also uploads the **project source** alongside the built files, so a later `railcode pull`
  can bring it back. The source respects the project's `.gitignore`, plus a built-in exclude
  list (vendored deps, build output, VCS/tool/editor caches, the `.railcode` marker, and the
  `.env*` locals — `.env`, `.env.local`, `.env.development.local`, `.env.production.local`,
  exact names only, so `.env.example` still ships; `.claude/` ships on purpose) and the
  resolved build-output dir. `--no-source` skips it. The CLI mirrors the server's default
  caps — 20 MB of source in total, 25 MB per file, 1000 files — so an oversized tree fails
  **before** the upload starts. An instance may configure lower values, in which case the
  server rejects what the CLI allowed.
- Sends the folder's recorded base version so the deploy is **conditional** — see
  [The Version Marker](#the-version-marker-railcode). `--force` deploys over a version
  someone else has moved past.
- Prints the live URL after upload, taken from the deploy **response** rather than assembled
  locally, so it is right even on a CI runner that has no saved config to derive an org slug
  from. The shape is `<app>.<org>.<serving-domain>`.

Deploy output resolution order:

1. A managed `type` (`hono+vite`, `hono+static`, `tanstack`, `next`) decides the plan first:
   the CLI runs that stack's build itself and uploads `dist` (default `dist/client`).
2. Otherwise `railcode.json` `"dist"` wins (use `"."` for a no-build static app). `"build"`
   still runs first if also set.
3. Otherwise `railcode.json` `"build"` runs and `dist/` is uploaded.
4. Otherwise a `package.json` with a `build` script runs `<pm> run build` — `<pm>` is read
   from `package.json#packageManager` first, else inferred from the lockfile (pnpm/yarn/bun),
   else `npm` — and uploads `dist/`.
5. Otherwise a root `index.html` can be deployed interactively (a `y/N` prompt); for CI set
   `"dist": "."`.

The `railcode.json` schema is
`{ app, type?, routes?, build?, dist?, server?, dev?: { root?, command?, port?, worker? } }`.

## Deploy From CI (GitHub Actions)

Don't hand a pipeline your personal token. Use a **deploy token**: an app-scoped credential
that can only `POST` this app's deploy route.

```bash
railcode ci github [--app <slug>] [--repo <owner/name>] [--branch <name>]
                   [--no-secret] [--force] [--yes]
```

Run it inside the project. It resolves the app from `railcode.json` (or `--app`) and
the repository from the `origin` remote, mints a deploy token, hands the plaintext to
GitHub as the repository secret `RAILCODE_API_TOKEN` **via the `gh` CLI over stdin** —
so it never reaches your screen, your shell history, or an argv another process can
read — and writes `.github/workflows/railcode-deploy.yml`. With `--no-secret`, without
`gh`, or when it can't tell which repo this is, it prints the token once plus the exact
`gh secret set` command instead. `--force` overwrites an existing workflow file. It also
removes `.railcode` from Git tracking (keeping the local file), so a committed marker can't
pin CI to an old deploy number. **Nothing is added to `railcode.json`** — a file inside the
repo can't prove where it runs, so trust stays server-side.

Manage the tokens directly with:

```bash
railcode token create [--app <slug>] [--name <label>] [--expires-in-days <n>] [--json]
railcode token list   [--app <slug>] [--json]
railcode token revoke [--app <slug>] <token-prefix>
```

The plaintext is shown **once**, at mint time. Creating one is **EDIT**-tier — it hands
out exactly the power the minter already has — and every owner/editor/admin of the app
can see and revoke every token on it, whoever minted it. A deploy token dies with its
creator's edit rights on the app, and deleting the app revokes its tokens. Long-lived by
default: an expiring CI credential breaks a pipeline with no warning, so `--expires-in-days`
is opt-in. Deploy tokens never appear in the personal-token list — they belong to the
app, and the dashboard manages them on the app's **CI** tab.

The generated workflow carries all three values the runner needs, because a runner has
no `~/.railcode/config.json`. It runs `deploy --force`: the selected branch is the
deployment authority, so a version conflict never blocks CI.

```yaml
      - run: npx --yes railcode@latest deploy --force
        env:
          RAILCODE_API_URL: https://api.railcode.app
          RAILCODE_ORG_UUID: <org uuid>          # an identifier, not a secret
          RAILCODE_API_TOKEN: ${{ secrets.RAILCODE_API_TOKEN }}
```

`railcode deploy --private` does not work from CI: setting access is a separate call the
deploy token is refused on (`403`), so the deploy lands and the command then exits `1`.
Set access from the dashboard or an authenticated session instead.

## The Version Marker (`.railcode`)

Every successful deploy and every `railcode pull` writes a small JSON file, `.railcode`, into
the project folder. It records which deploy the folder currently matches:

```json
{ "api_url": "…", "org_uuid": "…", "app": "demo", "app_uuid": "…", "deploy": 3 }
```

The next deploy sends that number back, and the server refuses to publish over work the
caller has not seen — an `If-Match` for deploys. Without it, two people who both pull the
same tree and both deploy would have the second silently erase the first.

- **Deploy numbers count from 1 per app.** An app's
  history starts at `#1` no matter what else the instance has deployed, and `#3` in one app
  says nothing about any other app.
- The marker is **scoped**. The CLI sends the base version only when the instance, org and
  app slug all match the deploy target, so a copied or re-pointed folder deploys
  unconditionally instead of claiming a base in another app's history. It also sends the
  recorded app uuid, and the server refuses a mismatch.
- A stale base gives a **409** that names the live version, who moved it, and when. Run
  `railcode pull`, then deploy again — or `railcode deploy --force` to publish over it. See
  [Working In A Shared App](#working-in-a-shared-app) before forcing: that 409 is a colleague.
- A base the app does not have gives a **422** naming the app's real range.
- `railcode init` adds `.railcode` to `.gitignore`. It is local state about one folder, so a
  colleague's `git clone` must not receive a stale one. Deleting it is always safe: the next
  deploy is simply unconditional.
- It is never uploaded as a servable file and never packed into the source bundle it helps
  build.

## Pull A Deploy's Source

```bash
railcode pull [<deploy>] [--app <slug>] [--dir <path>] [--force]
```

Downloads the source tree stored with a deploy — the live one by default, or the deploy
number you name. Behavior:

- `--app <slug>` picks the app (default: the `"app"` in `./railcode.json`); `--dir <path>`
  picks where to write (default: the current directory).
- Existing local files are **only** overwritten with `--force`, and the command lists which
  ones differ before it refuses. Files the deploy does not contain are left alone; nothing is
  ever deleted.
- Afterwards the folder records the deploy it now matches, so the next deploy is checked
  against it.
- A deploy made with `--no-source`, or one whose files have aged out of the retention window,
  answers that there is nothing to pull.
- Requires a server with deploy source-history endpoints. Older servers keep accepting
  deploys but cannot answer pull requests.

## App Access

A new app defaults to **`organization`** access — every member of your org may open it.
Access is otherwise managed in the **admin UI**, the `railcode apps` CLI commands, or the
access API. The owner or an org admin changes it; use `$manage-railcode-org` for broader app
ownership and organization administration:

```bash
railcode apps access <app>                          # show the current mode + per-user grants
railcode apps set-access <app> --mode private       # or: organization | restricted
railcode apps set-access <app> --mode restricted --members alice@x.io,bob@x.io
railcode apps set-access <app> --mode organization --editors dana@x.io   # editors: any mode
```
Modes: `organization` (every org member, the default), `private` (owners + editors),
`restricted` (owners + editors, plus explicitly-granted members). Org admins/owners bypass
per-app access entirely.
See [v1-legacy.md](v1-legacy.md) for the access model.

Grants come in **three tiers** — owner, **editor**, member (viewer):

| Tier | Can | Cannot |
| --- | --- | --- |
| owner | everything below, plus delete/archive/transfer/set-access, and `app kv`/`app files` | — |
| **editor** | deploy, read/revert deploy history, `pull` source, read analytics, read the access policy, add/remove **viewers** | delete, archive, transfer, change the mode, change the editor list, `app kv`/`app files` |
| member (viewer) | open the app while it is `restricted` | anything else |

Editors are **working rights, not an audience share**: an editor can open the app in *every*
mode, and their grant survives mode changes. `railcode apps access` prints the grants grouped
by tier for exactly this reason — do not read the editor list as "who can view this".

```bash
railcode apps add-editor <app> dana@x.io       # atomic; never rewrites the rest of the policy
railcode apps remove-editor <app> dana@x.io
railcode apps add-viewer <app> sam@x.io        # restricted mode, or an external user on an organization app
railcode apps remove-viewer <app> sam@x.io
```

Prefer the atomic `add-editor`/`remove-editor` over `set-access --editors` when you are
granting one person: `set-access` rewrites the whole policy and can race a concurrent edit.

- **`--editors` absent vs empty is a real distinction.** Omitting `--editors` leaves the
  server's editor list **alone**; `--editors ""` **clears** it. Same for `--members`.
- **`add-viewer`/`remove-viewer` are edit-gated**, so an editor can choose who else may view
  the app they work on. `add-viewer` works while the app is `restricted`, or on an
  `organization`-mode app for an **external** user (someone an org-wide app does not otherwise
  reach); it is a `400` in `private` mode, or when the member already has org-wide access.
- Transferring ownership **demotes the previous owner to editor** rather than cutting them off.

The only deploy-time control is `railcode deploy --private`: a **one-shot** action that sets
`mode: private` on that deploy and nothing more (it doesn't persist a flag anywhere, so a
later plain `railcode deploy` won't re-assert it — flip access back in the dashboard and it
stays flipped). There is no persisted `private` key in `railcode.json`.

## Working In A Shared App

An app can have **several people deploying it**, so do not assume the app you are working on
is yours alone. When you did not create the app in this session, establish your rights first:

```bash
railcode apps show <app>      # prints `your role`, `can manage`, `can edit`
```

`can edit` governs `deploy` / history / `revert` / `pull`; `can manage` governs delete,
archive, transfer, and the access mode (see [App Access](#app-access)). Treat a `403` as a
**real authority boundary** — report it and ask, rather than routing around it or retrying
with different flags.

Four rules in a shared app:

- **Pull before you deploy.** A `409` on deploy is not a malfunction — a colleague published
  after your last sync. The correct response is `railcode pull`, then `railcode deploy`. See
  [The Version Marker](#the-version-marker-railcode) and
  [Pull A Deploy's Source](#pull-a-deploys-source).
- **Ask before `--force`.** It overwrites a teammate's deploy and marks the history row as
  knowingly deploying over a conflict. Pull, look at what changed, and ask the user first —
  for `deploy` and for a `pull` that lists conflicting files you edited.
- **Never deploy from a tree that is missing `manifest.yaml`.** An absent manifest reads as
  *removed*; removal only sheds authority, so it auto-applies with no block and the app
  silently drops to pass-through. Confirm the manifest is present (and current) before you
  deploy someone else's app — see [App Manifest](#app-manifest-authority).
- **Never commit `.railcode`.** It is per-folder sync state; a stale one handed to a colleague
  makes their next deploy claim a base that isn't theirs. `railcode init` gitignores it; if
  you scaffolded some other way, add it yourself.

## Inspect And Seed App Storage

`railcode app kv` and `railcode app files` read and write **the deployed app's** KV and file
store from the terminal — the fastest way to confirm what an app (or an agent writing through
`app_data_write`) actually persisted, to seed demo records, or to clear a collection between
tests.

```bash
railcode app kv collections                      # every collection + record count
railcode app kv list <collection> [--query '[["stage","eq","won"]]'] [--limit 20] [--count]
railcode app kv get <collection> <key>
railcode app kv set <collection> <key> '{"n":1}'        # or --file value.json
railcode app kv delete <collection> <key>
railcode app kv drop <collection> [--yes]               # every record in the collection

railcode app files list
railcode app files download <name> [--out <path>]       # default: ./<name>
railcode app files upload <path> [--name <remote-name>]
railcode app files delete <name>
```

**These talk to the deployed instance, not `railcode dev`.** Local dev KV/files live on disk
under `~/.railcode/dev/<instance>/<app>/` and are only cleared with `railcode dev --reset`; a
`railcode app kv list` never shows them.

- **App resolution** — `--app <slug|uuid>`, else the `railcode.json` in the current directory,
  exactly like `deploy`.
- **Ownership required** — an app owner grant, or an org admin holding `app:manage_any`. A
  plain member with app *access* is rejected, and so is an **editor**: the editor tier confers
  deploy rights, not storage administration. That's an authority boundary, not a bug.
- **Scope** — `--scope shared|user|role` (default `shared`), with `--user <member-uuid>` or
  `--role <role-uuid>` required for those two. `--scope all` enumerates every scope with owner
  attribution but **only for the listings** (`kv collections`, `kv list`, `files list`); any
  record or file mutation must name a single scope.
- **`kv list` paging** — `--limit <n>` with `--offset <n>` as a whole multiple of `--limit`
  (the API pages rather than offsets). `--count` prints the match count instead of rows.
- **`kv set` values** — inline JSON or `--file <path>`, never both. Any JSON shape is valid:
  object, array, string, number, or bool. Cap: 256 KiB per serialized value (the server's
  `APP_KV_MAX_VALUE_BYTES` may override it); put larger payloads in `app files` and keep a
  small reference in KV.
- **`--query`** — the same `[[field, op, value], ...]` where-clause the data plane takes.
- `--json` prints raw JSON on the read commands; `drop` prompts on a TTY and needs `--yes`
  otherwise.

### Seeding

`kv set` is the practical way to fill a fresh app so its tables, filters, sorting, paging, and
charts can actually be reviewed. Match the shape the app itself writes — create one record
through the UI and read it back with `kv get` rather than inventing fields — and seed into the
scope the app reads, or the UI will look empty despite the records existing.

Treat `set`, `delete`, `drop`, `upload`, and `files delete` as writes to real tenant data:
they hit the live app the same way a user's click does. Confirm before running one that the
user didn't ask for, and never seed on top of an app that already holds real records without
asking.

## App Manifest (Authority)

Always write a `manifest.yaml` beside
`railcode.json` for every app you build or materially change. It declares **which privileged
operations an app performs and whose authority they run under**. It's separate from
`railcode.json` (which stays `{ app, type?, routes?, build?, dist?, server?, dev? }`) and is
uploaded on deploy.

**On apps v2, `run_as: app` is mandatory.** The worker *is* the app principal — there is no
browser caller whose personal grants could stand in — so a v2 deploy declaring `run_as: user`
is refused. (`run_as: user` remains the pass-through mode for generation-1 apps.)

`run_as: app` makes the app run privileged operations under its own **ratified** authority, so
callers who lack those grants can still use the feature through the app. Shape:

```yaml
run_as: app                 # or: user for pass-through apps
saved_queries: [my_orders]  # saved queries the app may invoke
connectors:                 # service-connector endpoints, per connector
  stripe: ["POST /v1/charges", "GET /v1/charges"]
llm: true                   # LLM gateway access (incl. tool-calling loops; the SDK calls a
                            # tool's run() makes still need their own declarations here)
email: true                 # transactional email gateway access (email.send)
adhoc_sql: [analytics]      # only when the user explicitly requested direct/ad-hoc SQL
agents: [sales-digest]      # managed agents this app may start (agents.start/invoke).
                            # MISSING = REFUSAL, not pass-through — an undeclared agent 403s
                            # even for a caller who could invoke it from the dashboard.
                            # (there is no personal_connectors: key — an account someone
                            # linked is just a connector row, declared under connectors:
                            # above by its name, e.g. "gmail-jp": [send_email])
crons:                      # apps v2 only: up to 5 per app, 1-minute minimum interval;
  - schedule: "0 6 * * *"   # the path must start with /api/ or /_serverFn/ and is
    path: /api/digest       # dispatched as a POST on the app's current deploy
egress: [api.example.com]   # apps v2 only: outbound hosts the worker may fetch — bare
                            # hostnames or single-level wildcards
```

Commands:

```bash
railcode manifest validate [path]   # strict local parse (default ./manifest.yaml)
railcode manifest show <app>        # the app's ratified doc (by slug); --json for raw
```

- `manifest validate` parses the file with the **same strict YAML grammar the server uses**
  (spaces not tabs; PyYAML 1.1 scalar rules — e.g. a bare `yes`/`no`/`on`/`off`/`null`/number
  resolves to a non-string and is rejected where a name is expected). It prints a summary of
  the declared operations; resource **names** (queries, connectors, connections, agents) are
  only checked against your org at deploy.
- **On deploy**, the manifest is ratified against the deployer's own grants — and the unit is
  the **diff** against what is already ratified, not the whole document:
  - *unchanged* (the content hash matches) → deploys as ordinary code, whatever you hold.
  - diff **adds** operations you hold, and/or only **removes** operations → **auto-ratifies**
    on the spot.
  - diff adds an operation you **don't** hold → the deploy is **rejected up front** with a
    `403`: *"This deploy adds authority you don't hold: `<ops>`."* Nothing is published — get
    the grant, or drop the operation from `manifest.yaml`. There is **no** pending-approval
    queue for this; blocking replaced it.

  Deploy prints the outcome (`Manifest unchanged.` / `Manifest ratified (you hold: …)` /
  `Manifest removed — …`). Deleting the file reverts the app to pass-through, but agents
  should keep an explicit `run_as: user` manifest unless the user asks to remove it.
- Only a `run_as: app` manifest grants anything, so a `run_as: user` manifest never needs
  ratification. Flipping `user` → `app` is therefore a **full** grant-add (you must hold
  everything declared); flipping `app` → `user` sheds it all and auto-applies.
- `manifest show` needs login and app access (403 otherwise); it prints who ratified the
  current doc and its content hash.
- `adhoc_sql` grants raw SQL authority and is intentionally scarce. Do not add it unless the
  user explicitly requested direct/ad-hoc SQL; otherwise use `saved_queries`.
- `connectors` covers accounts someone linked personally as well as shared org credentials —
  they are the same kind of row, told apart by the row's `owner` and `access_mode`, not by a
  separate manifest key. It ratifies like every other key: the
  deployer must be able to reach the row (own it, be an admin, or have it shared with them).
  Declaring `gmail-jp: [send_email]` never lets the app read that inbox; an undeclared row or
  tool is a `403` no matter who deployed the app.
