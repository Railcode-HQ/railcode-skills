# Worker SDK (`@railcode/sdk`)

The backend SDK for apps v2 workers. It runs in exactly two places: a **deployed Railcode
worker**, and **`railcode dev`**. Anywhere else (a browser bundle, a plain `node` script, a test
harness) the first call throws. There is no browser build.

```ts
import { ctx, db, files, llm, agents, query, connector, email, secrets } from "@railcode/sdk";
```

## Contents

- [`ctx` — the verified caller](#ctx--the-verified-caller)
- [`db` — the flat store](#db--the-flat-store)
- [`files`](#files)
- [SQL and saved queries](#sql-and-saved-queries)
- [`llm`](#llm) · [`toNdjson()`](#streaming-to-your-frontend--tondjson)
- [Managed agents](#managed-agents)
- [Service connectors](#service-connectors)
- [Connectors someone owns personally](#connectors-someone-owns-personally)
- [Per-user connectors](#per-user-connectors)
- [`appUsers` and `dataConnectors`](#appusers-and-dataconnectors)
- [`email`](#email)
- [`secrets`](#secrets)
- [Errors](#errors)
- [Authority: the manifest](#authority-the-manifest)

## `ctx` — the verified caller

```ts
ctx.user          // { id, email, name, user_type, is_admin, seat, roles: [{uuid, name}] } | null
ctx.trigger       // "http" | "cron"
ctx.isGuest       // true only for a signed-out visitor of a PUBLIC app (http, no caller)
ctx.invocationId  // this invocation's id — your idempotency key
ctx.waitUntil(p)  // extend past the response (deployed workers only)
```

`ctx.user` is **unforgeable**. It was verified at the platform gate and embedded in the
invocation token; app code cannot fake its caller. It is `null` on cron triggers and for
**guests of a public app** — signed-out visitors and people signed into another org.
`ctx.isGuest` tells the two apart (the release after CLI 0.3.9 / SDK 0.5.0):

| Caller | `ctx.user` | `ctx.isGuest` | `ctx.trigger` |
|---|---|---|---|
| Member, or someone the app is shared with (incl. External) | the user | `false` | `"http"` |
| Guest of a public app | `null` | `true` | `"http"` |
| Cron | `null` | `false` | `"cron"` |

This is the foundation of every authorization decision you write. Never take identity or
ownership from the request body.

```ts
const user = ctx.user;
if (!user) return c.json({ error: "sign in required" }, 401);   // guest (or cron)
if (!user.is_admin) return c.json({ error: "forbidden" }, 403);
```

`ctx.user.roles` carries the **caller's own** roles. There is no way to list the org's full role
set from a worker.

`ctx.user.user_type` (SDK 0.5.0) is the caller's platform type: `"owner" | "admin" | "builder" |
"viewer" | "external"`. `seat` collapses it to `"builder"` (owner/admin/builder) or `"viewer"`
(viewer/external) — use `user_type` when you must tell an **external** person (a client or
contractor who sees only the apps shared with them) from an internal viewer. Both are hints for
UX; every write is still **your** check. Under `railcode dev` the local token carries **your own**
role in the org, not a fixed `owner`.

## `db` — the flat store

**One flat key/value store per app.** No scopes, no namespaces, no per-user partition built in.
Data written by earlier deploys — including a v1 app's unscoped data before migration — is simply
there.

```ts
const notes = db.collection("notes");
await notes.put("key", { title: "hi" });   // returns the stored value
await notes.get("key");                    // the value, or null when absent
await notes.delete("key");
await notes.query().where("status", "eq", "open").orderBy("created_at", "desc").page(1, 100);
```

`get()` and `put()` return the **bare value**. Every paged read — `query().page()`, `first()`,
`list()` — returns `KvRecord<T>[]` = `{ key, value, updated_at }`, so read `.value`. A query also
offers `first()` (one record or `null`) and `count()`; `where()` and `prefix()` can be called on
the collection directly as shorthand for `query().where()` / `query().prefix()`.

`where` takes a **named operator**, not a SQL one: `eq | ne | gt | gte | lt | lte | in`.
Ordering is `orderBy(field, "asc" | "desc")`. `"="` and `.order()` do not exist and fail to
typecheck.

**You own partitioning and access control.** "Per-user" is a key convention plus a check you
write:

```ts
const key = `${ctx.user!.id}:${recordId}`;          // partition
const row = await notes.get(key);
if (!row) return c.json({ error: "not found" }, 404);  // and the check
```

`prefix()` is the matching read for that key convention — one caller's rows, without scanning
the collection:

```ts
await notes.query().prefix(`${ctx.user!.id}:`).orderBy("created_at", "desc").page(1, 100);
```

Do not simulate the old `db.user` / `db.role()` scopes and assume the platform enforces them. It
does not. A prefix is a convention; the check is what makes it real.

### `list()` is first-page-only

`query().page()` and `list()` return **one page** — default 100, max 500. A large collection
silently loses its tail unless you paginate:

```ts
const out = [];
for (let page = 1; ; page++) {
  const rows = await db.collection(name).query().page(page, 500);
  out.push(...rows);
  if (rows.length < 500) break;
}
```

### Frozen scopes: USER- and ROLE-scoped data

Any v2 worker can **read** the app's USER- and ROLE-scoped data; nothing on the worker plane can
write to it. Two things land there: a migrated v1 app's old scoped browser data, and a
**personal** agent's `app_data_write` (an org agent writes to the flat store instead).

```ts
await db.scoped(userId).collection("drafts").get(key);            // value | null
await db.scoped(userId).collection("drafts").list(page, size);    // KvRecord[] — one page
await db.scopedRole(roleUuid).collection("shared").list();
```

A frozen collection exposes **only** `get(key)` and `list(page = 1, size?)` — no `query()`, no
filters. `list()` is one page (default 100, max 500) and must be paginated like `page()`. Copy
what you need into the flat store under your own keys.

## `files`

Server-plane: **your worker holds the bytes**, so uploads are one direct call and downloads are a
streamed `Response`. No presign negotiation.

```ts
await files.put("report.pdf", bytes, "application/pdf");  // string | ArrayBuffer | Blob | stream
const resp = await files.get("report.pdf");               // Response | null
await files.list();
await files.delete("report.pdf");
```

### Handing a file to your frontend

```ts
const one   = await files.url("report.pdf");                    // { name, url, expires_in }
const batch = await files.urls(["a.png", "b.png", "c.png"]);    // { items, missing }
```

**Use `urls()` for more than one file.** A worker invocation has a finite subrequest budget
(~100), and a loop of `url()` is exactly what exhausts it. `urls()` presigns the whole batch with
one storage client. Names with no stored file come back under `missing` rather than throwing — a
partial answer is the normal case. Cap: 100 names per call (`422` above it).

## SQL and saved queries

Prefer **saved queries** — an admin publishes them, so the app never embeds SQL:

```ts
await savedQueries();                       // [{ name, description, params }]
await query("revenue_by_month", { year: 2026 });
```

Direct SQL only when the user explicitly asks. Always bind parameters:

```ts
await data("warehouse").runSQL("select * from orders where id = $1", [id]);
await postgres("warehouse").runSQL(...);    // dialect-pinned variants
await bigquery("analytics").runSQL(...);
await turso("edge").runSQL(...);
```

Listing saved queries (`savedQueries()`) is not manifest-gated. Invoking one needs
`saved_queries:` in the manifest; direct SQL needs the connection under `adhoc_sql:`.

## `llm`

```ts
const r = await llm.generate("Summarize: ...");                         // string in
const r2 = await llm.generate([{ role: "user", content: "..." }], { system, model });
for await (const ev of llm.stream(messages)) { /* text | step | done | error */ }
await llmProviders();                                                   // what the org has configured
```

The signature is `(input: string | LlmMessage[], opts?: LlmOptions)` for `generate`, `stream`
and `streamRaw`; `tools`, `system`, `model`, `provider`, `output` and `limits` all live in `opts`.
Text in, text out. **No embeddings, no vector search, no multimodal input.**

### Tool loops

Tools that carry a `run` make the SDK drive the loop: it validates each call's args against the
schema, executes `run` **in your worker**, feeds `summarize(result)` back, and repeats until the
model answers. Both entry points do it.

```ts
await llm.generate(messages, { tools });                    // resolves with the finished answer
for await (const ev of llm.stream(messages, { tools })) {}  // text + step events, live
```

`llm.streamRaw()` is the exception, and deliberately: it hands you the ndjson bytes to relay
straight to a browser, so there is nobody left in the worker to execute a `run`. It refuses
run-BEARING tools and accepts run-less defs — which is exactly the relay a browser-side loop
needs (see [migration.md](migration.md#the-interactive-llm-tool-loop)).

Manifest: `llm: true`. Exceeding a cap answers `429` — see [Errors](#errors) for which ones carry
a code.

### Streaming to your frontend — `toNdjson()`

Never hand-roll the `ReadableStream`. `toNdjson(source, opts?)` turns any iterable of JSON values
into an ndjson `Response` you return straight from a route:

```ts
app.post("/api/chat", async (c) => {
  const { messages } = await c.req.json();
  return toNdjson(llm.stream(messages, { tools }));
});
```

It owns the two things that are easy to get wrong:

- **A mid-stream failure cannot be an HTTP status** — the 200 is already sent. It becomes a
  terminal `{"type":"error", error, message}` frame. `errorFrame()` keeps a code-typed body's
  code (`daily_cost_limit_exceeded`, `managed_llm_monthly_limit_exceeded`, `provider_auth_error`,
  …); a plain-string `detail` (the per-app daily caps) becomes `provider_error` with the sentence
  as `message`.
- **A client that hangs up must stop the work.** Cancelling closes the source generator, so an
  abandoned run stops spending tokens.

It takes ANY iterable, so a route that interleaves its own frames and persists the turn is still
one call — write an async generator and return `toNdjson(frames())`. See `apps/chat`.

The browser side is ~20 lines: read, split on `\n`, `JSON.parse` each line, and keep a buffer
because a network chunk can split a line. Copy it from `apps/chat/frontend/src/lib/api.ts`.

## Managed agents

A worker can start a managed-agent run and read its outcome. This is how a v2 app reaches file
AI, code execution, and anything that must outlive the request.

```ts
const run = await agents.start("digest", { url });   // returns QUEUED immediately
run.request_id                                        // the poll handle
const later = await agents.get(run.request_id);
```

**Runs are never awaited in-band, and the worker never polls one.** There is no
`agents.invoke()` on the worker plane, and a `get()` loop spends a subrequest per poll while the
invocation token expires before a long run finishes. The shape is:

1. `agents.start()` in a worker route.
2. Return `request_id` to your frontend (or persist it in `db`).
3. The frontend polls a route of yours that calls `agents.get()`.

```ts
const run = await agents.start("digest", input);
await db.collection("jobs").put(jobId, { requestId: run.request_id });
return c.json({ status: "running", requestId: run.request_id }, 202);
```

The full queue-and-poll routes, with the ownership check on the poll, are in
[app-patterns.md](app-patterns.md#delegating-to-a-managed-agent).

### Rules that bite

- **Declare the agent.** `agents: [name, ...]` in `manifest.yaml`, ratified. **A missing
  declaration is a refusal, not pass-through** — an undeclared agent is
  `403 agent "x" was not in the manifest`, even one the caller could invoke from the dashboard
  themselves. An agent that doesn't exist is `404`.
- **Cron cannot start a run — or poll one.** No caller means no run owner, and `agents.get()`
  matches the same `(app, caller)` pair, so both refuse with `409`. Give the agent **its own
  schedule** instead of driving it from an app cron. (Function crons are early; see
  [app-patterns.md](app-patterns.md#cron).)
- **A run is owned by `(app, caller)`.** `agents.get()` reads only runs *this app* started for
  *this caller*. A run started from the dashboard is `404` to the worker, and vice versa.
- **Prefer org agents.** An **org** agent's `app_data_write` lands in the app's shared scope,
  which **is** your flat store — so the agent's results appear in `db` with no bridge. A
  **personal** agent writes into its owner's USER scope, which the worker can only read, via
  `db.scoped(ownerUuid)` (see [Frozen scopes](#frozen-scopes-user--and-role-scoped-data)).

## Service connectors

The org's shared third-party accounts. An admin owns the credential; the backend pins the host
and injects it — your worker never sees it.

```ts
await serviceConnectors();                       // what's enabled
await serviceConnectorDocs("stripe");            // how to call it
const r = await connector("stripe").fetch("/v1/charges", { method: "GET" });
await r.json();
```

Manifest: `connectors: { stripe: ["GET /v1/charges"] }` — bound **per endpoint**, not per
connector.

## Connectors someone owns personally

There is no separate "personal connector": the old `personalConnections` surface and the
`personal_connectors:` manifest key answer **410** with the replacement named in the body.

A connector someone links for themselves is the *same object* as a shared one — an org row with
an `owner` and an `access_mode` — so it uses the same handle:

```ts
await connector("gmail-jp").tools();                          // mcp: callable tools
await connector("gmail-jp").call("send_email", { ... });      // mcp: run one
await connector("stripe").fetch("/v1/charges");               // http: method/path proxy
await serviceConnectors();                                    // what this app may call
```

**`call()` on an MCP row resolves to the MCP content list, not the tool's payload** —
`[{ type: "text", text: "..." }, ...]`, which you unwrap yourself (treating the envelope as the
payload gives a silently empty object, not an error):

```ts
const content = await connector("gmail-jp").call<{ type: string; text?: string }[]>(
  "search_email",
  { query: "from:billing" },
);
const text = content.map((c) => c.text ?? "").join("");
const hits = JSON.parse(text);   // only when the tool documents JSON-as-text
```

Manifest: `connectors: { "gmail-jp": ["send_email"] }` — `["*"]` for the whole row. An app
declaring `gmail-jp: ["send_email"]` can send as that account and cannot read its inbox;
an undeclared tool is `403`.

**Linking is not the app's job.** The person runs `railcode connector link gmail` or links from
the dashboard, and the row exists before your app names it — there is no `connect()`, no
`redirect_url`, no OAuth flow to build. (The one URL an app ever forwards the browser to is a
**per-user** connector's `connectUrl`, below — the platform's page, not yours.)

**Names are not provider ids.** The default name is `<provider>-<handle>` — `gmail-jp` for
`jp@…` — and a name already taken in the org counts up (`gmail-jp-2`, `-3`); the person linking
may also type a different name. Read it from `railcode connector list`; never assume it equals
the provider.

**Crons work** — for shared and owned connectors. A connector's credential belongs to the
**row**, so a scheduled route can call one. Access is still checked against the app's
declaration and the row's sharing. The exception is a **per-user** connector, which has no
credential of its own and refuses under cron (`connector_needs_user`).

## Per-user connectors

A connector can be **per-user** (CLI 0.3.9, SDK 0.5.0): one name, no credential of its own, and
each member connects their **own** account under it. A call that names it goes out on the
*caller's* account. Use one when every person should act as themselves (their own meetings,
inbox, calendar); use a shared or owned connector when one account serves everyone, and for
anything that runs without a person.

**Nothing changes in the manifest or the call site.** `connectors: { granola: [list_meetings] }`
and `connector("granola").call("list_meetings", args)` are the same as for a shared row. What
changes is that a call can be **refused** until the caller has done two things on the platform's
connect page: connected their account, and approved *this app* for the operations its manifest
declares. That refusal is a 409 with `ApiError.connectionRequired` set:

```ts
err.connectionRequired   // { connector, reason: "not_connected" | "consent_required", connectUrl }
```

Relay `connectUrl` (plus `&return_to=<where they were>`) to the browser — the handler is in
[app-patterns.md](app-patterns.md#relay-platform-errors-verbatim). The platform page links the
account, asks for approval, and returns to `return_to` (validated server-side to the app's own
origin — anything else lands on the app's home). **Never build an OAuth URL yourself**, and
never ask the person to paste a token: there is nothing for the app to store.

Rules that follow from "the caller's account":

- **No caller, no call.** A cron route (`ctx.user === null`) gets a 409 with
  `err.code === "connector_needs_user"`. Schedule that work on an owned connector instead.
- **Approval is per app and per operation list.** A redeploy that declares *more* on the connector
  is refused for the new operations until the member approves again; one that declares less keeps
  working. Approval is withdrawn when the member disconnects.
- **Never under impersonation.** An admin acting as a member gets 403, on every plane.
- **Managed agents cannot use one.** An agent manifest naming a per-user connector is rejected.
- **Logs keep no content.** For per-user calls the platform records caller, operation and outcome,
  and withholds bodies, headers and upstream error text.

Two diagnostics, both only meaningful under a ratified `run_as: app` manifest that declares the
connector:

```ts
const granola = connector("granola");
const connection = await granola.connection();   // local DB only, no provider request
// { status: "not_connected" | "linking" | "consent_required" | "ready",
//   credentialMode: "shared" | "per_user", linked, consented, connectUrl }

if (connection.status === "ready") {
  const health = await granola.checkHealth();     // one read-only probe at the provider
  // { status: "healthy" | "reauth_required" | "permission_denied" | "unreachable"
  //           | "unsupported" | "inconclusive", checkedAt, upstreamStatus, connectUrl }
}
```

`connection()` is what a settings page renders ("Connect your Granola" vs "Connected as …");
a shared connector reports `ready` with `linked` and `consented` true. `checkHealth()` is
opt-in and costs an upstream request; `unsupported` means the provider has no probe path, not
that anything is wrong. Both are advisory — still handle the call-time 409. Under `railcode dev`
they forward to the **deployed** app's manifest, so deploy once before testing them.

**Which kind am I holding?** `railcode connector list` shows a `mode` column (`per-user` /
`shared`) when any per-user row exists; `railcode connector status <name> --app <slug>` shows
whether *you* connected and approved the app. From the worker, `connection().credentialMode`.

## `appUsers` and `dataConnectors`

Read-only org discovery, for building pickers and showing names:

```ts
await appUsers();          // [{ id, email, name, is_admin }] — id matches ctx.user.id
await dataConnectors();    // [{ name, engine }] — never a DSN
```

Both require the ratified `run_as: app` manifest.

## `email`

```ts
await email.send({ to, subject, html });
```

Send-only, platform-pinned sender, appended disclaimer. **You cannot receive email or send from a
custom address.** When mail must come from a specific person's own account, use a Gmail
**connector** they own instead. Manifest: `email: true`. Per-app daily cap → `429` (plain-string
`detail`, see [Errors](#errors)).

## `secrets`

```ts
secrets.STRIPE_KEY        // ambient, per-app
```

Set them with the CLI, never in code:

```bash
railcode secrets set STRIPE_KEY      # hidden prompt or piped stdin
railcode secrets import .env
railcode secrets ls                  # names + set-at + digest, never values
railcode secrets rm STRIPE_KEY
```

Write-only and **live app state, not part of a deploy** — every deploy, revert, and cold revert
re-applies the current set, so a revert can never resurrect a rotated value. Caps: 64 per app,
5 KB per value.

## Errors

```ts
import { ApiError, LlmRunError } from "@railcode/sdk";
```

`ApiError` carries `.status` and the raw response body as `.message`; `.detail` unwraps the
backend's sentence from `{"detail": "…"}` or `{"detail": {"error", "message"}}` (and falls back
to the raw body when it isn't JSON). **Relay it verbatim** from your worker routes — the
frontend's 403/409/429 handling depends on the status surviving the extra hop:

```ts
try {
  return c.json(await db.collection("notes").get(key));
} catch (err) {
  if (err instanceof ApiError) {
    let body: unknown;
    try { body = JSON.parse(err.message); } catch { body = { detail: err.detail }; }
    return c.json(body, err.status);
  }
  throw err;
}
```

`err.code` (SDK 0.5.0) is the backend's machine-readable code when the body carries one —
`connection_required`, `connector_needs_user`, `daily_cost_limit_exceeded`, … — and
`err.connectionRequired` is set only for a per-user connector that needs the caller to connect or
approve (see [Per-user connectors](#per-user-connectors)). Both are `undefined` otherwise.

Statuses worth handling by name: `403` undeclared authority; `409` not-connected,
consent-required or cron-incompatible (read `err.code`); `429` a quota. Do **not** branch on
`err.code` for a 429: the per-app daily caps (LLM tokens, email) answer with a plain-string
`detail` and the response header `X-Railcode-Quota: 1`, so `err.code` is `undefined` — check
`err.status === 429` and show `err.detail`. Only the org's daily USD cap
(`daily_cost_limit_exceeded`) and the managed credit (`managed_llm_monthly_limit_exceeded`)
carry a code.

## Authority: the manifest

`manifest.yaml` sits beside `railcode.json`. When a v2 app has a manifest it **must** say
`run_as: app` — the deploy is refused with `400` otherwise, because the worker is the principal
and there is no caller whose personal grants could stand in. Without a ratified manifest every
governed operation (`llm`, `email`, saved queries, SQL, connectors, agents, `appUsers()`,
`dataConnectors()`) is refused with `403`.

```yaml
run_as: app
llm: true
email: true
saved_queries:
  - revenue_by_month
adhoc_sql:
  - warehouse
connectors:
  stripe:
    - GET /v1/charges
  gmail-jp:
    - send_email
agents:
  - digest
egress:
  - api.example.com
  - "*.internal.example.com"
crons:
  - schedule: "0 6 * * *"
    path: /api/refresh
```

Declare **only what the worker actually uses**. A deploy whose manifest adds operations the
deployer doesn't personally hold is **refused with `403`** (block-on-deploy) — nothing is
staged for later approval. Have an admin grant the deployer that authority, or declare less. A
deploy whose additions the deployer does hold ratifies on the spot.

```bash
railcode manifest validate        # strict local parse, before deploying
railcode manifest show <app>      # the ratified doc
```
