# App Patterns

Use this reference when implementing a Railcode app UI, data model, SDK calls, or local
validation on the **multi-tenant** platform.

## Starter Layout

`railcode init <app> --template react` scaffolds a flat Vite app:

```text
railcode.json        { "app": "<slug>", "build": "pnpm run build", "dist": "dist" }
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
// likewise: files, llm, data, postgres, bigquery, snowflake, dataConnectors, connector,
// serviceConnectors, designSystem
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
const open = await tasks
  .where("done", "eq", false)
  .orderBy("updatedAt", "desc")
  .page(1, 50);

const mine    = await tasks.prefix(`${who.user.uuid}:`).page();
const changed = await tasks.updatedSince(lastSyncIso).page(1, 100);
const urgent  = await tasks.where("priority", "gte", 3).first();
const openN   = await tasks.where("done", "eq", false).count();
```

Field names are the virtual `key` / `updatedAt` (a.k.a. `updated_at`), or a dotted JSON path
inside the stored value (`assignee.email`). Comparisons are typed by the operand
(number/boolean/string). Pages are 1-based; default size is 100, the server caps size at 500.

## File Pattern

```ts
await files.upload(file.name, file, file.type || "application/octet-stream");
const entries = await files.list();
const url = files.url(file.name);        // use directly in <img src> / fetch
await files.delete(file.name);
```

The file API is the global `files`. Keep file names flat — no `/` folders. For
user-supplied names, generate a stable id for the file name and keep the display name in KV.

## SQL Pattern (Postgres / BigQuery / Snowflake)

```ts
const rows = await postgres("analytics").runSQL(
  "select id, name, status from customers where status = $1 order by name limit 100",
  [status],
);

// Engine-generic — routes by the connection's stored kind, so it works for any engine:
const bq = await data("warehouse").runSQL("select id, name from `ds.customers` limit 100");
```

Supported engines are **postgres**, **bigquery**, and **snowflake**. Use `data('name')` to
run against any connection (dispatched by stored kind), or the dialect-pinned
`postgres`/`bigquery`/`snowflake` when you want the SQL flavor fixed at the call site (a
mismatch is a 404). Any namespace's `.runSQL(...)` with no name uses the connection named
`default`. Queries are forwarded verbatim (never translated): Postgres uses `$1, $2, …`
placeholders, BigQuery/Snowflake use `?`. Pass user-selected filters only as params, never
string-concatenated. If the app must work across engines without hardcoding one, read each
connector's `engine` from `dataConnectors()` and pick the matching namespace (or just use
`data`). Show a useful empty state when `dataConnectors()` is empty or a connection isn't
configured. `rows` is an array of row objects with `rows.columns` / `rows.rowcount` /
`rows.truncated` metadata.

**Prefer a saved query when one exists.** Check `savedQueries()` first: if an admin has
published a query that covers your need, invoke it with `query('name', { ...params })`
instead of writing ad-hoc SQL (same rows shape). You get typed named params, server-side
SQL, and — when the template uses `:_ctx_user_email` / `:_ctx_user_id` — per-viewer row
scoping with no identity handling in the app:

```ts
const mine = await query("my_orders", { region });   // rows already scoped to the viewer
```

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

Streaming is text-only (`llm.stream()` rejects JSON output). Render provider errors and
token-cap failures as normal app states; do not retry indefinitely.

## Build And Check

For the react template:

```bash
pnpm install      # first time / when deps change
pnpm build        # tsc -p tsconfig.json && vite build → dist/
```

The static template has no build step. `railcode dev` does **not** install dependencies for
you — run `pnpm install` yourself when `node_modules` is missing.

If the app depends on SQL/LLM/connectors, test both the logged-out path (graceful empty /
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
- Assuming SQL/LLM/connectors are always available — they need admin configuration and (in
  `railcode dev`) a saved login; expect empty/`503` otherwise.
