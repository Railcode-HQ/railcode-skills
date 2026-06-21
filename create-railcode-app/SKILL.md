---
name: create-railcode-app
description: Build, modify, debug, and deploy Railcode static apps end-to-end. Use when creating a Railcode app from an idea, using the Railcode CLI, wiring the zero-config SDK globals, explaining Railcode auth/data "magic", testing with railcode dev, configuring access policies, or deploying apps to a Railcode server.
version: 0.1.0
---

# Create Railcode App

## Version Check (run first)

This skill targets **Railcode CLI 0.1.0**.

Run `railcode --version`. If the printed version does not match the target above, the
skill and CLI are out of sync. Update both, then continue with the refreshed skill:

```bash
railcode upgrade
npx skills update create-railcode-app
```

Both commands pull the latest, so they converge — after running them the printed version
matches the target. If a `railcode` command or flag documented here is missing or errors
unexpectedly, suspect version drift first and re-check this.

## Installing & Updating This Skill

This skill ships through the open agent-skills ecosystem (the `skills` CLI), so the same
commands work across Claude Code, Codex, Cursor, and other agents:

```bash
npx skills add yakkomajuri/railcode --skill create-railcode-app   # install
npx skills update create-railcode-app                             # update
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
  Any external database to query via `postgres('name').runSQL()` / `mysql('name').runSQL()`? Any `llm` use?
- **Design** — *"Should I use the default Railcode design system, or do you have a specific
  design direction?"* (drives step 2)
- **Browser testing** — *"Should I test my changes in a browser before calling it done?"*
  (drives step 4)

### 2. Fetch the design system (if the user wants it)

If the user chose the Railcode design system, pull it before writing any UI:

```bash
railcode login                                       # once, if not already logged in
railcode design-system pull .railcode/design-system.md
```

Read that file and make the app follow it. The pull needs a logged-in CLI and a reachable
Railcode server. If the user wants a custom direction instead, or the pull returns empty
(no admin has configured one), or there is no server to log in to, skip it and use the
fallback in the **Visual Direction** section.

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

Start from the Railcode workspace root when possible. A normal app-builder loop is:

```bash
railcode init my-app
cd apps/my-app
railcode dev
railcode deploy
```

If `railcode` is unavailable in a source checkout, build and link the CLI first:

```bash
cd cli
npm install
npm run build
npm link
```

Use lowercase app names with digits and dashes only. `railcode init <app>` creates source in `apps/<app>` and deployable static output in `app-bundles/<app>`. Treat `apps/<app>` as the source of truth; `app-bundles/<app>` is build output unless the project is an intentionally hand-written static app.

## Decide What To Load

Load only the reference needed for the task:

- [CLI workflow](references/cli-workflow.md): exact `railcode` commands and local dev/deploy behavior.
- [Platform magic](references/platform-magic.md): how same-origin auth, `/_api/sdk.js`, app identity, access policies, KV/files, SQL, and LLM work.
- [App patterns](references/app-patterns.md): implementation patterns for React/Vite apps, SDK wrappers, data modeling, SQL, LLM, and frontend expectations.
- [Deployment](references/deployment.md): server setup, DNS, app deploys, platform deploys, access policy deploys, and verification.

## Implementation Rules

Build the app as a static browser app. Do not add app-specific backend services, API keys, auth code, or hardcoded Railcode URLs unless the user explicitly asks for platform work. Browser code should call same-origin `/_api/*` through the Railcode SDK.

Use the starter's wrappers in `src/lib/railcode.ts` after `loadRailcodeSdk()` has loaded `/_api/sdk.js`. The global SDK surface is `me()`, `appUsers()`, `db.collection()`, `files`, `databaseConnectors()`, the per-engine `postgres('name').runSQL()` / `mysql('name').runSQL()` namespaces, and `llm`. (`sql()` and `connections()` remain as deprecated aliases.)

## Visual Direction

Treat the starter/template app as functional scaffolding, not a style guide. Do not copy its visual style into new apps unless the active design system calls for it.

If the user opted into the Railcode design system, pull it first with `railcode design-system pull` (see Build Process step 2) and make the app follow it. When no design system is configured or reachable — or the user wants a different look — default to the Railcode design system: quiet internal-tool UI, neutral surfaces, compact controls, clear tables/lists, modest borders/radius, and restrained accent color.

Apps must be responsive. Verify the main workflows work cleanly on desktop and mobile widths, with no overlapping text, clipped controls, or unusable tables.

Model data intentionally:

- KV is scoped per app and shared by that app's allowed users. Prefix keys with the logged-in user if the app needs per-user records.
- Use KV query builders (`where`, `prefix`, `updatedSince`, `updatedBefore`, `orderBy`, `page`, `first`, `count`) for large or ordered lists instead of loading the whole collection. `where()` operators are `==`, `!=`, `>`, `>=`, `<`, `<=`, and `in`.
- Files are scoped per app. File API names cannot contain `/`; encode hierarchy in metadata or key names instead.
- SQL connections are admin-configured server-side and read-only. Always use placeholders plus params.
- LLM provider/model/API key are admin-configured server-side. Send `metadata` for audit and attribution.

## Local Development

Run `railcode dev` from `apps/<app>` or any directory with a `railcode.json`. It serves the app at `http://127.0.0.1:7331`, runs the asset dev server when applicable, serves the SDK at `/_api/sdk.js`, and stores local KV/files under `~/.railcode/dev/<app>`.

Local dev mocks identity, app users, KV, and files. It forwards backend-backed APIs such as SQL, connections, and LLM to the configured Railcode API when the CLI has a saved API token.

## Validation

Before handing off a new or changed app, run the app's normal build:

```bash
cd apps/<app>
npm run build
```

When changing the CLI, SDK, backend, deployment workflow, or platform behavior, run the relevant project checks in addition to the app build. Typical checks are `npm run build` in changed Node packages and, for backend changes, `cd backend && uv run pytest && uv run ruff check`.

If the user asked for browser testing (Build Process step 1), also exercise the running app before handing off. Start `railcode dev`, then open `http://127.0.0.1:7331` with whatever browser tooling you have — a browser-automation MCP, browser-use, or your harness's built-in browser. Load the app, walk the primary workflow end to end, and confirm it works at both desktop and mobile widths. Treat console errors, failed `/_api/*` calls, and broken layouts as failures to fix, not ship.

## Deployment

Deploy a finished app from its app directory:

```bash
railcode deploy
```

`railcode deploy` builds the app and uploads the static output (`dist/` for a root app) over HTTP to the configured Railcode API. It needs two things:

- **Which server** — set `deploy.apiUrl` in `railcode.json`, or `RAILCODE_API_URL`, or rely on the saved CLI config from `railcode login`.
- **Auth** — it uses the saved API token, prompts for a browser login when needed, or reads `RAILCODE_API_TOKEN` for non-interactive runs.

On first deploy the app is created with public access for signed-in users, and the command prints the live URL. Tighten access later in the admin UI if the app is sensitive. For DNS, platform deploys, access-policy deploys, and verification, read the [Deployment reference](references/deployment.md).

Deploying an app (`railcode deploy`) is separate from updating the Railcode platform itself (a Docker Compose / Ansible flow in `deploy/ansible/`, also wired to a GitHub Action on pushes to `main`) — that only matters when the user runs the server, not when building apps on it.
