---
name: create-railcode-app
description: Build, modify, debug, test, and deploy Railcode static apps end-to-end. Use when creating a Railcode app from an idea, scaffolding with the Railcode CLI, wiring the zero-config SDK globals, explaining Railcode auth/data "magic", testing with railcode dev, declaring app authority, understanding app access, or deploying an app. Do not use for managed-agent authoring or general organization administration.
version: 0.1.41
---

# Create Railcode App

## Update First

Before answering a Railcode question or running a `railcode` command, update the Railcode
skills and CLI, then verify npm's published version:

```bash
npx skills add Railcode-HQ/railcode-skills
npm install -g railcode@latest
railcode --version
npm view railcode version
```

If the skill changes, re-read this file from the top. If npm is unreachable, say so and do not
claim the guidance is current. This version was checked against published **CLI 0.1.27**.

## Map The Request To Railcode

Use this table before choosing an architecture. If the request names an external product or
data source, always check data connections/saved queries, service connectors, **and personal
connectors** before deciding what is available; the detailed discovery commands are in step 1.

**Hard file boundary:** the app may upload, store, list, download, and display files with
`files`, but any AI that must **read, understand, extract, summarize, transform, or generate a
file** must be a **managed agent** with `app_files` and its sandbox. Never pass file contents,
file URLs, or file-derived payloads to `llm.generate()` / `llm.stream()` as a substitute, and
never use the in-page LLM to produce a file artifact. Use the app as the upload/results UI and
delegate the file work through `agents.invoke()` / `agents.start()`.

| What the user asks for | Use this Railcode feature |
|---|---|
| "Show company metrics/orders/customers from our database" | **Saved query** via `query()` (default); data connection + direct `data().runSQL()` only when explicitly requested |
| "Let each user connect their Gmail, Slack, or another personal account" | **Personal connector** via `personalConnections`; declare only the needed `personal_connectors` tools |
| "Connect my account to a product Railcode does not bundle" | **Custom MCP personal connector** by remote HTTPS URL, then call its `custom_<slug>` toolkit |
| "Use our team's shared Stripe, CRM, or other SaaS account" | Org **service connector** via `connector().fetch()`; an admin owns the shared credential |
| "Store app settings, drafts, approvals, or lightweight records" | App KV via `db.shared`, `db.user`, or `db.role()` according to ownership |
| "Upload, store, download, or display files without AI processing" | Scoped app `files` |
| "Read, extract, summarize, transform, or generate a file with AI" | **Managed agent** with `app_files` + sandbox; never `llm.generate()` / `llm.stream()` |
| "Edit this Word document / DOCX and preserve it as a file" | **Managed agent + companion app**: the app stores/manages source and output files; the agent loads the DOCX with `app_files`, edits it in its sandbox, and publishes the result with `app_data_write` |
| "Create or revise a PowerPoint / PPTX deck" | **Managed agent + companion app**: the app manages templates, inputs, and generated decks; the agent creates/edits the PPTX in its sandbox and publishes it back to the app |
| "Create a PDF report, form, or document" | **Managed agent + companion app**: the app manages inputs and downloadable outputs; the agent generates and verifies the PDF in its sandbox, then publishes it back to the app |
| "Analyze this Excel / XLSX workbook" | **Managed agent + companion app**: the app stores the workbook and results; the agent loads it with `app_files`, parses/analyzes it in its sandbox, and publishes durable results through `app_data_write` |
| "Summarize or classify data while the user is watching" | In-page `llm.generate()` / `llm.stream()` with narrowly wired tools |
| "Run in the background, on a schedule, from Slack, or after the tab closes" | **Managed agent** invoked with `agents`, often with this app as its companion UI |
| "Send a system-owned transactional email" | Platform `email.send()`; use a Gmail **personal connector** instead when mail must come from each user's own account |
| "Call an arbitrary website/API" | First look for a service or personal connector; otherwise offer admin connector setup or a custom MCP personal connector—apps cannot fetch the open web directly |

## Start From An Example

Railcode ships worked, deployable examples at
**https://github.com/Railcode-HQ/railcode-examples**. Read them to learn a pattern; copy one
when it covers much of what the user is asking for.

| Example | What it is | Showcases |
| --- | --- | --- |
| [`apps/kanban`](https://github.com/Railcode-HQ/railcode-examples/tree/main/apps/kanban) | A kanban board with drag-and-drop columns, a list view, and a command palette. | The plain static app: SDK globals, KV storage, Zustand state — no LLM or agents. |
| [`apps/chat`](https://github.com/Railcode-HQ/railcode-examples/tree/main/apps/chat) | A chat interface over your connected data sources (Postgres text-to-SQL, PostHog HogQL). | Per-user scoped storage, streaming answers, auditable inline tool calls, file uploads. |
| [`apps/crm`](https://github.com/Railcode-HQ/railcode-examples/tree/main/apps/crm) | A full CRM — companies, contacts, pipeline, activity, automations — with an **Ask AI** agent that can read and change anything a person could. | `llm.stream({ tools })` agent loops, human approval gating on writes, per-tab URL routing, managed agents deployed alongside an app. |

The repo's `agents/` directory holds examples that pair an app with a **managed agent** — reach
for those through `$create-railcode-agent` when the work needs one.

**Ask, don't assume.** When the request substantially overlaps an example, put the choice in the
step 1 question batch, naming the example in the user's own terms:

> *"Railcode provides an example CRM that covers a lot of these points. Should I use that as a
> starting point, or build from scratch?"*

Ask once, alongside the other scoping questions. Never copy an example unprompted, and don't
raise the question when nothing matches.

### Copying an example

Copy **only** the one directory, as plain files — never `git clone` the repo into the user's
project, add it as a submodule, or leave a `.git` behind:

```bash
mkdir -p my-crm
curl -fsSL https://github.com/Railcode-HQ/railcode-examples/archive/refs/heads/main.tar.gz \
  | tar -xz --strip-components=3 -C my-crm railcode-examples-main/apps/crm
```

`--strip-components=3` drops `railcode-examples-main/apps/<example>/`, so the example's files
land directly in `my-crm/`. Swap the trailing path for any row above (e.g.
`railcode-examples-main/apps/chat`). To study one file without copying anything, fetch it raw
from `https://raw.githubusercontent.com/Railcode-HQ/railcode-examples/main/<path>`.

A copied example already contains `railcode.json` — it replaces `railcode init`, so don't
scaffold over it. Make it the user's app **before** writing feature code:

- `railcode.json` — set `app` to the new name (lowercase, digits, dashes).
- `package.json` — rename `name`, then `npm install` (versions are exact pins with a lockfile).
- `manifest.yaml` — delete every authority this app doesn't actually use (`llm`, `agents`,
  `personal_connectors`, …). A copied manifest carries the example's authority, not the
  narrowest set for this app. Re-validate with `railcode manifest validate`.
- `agents/*/agent.yaml`, when present — rename each agent, update the app slug in its
  `app_data`/`app_files`/`app_data_write`, and update the names in `manifest.yaml`'s `agents:`
  list and in every `agents.invoke`/`agents.start` call, so the copy doesn't collide with an
  agent that already exists in the org.
- `README.md`, when the example ships one — retitle or replace; it describes the example.
- Delete the views, stores, and components for features the user didn't ask for.

If the download fails, say so and build from scratch — don't reconstruct an example from memory.

## Build Process (follow in order)

When building or substantially changing an app, work through these steps in order. Don't
start writing app code until steps 1–2 are done.

### 1. Ask before building

First, ask the user a few short questions to scope the app — **all in one batch, as early
as possible**. This is the moment the user is still present; questions dribbled out
mid-build risk landing after they've stepped away. Ask only what changes the design or
architecture, then pick sensible defaults for the rest and state them.

Phrase every question for a **non-technical user who knows nothing of Railcode
internals**: ask about intent, and let the answers determine the primitives without naming
them. *"Should each user get their own private storage, or does everyone work on the same
data?"* — not "db.shared or db.user?". *"Is this data already in a company database
someone maintains?"* — not "saved query or direct SQL?". The bullets below are what **you**
need to learn from the answers, not the words to use.

Before asking anything, check the request against **Limitations** below. If it needs
something Railcode can't do (a scraper, a public site, a webhook receiver, …), say so
plainly first and propose the nearest supported shape — don't build a broken
approximation. Cover at least:

**External source discovery is mandatory.** Whenever the user asks for an app that reads,
writes, syncs, searches, or acts on data from a named product or system ("X"), do not assume
that a new integration or direct API call is needed. Before settling the architecture, inspect
all three Railcode integration planes available to the signed-in user:

```bash
railcode db list                       # database/data-source connections
railcode query list                    # admin-published saved queries over those sources
railcode connector list                # org service connectors
railcode personal-connectors list      # per-user bundled and custom toolkits + connection status
```

If a likely service or personal connector exists, inspect its actual surface before designing
around it (`railcode connector docs <name>` or `railcode personal-connectors tools <toolkit>`).
Never invent connector names, endpoints, tool slugs, or schemas. If you cannot authenticate or
reach the Railcode instance, ask the user what is configured and present the discovery commands;
do not treat an empty or unavailable local result as proof that X is unsupported.

If nothing suitable is available, explain the gap and offer the relevant next choices instead
of silently dropping the integration: have an admin connect the underlying database and publish
a saved query; enable or create an org service connector for a shared credential/API; connect a
bundled personal toolkit; or connect X's remote MCP server by URL as a custom personal connector
(HTTPS; auth can be none, bearer token, or OAuth). Custom MCP personal connectors work for apps
as `custom_<slug>` toolkits. If X has neither an accessible API/database nor a remote MCP server,
say that Railcode cannot connect to it directly and ask which supported source the user wants to
use. Make the options user-facing (who owns the account, whether access is shared, and any admin
setup required), then let the user's choice determine the manifest authority.

- **What & who** — what should the app do, and who uses it? (drives access policy and
  whether data is per-user or shared)
- **Data** — what does it store or read? Per-user records or shared across the app's users?
  Any external database (Postgres/BigQuery/Turso) must be accessed through an
  admin-published **saved query** invoked with `query('name', params)` unless the user
  explicitly tells you to use direct/ad-hoc SQL. If the user asks for direct SQL, use
  `data('name').runSQL()` or a dialect-pinned `postgres`/`bigquery`/`turso` namespace
  with bound params. Any third-party SaaS API to reach via a `connector('name').fetch()`
  service connector? Any `llm` use? If AI is involved, also establish its **shape**: does it
  read, generate, or otherwise process files, need to write/run code, get triggered outside
  the app (Slack, schedule), or run unattended? Any yes → a **managed agent**, never the
  in-page LLM — see
  **In-Page LLM vs Managed Agents** below.
- **Starting point** — when an example in **Start From An Example** covers much of the
  request, ask whether to build on it: *"Railcode provides an example CRM that covers a lot
  of these points. Should I use that as a starting point, or build from scratch?"* (drives
  step 3)
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

If the user chose an example in step 1, copy that one directory and adapt it first — see
**Start From An Example**. Otherwise scaffold with `railcode init`. Either way, develop
locally — see the **Core Workflow** and **Local Development** sections — following the
**Implementation Rules**.

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

The CLI detects the app's package manager from `packageManager` or a lockfile and otherwise
uses `npm`. Examples use `npm`; substitute the app's declared manager. The npm build command
is `npm run build`.

Use lowercase app names with digits and dashes only (a DNS label: `^[a-z0-9][a-z0-9-]{0,62}$`).
`railcode init <app> [dir]` scaffolds a single self-contained app directory — `./<app>/` by
default, or an existing directory you name (`railcode init my-app .` scaffolds into the
current dir; non-empty is fine, but an existing `railcode.json` is refused without
`--force`). There is no
`apps/`/`app-bundles/` workspace split. The directory is the source of truth; the build
output (`dist/` for the react template, or the directory itself for the no-build static
template) is what `railcode deploy` uploads.

## Decide What To Load

Load only the reference needed for the task:

- [CLI workflow](references/cli-workflow.md): exact app-building commands (login/init/dev/deploy/design-system, app-facing data/connector/LLM calls, and access) plus local dev/deploy behavior.
- [Platform magic](references/platform-magic.md): how same-origin auth, `/_api/sdk.js`, app/org identity, access policies, KV/files, SQL, service connectors, LLM, and email work.
- [App patterns](references/app-patterns.md): implementation patterns for React/Vite apps, using the SDK globals, data modeling, SQL, connectors, LLM, and frontend expectations.
- [Deployment](references/deployment.md): `railcode deploy`, app access, and post-deploy verification.

For full working apps — a kanban board, a data chat, a CRM with an in-page agent loop — read
or copy from `railcode-examples`; see **Start From An Example** above.

## Implementation Rules

Build a static browser app. Do not add app-specific backend services, credentials, auth code,
or hardcoded Railcode URLs unless the user explicitly asks for platform work. Load
`/_api/sdk.js` in `index.html` and call its same-origin globals directly; do not import a
Railcode client package or create a custom SDK bootstrap.

Give every top-level section its own path (`/companies`, `/people`) and put the open record in
the path too (`/companies/acme`) — never keep navigation in an in-memory `view` variable. Deep
links, hard refresh, and back/forward must work, since these apps get linked in Slack and
tickets. Railcode serving falls back to the app's root `index.html`, so client-side routes
resolve with no config — see [App patterns](references/app-patterns.md).

Use the narrowest surface that fits:

| Need | SDK surface |
|---|---|
| Identity, app members, roles, design guidance | `me()`, `appUsers()`, `roles()`, `designSystem()` |
| Shared, private, or role-owned records | `db.shared`, `db.user`, `db.role(uuid)` |
| Passive file upload, storage, download, or display | `files.shared`, `files.user`, `files.role(uuid)` |
| Database reads | `query()` / `savedQueries()` by default; direct SQL only when explicitly requested |
| Shared third-party account | `connector()` / `serviceConnectors()` |
| Viewer's own third-party account | `personalConnections`; this includes remote custom MCP toolkits |
| Short, watched, text/data AI | `llm.generate()` / `llm.stream()` with narrowly wired tools |
| File AI, code execution, or durable/background AI | `agents.invoke()` / `agents.start()` and a managed agent |
| System-owned transactional mail | `email.send()` |

Tools passed to the in-page LLM add no authority; they expose only what their `run` handlers
call. Never wire file content, file URLs, file-derived payloads, or file generation into an
in-page tool. Delegate all AI file work to a managed agent with `app_files` and a sandbox.

See [App patterns](references/app-patterns.md) for code, [Platform magic](references/platform-magic.md)
for auth and scoping semantics, and [CLI workflow](references/cli-workflow.md) for manifest
authority and exact commands.

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
| Reads, understands, extracts, summarizes, transforms, or generates any file | **Managed agent** (`app_files` + sandbox); never the in-page LLM |
| Writes and runs code | **Managed agent** (sandbox) |
| Is triggered outside the app (Slack, cron, API) | **Managed agent** |
| Runs unattended, must survive tab close, or needs retries | **Managed agent** |
| Has effects that must not depend on who's viewing (shared writes, send as the system) | **Managed agent** |
| Needs a run history someone will audit or debug | **Managed agent** |

The planes compose: keep the chat shell in the page and delegate heavy steps by calling
`agents.invoke`/`agents.start` from a tool's `run` — see the delegation pattern in
[App patterns](references/app-patterns.md). The inverse also holds: a managed agent often
ships with a **companion app** that manages the files/records it relies on, renders its
results, and gives it a one-click test trigger — see `$create-railcode-agent`.

## Limitations

When a request hits a row below, say so up front and offer the nearest supported shape.
Do not quietly build an approximation that can't work.

| Not possible | Why, and the nearest supported path |
|---|---|
| Scrapers, or calls to arbitrary websites/APIs | Apps are same-origin (the SDK reaches only `/_api`); agent sandbox egress is allowlisted (PyPI/npm). Reach a *specific* API via an admin-configured service connector, or the caller's own personal connector — including any MCP server by URL |
| Custom backend code, or inbound endpoints (webhook receivers, public APIs) | Apps are static; nothing listens. Poll the source through a connector (interactively or on an agent schedule) instead of receiving events |
| Public or customer-facing apps | Every viewer must be a signed-in org member — no anonymous access, no self-signup. Railcode apps are internal tools |
| Real-time push (websockets, live presence/collaboration) | No push surface exists; UIs poll. LLM streaming is the only streaming response |
| Relational features over KV (joins, transactions, aggregations) | KV queries filter/order/page only. Keep heavy data in a connected warehouse and read it via saved queries |
| Receiving email, or sending from a custom address | `email.send()` is send-only with a platform-pinned sender and appended disclaimer |
| Multimodal LLM input, embeddings, or vector search | The LLM gateway is text-in/text-out; there is no embeddings API. File understanding = a managed agent extracting in its sandbox |
| Long-running or event-driven automation | Agent runs cap at 100 steps / 300 s; one cron per agent (null input); no data-change or inbound-webhook triggers (triggers are: app/API call, cron, Slack mention); agents can't invoke other agents |
| Heavy compute (model training, media transcoding) | The sandbox is ephemeral per run with a 300 s ceiling; outputs must be published via `publish_artifact_to_app` |
| Custom domains, native mobile apps, push notifications | Apps are responsive web apps served at `<app>.<org>.<base-domain>` |
| Bring-your-own API keys inside an app | Apps never hold secrets. Integrations exist only as admin-configured service connectors or the caller's personal connectors |

## Visual Direction

Treat the starter/template app as functional scaffolding, not a style guide. Do not copy its visual style into new apps unless the active design system calls for it. An example copied from `railcode-examples` is different — it ships a coherent internal-tool look you can keep building on — but still reconcile it with the active design system rather than assuming the example already matches it.

If the user opted into the Railcode design system, fetch it first with `railcode design-system` (see Build Process step 2) and make the app follow it. When no design system is configured or reachable — or the user wants a different look — default to the Railcode design system: quiet internal-tool UI, neutral surfaces, compact controls, clear tables/lists, modest borders/radius, and restrained accent color.

Apps must be responsive. Verify the main workflows work cleanly on desktop and mobile widths, with no overlapping text, clipped controls, or unusable tables.

**Give every app a favicon.** These tools get pinned and left open in a row of tabs, so a
default blank icon is a real cost. Draw a small **SVG** that says what the app is — a funnel for
a pipeline, a board for a kanban, an envelope for an inbox — in the active design system's accent
color, and link it from `index.html`:

```html
<link rel="icon" type="image/svg+xml" href="/favicon.svg" />
```

Put the file in `public/favicon.svg` for the react template (Vite copies `public/` into the build
output) or beside `index.html` for the no-build static template. Keep it readable at 16px: one
shape, no fine detail, no lettering. Set a real `<title>` in the same file — it's the label next
to that icon.

Keep data ownership explicit: use `db.user` / `files.user` for private data and `db.role(uuid)` /
`files.role(uuid)` for role data; do not simulate scopes with key or path prefixes. Use query
builders for large KV collections, bound parameters for SQL, and visible empty/error states for
unconfigured integrations. Detailed patterns live in [App patterns](references/app-patterns.md).

## Local Development

Run `railcode dev` from the directory containing `railcode.json` and open the URL it prints.
Identity, KV, and files are emulated locally; configured design, data, query, connector, LLM,
personal-connector, and email calls are forwarded to the real instance when logged in. They can
touch real data, incur spend, and cause side effects. Use `--reset` only when intentionally
clearing this app's local KV/files. See [CLI workflow](references/cli-workflow.md#local-dev).

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

Deploy reads `railcode.json`, builds when configured, uploads the resolved output, and prints
the live URL. A new app defaults to organization-wide access; use `railcode deploy --private`
for a private first deploy or set the intended policy explicitly afterward. Read
[Deployment](references/deployment.md) for resolution, access modes, and verification.
