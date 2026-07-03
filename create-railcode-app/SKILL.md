---
name: create-railcode-app
description: Build, modify, debug, and deploy Railcode static apps end-to-end. Use when creating a Railcode app from an idea, using the Railcode CLI, wiring the zero-config SDK globals, explaining Railcode auth/data "magic", testing with railcode dev, understanding app access, or deploying apps to a Railcode server.
version: 0.1.12
---

# Create Railcode App

## Version Check (run first)

Find the latest published CLI and compare it to what you have:

```bash
npm view railcode version      # latest published (source of truth)
railcode --version             # what's installed
```

If they differ, upgrade the CLI: `npm install -g railcode@latest` (or
`pnpm add -g railcode@latest`). It's a regular npm package, not a self-updating binary.

This skill was last written against **CLI 0.1.14** (the multi-tenant Railcode platform).
That number is provenance, not a target to match — npm is the source of truth for "latest."
If the latest published CLI is newer, the skill itself may lag, so update it too:

```bash
npx skills update create-railcode-app
```

If a `railcode` command or flag documented here is missing or errors unexpectedly, suspect
version drift first and re-check this.

## Installing & Updating This Skill

This skill ships through the open agent-skills ecosystem (the `skills` CLI), so the same
commands work across Claude Code, Codex, Cursor, and other agents:

```bash
npx skills add yakkomajuri/railcode-skills --skill create-railcode-app   # install
npx skills update create-railcode-app                                    # update
```

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
  Any external database (Postgres/BigQuery/Snowflake) to query via `data('name').runSQL()`
  or a dialect-pinned `postgres`/`bigquery`/`snowflake` namespace — or better, an
  admin-published **saved query** invoked with `query('name', params)`? Any third-party SaaS
  API to reach via a `connector('name').fetch()` service connector? Any `llm` use?
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
pnpm install                  # only for the react template (the static template has no deps)
railcode dev                  # local server with an emulated /_api
railcode deploy               # build (if configured) + upload to your org
```

The CLI is the npm package `railcode` (`npm install -g railcode@latest`).

Use lowercase app names with digits and dashes only (a DNS label: `^[a-z0-9][a-z0-9-]{0,62}$`).
`railcode init <app>` scaffolds a single self-contained app directory `./<app>/` — there is
no `apps/`/`app-bundles/` workspace split. The directory is the source of truth; the build
output (`dist/` for the react template, or the directory itself for the no-build static
template) is what `railcode deploy` uploads.

## Decide What To Load

Load only the reference needed for the task:

- [CLI workflow](references/cli-workflow.md): exact `railcode` commands (login/init/dev/deploy/design-system) and local dev/deploy behavior.
- [Platform magic](references/platform-magic.md): how same-origin auth, `/_api/sdk.js`, app/org identity, access policies, KV/files, SQL, service connectors, and LLM work.
- [App patterns](references/app-patterns.md): implementation patterns for React/Vite apps, using the SDK globals, data modeling, SQL, connectors, LLM, and frontend expectations.
- [Deployment](references/deployment.md): `railcode deploy`, app access, and post-deploy verification.

## Implementation Rules

Build the app as a static browser app. Do not add app-specific backend services, API keys, auth code, or hardcoded Railcode URLs unless the user explicitly asks for platform work. Browser code should call same-origin `/_api/*` through the Railcode SDK.

Load the SDK with a `<script src="/_api/sdk.js"></script>` tag in `index.html` (both starter
templates do this). On load it attaches a fixed set of globals to `window` — there is no
`loadRailcodeSdk()` bootstrap or `src/lib/railcode.ts` wrapper to import; call the globals
directly (in TypeScript, `declare` them or add an ambient `.d.ts`). The global SDK surface is:

- `me()` → `{ user, app, org }` (each `{ uuid, ... }`); `appUsers()` → the org's members.
- `designSystem()` → the org's design-system guidance (markdown string), same content as
  `railcode design-system`.
- `db.collection(name)` → per-app KV (`get`/`put`/`delete`/`list`, plus the
  `where`/`prefix`/`updatedSince`/`updatedBefore`/`orderBy`/`page`/`first`/`count` query
  builder).
- `files` → `upload(name, data, contentType?)`, `url(name)`, `list()`, `delete(name)`.
- `llm` → `llm.generate(input, opts)` and the streaming `llm.stream(input, opts)`.
- `data('name').runSQL(query, params)` runs SQL against a connection of any kind
  (dispatched on its stored engine server-side); the dialect-pinned `postgres('name')` /
  `bigquery('name')` / `snowflake('name')` only reach connections of that engine. Each takes
  `.runSQL(query, params)`, or `.runSQL(...)` alone for the connection named `default`.
  `dataConnectors()` lists configured connections as `{ engine, name }` (engine is one of
  `postgres`, `bigquery`, `snowflake`).
- `query(name, params?)` → invoke an admin-published **saved query** by name (returns the
  same rows shape as `runSQL`); `savedQueries()` lists the callable signatures
  (`{ name, description, params, version }` — never the SQL). Prefer a saved query over
  ad-hoc SQL when one exists: the server injects `_ctx_*` binds from the signed-in viewer,
  so results can be row-scoped per caller without the app passing any identity. (New in
  CLI/SDK 0.1.14.)
- `connector('name').fetch(path, opts)` → call an admin-configured third-party SaaS API
  through the server-side proxy (the credential never reaches the browser);
  `serviceConnectors()` lists the connectors this app may call.

The SDK also ships a hidden live activity drawer that logs every call; toggle it with
``Ctrl+` `` (control + backtick) while developing. It is present in production too, just
dormant until opened.

## Visual Direction

Treat the starter/template app as functional scaffolding, not a style guide. Do not copy its visual style into new apps unless the active design system calls for it.

If the user opted into the Railcode design system, fetch it first with `railcode design-system` (see Build Process step 2) and make the app follow it. When no design system is configured or reachable — or the user wants a different look — default to the Railcode design system: quiet internal-tool UI, neutral surfaces, compact controls, clear tables/lists, modest borders/radius, and restrained accent color.

Apps must be responsive. Verify the main workflows work cleanly on desktop and mobile widths, with no overlapping text, clipped controls, or unusable tables.

Model data intentionally:

- KV is scoped per app and shared by that app's allowed users. Prefix keys with the logged-in user if the app needs per-user records.
- Use KV query builders (`where`, `prefix`, `updatedSince`, `updatedBefore`, `orderBy`, `page`, `first`, `count`) for large or ordered lists instead of loading the whole collection. `where()` operators are the string names `eq`, `ne`, `gt`, `gte`, `lt`, `lte`, and `in` (e.g. `.where("done", "eq", false)`), not symbols.
- Files are scoped per app. File API names cannot contain `/`; encode hierarchy in metadata or key names instead.
- SQL connections (Postgres/BigQuery/Snowflake) are admin-configured server-side and read-only. Always use placeholders plus params.
- LLM provider/model/API key are admin-configured server-side. Send `metadata` for audit and attribution.

## Local Development

Run `railcode dev` from the app directory (any directory with a `railcode.json`). It serves the app at the first available local port starting at `http://127.0.0.1:7331`, runs the app's own dev server (Vite) and reverse-proxies it (HMR included) when there's a `package.json` `dev` script, serves the SDK at `/_api/sdk.js`, and stores local KV/files under `~/.railcode/dev/<instance>/<app>/` (namespaced per instance+org). Use the printed URL; it may be `7332` or higher when another dev server is already running. Useful flags: `--port <n>` (starting proxy port), `--asset-port <n>` (starting Vite port), `--reset` (wipe this app's local KV/files first).

Local dev emulates identity (`me`), app users, KV, and files entirely on local disk. The design system, SQL (`data`/`postgres`/`bigquery`/`snowflake`), data connectors, saved queries (`query`/`savedQueries`), service connectors, and LLM are **forwarded to the configured Railcode instance** when the CLI has a saved API token — so those use the org's real provider, quota, and databases (real spend, real data). Not logged in: `dataConnectors()`/`serviceConnectors()`/`savedQueries()` return empty and `data().runSQL()`/`query()`/`llm` return `503`. The startup banner prints which mode you're in.

## Validation

Before handing off a new or changed app, run the app's normal build (the react template):

```bash
cd <app>
pnpm build
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
open it. Access is set in the **admin UI** (or via
`PUT /api/organizations/{org}/apps/{app}/access`), not at deploy time. The three modes are:

- **`organization`** — every org member (the default).
- **`private`** — owners only.
- **`restricted`** — owners plus explicitly-granted members.

Org admins/owners bypass per-app access (they can see and manage every app). If an app holds
sensitive data, deploy it and then set it to `private`/`restricted` in the admin console
before sharing the URL widely. For verification steps, read the
[Deployment reference](references/deployment.md).
