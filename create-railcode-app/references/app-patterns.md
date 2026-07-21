# App Patterns

Use this reference when implementing a Railcode app UI, data model, SDK calls, or local
validation on the **multi-tenant** platform.

## Starter Layout

`railcode init <app> --template react` scaffolds a flat Vite app:

```text
railcode.json        { "app": "<slug>", "build": "npm run build", "dist": "dist" }
package.json         React 19 + react-dom + Zustand 5; scripts: dev (vite), build (tsc && vite build)
index.html           loads <script src="/_api/sdk.js"></script> then /src/main.tsx
tsconfig.json
vite.config.ts       builds to dist/
src/
  main.tsx
  App.tsx            demo: me() + db.collection().put/get via a Zustand store
  styles.css
```

`railcode init <app>` with no `--template` (or `--template static`) instead writes a
**no-build** single `index.html` + `railcode.json` (`{ "app": "<slug>", "dist": "." }`).

There is no `lib/`, `store/`, or `components/` scaffolding, no Tailwind, and no
`src/lib/railcode.ts` wrapper — add the structure your app needs. `vite.config.ts` builds to
`dist/`; don't change the output path unless `railcode.json` `dist` changes with it.

## Loading And Using The SDK

The SDK is loaded by the `<script src="/_api/sdk.js"></script>` tag in `index.html`, which
attaches globals to `window` **before** your bundle runs. Call them directly — there is no
`loadRailcodeSdk()` and no module to import. In TypeScript, declare the globals you use (the
starter does this inline; for a larger app put them in an ambient `src/railcode.d.ts`):

```ts
declare const me: () => Promise<{
  user: { uuid: string; name: string; email: string };
  app: { uuid: string; slug: string; name: string };
  org: { uuid: string; slug: string; name: string };
}>;
declare const db: {
  collection: <T = unknown>(name: string) => {
    get(key: string): Promise<T | null>;
    put(key: string, value: T): Promise<T>;
    delete(key: string): Promise<void>;
    list(): Promise<{ key: string; value: T; updated_at: string }[]>;
    where(field: string, op: string, value: unknown): /* Query */ any;
    prefix(value: string): /* Query */ any;
  };
};
// likewise: files, llm, llmProviders, data, postgres, bigquery, turso, dataConnectors,
// connector, serviceConnectors, designSystem, email, personalConnections
```

If a global is `undefined` at runtime, the page is almost certainly being served directly by
Vite instead of through `railcode dev` (so `/_api/sdk.js` never loaded) — fail loudly with a
clear message rather than silently no-op.

## UI Expectations

Railcode apps are internal/admin apps. Build the actual working interface as the first
screen, not a marketing page. Favor dense, readable, task-focused layouts with clear states
for loading, empty data, errors, and successful writes.

Do not add custom auth/login screens — users arrive already authenticated through the
platform serving gate. Use `me()` only to show identity or to namespace data. Use
`me().user.uuid` for stable keys and ownership checks; `me().user.name`/`.email` are for
display. Never leak platform internals (bearer tokens, DSNs, LLM provider config, admin-only
settings) into browser state.

## State And Data Modeling

Use Zustand or local React state for client state. Keep persisted data in Railcode
KV/files/SQL by use case:

- **KV** — app-owned JSON records, preferences, drafts, lightweight collaboration state.
- **files** — binary uploads or generated artifacts.
- **SQL (postgres)** — read-only views over external Postgres configured by an admin.
- **service connectors** — read/write against an admin-configured third-party SaaS API.
- **LLM** — summarization, classification, drafting, structured extraction.

Define collection names and key formats explicitly near the data layer:

```ts
const TASKS = "tasks";
const taskKey = (id: string) => id;                       // shared
const userTaskKey = (userUuid: string, id: string) => `${userUuid}:${id}`;  // per-user
```

If data is per-user, prefix by `me().user.uuid`, not by a display name. If data is shared,
make conflict behavior obvious in the UI.

## KV Pattern

```ts
type Task = { id: string; title: string; done: boolean; priority: number; updatedAt: string };

const tasks = db.collection<Task>("tasks");

await tasks.put(task.id, task);
const saved = await tasks.get(task.id);
const all = await tasks.list();        // first page, each row { key, value, updated_at }
await tasks.delete(task.id);
```

For large lists, server-side filters, deterministic ordering, and pagination, use the query
builder. Operators are the **string names** `eq`, `ne`, `gt`, `gte`, `lt`, `lte`, `in`, and
`page(pageNumber, size?)` takes a **numeric** size:

```ts
const newest = await tasks
  .query()
  .orderBy("updatedAt", "desc")
  .page(1, 50);

const open = await tasks
  .where("done", "eq", false)
  .orderBy("updatedAt", "desc")
  .page(1, 50);

const mine    = await tasks.prefix(`${who.user.uuid}:`).page();
const changed = await tasks.query().updatedSince(lastSyncIso).page(1, 100);
const urgent  = await tasks.where("priority", "gte", 3).first();
const openN   = await tasks.where("done", "eq", false).count();
```

`where()` and `prefix()` can start a query from a collection. For pure ordering/paging
with no filter, or for updated-time filters, start with `query()` first —
`tasks.orderBy(...)` and `tasks.updatedSince(...)` are not collection methods.

Field names are the virtual `key` / `updatedAt` (a.k.a. `updated_at`), or a dotted JSON path
inside the stored value (`assignee.email`). Comparisons are typed by the operand
(number/boolean/string). Pages are 1-based; default size is 100, the server caps size at 500.

## File Pattern

```ts
await files.upload(file.name, file, file.type || "application/octet-stream");
const entries = await files.list();
const url = files.url(file.name);        // use directly in <img src> / fetch
const batch = await files.urls(entries.map((entry) => entry.name));
// batch.items: [{ name, url, expires_in }]; batch.missing: string[]
await files.delete(file.name);
```

The file API is the global `files`. Names may contain `/` for nested paths. For a gallery or
file-heavy view, prefer `files.urls(names)` over many `files.url(name)` redirects: it resolves
up to 100 existing files in one authenticated request and caches returned URLs in memory until
shortly before expiry. Missing names are reported separately. For user-supplied names, generate
a stable id for the storage name and keep the display name in KV. The current `railcode dev`
emulator supports the same batched call, including shared/user/role storage scopes.

## Saved Query Pattern (Postgres / BigQuery / Turso)

Use saved queries for database access unless the user explicitly tells you to use direct or
ad-hoc SQL. Do not fall back to direct SQL just because `savedQueries()` does not list a
perfect match; ask for the saved query name, ask an admin to publish one, or get explicit
instruction from the user to use direct SQL.

Check `savedQueries()` first and invoke the matching query with `query('name', { ...params })`.
Saved queries return the same rows shape as direct SQL, with typed named params and
server-side SQL. When the template uses `:_ctx_user_email` / `:_ctx_user_id`, results are
row-scoped to the viewer with no identity handling in the app:

```ts
const available = await savedQueries();
const mine = await query("my_orders", { region });   // rows already scoped to the viewer
```

## Direct SQL Pattern (Explicit User Request Only)

Only use `data('name').runSQL()` or the dialect-pinned `postgres`/`bigquery`/`turso`
namespaces when the user explicitly asks for direct/ad-hoc SQL. If you use direct SQL, use
placeholders plus params; never concatenate user-selected filters into a SQL string.

```ts
const rows = await postgres("analytics").runSQL(
  "select id, name, status from customers where status = $1 order by name limit 100",
  [status],
);

// Engine-generic — routes by the connection's stored kind, so it works for any engine:
const bq = await data("warehouse").runSQL("select id, name from `ds.customers` limit 100");
```

Supported engines are **postgres**, **bigquery**, and **turso**. Use `data('name')` to
run against any connection (dispatched by stored kind), or the dialect-pinned
`postgres`/`bigquery`/`turso` when you want the SQL flavor fixed at the call site (a
mismatch is a 404). Any namespace's `.runSQL(...)` with no name uses the connection named
`default`. Queries are forwarded verbatim (never translated): Postgres uses `$1, $2, …`
placeholders, BigQuery/Turso use `?`. Pass user-selected filters only as params, never
string-concatenated. If the app must work across engines without hardcoding one, read each
connector's `engine` from `dataConnectors()` and pick the matching namespace (or just use
`data`). Show a useful empty state when `dataConnectors()` is empty or a connection isn't
configured. `rows` is an array of row objects with `rows.columns` / `rows.rowcount` /
`rows.truncated` metadata.

## Service Connector Pattern

```ts
const stripe = connector("stripe");
const resp = await stripe.fetch("/v1/customers?limit=10");        // GET by default
if (resp.ok) {
  const data = await resp.json();
}
const created = await stripe.fetch("/v1/customers", {
  method: "POST",
  body: "email=user@example.com",
});
```

You control only method, path, and body; the backend pins the host and injects the
credential. Call `serviceConnectors()` to discover available connectors and their
`allowed_methods`; a disallowed method returns 405.

## LLM Pattern

Text (message form):

```ts
const result = await llm.generate(
  [
    { role: "system", content: "Write concise operational summaries." },
    { role: "user", content: noteText },
  ],
  { maxOutputTokens: 300, metadata: { feature: "note-summary", object_type: "note", object_id: noteId } },
);
// result.text, result.usage, result.cost, result.requestId
```

Structured output (strict mode: every object needs `additionalProperties: false` and must
list all its keys in `required`; make optional fields nullable):

```ts
const result = await llm.generate(prompt, {
  output: {
    type: "json",
    schema: {
      type: "object",
      additionalProperties: false,
      properties: {
        priority: { type: "string", enum: ["low", "medium", "high"] },
        reason: { type: ["string", "null"] }
      },
      required: ["priority", "reason"]
    }
  },
  metadata: { feature: "priority-classifier" },
});
// result.output holds the parsed JSON
```

Streaming is text-only without run-bearing tools (`llm.stream()` rejects JSON output
client-side; on a tool loop the JSON value lands on the `done` event instead). A stream's
`{ type: "error" }` event carries a classified `error` code (e.g. `provider_auth_error`,
`provider_rate_limited`) and a `retryable` flag — check `retryable` before offering a retry
rather than assuming every failure is transient. Render provider errors and token-cap
failures as normal app states; do not retry indefinitely.

Tool calling (post-0.1.26; needs a platform SDK that has it — see the "Tool calling"
section of [platform-magic.md](platform-magic.md)):
pass `tools` — `{ name, description, schema?, run?, summarize? }` objects wrapping the SDK
calls the app already makes. All tools with `run` → the SDK runs the whole agentic loop in
the page; none with `run` → single turn, requested calls returned unexecuted on `toolCalls`;
mixing throws.

```ts
const lookupOrder = {
  name: "lookup_order",
  description: "Fetch one order by id from the app's KV. Returns the raw order record.",
  schema: {
    type: "object",
    properties: { id: { type: "string" } },
    required: ["id"],
  },
  run: ({ id }: { id: string }) => db.collection("orders").get(id),
};

const result = await llm.generate(question, {
  system: "You are the order-support assistant.",
  tools: [lookupOrder],
  limits: { maxSteps: 6 },
  metadata: { feature: "order-support" },
});
if (result.stopReason !== "end") showBudgetNotice(result.stopReason); // text may be empty
renderSteps(result.steps);   // every executed call, raw results included
renderAnswer(result.text);
// continue the conversation: pass result.messages (+ the new user turn) as the next input

for await (const event of llm.stream(question, { tools: [lookupOrder] })) {
  if (event.type === "step") upsertToolCard(event.step); // emitted twice per call — upsert by step.id
  else if (event.type === "text") appendText(event.text);
  else if (event.type === "done") finish(event);         // event.text, .steps, .stopReason
  else showLlmError(event);                              // classified error + retryable
}
```

Keep tool `description`s prescriptive (what it's for AND how to use it well) — they are the
model's only manual. Big `run` results are fine for the UI but reach the model only as
`summarize(result)` (default JSON) clipped to ~6,000 chars, so summarize aggressively and
tell the model to aggregate/limit inside the tool call. Cancellation via `signal` resolves
normally with `stopReason: "aborted"` — branch on `stopReason`, not try/catch.

Before reaching for this at all, check the decision table in `SKILL.md` ("In-Page LLM vs
Managed Agents") — files, code, outside triggers, and unattended work belong to a managed
agent. The two compose: keep the chat shell in the page and delegate the heavy step to an
agent from inside a tool:

```ts
// The app's manifest declares `agents: [report-extractor]`; the agent's own manifest
// declares `app_files: [<this-app>]` so it can load the uploaded file into its sandbox.
const extractReport = {
  name: "extract_report",
  description:
    "Parse an uploaded report file and return its extracted metrics. Use for any " +
    "question about the contents of an uploaded PDF/XLSX — do not guess from the filename.",
  schema: {
    type: "object",
    properties: { file: { type: "string" } },
    required: ["file"],
  },
  run: async ({ file }: { file: string }) => {
    const run = await agents.invoke("report-extractor", { file }); // polls to terminal status
    if (run.status !== "success") throw new Error(run.error_message ?? run.status);
    return run.output_json;
  },
  summarize: (out) => JSON.stringify(out),
};
```

For long agent runs, use `agents.start()` + `agents.get(requestId)` inside `run` and
surface progress through the UI instead of blocking `invoke()` against the loop's
`timeoutMs` — or raise `limits.timeoutMs` to cover the agent's expected runtime.

Model selection is optional. Omit `provider`/`model` and the call uses the org default. To let
the app target a specific model, enumerate the org's catalog with `llmProviders()`
(`[{ provider, default, models: [{ model, default }] }]`) and pass `opts.model` (its provider
is implied) and/or `opts.provider` (alone → that provider's default model):

```ts
const providers = await llmProviders();          // discover the configured (provider, model) catalog
const result = await llm.generate(prompt, { model: "claude-opus-4-8", metadata: { feature: "draft" } });
```

## Email Pattern

Send transactional email server-side. Apps set only recipients/subject/body; the platform
owns the sender and appends a disclaimer.

```ts
const res = await email.send({
  to: order.customerEmail,                 // string | string[]
  subject: `Order ${order.id} confirmed`,
  html: renderReceipt(order),              // html and/or text (at least one)
  replyTo: "support@acme.com",             // optional; cc/bcc optional too
});
// res.id, res.status, res.requestId
```

`email` is **off by default** and governed: a `run_as: user` app needs the caller to hold the
`email` grant (admin-granted), or the app declares `email: true` in its manifest under
`run_as: app`. Expect `403` (not granted), `429` (daily recipient cap — attempts count even
when the send fails), and `503` (self-hosted or provider unconfigured). Render those as
ordinary UI states; never retry in a loop. Do not put addresses the user hasn't consented to
in `to`/`cc`/`bcc`. Under `railcode dev` this forwards to the org's real mailer (real email is
sent) when logged in — new in CLI 0.1.19.

## Personal Connectors Pattern

Declare the narrowest toolkit/tool set your app actually calls, under `run_as: app` in
`manifest.yaml`:

```yaml
run_as: app
personal_connectors:
  - gmail:send_email
```

Gate the UI on connection state, not just a try/catch — `call()`'s `409` means "not
connected yet," which is a normal state to design for, not an error:

```ts
async function sendViaGmail(to: string, subject: string, body: string) {
  try {
    const { result } = await personalConnections.call("gmail", "send_email", {
      recipient_email: to, subject, body,
    });
    return result;
  } catch (err) {
    if (err.status === 409) {
      // Not connected yet — show a "Connect Gmail" affordance instead of an error.
      const { redirect_url } = await personalConnections.connect("gmail");
      window.open(redirect_url, "_blank", "width=500,height=650"); // popup, not location.href
      return null;
    }
    throw err; // 403 (undeclared) means the manifest is missing the toolkit/tool — fix the manifest
  }
}
```

- Use `personalConnections.tools("gmail")` at build time (or `railcode personal-connectors
  tools gmail`) to see the exact tool name and argument schema before writing the manifest
  entry or the call. In-house tool slugs are lowercase and case-sensitive; copy the returned
  slug exactly rather than guessing it.
- `list()` tells you per-toolkit connection status up front, so you can show a settings-style
  "connect your account" panel instead of waiting for a `call()` to fail.
- **Always open `connect()`'s `redirect_url` in a popup, never `location.href`.** A full-page
  redirect abandons whatever the user was doing; poll `list()` while the popup is open and
  close it once the toolkit reports connected (cross-origin popups can't be observed closing
  from JavaScript, so poll rather than listen for a close event).
- This is the caller's **own** account, scoped by what **this app** declares — do not confuse
  it with an org-admin `connector()` service connector (one shared credential) or with a
  managed agent's `tools.personal_connectors` (runs as the agent's owner, not the app's
  viewer).

## Build And Check

For the react template:

```bash
npm install       # first time / when deps change
npm run build     # tsc -p tsconfig.json && vite build → dist/
```

Commands use `npm`; the CLI follows whatever package manager your app declares (a
`packageManager` field or lockfile — pnpm/yarn/bun), defaulting to `npm`. The static template
has no build step. `railcode dev` does **not** install dependencies for you — run `npm install`
(or your manager's install) yourself when `node_modules` is missing.

If the app depends on SQL/LLM/connectors/email, test both the logged-out path (graceful empty /
503 states) and the logged-in path (real backend) separately:

```bash
railcode dev --reset                 # logged-out (or your saved session); wipe local KV/files first
RAILCODE_API_URL=https://api.apps.example.com RAILCODE_API_TOKEN=<token> railcode dev
```

## Common Pitfalls

- Opening the raw Vite URL bypasses `/_api/sdk.js`; always use the `railcode dev` URL.
- Editing `dist/` directly is lost on the next build.
- A new app defaults to **`organization`** access (every org member). Set it to
  `private`/`restricted` in the admin UI before sharing a sensitive app's URL.
- Un-namespaced KV keys accidentally share private data across the app's users — prefix by
  `me().user.uuid` for per-user state.
- Using `==`/`>` style symbols in `where()` — the operators are the string names
  (`eq`/`gt`/…). Passing `{ size }` as an object to `page()` — it takes a numeric size.
- String-concatenating SQL user input creates injection risk even though queries are
  read-only.
- Assuming SQL/LLM/connectors/email are always available — they need admin configuration and (in
  `railcode dev`) a saved login; expect empty/`503` otherwise. Email additionally needs an
  explicit `email` grant (or `email: true` manifest) — expect `403` until granted.
- Opening `personalConnections.connect()`'s URL with `location.href` instead of a popup — it
  abandons the app's in-progress state. And treating `call()`'s `409` (not connected yet) as
  an error instead of a normal "connect your account" state.
