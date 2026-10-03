# Migrating a Next.js app to Railcode

Next.js runs on Railcode as one worker that renders every page: Server Components, Server
Actions, Route Handlers and streaming all work. The app is built through the OpenNext
Cloudflare adapter into a single module.

There are two ways to get there, and which one you use depends on what is released where you
are deploying. **Check first.**

## Contents

- [Which path](#which-path)
- [Will this app fit](#will-this-app-fit)
- [Path A — `type: next`](#path-a--type-next)
- [Porting the code (both paths)](#porting-the-code-both-paths)
- [Build, run, deploy](#build-run-deploy)
- [Verify](#verify)
- [Gotchas](#gotchas)
- [What has and has not been proven](#what-has-and-has-not-been-proven)
- Path B is in [nextjs-under-api.md](nextjs-under-api.md), with its cache adapter in
  [nextjs-cache-adapter.ts](nextjs-cache-adapter.ts)

## Which path

```bash
railcode --help | grep -- "--template"     # 1. does the template list include "next"?
npm view @railcode/next version            # 2. is the preset published?
curl -s <api-url>/api/config               # 3. is "worker_routes" in deploy_capabilities?
```

`<api-url>` is the Railcode server the CLI is logged in to (`https://api.railcode.app` unless
the user logged in with `--api-url`).

| All three are true | Use |
|---|---|
| Yes | **Path A** — `"type": "next"`. The app is served at its normal URLs and carries no adapter config |
| Any is missing | **Path B** — [the app lives under `/api`](nextjs-under-api.md), with a hand-written build script. It works on CLI 0.3.7 today |

When this guide was written (CLI 0.3.7) none of the three were released yet, so expect Path B
until they are. Do not assume: run the checks. The CLI refuses a Path A deploy against a
server that lacks `worker_routes`, so a wrong guess fails loudly rather than deploying a
broken app.

Everything from [Porting the code](#porting-the-code-both-paths) onward applies to both paths.

## Will this app fit

Read the project before promising a migration. Stop and tell the user if any **blocker**
applies.

| The app has | Verdict |
|---|---|
| Public pages, anonymous visitors, self-signup | **Blocker.** Every viewer is a signed-in org member |
| Webhooks or public API routes called by other services | **Blocker** for those routes. Poll on a cron, or leave them on the old host |
| Pages Router (`pages/`) | Untested. The adapter supports it; nothing here has been verified with it. Say so, and budget time |
| A Next.js version older than 15.5.27, or 16.0–16.3.7 | Upgrade first. The adapter needs `>=15.5.27 <16` or `>=16.3.8` |
| `export const runtime = "edge"` | Remove it. The adapter runs everything in the Node-compatible runtime |
| `middleware.ts` / `proxy.ts` | Move the logic. It adds about 3 MB to the worker — see [Gotchas](#gotchas) |
| `next/image` optimization | Set `images: { unoptimized: true }`. There is no image optimizer |
| `next/og`, or any dependency that loads `.wasm` | Not available. The worker is one module |
| Native Node addons, `fs` writes, child processes, raw TCP (a Postgres driver over a socket) | Not available in the worker runtime. Use `db`, `files`, or a data connector |
| NextAuth / Auth.js, Clerk, a custom session | Delete it. Auth is ambient (`ctx.user`) |
| ISR, `revalidate`, `"use cache"`, `revalidateTag` | Work on Path A (stored in the app's store). On Path B they need the cache adapter described there |

Check the worker size early. A plain App Router app builds to about 3 MB; Cache Components
(`cacheComponents: true`) brings it to about 5.1 MB because Next ships a second copy of React.
The limit is 5 MB on servers without Path A support and 10 MB with it.

## Path A — `type: next`

Starting from nothing, `railcode init <app> --template next` scaffolds a working app. For an
existing project, add these by hand.

**`railcode.json`**

```json
{ "app": "my-app", "type": "next", "dist": "dist/client", "server": "dist/server/index.js" }
```

**`manifest.yaml`** — `run_as: app` is required. Add only what the code uses.

```yaml
run_as: app
```

**`package.json`**

```bash
npm install @railcode/sdk
npm install -D @railcode/next
```

```json
{ "scripts": { "dev": "railcode dev", "build": "next build" } }
```

`build` must stay the plain Next build. The adapter runs that script, so a `build` that calls
the Railcode build starts a build inside every build until the machine runs out of memory.
`@railcode/next` refuses that shape, but do not rely on the guard: leave `build` alone.

**`next.config.ts`** — remove `output: "standalone"` / `output: "export"` and any `basePath`
you do not want. Add:

```ts
const nextConfig: NextConfig = {
  images: { unoptimized: true },
  // Optional, on a laptop: `next build` otherwise uses every core.
  experimental: { cpus: 2 },
};
```

**`.gitignore`** — add `dist/`, `.open-next/`, `.wrangler/`, `.dev.vars`, `.railcode`.

Do **not** add `wrangler.jsonc` or `open-next.config.ts`. The preset generates both under
`node_modules/.railcode/next/`. Add an `open-next.config.ts` only to change adapter options:

```ts
import { defineRailcodeConfig } from "@railcode/next/open-next";
export default defineRailcodeConfig({ /* overrides */ });
```

## Porting the code (both paths)

### 1. Auth: delete it

Remove the auth library, its route handlers (`app/api/auth/*`), its provider wrapper, the
login page and any session checks in middleware. Replace every "who is this" with:

```ts
import { ctx } from "@railcode/sdk";

const user = ctx.user!; // { id, email, name, is_admin, roles } — verified by the platform
```

`ctx.user` is only `null` on a cron-triggered request. Authorization stays your code: check
`user.is_admin` or `user.roles` where the old app checked a session role.

### 2. SDK calls need a request

`next build` prerenders pages, and there is no request (so no user, no store) at build time.
A page that calls the SDK while being prerendered fails the build with
`@railcode/sdk only runs inside a deployed Railcode worker`.

Put the request boundary in one helper and route every identity read through it:

```ts
import { connection } from "next/server";
import { ctx } from "@railcode/sdk";

export async function me() {
  await connection(); // this render is per request, never at build time
  return ctx.user!;
}
```

Without Cache Components, `export const dynamic = "force-dynamic"` on the page does the same.
With Cache Components, read `me()` **before** entering a `"use cache"` function and pass the
user id in as an argument; a cached function cannot read request data itself.

### 3. Data

The app gets one flat store. Put the user id in the key and never take ownership from the
request:

```ts
import { db } from "@railcode/sdk";

const todos = db.collection<Todo>("todos");
const key = (userId: string, id: string) => `${userId}:${id}`;

export async function listTodos() {
  const user = await me();
  const rows = await todos.prefix(`${user.id}:`).page(1, 200);
  return rows.map((row) => row.value);
}
```

Keys cannot contain `/`. For relational data that already lives in a company database, use a
data connector and saved queries instead of an ORM over a socket.

### 4. Server Actions, Route Handlers, streaming

These need no changes beyond auth and data. `"use server"` actions, `useOptimistic`,
`useFormStatus`, `redirect()`, `cookies()`, streamed `Response` bodies and `after()` were all
exercised on a deployed app.

Work that continues after the response must be registered, or it is dropped when the
invocation ends: use Next's `after()`, or `ctx.waitUntil(promise)`.

### 5. Secrets and env

```bash
railcode secrets set STRIPE_KEY        # prompts; never pass the value inline
railcode secrets import .env.production
```

Read them as `secrets.STRIPE_KEY` from `@railcode/sdk`. `NEXT_PUBLIC_*` values are inlined at
build time as usual, from the environment the build runs in.

### 6. Outbound calls, cron, files, LLM

- Every host the server fetches goes under `egress:` in `manifest.yaml`.
- A cron is a manifest entry that calls one of the app's own routes. The path must start with
  `/api/`, so the handler lives at `app/api/<name>/route.ts`. `ctx.user` is `null` there.
- Uploads move to `files`; a hosted LLM client moves to `llm` (`llm: true` in the manifest).

### 7. Middleware

Move what `middleware.ts` / `proxy.ts` did:

| It did | Do instead |
|---|---|
| Auth redirects | Nothing. The platform gates the app |
| Role checks | Check in the page or layout; `forbidden()` with `experimental.authInterrupts` renders `forbidden.tsx` |
| Redirects and rewrites | `redirects()` / `rewrites()` in `next.config.ts`, or a Route Handler |
| Headers | `headers()` in `next.config.ts` |

## Build, run, deploy

```bash
railcode dev        # Path A: runs `next dev` with the SDK's dev credentials
railcode deploy     # builds, uploads, prints the URL
```

`railcode dev` uses a local scratch store, so it never touches deployed data. It runs Next in
Node, while the deployed app runs in the worker runtime: a Node-only dependency works locally
and fails when deployed. The first deploy is the real compatibility test, so deploy early.

Deploy to a new slug and leave the original app running.

One build at a time. `next build` plus the adapter plus the bundler is the heaviest thing this
machine will do today; never start a second while one is running, and stop dev servers before
building.

## Verify

A deploy that uploads has proved nothing about rendering. In a browser signed in to the org:

1. Load `/` and a deep link directly (not by clicking through). Both render, with styles.
2. Submit a form backed by a Server Action. The page updates and no error boundary appears.
3. Reload and confirm the write persisted.
4. Exercise one streaming route if the app has one.
5. Take a screenshot and look at it. Contrast and layout bugs do not show up in a DOM check.

Then read the logs:

```bash
railcode logs app --app <slug>           # one line per invocation: path, status, user
railcode logs app <invocation-id>        # console output and the real error
```

Next reports the actual error there even when the browser shows only "This page couldn't
load". A request that hangs leaves no log line at all — see the cache gotcha below.

## Gotchas

| Symptom | Cause and fix |
|---|---|
| Machine slows to a halt; dozens of `opennextjs-cloudflare build` processes | `package.json` `build` points at the Railcode build. The adapter runs `npm run build`. Set it back to `next build`, kill the processes |
| Every Server Action returns 500: `x-forwarded-host ... does not match origin` | The worker sees the platform's internal `Host`. Fixed in the platform on servers with Path A support. On Path B the worker entry rewrites both `Host` and `x-forwarded-host` — see that guide. Do not "fix" it with `serverActions.allowedOrigins` and a wildcard: that admits every other app on the same parent domain |
| Build fails: `@railcode/sdk only runs inside a deployed Railcode worker` | A page that calls the SDK is being prerendered. Add the `connection()` boundary |
| Upload rejected as too large, or a 502 during deploy | The worker is over the size limit. Remove `proxy.ts`/middleware first (about 3 MB), then heavy server dependencies |
| A page works once, then every later request for it hangs with no log | A cache write started after the response and was never awaited, so later requests wait on a promise that cannot settle. `@railcode/next` handles this. In a custom cache adapter, pass every write to `ctx.waitUntil` |
| `"use cache"` re-runs on every request | The adapter's default caches are no-ops. Path A wires real ones; on Path B add the adapter |
| `notFound()` renders the not-found page but answers HTTP 200 | A `loading.tsx` above it already started the stream. Move `loading.tsx` into a route group if the status matters |
| A list page makes N extra worker calls on load | `<Link>` prefetches every visible route. Use `prefetch={false}` on long lists |
| `tsc` fails after adding a parallel route (`@modal`) | Stale `.next/types`. Rebuild |
| Next warns about a lockfile in the home directory | Set `turbopack: { root: import.meta.dirname }` |
| A missing key shows as an `error` operation in the logs | A `db` `get` that finds nothing is logged that way. It is not a failure |

## What has and has not been proven

Proven on a deployed app (Next.js 16.3.8, App Router, through Path B): Server Components,
Server Actions with `useOptimistic` and `useFormStatus`, `searchParams`/`params`,
`loading.tsx`, `error.tsx`, `not-found.tsx`, `forbidden()`, `generateMetadata`, Route Handlers
including a streamed LLM response, `after()`, intercepting and parallel routes, `cookies()`,
`next/font`, `instrumentation.ts` `onRequestError`, and Cache Components with `"use cache"`,
`cacheLife`, `cacheTag` and `updateTag`.

Path A was verified by building that same app with `@railcode/next` and running it locally
(pages at their normal URLs, `railcode dev` with the SDK). It had not been deployed to a
Railcode server when this was written.

Not tested at all: Pages Router, i18n routing, `next/image` with a custom loader, multi-user
isolation under load, and Next.js 15.
