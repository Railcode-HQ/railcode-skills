---
name: create-railcode-app
description: Build, modify, debug, test, and deploy Railcode static apps end-to-end. Use when creating a Railcode app from an idea, scaffolding with the Railcode CLI, wiring the zero-config SDK globals, explaining Railcode auth/data "magic", testing with railcode dev, declaring app authority, understanding app access, or deploying an app. Do not use for managed-agent authoring or general organization administration.
version: 0.1.29
---

# Create Railcode App

## Step 0 — Update the skill and the CLI first (ALWAYS, before anything else)

Before you scope an app, scaffold, run any `railcode` command, deploy, or even answer a
Railcode/CLI question — **update both this skill and the CLI to latest.** Don't
check-then-maybe-upgrade; just try to update both, every time this skill runs:

```bash
npx skills add Railcode-HQ/railcode-skills     # install/update ALL Railcode skills to latest
npm install -g railcode@latest                 # upgrade the CLI (or: pnpm add -g railcode@latest)
railcode --version                             # confirm what you now have
npm view railcode version                      # latest published (source of truth) — should match
```

Then honor what you find:

- **If the skill updated itself**, its instructions may have just changed under you. The copy
  in your context is now stale — **re-read this `SKILL.md` from the top** before acting on it.
- **If `railcode --version` still trails `npm view railcode version`** after the upgrade, the
  global install is shadowed (wrong package manager or PATH). Resolve that before continuing —
  the CLI is a regular npm package, not a self-updating binary, so it only moves when upgraded.
- **If npm or the network is unreachable**, you can't confirm you're current — say so plainly
  in your handoff and proceed with the installed version rather than blocking, but don't claim
  the skill or CLI reflects the latest.

This skill was last checked against the published **CLI 0.1.26** (the multi-tenant Railcode
platform). It intentionally documents only commands relevant to building apps. Use
`$create-railcode-agent` for managed-agent manifests/runs/schedules and
`$manage-railcode-org` for organization administration. npm is the source of truth for the
latest published CLI. If a documented command or flag is missing or errors unexpectedly,
suspect version drift first and re-run the updates above.

That same `skills add Railcode-HQ/railcode-skills` command is also the first-time install —
`add` upserts, so it installs what's missing and refreshes what's already there. Targeting the
whole `Railcode-HQ/railcode-skills` repo (rather than a single `--skill`) keeps every Railcode
skill current in one shot, and it works across Claude Code, Codex, Cursor, and other agents on
the open agent-skills ecosystem.

## Build Process (follow in order)

When building or substantially changing an app, work through these steps in order. Don't
start writing app code until steps 1–2 are done.

### 1. Ask before building

First, ask the user a few short questions to scope the app. Ask only what changes the
design or architecture, then pick sensible defaults for the rest and state them. Cover at
least:

- **What & who** — what should the app do, and who uses it? (drives access policy and
  whether data is per-user or shared)
- **Data** — what does it store or read? Per-user records or shared across the app's users?
  Any external database (Postgres/BigQuery/Turso) must be accessed through an
  admin-published **saved query** invoked with `query('name', params)` unless the user
  explicitly tells you to use direct/ad-hoc SQL. If the user asks for direct SQL, use
  `data('name').runSQL()` or a dialect-pinned `postgres`/`bigquery`/`turso` namespace
  with bound params. Any third-party SaaS API to reach via a `connector('name').fetch()`
  service connector? Any `llm` use? If AI is involved, also establish its **shape**: does it
  process uploaded files, need to write/run code, get triggered outside the app (Slack,
  schedule), or run unattended? Any yes → a **managed agent**, not the in-page LLM — see
  **In-Page LLM vs Managed Agents** below.
- **Design** — *"Should I use the default Railcode design system, or do you have a specific
  design direction?"* (drives step 2)
- **Browser testing** — *"Should I test my changes in a browser before calling it done?"*
  (drives step 4)

### 2. Fetch the design system (if the user wants it)

If the user chose the Railcode design system, pull it before writing any UI:

```bash
railcode login                                       # once, if not already logged in
railcode design-system
```

`railcode design-system` prints your org's configured design-system guidance (markdown) to
stdout. Use it as the active design direction. The command needs a logged-in CLI and a
reachable Railcode server. If the user wants a custom direction instead, or it returns empty
(no admin has configured one for the org), or there is no server to log in to, skip it and
use the fallback in the **Visual Direction** section.

### 3. Build the app

Scaffold and develop locally — see the **Core Workflow** and **Local Development**
sections — following the **Implementation Rules**.

Always write or update the app's `manifest.yaml` beside `railcode.json`. Use `run_as: user`
for pass-through apps with no privileged app authority, and `run_as: app` only when the app
needs ratified saved-query, connector, LLM, email, managed-agent invocation, personal-connector
tool-calling, or explicitly requested direct-SQL authority.
Validate it with `railcode manifest validate` before deploy.

### 4. Test before calling it done

Run the checks in the **Validation** section: always the app build, plus a browser pass if
the user asked for browser testing in step 1. Fix what you find before declaring the work
done.

### 5. Deploy (when the user wants it live)

Publish with `railcode deploy` — see the **Deployment** section.

## Core Workflow

A normal app-builder loop is:

```bash
railcode init my-app          # scaffolds a standalone ./my-app/ directory
cd my-app
npm install                   # only for the react template (the static template has no deps)
railcode dev                  # local server with an emulated /_api
railcode deploy               # build (if configured) + upload to your org
```

The CLI is the npm package `railcode` (`npm install -g railcode@latest`).

The CLI drives **your app's** package manager, not a fixed one: it detects a `packageManager`
field or a lockfile (pnpm/yarn/bun) and falls back to **`npm`** when there's no lockfile, so a
fresh scaffold never forces pnpm onto the machine (new in CLI 0.1.17 — older CLIs hardcoded
pnpm). Examples here use `npm`; substitute your own manager. Note npm's build is `npm run
build`, not `npm build`.

Use lowercase app names with digits and dashes only (a DNS label: `^[a-z0-9][a-z0-9-]{0,62}$`).
`railcode init <app>` scaffolds a single self-contained app directory `./<app>/` — there is
no `apps/`/`app-bundles/` workspace split. The directory is the source of truth; the build
output (`dist/` for the react template, or the directory itself for the no-build static
template) is what `railcode deploy` uploads.

## Decide What To Load

Load only the reference needed for the task:

- [CLI workflow](references/cli-workflow.md): exact app-building commands (login/init/dev/deploy/design-system, app-facing data/connector/LLM calls, and access) plus local dev/deploy behavior.
- [Platform magic](references/platform-magic.md): how same-origin auth, `/_api/sdk.js`, app/org identity, access policies, KV/files, SQL, service connectors, LLM, and email work.
- [App patterns](references/app-patterns.md): implementation patterns for React/Vite apps, using the SDK globals, data modeling, SQL, connectors, LLM, and frontend expectations.
- [Deployment](references/deployment.md): `railcode deploy`, app access, and post-deploy verification.

## Implementation Rules

Build the app as a static browser app. Do not add app-specific backend services, API keys, auth code, or hardcoded Railcode URLs unless the user explicitly asks for platform work. Browser code should call same-origin `/_api/*` through the Railcode SDK.

Load the SDK with a `<script src="/_api/sdk.js"></script>` tag in `index.html` (both starter
templates do this). On load it attaches a fixed set of globals to `window` — there is no
`loadRailcodeSdk()` bootstrap or `src/lib/railcode.ts` wrapper to import; call the globals
directly (in TypeScript, `declare` them or add an ambient `.d.ts`). The global SDK surface is:

- `me()` → `{ user, app, org }`; `user` includes org-level `is_admin` plus assigned custom
  roles as `{ uuid, name }`, and `is_app_owner` — whether the caller holds the running app's
  owner grant (a UI hint; server-side authorization is unaffected). `appUsers()` → org members
  with `is_admin` but no role memberships. `roles()` → every custom org role as
  `{ uuid, name, description, is_member }` (`is_member` = whether the current caller belongs
  to that role).
- `designSystem()` → the org's design-system guidance (markdown string), same content as
  `railcode design-system`.
- `db.collection(name)` → per-app KV (`get`/`put`/`delete`/`list`). Start a query with
  `query()` for pure ordering/paging, or with the collection helpers `where(...)` /
  `prefix(...)`; query-only methods include `updatedSince`/`updatedBefore`/`orderBy`/
  `page`/`first`/`count`. **Storage scopes:** `db.collection(...)` is app-wide (an alias for
  `db.shared`); `db.user.collection(...)` is the caller's own private namespace;
  `db.role(uuid).collection(...)` is one org role's shared namespace (the caller must be a
  live member — owner/admin may reach any; get role UUIDs from `roles()`). The same
  `(collection, key)` never collides across scopes, and the server enforces access.
- `files` → `upload(name, data, contentType?)`, synchronous single-file `url(name)`,
  batched async `urls(names)`, `list()`, and `delete(name)`. Use `await files.urls(names)`
  for file-heavy views: it resolves up to 100 existing files with one authenticated request,
  returns `{ items: [{ name, url, expires_in }], missing }`, and caches resolved URLs in
  memory until shortly before expiry. Files carry the **same scopes** as KV:
  `files.user.upload(...)`, `files.role(uuid).url(...)`, and `files.shared.*` — bare
  `files.*` is an alias for `files.shared`. `railcode dev` emulates every scope on local
  disk (including `urls`).
- `llm` → `llm.generate(input, opts)` and the streaming `llm.stream(input, opts)`;
  `llmProviders()` lists the org's configured providers as
  `{ provider, default, models: [{ model, default }] }`. Calls route by `(provider, model)`:
  pass `opts.model` (a catalog model name — its provider is implied) and/or `opts.provider`
  (alone → that provider's default model), or neither to use the org default. Apps never see
  API keys. (Multi-model discovery new in CLI/SDK 0.1.15.) Both calls also accept
  `opts.tools` — user-defined `{ name, description, schema?, run?, summarize? }` objects
  wrapping anything the app can already do. When **every** tool has a `run` handler, the
  SDK executes the whole agentic loop in the page (the model plans, the SDK validates args,
  runs the tool, feeds the summarized result back, repeats until the model answers) and the
  result carries `steps`, `messages`, and `stopReason`; when **no** tool has `run`, the call
  is a single turn and the model's requested calls come back unexecuted on `toolCalls`
  (mixing run and run-less tools throws). Tools grant **no new authority** — the model can
  only reach what you wire into a `run` function. See
  [Platform magic](references/platform-magic.md) for the loop mechanics and
  **In-Page LLM vs Managed Agents** below for when to use this at all. (Tool calling is
  new post-0.1.26: deployed apps get it from the platform-served SDK once the platform
  deploy includes it; `railcode dev` serves the CLI's bundled SDK, so local dev gains it
  with the first CLI release after 0.1.26.)
- `data('name').runSQL(query, params)` runs SQL against a connection of any kind
  (dispatched on its stored engine server-side); the dialect-pinned `postgres('name')` /
  `bigquery('name')` / `turso('name')` only reach connections of that engine. Each takes
  `.runSQL(query, params)`, or `.runSQL(...)` alone for the connection named `default`.
  `dataConnectors()` lists configured connections as `{ engine, name }` (engine is one of
  `postgres`, `bigquery`, `turso`). Do not use direct/ad-hoc SQL unless the user
  explicitly asks for it; saved queries are the default for database access.
- `query(name, params?)` → invoke an admin-published **saved query** by name (returns the
  same rows shape as `runSQL`); `savedQueries()` lists the callable signatures
  (`{ name, description, params, version }` — never the SQL). Always use a saved query for
  database access unless the user explicitly tells you to use direct/ad-hoc SQL. The server
  injects `_ctx_*` binds from the signed-in viewer, so results can be row-scoped per caller
  without the app passing any identity. (New in CLI/SDK 0.1.14.)
- `connector('name').fetch(path, opts)` → call an admin-configured third-party SaaS API
  through the server-side proxy (the credential never reaches the browser);
  `serviceConnectors()` lists the connectors this app may call.
- `email.send({ to, subject, html?, text?, cc?, bcc?, replyTo? })` → send transactional
  email through the platform mail gateway; returns `{ id, status, requestId }`. The
  platform owns the sender identity (a fixed `Railcode <…@mail-service.railcode.app>`
  From) and appends a disclaimer — apps set only recipients/subject/body, never keys.
  Governed and **off by default**: the org must grant `email` (or a `run_as: app`
  manifest declares `email: true`). Per-org daily recipient cap; self-hosted or an
  unconfigured provider returns `503`. (New in CLI/SDK 0.1.19.)
- `agents.invoke(name, input?)` → invoke a managed agent available to the deployed app and
  resolve with the FINISHED run (it polls a queued/running run to a terminal status for you).
  Runs execute off the request now, so a long agent no longer risks a gateway timeout. A
  `run_as: app` manifest declares allowed agents under `agents: [name]`; use
  `$create-railcode-agent` to author or operate the managed agent itself. Use
  `agents.start(name, input?)` (returns immediately with the queued run) plus
  `agents.get(requestId)` to poll yourself — e.g. to show progress instead of blocking on
  `invoke()`. (`start`/`get` and the `queued` status new in CLI/SDK 0.1.24.)
- `personalConnections` → the **caller's own** connected third-party accounts (Gmail, Slack,
  ...) — distinct from `connector()` (an org-admin-configured service
  connector). `list()` and `connect(toolkit)` are identity ops (no manifest check beyond the
  app only offering toolkits it declares); `tools(toolkit)` and `call(toolkit, tool, args)` are
  bound by **this app's ratified `personal_connectors:` manifest declaration** — undeclared is
  a `403` every time, even though the caller could do it by hand. A manifest declaring
  `gmail:send_email` lets the app send mail as the caller and nothing else. Tool slugs are
  lowercase and case-sensitive; copy the exact slug returned by `tools(toolkit)`. `call()`
  returns `409` if the caller hasn't connected that toolkit yet — render that as a "Connect
  your account" prompt, not an error. (New in CLI/SDK 0.1.26.)

The SDK also ships a live activity drawer that logs every call; toggle it with ``Ctrl+` ``
(control + backtick). Org admins/owners **and the current app's owner** also get a small
floating button, bottom-right, that does the same thing — everyone else keeps the
undocumented keyboard toggle only. It is present in production too, just dormant until
opened.

## In-Page LLM vs Managed Agents (Cloud)

The **in-page LLM** (`llm.generate`/`llm.stream`, with or without `tools`) runs in the
viewer's tab with the app's SDK authority and dies with the tab — bounded to 8 planning
turns / 120s by default. A **managed agent** (`$create-railcode-agent`, invoked from apps
via `agents.invoke`/`agents.start`) runs server-side under its own ratified manifest, with
a code sandbox and durable, auditable runs. The boundary is **capability, not
sophistication** — a multi-step saved-query analytics assistant is fine in the page;
"summarize this PDF" is not. Pick the first matching row:

| The AI feature… | Use |
|---|---|
| Summarizes / classifies / analyzes data the app already reads — user watching, done in seconds | **In-page LLM** |
| Processes, parses, or analyzes an uploaded file (PDF, XLSX, …) | **Managed agent** (`app_files` + sandbox) |
| Writes and runs code | **Managed agent** (sandbox) |
| Is triggered outside the app (Slack, cron, API) | **Managed agent** |
| Runs unattended, must survive tab close, or needs retries | **Managed agent** |
| Has effects that must not depend on who's viewing (shared writes, send as the system) | **Managed agent** |
| Needs a run history someone will audit or debug | **Managed agent** |

The planes compose: keep the chat shell in the page and delegate heavy steps by calling
`agents.invoke`/`agents.start` from a tool's `run` — see the delegation pattern in
[App patterns](references/app-patterns.md).

## Visual Direction

Treat the starter/template app as functional scaffolding, not a style guide. Do not copy its visual style into new apps unless the active design system calls for it.

If the user opted into the Railcode design system, fetch it first with `railcode design-system` (see Build Process step 2) and make the app follow it. When no design system is configured or reachable — or the user wants a different look — default to the Railcode design system: quiet internal-tool UI, neutral surfaces, compact controls, clear tables/lists, modest borders/radius, and restrained accent color.

Apps must be responsive. Verify the main workflows work cleanly on desktop and mobile widths, with no overlapping text, clipped controls, or unusable tables.

Model data intentionally:

- KV is scoped per app. `db.shared` (the default `db.collection`) is shared by the app's allowed users; use `db.user` for the caller's private records (no manual user-key prefixing needed) and `db.role(uuid)` for data shared within one org role.
- Use KV query builders for large or ordered lists instead of loading the whole collection.
  `where()` and `prefix()` can start a query from a collection; pure ordering or paging starts
  with `.query()` (for example `.query().orderBy("updatedAt", "desc").page(1, 50)`).
  `orderBy`, `updatedSince`, `updatedBefore`, `page`, `first`, and `count` are query methods,
  not direct collection methods. `where()` operators are the string names `eq`, `ne`, `gt`,
  `gte`, `lt`, `lte`, and `in` (e.g. `.where("done", "eq", false)`), not symbols.
- Files are scoped per app. Names may contain `/` for nested paths, but cannot start with
  `/`, contain `\`, use `.`/`..` traversal segments, or begin with a `users/` or `roles/`
  segment (both reserved server-side — an upload/read with such a name is rejected 400).
  Prefer `files.urls(names)` when a view needs many files.
- SQL connections (Postgres/BigQuery/Turso) are admin-configured server-side and read-only. Always use placeholders plus params.
- LLM provider/model/API key are admin-configured server-side. Send `metadata` for audit and attribution. LLM tool loops run in the page with the app's existing SDK access — wire into a tool's `run` only what the model should be able to reach.
- Email goes through the platform gateway server-side (fixed sender, appended disclaimer; apps never handle keys). It is **off by default** — needs an `email` grant or a ratified `email: true` manifest — and rate-limited per org; render `403`/`429`/`503` as normal app states, not retries.

## Local Development

Run `railcode dev` from the app directory (any directory with a `railcode.json`). It serves the app at the first available local port starting at `http://127.0.0.1:7331`, runs the app's own dev server (Vite) and reverse-proxies it (HMR included) when there's a `package.json` `dev` script, serves the SDK at `/_api/sdk.js`, and stores local KV/files under `~/.railcode/dev/<instance>/<app>/` (namespaced per instance+org). Use the printed URL; it may be `7332` or higher when another dev server is already running. Useful flags: `--port <n>` (starting proxy port), `--asset-port <n>` (starting Vite port), `--reset` (wipe this app's local KV/files first).

Local dev emulates identity (`me`), app users, KV, and files entirely on local disk. The design system, SQL (`data`/`postgres`/`bigquery`/`turso`), data connectors, saved queries (`query`/`savedQueries`), service connectors, LLM, and email (`email.send`) are **forwarded to the configured Railcode instance** when the CLI has a saved API token — so those use the org's real provider, quota, databases, and mail delivery (real spend, real data, real email). Not logged in: `dataConnectors()`/`serviceConnectors()`/`savedQueries()` return empty and `data().runSQL()`/`query()`/`llm`/`email.send()` return `503`. The startup banner prints which mode you're in. Even in local development, prefer `query()`/`savedQueries()` and do not use direct SQL unless explicitly instructed. Email forwarding under `railcode dev` is new in CLI 0.1.19 — earlier CLIs 404 on `email.send()` locally.

CLI 0.1.23's dev emulator supports scoped file operations including batched `files.urls()`.

## Validation

Before handing off a new or changed app, run the app's normal build (the react template):

```bash
cd <app>
npm run build
```

The no-build **static** template has no build step — just confirm the files load via
`railcode dev`.

If the user asked for browser testing (Build Process step 1), also exercise the running app before handing off. Start `railcode dev`, then open the printed local URL, usually `http://127.0.0.1:7331`, with whatever browser tooling you have — a browser-automation MCP, browser-use, or your harness's built-in browser. Load the app, walk the primary workflow end to end, and confirm it works at both desktop and mobile widths. Treat console errors, failed `/_api/*` calls, and broken layouts as failures to fix, not ship.

## Deployment

Deploy a finished app from its app directory:

```bash
railcode deploy
```

`railcode deploy` reads `railcode.json` (`{ app, build?, dist? }`), runs the build command when one is configured, then uploads the output directory (which must contain a root `index.html`) over HTTP to the configured Railcode instance. It needs two things:

- **Which server** — `--api-url`, then `RAILCODE_API_URL`, then the saved CLI config from `railcode login`. (There is no `deploy.apiUrl` manifest key in the multi-tenant CLI.)
- **Auth** — it uses the saved API token, or reads `RAILCODE_API_TOKEN` for non-interactive runs. On a `401` the saved token is cleared and you're told to `railcode login` again.

The app is **created-or-resolved by slug in your saved org**, then the live URL is printed —
`http://<app>.<org>.<serving-domain>/` (e.g. `https://my-app.acme.railcode.dev/`).

### Access

A newly created app defaults to **`organization`** access — every member of your org can
open it. Access is otherwise managed in the **admin UI** (or via
`PUT /api/organizations/{org}/apps/{app}/access`); the one deploy-time exception is
`railcode deploy --private`, a **one-shot** flag that sets the app private for that single
deploy only — it is never persisted (`railcode init` no longer accepts or writes a private
flag). The three modes are:

- **`organization`** — every org member (the default).
- **`private`** — owners only.
- **`restricted`** — owners plus explicitly-granted members.

Org admins/owners bypass per-app access (they can see and manage every app). If an app holds
sensitive data, deploy it with `--private` (or set `private`/`restricted` in the admin
console) before sharing the URL widely. For verification steps, read the
[Deployment reference](references/deployment.md).
