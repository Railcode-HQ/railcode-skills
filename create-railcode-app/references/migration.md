# Migrating a v1 app to apps v2

Two different things wear the word "migrate". Separate them before you start, because they have
different risks and only one of them is irreversible.

| | What it is | Reversible? |
|---|---|---|
| **The code rewrite** | Rebuilding the app as a static frontend + worker | Yes — it's just code |
| **The `migrate` gate** | Flipping the app row's `generation` from 1 to 2 | **No. One-way, permanent.** |

If [SKILL.md](../SKILL.md#when-a-v1-app-cant-do-whats-asked) sent you here because a v1 app was
asked for something it cannot do, the migration is the deliverable, and the feature that
triggered it becomes the first worker route.

## Decide the path first

**Path A — a new app slug (strongly preferred).**

Build the v2 app as a *new* app, leave the v1 app running, cut over when it works.

- No downtime, no gate, nothing irreversible.
- You can rehearse the whole thing against real infrastructure.
- Cost: the new app starts with an empty store. If the old data matters, you copy it.

**Path B — migrate in place.**

Use when the app's live data must come along and the slug/URL must not change.

- Irreversible, and it has a **forced downtime window** (below).
- You cannot rehearse it. See the trap.

### The trap: you cannot rehearse Path B

A v2 worker cannot be tested against its own live v1 app before the flip:

- `railcode deploy` **422s** if you send a server module while the app is still generation 1.
- `/fn/data` (the worker data plane) **refuses** any app below generation 2.

So on Path B the order is forced, and there is a gap in the middle where the app is broken:

```
railcode migrate      # v1 data plane dies here — the browser SDK stops working
   ↓  ...app is down for its users...
railcode deploy       # the worker takes over here
```

Keep that window as short as you can: have the v2 build finished, built, and validated
(`railcode manifest validate`, a clean `railcode dev` run) **before** you type `railcode migrate`.

`railcode migrate` (`POST …/apps/{uuid}/migrate`) needs the app's **manage** tier (owner grant or
an admin) **plus** `app:deploy` — an editor cannot run it. It answers **409** while a deploy of
the app is in progress (retry in a moment) and is a no-op **200** (`already a v2 app`) on an app
that is already generation 2.

Once the app is v2, clear any stored notes about the v1 browser SDK — see
[Clear Any v1 SDK Memory](../SKILL.md#clear-any-v1-sdk-memory).

## What happens to the data

**Unscoped v1 data carries over untouched.** A v2 app's flat store **is** the same app scope v1's
shared/unscoped data lived in. Same app row, same collections, same keys. Your worker's
`db.collection("notes").get(k)` reads exactly what the v1 page wrote with `db.collection("notes")`.
Nothing to copy, nothing to migrate.

**Scoped v1 data freezes.** Anything written through `db.user`, `db.role(uuid)`, `files.user`, or
`files.role(uuid)` becomes readable but permanently un-writable. A frozen collection exposes
only `get(key)` and `list(page = 1, size?)` — no `put`, no `delete`, no query builder. `list()`
returns `{ key, value, updated_at }` records one page at a time (default 100, max 500):

```ts
await db.scoped(userUuid).collection("drafts").list(page, size);  // read-only
await db.scopedRole(roleUuid).collection("shared").get(key);      // read-only
```

There is no write path and there will not be one. If that data must stay live, your worker has to
copy it into the flat store under keys you choose — usually on first read per user, paging
`list()` until a page comes back short (the same rule as flat `list()`, below):

```ts
const flatKey = `${ctx.user!.id}:drafts`;
let mine = await db.collection("drafts").get(flatKey);
if (!mine) {                                            // one-time lift
  const frozen = db.scoped(ctx.user!.id).collection("drafts");
  const size = 500;
  const rows = [];                                      // { key, value, updated_at }[]
  for (let page = 1; ; page++) {
    const batch = await frozen.list(page, size);
    rows.push(...batch);
    if (batch.length < size) break;
  }
  mine = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  await db.collection("drafts").put(flatKey, mine);
}
```

So: **an app that only ever used the default (unscoped) store has no data problem at all.** An app
built around `db.user` has the most work.

## The code rewrite

Almost none of the app changes. Views, components, stores, and business logic are untouched. What
changes is the one place SDK calls happen.

### 1. Find the seam

A well-built v1 app funnels every SDK call through a single wrapper module. Find it, and find what
the rest of the app *actually* imports from it:

```bash
rg -n "from ['\"].*lib/railcode['\"]" src
```

Do this before building anything. A real wrapper typically *declares* far more than the app uses —
build routes only for the surface that is actually imported. Confirm each candidate is unused
before you drop it.

### 2. Rewrite the wrapper, keep its signature

Keep the exported API byte-identical, but make every function `fetch()` a worker route. Everything
downstream compiles and runs unchanged. This is the whole trick.

```ts
// before (v1): window.db.collection(name).get(key)
// after  (v2):
export function collection(name: string) {
  return {
    get: (key: string) => post("/api/rc/kv", { op: "get", name, key }),
    put: (key: string, value: unknown) => post("/api/rc/kv", { op: "put", name, key, value }),
  };
}
```

### 3. Build one worker route per capability actually used

| v1 wrapper export | v2 implementation |
|---|---|
| `me()` / `getIdentity()` | The page may fetch **`/_api/me`** directly — it and `/_api/logout` are the only `/_api` routes a v2 app keeps. Better: return `ctx.user` from a route of your own |
| `collection(name)` | `POST /api/rc/kv` → worker `db.collection(name)` |
| `files.*` | `POST /api/rc/files` → worker `files`; use `files.urls()` for galleries |
| `query()` / `data().runSQL()` | `POST /api/rc/query` → worker `query` / `data` |
| `connector().fetch()` | `POST /api/rc/connector` → worker `connector` |
| `personalConnections.*` | **Removed.** The account is now a connector row: `POST /api/rc/connector` → worker `connector(name)`. Get the row's name from `railcode connector list` — it may be suffixed (`gmail-jp`) |
| `llm.generate` | `POST /api/rc/llm` → worker `llm` |
| `agents.invoke` / `start` | `POST /api/rc/agent` → worker `agents.start` + a poll route |
| `roles()` | **No worker equivalent.** `ctx.user.roles` gives the caller's own roles only |
| `designSystem()` | **No worker equivalent.** Fetch at build time with `railcode design-system` |

### 4. Two rules that bite

**Relay the original status.** Wrap SDK calls and, on `ApiError`, respond with its `.status` and
body verbatim. The browser's 403/409/429 handling depends on it surviving the extra hop.

**Paginate KV `list()`.** It is first-page-only (default 100, max 500). In v1 you may have been
quietly getting away with it; in a worker loop you will silently drop a large collection's tail.

### 5. Manifest

`run_as: app` is mandatory. Declare **every** capability the worker uses.

**Connectors and agents are refusals, not pass-through** — declare every connector (by its row
name, with the operations used) and every agent name, even ones the v1 manifest never listed,
or they 403 at runtime.

## The interactive LLM tool loop

This is the one genuinely hard case.

If the v1 app runs `llm.stream({ tools })` where the tools **pause for a human approval** or
**close over live browser state** (a store, a callback), you cannot move that loop into the
worker. A worker invocation is one request: there is no inbound channel to deliver an "Approve"
click to a running invocation, and the tools' `run` closures don't exist server-side.

**Keep the loop in the browser; proxy each model turn to the worker.** The SDK's tool loop is a
pure, dependency-injected generator that takes a `wire` with `generate`/`stream` runners:

1. Vendor `tool-loop.ts` into the app.
2. Give it a browser `wire` whose `generate` POSTs to your worker's LLM route.
3. Tools (`run`, with approval and store access) execute in the page exactly as before; only each
   planning **turn** crosses to the worker.

**Relay each turn with the tool DEFINITIONS attached.** The worker route calls `llm.stream()` (or
`generate`) with the run-less defs the browser sent and passes the events back; the browser's loop
executes the `run` handlers and threads the next turn. Step events, approval, transcript threading
and stop reasons all keep working, and text still streams live.

Needs `@railcode/sdk` ≥ 0.3.0.

## Stack taxes (only if you pick TanStack)

Framework taxes are not migration work. `hono+vite` and `hono+static` add no new classes of bug;
TanStack Start's build-time prerender (no `window` at import time) and router reconciliation
(`ssr: false` splat route) are covered by the `tanstack` template notes in
[cli-workflow.md](cli-workflow.md#create-an-app) and by the migrate-to-railcode skill.

## Checklist

- [ ] Chose Path A (new slug) or Path B (in-place) **deliberately**, and told the user Path B is
      one-way with downtime.
- [ ] Grepped the wrapper's importers; built routes only for the surface actually used.
- [ ] Identity from `ctx.user` (or `/_api/me`).
- [ ] KV `list()` paginates.
- [ ] Worker routes relay `ApiError` status + body verbatim.
- [ ] `run_as: app`; **every** capability declared, including every connector row (shared, owned
      or per-user) and every agent name.
- [ ] Scoped v1 data: either lifted into the flat store, or confirmed unused.
- [ ] Interactive tool loops: browser loop + worker turns relayed through `llm.stream()` with
      run-less tool defs.
- [ ] Deployed and confirmed the manifest ratified (`railcode manifest show <app>`).
- [ ] Walked the app live and read `railcode logs app --app <slug>`.

## Budget it honestly

Most of the cost is reading the app well enough to keep the port to one seam, plus any
interactive tool loop; the scaffold itself is small — tell the user that before you start.
