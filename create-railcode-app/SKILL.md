---
name: create-railcode-app
description: Build, modify, debug, test, and deploy Railcode apps end-to-end. Use when creating a Railcode app from an idea, scaffolding with the Railcode CLI, writing a backend worker with @railcode/sdk, wiring a frontend to worker routes, declaring app authority, testing with railcode dev, migrating a legacy v1 app to apps v2, maintaining an existing v1 browser-SDK app, or deploying. Do not use for managed-agent authoring or general organization administration.
version: 0.2.2
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
claim the guidance is current. This version was written against **CLI 0.2.2** and
**`@railcode/sdk` 0.3.0**.

Since 0.1.28 the CLI self-updates within its major version — but only on an **interactive
terminal**, and agent-driven sessions are non-interactive, so keep running the explicit
`npm install -g railcode@latest` above rather than assuming you're on the latest.

## First: Which Generation?

Railcode apps come in two shapes, and **almost every rule below depends on which one you are
holding**. Settle this before anything else.

- **A new app is always generation 2 (apps v2).** There is no choice, no flag, no
  `railcode.json` key. The server assigns it.
- **An existing app may be generation 1 (v1)** — the legacy browser-SDK shape. Existing apps
  were backfilled to 1 and stay there until someone explicitly migrates them.

```bash
railcode apps show <app> --json | grep generation     # 1 = legacy, 2 = apps v2
```

The plain text output does **not** print the generation; use `--json`.

| Situation | Do this |
|---|---|
| Building a new app | **Apps v2.** Continue with this file. |
| Changing an app whose `railcode.json` has a `"type"` and a `"server"` | **Apps v2.** Continue with this file. |
| Changing an app whose `index.html` loads `/_api/sdk.js` | **Generation 1.** Read [v1 legacy](references/v1-legacy.md) — the rules here mostly do not apply. |
| User wants a v1 app rebuilt as v2 | Read [Migration](references/migration.md) **first**. It is one-way and has a downtime window. |

If you cannot reach the server to check, decide from the source tree: `/_api/sdk.js` in
`index.html` means v1; a `"server"` key in `railcode.json` means v2.

## The v2 Model In One Paragraph

A v2 app is a **static frontend plus a backend worker**, deployed and versioned as one unit.
**There is no browser SDK.** The frontend is plain static files that `fetch()` your own worker
routes; the worker imports `@railcode/sdk` and is the only thing that touches platform
capabilities. The worker **is** the app's principal (`run_as: app` is mandatory) and receives a
verified, unforgeable `ctx.user`. Authorization is worker code — that is the point: "X submits,
Y approves, X can't approve their own" now lives in a trusted place instead of in a tab.

Everything else follows from that. If you catch yourself reaching for a `window.db` or a
`/_api` data call from the page, stop: that is the v1 shape.

## Map The Request To Railcode

Use this table before choosing an architecture. If the request names an external product or
data source, always check data connections/saved queries, service connectors, **and personal
connectors** before deciding what is available; the discovery commands are in Build step 1.

| What the user asks for | Use this Railcode feature (all called from the worker) |
|---|---|
| "Show company metrics/orders/customers from our database" | **Saved query** via `query()` (default); data connection + `data().runSQL()` only when explicitly requested |
| "Let each user connect their Gmail, Slack, or another personal account" | **Personal connector** via `personalConnections`; declare only the needed `personal_connectors` |
| "Connect my account to a product Railcode does not bundle" | **Custom MCP personal connector** by remote HTTPS URL, then call its `custom_<slug>` toolkit |
| "Use our team's shared Stripe, CRM, or other SaaS account" | Org **service connector** via `connector().fetch()`; an admin owns the shared credential |
| "Store app settings, drafts, approvals, or lightweight records" | `db` — one flat store; partitioning and access policy are **your worker's code** |
| "Upload, store, download, or display files" | `files` (server-plane: your worker holds the bytes) |
| "Read, extract, summarize, transform, or generate a file with AI" | **Managed agent** with `app_files` + sandbox, started with `agents.start()` |
| "Summarize or classify data while the user waits" | `llm.generate()` / `llm.stream()` in the worker |
| "Run on a schedule" | A `crons:` entry hitting one of your worker routes — **or** the agent's own schedule |
| "Run in the background, from Slack, or after the tab closes" | **Managed agent** via `agents.start()`, results polled from the worker |
| "Send a system-owned transactional email" | `email.send()`; a Gmail personal connector when mail must come from the user's own account |
| "Call an arbitrary website/API" | Declare the host under `egress:`, or use a service/personal connector. The default allow-list is the data plane only |

**The file boundary still holds.** The worker may `put`/`get`/`list`/`delete` files, but any AI
that must **read, understand, extract, summarize, transform, or generate** a file must be a
**managed agent** with `app_files` and its sandbox. Never feed file contents or file URLs to
`llm.generate()` as a substitute. Start the agent from the worker with `agents.start()` and read
its result back.

## Start From An Example

`railcode init` is the starting point for a new app: each worker template scaffolds a working
platform tour (identity, a todo list on `db`, files, and the read-only org surfaces) you can read
and then delete.

For anything past the tour, read `railcode-examples`. Every app there is **generation 2** —
`frontend/` + `server/index.ts`, the shape you are building — so it is safe to copy from, and
each was chosen to carry one lesson:

| Example | Read it for |
| --- | --- |
| `apps/kanban` | The plainest worker app. A shared store, and one asymmetric rule (delete is the author or an admin) written where a caller cannot reach it. |
| `apps/chat` | The agent loop running in the worker and streaming ndjson to the page; **per-user isolation rebuilt as keys plus an owner check** (`server/keys.ts`); batched file URLs with a fallback for non-S3 storage. |
| `apps/crm` | A large v1 app ported through ONE module, and the tool loop that had to stay in the browser because its writes wait for a human approval click. |
| `agents/pitch-deck` | `agents.start()` + poll, a run that reattaches after a refresh, and agent output landing in the app's own store with no bridge. |
| `agents/proposals` | Why a schedule belongs to the AGENT, not the app: cron has no caller, so `agents.start()` from cron is a 409. |

Copy a whole example as a starting point:

```bash
mkdir my-app && curl -fsSL \
  https://github.com/Railcode-HQ/railcode-examples/archive/refs/heads/main.tar.gz \
  | tar -xz --strip-components=3 -C my-app railcode-examples-main/apps/kanban
```

Then set `app` in `railcode.json` to your slug. To study one file without copying, fetch it raw
from `https://raw.githubusercontent.com/Railcode-HQ/railcode-examples/main/<path>`.

## Build Process (follow in order)

Don't start writing app code until steps 1–2 are done.

### 1. Ask before building

Ask the user a few short questions to scope the app — **all in one batch, as early as
possible**. This is the moment the user is still present; questions dribbled out mid-build risk
landing after they've stepped away. Ask only what changes the design, then pick sensible
defaults for the rest and state them.

Phrase every question for a **non-technical user who knows nothing of Railcode internals**: ask
about intent, and let the answers determine the primitives without naming them. *"Should each
user see only their own records, or does everyone work on the same data?"* — not "how should the
worker partition the flat store?".

Before asking anything, check the request against **Limitations** below. If it needs something
Railcode can't do, say so plainly first and propose the nearest supported shape.

**External source discovery is mandatory.** Whenever the user asks for an app that reads,
writes, syncs, searches, or acts on data from a named product ("X"), do not assume a new
integration is needed. Inspect all four planes first:

```bash
railcode db list                       # data connections
railcode query list                    # admin-published saved queries
railcode connector list                # org service connectors
railcode personal-connectors list      # per-user toolkits + connection status
```

If something plausible exists, inspect its real surface before designing around it
(`railcode connector docs <name>`, `railcode personal-connectors tools <toolkit>`). Never invent
connector names, endpoints, or tool slugs. If you cannot reach the instance, ask the user what is
configured and show them these commands; an empty local result is not proof that X is
unsupported.

If nothing suitable exists, explain the gap and offer the real next choices instead of silently
dropping the integration: have an admin connect the database and publish a saved query; create an
org service connector for a shared credential; connect a bundled personal toolkit; or connect X's
remote MCP server by URL as a custom personal connector. If X has neither an API/database nor a
remote MCP server, say Railcode cannot reach it directly and ask which supported source to use.

Cover at least:

- **What & who** — what should the app do, and who uses it? (drives access policy, and how the
  worker partitions the flat store)
- **Data** — what does it store or read? Per-user or shared? External database → an
  admin-published **saved query** unless the user explicitly asks for direct SQL. Third-party
  SaaS → a service connector. Any LLM use? If AI is involved, establish its **shape**: does it
  process files, run code, or need to survive the request? Any yes → a **managed agent**.
- **Stack** — default to `hono+vite`. Offer `hono+static` for something small, `tanstack` when
  the user wants file-based routing and server functions, `static` when there is no backend at
  all.
- **Design** — *"Should I use the default Railcode design system, or do you have a specific
  design direction?"*
- **Browser testing** — *"Should I test my changes in a browser before calling it done?"*

### 2. Fetch the design system (if the user wants it)

```bash
railcode login              # once, if not already logged in
railcode design-system
```

Prints your org's design-system guidance (markdown). If it returns empty or there is no server,
skip it and use **Visual Direction** below.

### 3. Build the app

```bash
railcode init <app> [dir] [--template hono+vite|hono+static|tanstack|static]
cd <app>
npm install
railcode dev
```

**The CLI owns the build.** The app declares no bundler, no `wrangler`, no Cloudflare package,
and no worker build script. Write `server/index.ts` and a frontend; `railcode deploy` produces
the one self-contained ESM module the platform needs.

Then follow **Implementation Rules** below, and write `manifest.yaml` beside `railcode.json`.
**On v2, `run_as: app` is mandatory.** Declare every capability the worker actually uses and
nothing more. Validate before deploying:

```bash
railcode manifest validate
```

### 4. Test before calling it done

Run the checks in **Validation**. Fix what you find before declaring the work done.

### 5. Deploy (when the user wants it live)

```bash
railcode deploy
```

To deploy on every push, run `railcode ci github` in the project: it mints an app-scoped
**deploy token**, sets it as the repo secret via `gh`, and writes the workflow. Never put a
personal token in CI.

## Decide What To Load

Load only the reference the task needs:

- [Worker SDK](references/worker-sdk.md) — the `@railcode/sdk` surface: `ctx`, `db`, `files`,
  `llm`, `agents`, `query`, connectors, `email`, `secrets`. **The main reference for v2 work.**
- [App patterns](references/app-patterns.md) — worker routes, frontend↔worker wiring, data
  modeling, authorization in worker code, cron, error relaying.
- [CLI workflow](references/cli-workflow.md) — exact commands: init/dev/deploy/secrets/logs/
  migrate, manifest authority, app access.
- [Deployment](references/deployment.md) — deploy resolution, access modes, verification.
- [Migration](references/migration.md) — turning an existing v1 app into a v2 app.
- [v1 legacy](references/v1-legacy.md) — the browser-SDK platform, **for maintaining existing
  generation-1 apps only**. Never build anything new from it.

## Implementation Rules

**Split the app in two and keep the split clean.**

The **frontend** is static. It holds no credentials, no platform calls, and no authority. It
does exactly one privileged-looking thing: `fetch()` your worker's own routes under `/api/*`.
The only platform endpoints a v2 page may call are `/_api/me` and `/_api/logout` (what the
chrome bar uses); normally get identity from your own worker instead.

The **worker** imports `@railcode/sdk` and is where everything real happens. Use the narrowest
surface that fits:

| Need | Worker SDK surface |
|---|---|
| Who is calling | `ctx.user` (verified; `null` only on cron) |
| Records, settings, drafts | `db` — one flat store; you own partitioning |
| Files | `files.put/get/url/urls/list/delete` |
| Database reads | `query()` / `savedQueries()` by default; `data()`/`postgres()`/`bigquery()`/`turso()` only when asked |
| Shared third-party account | `connector('name').fetch()` |
| Caller's own third-party account | `personalConnections` |
| Short, watched AI | `llm.generate()` / `llm.stream()` |
| File AI, code execution, durable AI | `agents.start()` + a managed agent |
| Org member directory | `appUsers()` |
| Per-app secrets | `secrets.NAME` |
| System-owned mail | `email.send()` |

**Authorization is your code, and nothing else does it for you.** App access control decides who
may *open* the app. Everything after that — who may edit, approve, delete, see whose records —
is a check you write in the worker against `ctx.user`. There is no scoped store doing it
implicitly any more: `db` is one flat store, so "per-user" means *you* key by `ctx.user.id` and
*you* check it on read.

**Never trust a value from the request body for identity or ownership.** Read it from
`ctx.user`. The one thing a v2 worker gets for free is a caller it can believe.

**Give every top-level section its own path** (`/companies`, `/companies/acme`) — never keep
navigation in an in-memory `view` variable. Deep links, hard refresh, and back/forward must work;
these apps get linked in Slack and tickets. Railcode serving falls back to `index.html`, so
client-side routes resolve with no config.

**Relay the SDK's error status.** When a worker route wraps an SDK call, catch `ApiError` and
respond with its `.status` and body — the frontend's 403/409/429 handling depends on surviving
the extra hop. Swallowing it into a 500 destroys every typed error the platform gives you.

## Worker LLM vs Managed Agents

On v2 there is no in-page LLM — `llm` runs in the worker. The real boundary is now **worker LLM
vs managed agent**, and it is **capability, not sophistication**:

| The AI feature… | Use |
|---|---|
| Summarizes / classifies data the worker already reads, in seconds | **Worker `llm`** |
| Reads, understands, extracts, transforms, or generates any file | **Managed agent** (`app_files` + sandbox) |
| Writes and runs code | **Managed agent** (sandbox) |
| Must survive the request, be retried, or take minutes | **Managed agent** |
| Is triggered from Slack or by an agent schedule | **Managed agent** |
| Needs a run history someone will audit | **Managed agent** |

The planes compose: the worker runs the fast turns itself and delegates heavy steps with
`agents.start()`, then polls the run. See [Worker SDK](references/worker-sdk.md#managed-agents).

## Limitations

When a request hits a row below, say so up front and offer the nearest supported shape. Do not
quietly build an approximation that can't work.

**Platform shape**

| Not possible | Why, and the nearest supported path |
|---|---|
| Self-hosted worker features | Apps v2 workers are **cloud only**; a self-hosted deploy refuses them with `501`. A `static` app still works self-hosted |
| Public or customer-facing apps | Every viewer must be a signed-in org member — no anonymous access, no self-signup. These are internal tools |
| Inbound webhooks / public API endpoints | Your worker only runs on an authenticated app request or your own cron. Poll the source on a cron instead of receiving events |
| Arbitrary outbound calls | Egress is an allow-list. Declare hosts under `egress:` (exact names or one wildcard level; no schemes, ports, or paths); the default is the data plane only |
| Real-time push (websockets, presence) | No push surface; UIs poll. LLM streaming is the only streaming response |
| Next.js | Needs the OpenNext adapter, and its SSR model doesn't map to the bounded single worker. Any other bundler that emits one self-contained ESM module works |
| Custom domains, native mobile, push notifications | Apps are responsive web apps at `<app>.<parent>` |
| Bring-your-own API keys in frontend code | The frontend holds nothing. Use `secrets` in the worker, or a connector |

**Worker runtime**

| Constraint | Value |
|---|---|
| The worker must be **one self-bundled ESM module** | A code-split, CJS, or dependency-referencing worker deploys and then **crashes at invocation**. The CLI guarantees this for its templates; bring-your-own is on you |
| Subrequest budget | ~100 per invocation. Use `files.urls()` for batches, not a loop of `files.url()` |
| Module size | 5 MB soft cap |
| Secrets | 64 per app, 5 KB per value, write-only |
| Daily caps | LLM tokens and emails per app; both return a typed `429` |
| Invocation logs | Retained ~14 days |

**Data**

| Constraint | Detail |
|---|---|
| `db` is one flat store | No joins, transactions, or aggregations. Partitioning is your key design. Keep heavy data in a warehouse and read it via saved queries |
| KV `list()` is first-page-only | Default 100, max 500 — **paginate in the worker or you silently drop the tail** |
| No embeddings or vector search | The LLM gateway is text-in/text-out |
| Presigned file URLs need S3-backed storage | On local-storage deployments `files.url()`/`files.urls()` answer `501`; stream bytes through your own route with `files.get()` instead |

**Agents and cron**

| Constraint | Detail |
|---|---|
| Cron cannot start an agent run | A cron invocation has no caller, so a run would have no owner — refused with `409`. Give the agent **its own schedule** instead |
| Cron caps | 5 schedules per app, 1-minute minimum |
| Cron is at-least-once and may overlap | `ctx.invocationId` is your idempotency key. Never promise "exactly once" |
| Cron dispatches **POST** | A route declared `GET`-only will 404 on every fire and look like a broken schedule |
| Personal connectors don't compose with cron | Every call acts as `ctx.user`; cron has none, so it refuses with `409` |
| Agent runs are never awaited in-band | `agents.start()` returns a queued run; `agents.get(request_id)` reads it back. The worker SDK has **no** call that waits, and a `get()` loop is not one — poll from the frontend or a later invocation |
| Prefer **org** agents with v2 apps | An org agent writes into the app's shared scope, which **is** a v2 app's flat store. A personal agent writes into its owner's user scope, which on a migrated app is frozen and read-only |
| Not exposed to the worker | The org's role list, and design-system guidance. `ctx.user.roles` gives the caller's own roles; fetch design guidance at build time with `railcode design-system` |

## Visual Direction

Treat the scaffold as functional scaffolding, not a style guide — the templates ship a platform
tour meant to be read and deleted.

If the user opted into the Railcode design system, fetch it with `railcode design-system` and
follow it. Otherwise default to its spirit: quiet internal-tool UI, neutral surfaces, compact
controls, clear tables/lists, modest borders/radius, restrained accent color.

Apps must be responsive — verify the main workflows on desktop and mobile widths, with no
overlapping text, clipped controls, or unusable tables.

**Give every app a favicon.** These tools get pinned in a row of tabs, so a blank icon is a real
cost. Draw a small **SVG** that says what the app is — a funnel for a pipeline, a board for a
kanban — in the accent color, and link it:

```html
<link rel="icon" type="image/svg+xml" href="/favicon.svg" />
```

Put it in the frontend's static root (`public/` for the Vite stacks, beside `index.html` for
`hono+static`). Keep it readable at 16px: one shape, no fine detail, no lettering. Set a real
`<title>` in the same file — it's the label next to that icon.

## Local Development

```bash
railcode dev
```

Runs the frontend **and the worker**, serving exactly the paths production carves (`/api/*`,
`/_serverFn/*`). The worker calls the CLI's local data plane over HTTP with the same wire shape
as production, so **"works in `railcode dev`" means "works deployed."**

`db`/`files` hit a local scratch store (`--reset` clears it; dev never touches live data).
Governed capabilities — SQL, saved queries, LLM, email, connectors, agents — **forward to the
real instance** under a dev token carrying your identity. They hit real providers, real data, and
real spend, including sending email and starting real agent runs.

Accepted limits: a single identity, secrets from your local env, and cron triggered by hand.

Local dev storage is separate from the deployed app's: `railcode app kv` / `railcode app files`
read and write the **live** app, never the local emulation.

## Validation

```bash
cd <app>
railcode dev            # confirm the frontend loads and its /api routes answer
railcode manifest validate
```

**Check the worker's own logs.** This is the v2 debugging surface and it has no v1 equivalent:

```bash
railcode logs app --app <slug>            # invocations: path, status, duration, who
railcode logs app <invocation_id>         # one full trace: console lines, errors, authority ops
```

Every invocation is a record, and every governed call inside it appears as an op with its
verdict — so a refusal shows up as `denied` with the resource name rather than as a silent
failure.

**Seeding data to test with.** An app with an empty store only ever shows empty states. Once
deployed, seed a few realistic records with `railcode app kv set <collection> <key> '<json>'`
(`--file` for anything long) and `railcode app files upload <path>` — matching the shape the
worker actually writes, which you can confirm with `railcode app kv get`. Say what you seeded and
remove throwaway rows afterwards. Ask first if the app already holds real data. Under
`railcode dev`, seed through the app's own UI instead — the CLI doesn't touch local dev storage.

If the user asked for browser testing, exercise the running app end to end at desktop and mobile
widths. Treat console errors, failed `/api/*` calls, and broken layouts as failures to fix.

## Deployment

```bash
railcode deploy
```

Reads `railcode.json`, runs the CLI-owned build, uploads the static tree **and** the worker as
one unit, ratifies the manifest, and prints the live URL. The static tree and the worker activate
and revert **together** — a revert restores the exact executable that deploy ran.

A new app defaults to organization-wide access; use `--private` for a private first deploy.

**If you did not create this app, you may not be its only deployer.** Apps carry **editors** — a
co-deploy tier — so check your rights with `railcode apps show <app>` (`can edit` / `can
manage`), `railcode pull` before deploying, and treat a deploy `409` as a colleague who published
after your last sync rather than something to `--force` past.

**Secrets are live app state, not part of a deploy.** Set them once and every later deploy,
revert, and cold revert re-applies the current set:

```bash
railcode secrets set NAME        # hidden prompt, or piped on stdin — never inline
railcode secrets ls              # names + set-at + digest, never values
```

Read [Deployment](references/deployment.md) for resolution, access modes, and verification.
