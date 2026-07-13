# Platform Magic

Use this reference when an agent needs to explain or rely on Railcode's zero-config auth,
data, SDK, access, SQL, service-connector, or LLM behavior on the **multi-tenant** platform.

## Request Routing

Railcode is multi-tenant: every app belongs to an **organization**, and apps are static apps
served from per-org subdomains. With the default two-label host strategy:

```text
https://<app_slug>.<org_slug>.<BASE_DOMAIN>/      e.g. https://notes.acme.railcode.dev/
```

(A platform configured for `single_label` serving drops the org label:
`https://<app_slug>.<BASE_DOMAIN>/`. The CLI records which strategy your instance uses and
prints the right live URL.)

The same host also exposes the platform data plane at **`/_api/*`**. Because the browser
calls same-origin URLs, app code needs no CORS config, no API URLs, and no credentials. The
backend scopes every `/_api/*` call server-side to `(org, app)` from the request's host +
session — the app never names itself or its org in client code.

Reserved subdomains (the dashboard/login parent, `api`, `admin`, etc.) cannot be app slugs.

## Auth And App Identity

Railcode derives context from server-controlled request state, not from browser JavaScript:

- **Serving (app pages + `/_api/*`)** is gated by a **parent-scoped serving cookie**
  (`Domain=.<parent>`), the only cross-subdomain credential. The platform verifies org
  membership and per-app access before any app byte or `/_api/*` response is served. App
  identity comes from the `Host` header.
- **Dashboard/API** (the control plane) uses **bearer tokens** — `Authorization: Bearer
  <token>` — with no cookies/CSRF.
- **CLI** uses a long-lived, revocable **personal API token**. CLI/token-driven app routes
  are explicit and org-scoped: `/api/organizations/{org}/apps/{app}/...` (deploy, SQL, LLM,
  connections in `railcode dev`).

The "magic": frontend code just calls same-origin `/_api/*`, and the backend already knows
both who is calling and which app/org is calling.

## SDK Surface

Every app loads the SDK with a same-origin script tag:

```html
<script src="/_api/sdk.js"></script>
```

On load it attaches a fixed set of globals to `window`. There is no `loadRailcodeSdk()`
bootstrap and no wrapper module — call the globals directly (in TypeScript, `declare` them).
Every call is same-origin against `/_api/*`, credentialed by the serving cookie:

```js
const who   = await me();          // user includes is_admin + assigned {uuid,name} custom roles
const people = await appUsers();   // [{ uuid, name, email, is_admin }] — no role memberships
const orgRoles = await roles();    // [{ uuid, name, description, is_member }] — every custom org role
const ds    = await designSystem();// the org's design-system guidance (markdown string)

await db.collection("notes").put("n1", { text: "hi", n: 3 });
await db.collection("notes").get("n1");

await files.upload("logo.png", blob, "image/png");
const url = files.url("logo.png");
const resolved = await files.urls(["logo.png", "avatars/alice.png"]);

const rows = await postgres("analytics").runSQL("select * from orders where id = $1", [id]);
const bq   = await bigquery("warehouse").runSQL("select id from `ds.orders` where id = @p", []);
const any  = await data("analytics").runSQL("select 1");   // engine-generic (dispatch by kind)
const conns = await dataConnectors();             // [{ engine, name }]

const mine = await query("my_orders", { region: "emea" });  // invoke a saved query by name
const qs   = await savedQueries();                // [{ name, description, params, version }]

const resp = await connector("stripe").fetch("/v1/charges", { method: "POST", body });
const svc  = await serviceConnectors();           // [{ name, description, auth_type, allowed_methods }]

const out  = await llm.generate("Summarize this record.", { metadata: { feature: "summary" } });
```

The globals are exactly: `me`, `appUsers`, `roles`, `designSystem`, `db`, `files`, `data`, `postgres`,
`bigquery`, `turso`, `dataConnectors`, `query`, `savedQueries`, `connector`,
`serviceConnectors`, `llm`, `llmProviders`, `email`, `agents`. Notes:

- `me()` returns nested objects. Use **`me().user.uuid`** as the stable per-user key for
  ownership/permissions/KV prefixes; `me().user.name`/`.email` are for display.
  `me().user.is_admin` is true for org owners and admins, and `me().user.roles` is the
  caller's assigned custom roles as `{ uuid, name }[]`. These are UI hints only; server-side
  authorization remains authoritative.
- SQL runs through the database namespaces: `data(name)` is engine-generic (dispatches on the
  connection's stored kind server-side); `postgres(name)` / `bigquery(name)` / `turso(name)`
  are dialect-pinned and only reach connections of that engine. `dataConnectors()` lists the
  configured connections as `{ engine, name }`, where engine is `postgres`, `bigquery`, or
  `turso`.

The SDK also ships a hidden live inspector drawer that logs every call (`db`, `files`, `llm`,
`email`, `data`/`postgres`/`bigquery`/`turso`, `connector`, `me()`, `appUsers()`, `roles()`, `designSystem()`) with a pending → ok/error
transition and timing. It has no on-screen affordance — toggle it with ``Ctrl+` `` (control +
backtick). It is present in production too, just dormant until opened. Do not swallow SDK
errors; surface useful error states in the app.

## Access Policies

Access governs **who, within the app's org, may open the app** — distinct from org membership
(non-members never reach an org's apps at all). A user who can't access an app gets a **404**
(existence hidden), never a bare 403.

An app's `access_mode` is one of:

- **`organization`** — every org member (the **default** for a newly created/deployed app).
- **`private`** — owners only.
- **`restricted`** — owners plus explicitly-granted members.

Org admins/owners **bypass** per-app access — they see and manage every app in the org.
Access is read/set in the **admin UI** or via `GET`/`PUT
/api/organizations/{org}/apps/{app}/access`.

`appUsers()` returns the app's org members (`{ uuid, name, email, is_admin }`) without custom
role memberships; use it for assignee pickers, mentions, and display, not as an authorization
check. `roles()` returns every custom org role, including empty roles, as
`{ uuid, name, description, is_member }` (`is_member` flags the roles the caller belongs to);
match those UUIDs against `me().user.roles` when building role-aware UI. The server remains
authoritative for access.

## KV Store

`db.collection(name)` is a per-app JSON key/value store, shared across that app's allowed
users. Mutations: `put(key, value)`, `get(key)`, `delete(key)`, `list()`.

Use shared keys for collaboration surfaces, and **user-prefixed keys** for per-user private
state (prefix by the stable user uuid):

```js
await db.collection("messages").put(messageId, message);            // shared

const who = await me();
await db.collection("drafts").put(`${who.user.uuid}:${draftId}`, draft);  // per-user
```

For anything that can grow past a small list, use the query builder instead of `list()`:

```js
const newest = await db.collection("messages")
  .query()
  .orderBy("updatedAt", "desc")
  .page(1, 50);

const page = await db.collection("messages")
  .where("roomId", "eq", roomId)
  .orderBy("updatedAt", "desc")
  .page(1, 50);                       // page(pageNumber, size?) — size is a number

const mine    = await db.collection("drafts").prefix(`${who.user.uuid}:`).page();
const changed = await db.collection("messages").query().updatedSince(lastSeenIso).count();
const first   = await db.collection("messages").where("pinned", "eq", true).first();
```

`where()` and `prefix()` can start a query from a collection. For pure ordering/paging
with no filter, or for updated-time filters, start with `query()` first —
`db.collection("messages").orderBy(...)` and `.updatedSince(...)` are not collection
methods.

Query semantics (the dev engine is a byte-for-byte port of the backend, so dev matches prod):

- `where(field, op, value)` operators are the **string names** `eq`, `ne`, `gt`, `gte`,
  `lt`, `lte`, `in` — not symbols. `in` takes an array.
- `field` is a virtual field — `key` (string) or `updatedAt`/`updated_at` (datetime; no `in`)
  — or a **dotted JSON path** into the stored value (`done`, `assignee.email`). The
  comparison is typed by the operand (number/boolean/string), not lexicographic. A
  missing/null field excludes the row.
- `prefix()` does a byte-range key scan; `updatedSince()` is inclusive, `updatedBefore()` is
  exclusive; `orderBy(field, "asc"|"desc")` defaults to `key`/ascending.
- Paging is 1-based; **default size 100, max 500**. `list()` returns the first page of all
  rows (shaped `{ key, value, updated_at }`); prefer `page()`/`first()`/`count()` for large
  collections.

## Files

Files are per-app objects:

```js
await files.upload("logo.png", blob, "image/png");   // upload(name, data, contentType?)
const url = files.url("logo.png");                    // GET URL (use in <img src>, fetch)
const entries = await files.list();                   // [{ name, content_type, size, updated_at }]
const resolved = await files.urls(["logo.png", "docs/report.pdf"]);
// { items: [{ name, url, expires_in }], missing: [] }
await files.delete("logo.png");
```

`data` may be a `Blob`, `ArrayBuffer`, or typed array; the content type is inferred from a
`Blob` when omitted. File names cannot start with `/`, contain `\`, or use `.`/`..` traversal
segments; `/` is supported for nested paths. Use `files.urls(names)` for galleries and other
file-heavy views: it resolves up to 100 existing files with one authenticated request, reports
missing names, and caches resolved URLs in memory until shortly before expiry. Served bytes are
returned `Content-Disposition: attachment` + `nosniff`. The current `railcode dev` file
emulator does not implement the batch endpoint; use `files.url(name)` locally.

## SQL (Postgres / BigQuery / Turso)

Use saved queries for database access unless the user explicitly tells you to use direct or
ad-hoc SQL. The direct SQL APIs below exist for explicitly requested ad-hoc SQL only; normal
apps should invoke admin-published saved queries with `query(name, params)`.

An admin registers global SQL connections server-side. Browser apps query them through a
database namespace without ever seeing DSNs, passwords, or service-account keys:

```js
const rows = await postgres("analytics").runSQL(
  "select id, total from orders where customer_id = $1",
  [customerId],
);
// rows is an array of row objects, plus rows.columns / rows.rowcount / rows.truncated
```

Rules:

- `data('name').runSQL(sql, params)` runs against a connection of **any** kind — the backend
  dispatches on the connection's stored engine. The dialect-pinned `postgres('name')` /
  `bigquery('name')` / `turso('name')` only reach connections of that engine (a mismatch
  is a 404). Either form takes `.runSQL(sql, params)`, or `.runSQL(...)` with no name for the
  connection named `default`.
- **postgres**, **bigquery**, and **turso** are supported; the backend rejects other
  engines. The query is forwarded verbatim and never translated, so write in the target
  engine's SQL dialect (Postgres uses `$1` placeholders; BigQuery/Turso use `?`).
- Treat SQL as **read-only**. Always use placeholders + a params array; never concatenate user
  input.
- Call `dataConnectors()` to discover configured connections as `{ engine, name }`. Expect it
  to be empty in unauthenticated local dev (and show a clean empty state).
- The server caps result rows (the envelope's `truncated` flag tells you when it did).
- On Postgres and Turso the platform opens sessions **read-only**, so writes fail regardless of
  the credential. BigQuery has no session-level read-only mode; its connection credential's
  privileges are the boundary. Treat all app SQL as read-only.
- Do not use these direct SQL APIs unless the user explicitly requested direct/ad-hoc SQL.

## Saved Queries

*(New in CLI/SDK 0.1.14.)* A **saved query** is a named, versioned SQL template an org
admin publishes against one data connection. Apps invoke it by name — the typed,
grant-gated alternative to writing ad-hoc SQL in the app:

```js
const qs   = await savedQueries();   // [{ name, description, params, version }] — never the SQL
const rows = await query("my_orders", { region: "emea" });   // limit omitted → server binds its default
```

- `query(name, params?)` returns the same rows shape as `runSQL` (array of row objects plus
  `.columns`/`.rowcount`/`.truncated`). Params are **named and typed**
  (`string|int|float|bool`, declared by the admin); a wrong type, a missing required param,
  or an undeclared param is a clean `400` naming the param. Params declared with a default
  are optional.
- **Context binds are the killer feature**: a template may reference `:_ctx_user_id`,
  `:_ctx_user_email` and `:_ctx_org`, which the server injects from the signed-in viewer.
  A template like `where rep_email = :_ctx_user_email` gives every viewer their own rows —
  the app passes no identity and cannot forge one (a caller-supplied `_ctx*` param is
  rejected with a 400).
- **Always use saved queries instead of ad-hoc SQL** unless the user explicitly requested
  direct/ad-hoc SQL: admins can grant-gate invocation per query, the SQL stays server-side,
  and per-caller row scoping comes free. `savedQueries()` tells you what's callable; ask the
  org admin (or use `railcode query create`, admin-only) to publish new ones.
- Invoking an unknown query is a `404`; a query the viewer isn't granted is a `403` — show
  a clean state for both.

## Service Connectors (third-party HTTP)

A **service connector** is an admin-configured proxy to a downstream SaaS API (Stripe,
Mixpanel, …). The app names a connector and supplies only the method, path, and body; the
backend pins the host and injects the credential the app never sees:

```js
const conn = connector("stripe");
const resp = await conn.fetch("/v1/charges?limit=3");                 // GET by default
const post = await conn.fetch("/v1/charges", { method: "POST", body: "amount=500&currency=usd" });
if (resp.ok) {
  const data = await resp.json();   // also: await resp.text(), resp.status, resp.headers
}
```

`serviceConnectors()` lists what this app may call as
`{ name, description, auth_type, allowed_methods }`. The proxy rejects a method not in
`allowed_methods` (405) and strips upstream auth/`Set-Cookie` headers; the response is
truncated at a size limit (`resp.truncated`).

## LLM

API keys and the org default `(provider, model)` are admin-controlled — apps never see keys.
An org can configure **many models across many providers**; an app may optionally target a
specific `(provider, model)` from that catalog, or send neither and get the org default:

```js
const result = await llm.generate("Classify this customer.", {
  output: {
    type: "json",
    schema: {
      type: "object",
      additionalProperties: false,
      properties: {
        status: { type: "string", enum: ["healthy", "risk", "unknown"] },
        reason: { type: ["string", "null"] }
      },
      required: ["status", "reason"]
    }
  },
  metadata: { feature: "customer-health", object_type: "customer", object_id: customerId }
});
// result: { text, output, usage, cost, provider, model, finishReason, requestId }
```

- Input is a prompt string **or** a `messages: [{ role, content }]` array. Options:
  `provider`, `model`, `system`, `output`, `temperature`, `maxOutputTokens`, `metadata`.
- `llmProviders()` lists the callable catalog as `{ provider, default, models: [{ model,
  default }] }` (the same data `railcode llm providers` prints). Pass a catalog `model` (its
  provider is implied) and/or a `provider` (alone → that provider's default model); omit both
  for the org default. *(Multi-model discovery new in SDK 0.1.15.)*
- `llm.generate()` supports `{ output: { type: "json", schema } }`. JSON schemas run in
  **strict mode**: every object must set `additionalProperties: false` and list **all** keys
  in `required` — make optional fields nullable (`{ type: ["string", "null"] }`) rather than
  omitting them.
- `llm.stream(input, opts)` is an async iterator of `{ type: "text" }` / `{ type: "done" }` /
  `{ type: "error" }` events; it is **text-only** and rejects JSON output client-side.
- Always send `metadata` for audit/attribution. Expect daily token caps, provider timeouts,
  and input limits enforced server-side; render those failures as normal app states and do
  not retry indefinitely.

## Email

`email.send(opts)` sends transactional email through the platform mail gateway. Apps control
only recipients, subject, and body — the platform pins the **sender** (a fixed
`Railcode <…@mail-service.railcode.app>` From) and appends a disclaimer, so an app name can't
smuggle an address token into the header. Keys never reach the browser.

```js
const res = await email.send({
  to: "user@example.com",             // string or string[]
  subject: "Your report is ready",
  html: "<p>It's <b>ready</b>.</p>",  // html and/or text (at least one)
  text: "It's ready.",
  cc: ["ops@example.com"],            // optional; cc/bcc also string | string[]
  replyTo: "support@example.com",     // optional
});
// res: { id, status, requestId }
```

- **Off by default.** `email` is not seeded org-wide. A `run_as: user` app needs the
  signed-in caller to hold the `email` grant (an admin grants it); a `run_as: app` app
  declares `email: true` in its manifest and it ratifies against the deployer's grants.
  Ungranted calls return `403`.
- **Governed, not free.** Each org has a daily recipient cap (attempts count against it,
  even failed sends) → `429` when exhausted; suppressed (bounced/complained) recipients are
  rejected. Self-hosted or an unconfigured provider returns `503 email_unavailable`. Render
  all of these as normal app states — never retry loops.
- Discovery: `GET /_api/email` reports `{ configured, from, dailyRemaining }` if you need to
  gate UI, but the SDK surface apps call is just `email.send`.
- *New in CLI/SDK 0.1.19.*

## Local Dev Bridge

`railcode dev` preserves the same SDK calling style locally (see
[cli-workflow.md](cli-workflow.md) for full behavior):

- Identity (`me`), `appUsers`, `roles` (an empty custom-role list), KV, and files are
  **emulated on local disk** under
  `~/.railcode/dev/<instance>/<app>/`. The KV query engine is a port of the backend, so
  `where`/`prefix`/`orderBy`/`page`/`first`/`count` behave exactly as in production.
- `designSystem()`, `data()/postgres()/bigquery()/turso().runSQL()`, `dataConnectors()`,
  `query()`/`savedQueries()`, `serviceConnectors()`, `connector().fetch()`, `llm`,
  `llmProviders()`, and `email.send()` **forward to the real instance** when the CLI has a
  saved token — real provider, quota, databases, connectors, and **mail delivery** (real
  spend + data — `email.send()` sends actual email). Email forwarding is new in CLI 0.1.19;
  earlier CLIs 404 on `email.send()` in dev.
- Not logged in: `dataConnectors()`/`serviceConnectors()`/`savedQueries()` return empty and
  `data().runSQL()`/`query()`/`llm`/`email.send()` return `503` (never `401`). The startup
  banner says which mode you're in, so you don't have to fire a request to find out.

This lets agents build most app behavior without a live server, then layer on
production-backed SQL/LLM/connectors/email once credentials and access are available.
