# App Patterns (apps v2)

Implementation patterns for a Railcode v2 app: a static frontend plus a backend worker. For the
SDK surface itself see [worker-sdk.md](worker-sdk.md). For a generation-1 app see
[v1-legacy.md](v1-legacy.md) — the patterns here do not apply there.

## Contents

- [Layout by stack](#layout-by-stack)
- [The split, and why it matters](#the-split-and-why-it-matters)
- [Worker route patterns](#worker-route-patterns)
- [Authorization is your code](#authorization-is-your-code)
- [Data modeling on a flat store](#data-modeling-on-a-flat-store)
- [Frontend patterns](#frontend-patterns)
- [Files](#files)
- [LLM](#llm)
- [Delegating to a managed agent](#delegating-to-a-managed-agent)
- [Cron](#cron)
- [Public apps](#public-apps)
- [Common pitfalls](#common-pitfalls)

## Layout by stack

`railcode init` scaffolds five stacks and **the CLI owns the build for all of them** — the app
declares no bundler, no `wrangler`, and no Cloudflare package.

**`hono+vite`** (default) — Vite + React frontend, Hono worker:

```
frontend/          # client (Vite root)
server/index.ts    # export default app
railcode.json      # { app, type: "hono+vite", dist: "dist/client", server: "dist/server/index.js" }
manifest.yaml
```

**`hono+static`** — one `index.html`, no frontend build, Hono worker:

```
frontend/index.html
server/index.ts
railcode.json      # { app, type: "hono+static", dist: "dist/client", server: "dist/server/index.js" }
```

**`tanstack`** — TanStack Start in SPA mode; server functions (`/_serverFn/*`) and routes
(`/api/*`) run in the worker. Data routes must be `ssr: false`.

**`next`** — Next.js (App Router), whole: Server Components, Server Actions, Route Handlers and
streaming all run in the worker, which answers every path (`routes: all` is implied). Built with
`@railcode/next`, so the app carries no wrangler or OpenNext config. Pages that call
`@railcode/sdk` must render per request — there is no invocation at build time.

**`static`** — pure hosting. No worker and no worker manifest keys.

**Bring your own** — any bundler that emits a static `dist` plus **one self-contained ESM module**
with `export default { fetch }`. Point `"dist"` and `"server"` at them. The one rule: the module
must inline everything (esbuild `bundle: true`, Vite `inlineDynamicImports`). A code-split or CJS
worker deploys and then crashes at invocation.

## The split, and why it matters

The frontend is static files: it holds no credentials and proves nothing. Any check it makes is a
UX affordance, not a control — a user can call `/api/*` directly with `curl` from a logged-in
session, so **every rule must also exist in the worker**, where `ctx.user` is verified and all
authority lives.

The only platform endpoints a v2 page may call are `/_api/me` and `/_api/logout` (the chrome
bar's). Prefer getting identity from your own worker route so there is one source of truth.

## Worker route patterns

### The shape

```ts
import { Hono } from "hono";
import { ApiError, ctx, db } from "@railcode/sdk";

const app = new Hono();

app.get("/api/me", (c) => c.json({ user: ctx.user }));

app.get("/api/notes", async (c) => {
  const rows = await db.collection("notes").query()
    .where("owner", "eq", ctx.user!.id).orderBy("updated_at", "desc").page(1, 100);
  return c.json({ items: rows.map((r) => r.value) });   // page() returns KvRecord[]
});

export default app;
```

Everything hangs off `/api/*` (and `/_serverFn/*` on TanStack). Those are the paths the platform
carves to your worker; anything else is served as a static file.

### Describe your routes at `/api/openapi.json`

Agents reach your app through the [Railcode MCP](https://github.com/Railcode-HQ/railcode/blob/main/docs/mcp.md),
which has no idea what your routes are. If you serve an OpenAPI document at
**`/api/openapi.json`**, `list_app_tools` lists your endpoints and what each one requires and
`describe_app_tool` returns one endpoint's parameters and body schema. Without it an agent
guesses, and a wrong path and a wrong method both answer `404`.

Serve it from the worker, not as a static file: MCP callers may only fetch `/api/*` and
`/_serverFn/*`, so `frontend/public/openapi.json` is unreachable. Keep the document beside the
routes in `server/openapi.ts` and mount it:

```ts
// server/openapi.ts
export const openapi = {
  openapi: "3.1.0",
  info: { title: "Notes", version: "1.0.0", description: "Team notes. Errors are {error}." },
  paths: {
    "/api/notes": {
      get: { summary: "List the caller's notes, newest first" },
      post: {
        summary: "Create a note",
        requestBody: {
          required: true,
          content: { "application/json": { schema: {
            type: "object",
            properties: { title: { type: "string", maxLength: 200 }, body: { type: "string" } },
            required: ["title"],
          } } },
        },
      },
    },
    "/api/notes/{id}": {
      delete: {
        summary: "Delete one note",
        parameters: [{ name: "id", in: "path", required: true, schema: { type: "string" } }],
      },
    },
  },
};

// server/index.ts
app.get("/api/openapi.json", (c) => c.json(openapi));
```

Two platform facts shape the document:

- **Mark what is required.** `required: true` on a path parameter, and `required` on the body
  schema — those are exactly what `list_app_tools` reports as the arguments to supply. An
  optional body's own required fields are not reported, because they only bind once a body is sent.
- **Local `$ref`s are fine** (the MCP inlines them); external `$ref`s are dropped.

### Relay platform errors verbatim

Wrap SDK calls so a `403`/`409`/`429` reaches the browser as itself. Collapsing them into a `500`
throws away every typed error the platform gives you.

```ts
async function relay<T>(c: Context, fn: () => Promise<T>) {
  try {
    return c.json(await fn());
  } catch (err) {
    if (err instanceof ApiError) {
      let body: unknown;
      try { body = JSON.parse(err.message); } catch { body = { detail: err.detail }; }
      return c.json(body, err.status);
    }
    throw err;
  }
}

// connector().fetch() resolves to a Response-like envelope — read its body before returning it
app.post("/api/charge", (c) =>
  relay(c, async () => (await connector("stripe").fetch("/v1/charges", { method: "POST" })).json()),
);
```

Then the frontend can act on meaning:

```ts
if (res.status === 409) showConnectPrompt();      // connector not linked / needs re-auth
if (res.status === 429) showQuotaNotice();        // a quota — the body's detail says which
if (res.status === 403) showNotAllowed();         // undeclared authority
```

For a **per-user** connector the 409 carries somewhere to go. Relay the platform's URL and let the
browser follow it; the connect page links the account, asks the person to approve this app, and
comes back to `return_to`:

```ts
// worker
app.onError((err, c) => {
  if (err instanceof ApiError && err.connectionRequired) {
    const back = encodeURIComponent(c.req.url);
    return c.json({ connect: `${err.connectionRequired.connectUrl}&return_to=${back}` }, 409);
  }
  throw err;
});

// frontend
if (res.status === 409) {
  const { connect } = await res.json();
  if (connect) window.location.assign(connect);   // platform page, not your OAuth
}
```

Do not cache "connected": approval can be withdrawn and a wider redeploy re-asks, so the 409 can
return at any time. A settings page can show state up front with `connector(name).connection()`.

### Cron routes must accept POST

The scheduler dispatches **POST**. A `GET`-only route 404s on every fire and looks like a broken
schedule, not a bug in your code.

```ts
app.post("/api/refresh", async (c) => { /* ... */ });
```

## Authorization is your code

There is no scoped store enforcing ownership any more. `db` is one flat store; a key prefix is a
convention, and the check is what makes it real.

```ts
// ❌ the id came from the caller — reading it proves nothing
const row = await db.collection("notes").get(c.req.param("id"));
return c.json(row);

// ✅ verify what you read against the verified caller
const row = await db.collection("notes").get(c.req.param("id"));
if (!row || row.owner !== ctx.user!.id) return c.json({ error: "not found" }, 404);
```

Prefer **404 over 403** for records the caller shouldn't know exist — a 403 confirms existence.

Rules like "X submits, Y approves, X can't approve their own" are worker code, in a place a user
cannot reach:

```ts
app.post("/api/requests/:id/approve", async (c) => {
  const user = ctx.user;
  if (!user) return c.json({ error: "cron cannot approve" }, 409);
  const req = await db.collection("requests").get(c.req.param("id"));
  if (!req) return c.json({ error: "not found" }, 404);
  if (req.submitted_by === user.id) return c.json({ error: "cannot approve your own" }, 403);
  if (!user.is_admin) return c.json({ error: "approver role required" }, 403);
  await db.collection("requests").put(req.id, { ...req, status: "approved", approved_by: user.id });
  return c.json({ ok: true });
});
```

## Data modeling on a flat store

One store, so keys carry the structure. Pick a convention and keep it everywhere.

| Ownership | Key convention |
|---|---|
| Shared across everyone | `"<id>"` |
| Per user | `"<userId>:<id>"` |
| Per role/team | `"role:<roleUuid>:<id>"` |
| A singleton (settings) | `"settings"` |

Store the owner **inside the record too**, so a read can be verified without re-parsing the key:

```ts
await db.collection("notes").put(`${user.id}:${id}`, {
  id, owner: user.id, title, body, updated_at: new Date().toISOString(),
});

// paged reads come back as KvRecord — the record is under .value
const latest = await db.collection("notes").query().prefix(`${user.id}:`)
  .orderBy("updated_at", "desc").first();
if (latest && latest.value.owner !== user.id) /* never trust the prefix alone */;
```

**Always paginate.** `page()` returns one page (default 100, max 500); loop until a short page —
the loop is in [worker-sdk.md](worker-sdk.md#list-is-first-page-only).

For anything genuinely large — analytics, history, joins — keep it in a warehouse and read it
through a saved query. KV filters, orders, and pages; it does not aggregate or join.

## Frontend patterns

**One small client module, and nothing else talks to the network.**

```ts
// src/lib/api.ts
async function call(path: string, init?: RequestInit) {
  const res = await fetch(path, {
    ...init,
    headers: { "content-type": "application/json", ...(init?.headers ?? {}) },
  });
  if (!res.ok) throw Object.assign(new Error(await res.text()), { status: res.status });
  return res.status === 204 ? null : res.json();
}

export const api = {
  me: () => call("/api/me"),
  notes: () => call("/api/notes"),
  saveNote: (n: unknown) => call("/api/notes", { method: "POST", body: JSON.stringify(n) }),
};
```

Components and stores import `api`. They never `fetch` directly, never build URLs, and never see
a platform endpoint.

**Routing.** Give every top-level section its own path and put the open record in the path too
(`/companies`, `/companies/acme`). Never keep navigation in an in-memory `view` variable — deep
links, hard refresh, and back/forward must work, because these apps get pasted into Slack and
tickets. The platform falls back to `index.html` for unknown paths, so client-side routing needs
no config.

**State.** Keep shared/cross-component state in a store (Zustand in the scaffolds); use local
component state only for things that are genuinely local, like a form's in-progress input.

**Show real empty and error states.** An unconfigured connector, an unlinked personal account, or
an empty collection should render something honest and actionable — not a spinner forever.

## Files

Upload through your worker; the worker holds the bytes.

```ts
app.put("/api/files/:name", async (c) => {
  const body = await c.req.arrayBuffer();
  const meta = await files.put(c.req.param("name"), body, c.req.header("content-type"));
  return c.json(meta);
});
```

**Displaying many files — use the batch.** One `url()` per file is what exhausts the invocation's
subrequest budget:

```ts
// ❌ N subrequests
const urls = await Promise.all(names.map((n) => files.url(n)));

// ✅ one
const { items, missing } = await files.urls(names);
```

`missing` is data, not an error — render those names as unavailable rather than failing the page.

## LLM

`llm` runs in the worker, so the browser never holds a model call.

```ts
app.post("/api/summarize", (c) => relay(c, async () => {
  const { text } = await c.req.json();
  return llm.generate(`Summarize:\n${text}`);
}));
```

`generate` and `stream` both run the tool loop when tools carry `run`; `streamRaw()` refuses
run-bearing tools because it only relays bytes. Stream to the page through `toNdjson()`, never a
hand-rolled `ReadableStream`. The facts and failure modes are in
[worker-sdk.md](worker-sdk.md#llm).

```ts
app.post("/api/chat", async (c) => toNdjson(llm.stream(await c.req.json(), { tools })));
```

**Never feed a file into the LLM.** File contents, file URLs, and file-derived payloads are a
managed agent's job, always.

## Delegating to a managed agent

The worker handles fast turns and hands off anything that must outlive the request.

```ts
app.post("/api/extract", async (c) => {
  const { file } = await c.req.json();
  const run = await agents.start("extractor", { file });          // returns QUEUED
  await db.collection("jobs").put(run.request_id, {
    owner: ctx.user!.id, file, status: "running",
  });
  return c.json({ requestId: run.request_id }, 202);
});

app.get("/api/extract/:id", async (c) => {
  const job = await db.collection("jobs").get(c.req.param("id"));
  if (!job || job.owner !== ctx.user!.id) return c.json({ error: "not found" }, 404);  // db does not check
  const run = await agents.get(c.req.param("id"));
  return c.json({ status: run.status, output: run.output_json });
});
```

The frontend polls `/api/extract/:id`; the worker never waits for or polls a run itself (why:
[worker-sdk.md](worker-sdk.md#managed-agents)).

**Results can also arrive by themselves.** An **org** agent's `app_data_write` lands in the app's
shared scope, which **is** your flat store — so an agent can write straight into a collection your
worker reads, with no bridge at all.

## Cron

> Function crons are early and their limits are under review. The caller-less trigger model below
> is settled and the refusals are deliberate. **Do not build an app whose core loop needs a cron
> to do something this section says it cannot** — take the alternative below instead.

```yaml
crons:
  - schedule: "0 6 * * *"
    path: /api/refresh
```

**A cron invocation has no caller.** `ctx.user` is `null` and `ctx.trigger` is `"cron"`. That
one fact produces every limit here.

### What a cron cannot do

| Refused (`409`) | Why |
|---|---|
| `agents.start()` | A run is owned by `(app, caller)`. No caller, no owner |
| `agents.get()` | The same ownership pair — a cron cannot even poll a run an **http** invocation started |
| A **per-user** connector | No credential of its own; the call needs a signed-in caller (`connector_needs_user`) |

All refuse up front, before any upstream call.

**The limit that actually bites is your own authorization code.** A route that reads
`ctx.user.roles` or filters by `ctx.user.id` will throw under cron — or worse, return everything,
because the flat store enforces nothing. Branch on `ctx.trigger`, or guard early:

```ts
if (!ctx.user) return c.json({ error: "cron cannot do this" }, 409);
```

### What a cron CAN do

Everything else: `db` (including the read-only `db.scoped(userId)` / `db.scopedRole(roleUuid)` —
the owner is an argument, not the caller), `files`, `data`/`postgres`/`bigquery`/`turso`,
`query`/`savedQueries`, `llm`, `email`, `appUsers()`, `secrets`, egress, and **shared and owned
connectors** — those are the app's own authority, never a caller's. The one connector a cron
cannot call is a per-user one.

### Scheduled work on someone's personal account

Don't drive it from the app cron — give a **personal** agent the connector (Granola, Gmail, ...)
and its own schedule (`railcode agent schedule`). Its identity is fixed to its owner, it writes
results into that owner's USER scope, and your worker reads them with `db.scoped(ownerUuid)`.
Authoring the agent is the `create-railcode-agent` skill's job; the worked example,
`agents/proposals`, lives in the `Railcode-HQ/railcode-examples` repo.

### Operational rules

- **At-least-once, and runs may overlap.** Use `ctx.invocationId` as an idempotency key and make
  external side effects safe to repeat. Never promise "exactly once".
- Caps: 5 schedules per app, 1-minute minimum.
- A schedule pauses with a visible reason if the current deploy has no worker.


## Public apps

An owner or org admin can make an app **public**: anyone with the link opens it without signing
in (`railcode apps set-access <app> --public on`, or the Access page; CLI 0.3.10+ / SDK 0.5.1+, on an instance
that offers it). Then strangers reach **every** worker route:

- Signed-out visitors and people signed into **another org** arrive with `ctx.user === null`
  and `ctx.isGuest === true`. Org members (and people the app is shared with) keep their
  identity.
- A guest gets the worker's full authority: the app's `db`/`files` and whatever the manifest
  grants (`llm`, `email`, saved queries, connectors), billed to the org. A route that doesn't
  check the caller lets anyone use the LLM, read every row, or write data.

Decide per route what a guest may do, and gate the rest:

```ts
import { ctx } from "@railcode/sdk";

// Everything under /api/admin needs a member.
app.use("/api/admin/*", async (c, next) => {
  if (!ctx.user) return c.json({ error: "sign in required" }, 401);
  await next();
});

// A public form: guests may submit, only members may read submissions.
app.post("/api/contact", async (c) => { /* validate + rate-limit, then db.put */ });
app.get("/api/contact", async (c) => {
  if (!ctx.user) return c.json({ error: "sign in required" }, 401);
  /* ... */
});
```

- Never treat `ctx.user === null` as "this is the scheduler" — a guest looks the same. Gate
  cron-only work on `ctx.trigger === "cron"`.
- Keep GET/HEAD handlers free of side effects: on a public app, links from other sites
  can trigger them.
- The page shows no Railcode bar to guests (`/_api/me` answers 403); render your own
  signed-out state from `/api/me`.

## Common pitfalls

| Pitfall | What happens | Fix |
|---|---|---|
| Checking permissions only in the frontend | Anyone can `curl` `/api/*` from a logged-in session | Re-check in the worker against `ctx.user` |
| Taking a user id from the request body | Trivially spoofed | Read `ctx.user.id` |
| Assuming a key prefix isolates data | It doesn't; `db` is flat | Verify the owner on read |
| Using `query()` without paging | Silently drops everything past the first page | Loop until a short page |
| A loop of `files.url()` | Burns the subrequest budget | `files.urls(names)` |
| `llm.streamRaw({ tools })` with `run` handlers | Throws — a relay can't execute a tool | `llm.stream()`, or drop `run` and handle the calls yourself |
| A `GET` cron route | 404s on every fire | Accept POST |
| Cron calling `agents.start()`/`get()` | `409` | Give the agent its own schedule (see [Cron](#cron)). **Shared and owned connectors are fine under cron** — the credential belongs to the row; a **per-user** connector refuses with `409 connector_needs_user` |
| Swallowing `ApiError` into a 500 | The UI can't tell quota from forbidden | Relay `.status` verbatim |
| A hand-rolled `ReadableStream` for a stream | A mid-stream failure vanishes; a hang-up keeps burning tokens | `toNdjson(source)` |
| A code-split or CJS worker bundle | Deploys, then crashes at invocation | One self-contained ESM module |
| Adding `"server"` to a generation-1 app | Deploy `422` | Migrate first — one-way |
