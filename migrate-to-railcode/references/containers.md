# Migrating a container application to Railcode

A container application here means a project whose deployment unit is a `Dockerfile` or a
docker-compose stack: a long-running HTTP server (Express, Fastify, NestJS, Flask, FastAPI,
Django, Rails, a Go or Java service), usually with a database, often with Redis, a job worker
and a reverse proxy beside it.

Railcode does not run containers. The image is not uploaded and nothing in the `Dockerfile`
executes. What migrates is **what the container does**: its routes, its data, its scheduled
work and its UI are rebuilt as a Railcode app — a static frontend plus one TypeScript worker.
For an internal tool this is usually a smaller codebase than the original, because login, the
database server, the proxy, the queue and the deployment config all disappear.

This guide is built from the platform's documented behaviour. It has not yet been checked
against a recorded migration the way the Next.js guide has, so verify each step as you go and
report what was wrong (see [SKILL.md](../SKILL.md#feedback)).

## Contents

- [Size it first](#size-it-first)
- [Read the container as an inventory](#read-the-container-as-an-inventory)
- [The target shape](#the-target-shape)
- [Port the HTTP layer](#port-the-http-layer)
- [Port the data](#port-the-data)
- [Port background work](#port-background-work)
- [What a long-running server assumed](#what-a-long-running-server-assumed)
- [Build, run, deploy, verify](#build-run-deploy-verify)

## Size it first

How much work this is depends almost entirely on the server's language.

| The server is written in | What the port is |
|---|---|
| TypeScript or JavaScript (Express, Fastify, Koa, NestJS, Hono) | A port. Route handlers and business logic move across with their framework calls swapped; npm dependencies mostly stay. Check each dependency against [What a long-running server assumed](#what-a-long-running-server-assumed) |
| Python, Ruby, Go, Java, PHP, anything else | A translation. The worker is JavaScript, so every route and every piece of business logic is rewritten in TypeScript. This is routine for a CRUD tool of a few dozen routes and expensive for a service whose value is in a language-specific library (pandas, NumPy, a JVM library) |

Tell the user which of the two it is, with a route count, before starting. For a translation,
propose a first slice (the three or four screens people use daily) and migrate that beside the
original rather than committing to the whole surface at once.

If the service's core is a library with no JavaScript counterpart, look for a way to keep the
behaviour before giving up: a hosted API for the same job reached through `egress:`, a managed
agent (agents can run code), or leaving that one computation on the old host behind an HTTP
endpoint the worker calls. If none of those works, it belongs in
[What Railcode cannot host today](../SKILL.md#what-railcode-cannot-host-today).

## Read the container as an inventory

The `Dockerfile` and `docker-compose.yml` are the most honest description of what the project
depends on. Read them line by line and decide what each line becomes.

**Dockerfile**

| Line | What it tells you | On Railcode |
|---|---|---|
| `FROM node:…` / `python:…` / `golang:…` | The language, so the size of the job (above) | The worker is TypeScript |
| `RUN apt-get install …`, `apk add …` | System packages the code needs: image tools, a PDF renderer, a headless browser, database clients | None are available. Each one is an item for [Find another way](../SKILL.md#find-another-way) |
| `RUN npm ci` / `pip install` | Dependencies. Look for native addons (`sharp`, `bcrypt`, `canvas`, `sqlite3`, `psycopg2`) | Pure-JavaScript packages bundle into the worker. Native ones must be replaced |
| `ENV`, `ARG` | Configuration and secrets | Secrets go to `railcode secrets`; plain config becomes constants in the code |
| `VOLUME`, `COPY ./data` | Files the server reads or writes on disk | `files` for user content; small static data is imported into the bundle |
| `EXPOSE`, `HEALTHCHECK`, `USER` | Process plumbing | Delete |
| `CMD` / `ENTRYPOINT` | What actually runs. More than one process (a server and a scheduler started by a shell script, `supervisord`) means more than one thing to port | The server becomes the worker; the rest is [background work](#port-background-work) |

**docker-compose services**

| Service | On Railcode |
|---|---|
| The web or API server | The worker (`server/index.ts`) |
| A frontend container (nginx serving a build, a Vite or CRA dev server) | The static `frontend/` |
| Postgres, MySQL, Mongo, SQLite on a volume | See [Port the data](#port-the-data) |
| Redis | Whatever it was used for: a cache → a `db` collection with an `expires_at`; sessions → gone with the login; a queue → [background work](#port-background-work); pub/sub → frontend polling |
| A job worker (Celery, Sidekiq, BullMQ, RQ) | A cron route draining a `jobs` collection |
| A scheduler (cron container, Celery beat, `node-cron`) | `crons:` in `manifest.yaml` |
| nginx, Traefik, Caddy | Delete. Railcode routes `/api/*` to the worker and serves the rest as static files. Copy any path rewrites into the routes |
| MinIO, a local S3 | `files` |
| Mailhog, an SMTP relay | `email` |
| An auth service (Keycloak, an OAuth proxy) | Delete. Sign-in is the platform's |
| Elasticsearch, Meilisearch, a vector database | Not hosted. See the search row in [Find another way](../SKILL.md#find-another-way) |
| `depends_on`, networks, healthchecks, restart policies | Delete |

Also list every route the server exposes and mark who calls it. Routes called by the app's own
frontend migrate. Routes called by anything else — a webhook, a partner, a mobile app, another
service — cannot be reached on Railcode; settle those with the user before porting, using
[Find another way](../SKILL.md#find-another-way) and
[What Railcode cannot host today](../SKILL.md#what-railcode-cannot-host-today).

## The target shape

Scaffold a fresh app in a **new directory** and move code into it. Do not convert the old
repository in place: keeping the original runnable is what lets you compare behaviour.

```bash
railcode init <app> --template hono+vite     # React frontend + Hono worker
# or, if the project has no build step for its UI:
railcode init <app> --template hono+static
```

```
frontend/          # the UI: static files, holds no credentials
server/index.ts    # every route, as one Hono app: export default app
manifest.yaml      # what the worker is allowed to use
railcode.json
```

Read the scaffolded platform tour once (it shows `ctx.user`, `db` and `files` working), then
delete it. The CLI owns the build; the app needs no bundler config, no `wrangler` and no
Dockerfile.

If the existing frontend is already a single-page app (React, Vue, Svelte built by Vite or
similar), keep it: move it into `frontend/`, or use a bring-your-own build that emits a static
`dist`. Its API calls must go to `/api/...` on the same origin, with no base URL and no auth
header. If the server rendered HTML from templates, the templates become frontend components
that fetch JSON.

## Port the HTTP layer

Every route moves under `/api/`. That prefix is what the platform sends to the worker;
everything else is served from the static tree.

**Express to Hono**

| Express | Hono |
|---|---|
| `app.get("/notes/:id", (req, res) => …)` | `app.get("/api/notes/:id", async (c) => …)` |
| `req.params.id`, `req.query.q` | `c.req.param("id")`, `c.req.query("q")` |
| `req.body` (with `express.json()`) | `await c.req.json()` |
| `req.headers["x-thing"]` | `c.req.header("x-thing")` |
| `res.json(data)`, `res.status(404).json(e)` | `return c.json(data)`, `return c.json(e, 404)` |
| `res.send(text)`, `res.sendFile(path)` | `return c.text(text)`; files come from `files.get(name)`, which returns a `Response` |
| `app.use(middleware)` | `app.use("/api/*", async (c, next) => { …; await next(); })` |
| `express.Router()` | `const notes = new Hono(); app.route("/api/notes", notes)` |
| `multer` upload | `await c.req.arrayBuffer()` or `await c.req.formData()`, then `files.put(...)` |
| `req.user` (Passport), `req.session` | `ctx.user`, imported from `@railcode/sdk` |
| `app.listen(port)` | `export default app` |

The same mapping applies from any other framework: a route is a method, a path and a function
from request to response. FastAPI's `@app.get("/items/{id}")` and Rails' `resources :items`
become the same Hono lines.

**Auth and authorization**

Delete the login routes, the session store, password hashing, JWT signing, the auth
middleware and the user-registration flow. Then put the *authorization* back, because the
platform only tells you who the caller is:

```ts
import { Hono } from "hono";
import { ctx, db } from "@railcode/sdk";

const app = new Hono();

app.delete("/api/notes/:id", async (c) => {
  const user = ctx.user;
  if (!user) return c.json({ error: "no caller" }, 409);        // a cron has no user
  const key = `${user.id}:${c.req.param("id")}`;                 // ownership lives in the key
  if (!(await db.collection("notes").get(key))) return c.json({ error: "not found" }, 404);
  await db.collection("notes").delete(key);
  return c.json({ ok: true });
});

export default app;
```

Role checks that the old server did (`requireAdmin`, a `role` column) become checks on
`ctx.user.is_admin` and `ctx.user.roles`, or on a role the app stores in `db`. Every check
must be in the worker: the frontend is static files and anyone signed in can call `/api/*`
directly.

**Validation, errors, CORS**

Keep request validation (zod and similar libraries work as they are). Drop CORS setup: the
frontend and the worker share an origin. Relay platform errors with their status rather than
turning them into 500s — `create-railcode-app/references/app-patterns.md` has the pattern.

## Port the data

Decide per table, not for the database as a whole.

| The data is | Put it |
|---|---|
| Owned by this app and simple: notes, tasks, settings, per-user records, small lookup lists | `db` collections |
| Shared with other systems, large, reported on with SQL, or dependent on transactions and constraints | Leave it in its database. An org admin connects that database as a data connector; the worker calls saved queries (`query(name, params)`), or direct SQL when the user asks for it |
| Uploaded or generated files | `files` |
| Sessions, password hashes, refresh tokens, email-verification rows | Nowhere. Delete |

A database running *inside* the compose stack is reachable by nobody once the stack is gone.
If its data must stay relational, it has to move to a database the org hosts somewhere
Railcode can connect to; that is the user's decision and an admin's setup step, so raise it
early.

For data connectors, confirm what the connection permits before designing around it: ask the
user or an admin whether the app may write through it, and prefer saved queries an admin
publishes over SQL embedded in the app.

**Moving tables into `db`**

`db` is a flat key/value store with field queries, not SQL. Three habits make it work:

- **Design the key for the main read.** A user's records are `<userId>:<id>` and are read
  with `query().prefix(...)`. A shared list is keyed by its own id.
- **Replace joins with a little duplication.** Store the author's name on the comment. For a
  true many-to-many, keep a second collection keyed `<a>:<b>`.
- **Always paginate.** `query()` returns one page (100 by default, 500 at most). Loop until a
  short page, or the tail is silently lost.

There are no transactions, unique constraints or atomic increments. Where the original relied
on one, either keep that table in a real database, or say so and design around it (a
deterministic key gives uniqueness; a recount gives a total).

The ORM goes away: Prisma, SQLAlchemy and ActiveRecord models become TypeScript types and a
few functions over `db.collection(...)`. Put those functions in one module per entity so
routes never build keys themselves.

Existing rows do not move by themselves. Export from the old database and import through a
temporary admin-only route or `railcode app kv`, translating user ids as described in
[SKILL.md](../SKILL.md#4-deploy-beside-the-original).

## Port background work

A container can run a queue worker forever. A Railcode worker runs when called. The
replacement is a cron that wakes up, does a bounded amount of work, and stops.

```yaml
# manifest.yaml
run_as: app
crons:
  - schedule: "* * * * *"
    path: /api/jobs/drain
```

```ts
app.post("/api/jobs/drain", async (c) => {          // cron calls with POST
  if (ctx.trigger !== "cron" && !ctx.user?.is_admin) return c.json({ error: "forbidden" }, 403);
  const jobs = db.collection("jobs");
  const batch = await jobs.query().where("status", "eq", "queued").orderBy("created_at", "asc").page(1, 10);
  for (const job of batch) {
    await jobs.put(job.id, { ...job, status: "running", claimed_by: ctx.invocationId });
    await runJob(job);                               // must be safe to run twice
    await jobs.put(job.id, { ...job, status: "done", finished_at: new Date().toISOString() });
  }
  return c.json({ processed: batch.length });
});
```

`query()` returns the stored values, so each job must carry its own key (`id` here) for the
drain to write it back.

Rules that come from how cron works:

- **At least once, possibly overlapping.** Two runs can pick up the same job. Make each job
  safe to repeat, and record what was done so a repeat is a no-op.
- **Small batches.** An invocation has about 100 subrequests, and every `db` call, fetch and
  SDK call spends one. Size the batch so the worst case fits.
- **No caller.** `ctx.user` is `null` under cron. Store who queued the job on the row, and do
  not run code that reads `ctx.user`.
- **Five schedules, one-minute minimum.** One drain route can serve every job type.
- **A cron cannot start or read managed agent runs.** Start those from a user's request.
- `railcode dev` does not schedule crons. Trigger the route by hand with `POST`.

When the user is waiting for the result (an import they just started), let the frontend drive
it instead: a route does one step and returns a cursor, and the page calls it until done.
That gives a progress bar and needs no cron.

Work that is long and open-ended, needs to run code, or reads documents with AI belongs in a
managed agent started with `agents.start()` and polled from the frontend.

## What a long-running server assumed

Server code written for a container assumes things that are not true in a worker. Search the
codebase for each.

| The code does this | In a worker | Do this instead |
|---|---|---|
| Keeps state in module variables: an in-memory cache, a counter, a connection pool, a `Map` of sessions | Not kept between requests | Store it in `db`, or recompute it |
| `setInterval`, `setTimeout` for later work, `node-cron` | The invocation ends with the response | A cron route |
| Finishes work after sending the response | May be cut off | Do it before responding, or queue a job |
| Reads or writes local files (`fs`, `/tmp`, an uploads directory) | No filesystem | `files`; import static data into the bundle |
| Spawns processes (`child_process`, `subprocess`) | Not available | A JavaScript library, a hosted API, or a managed agent |
| Opens TCP connections (`pg`, `mysql2`, `mongoose`, `ioredis`, `nodemailer` over SMTP) | Not available | Data connectors, `db`, `email` |
| Calls any host it likes | Blocked unless declared | List each host under `egress:` |
| Reads `process.env.X` | Not populated with the old values | `secrets.X`, after `railcode secrets set X` |
| Depends on a native addon (`sharp`, `bcrypt`, `canvas`) | Does not load | A pure-JavaScript alternative (`bcryptjs`), or remove the need: password hashing goes with the login |
| Makes hundreds of calls in one request | About 100 subrequests per invocation | Batch (`files.urls()`), page, or split into steps |
| Listens on a websocket | No push surface | Frontend polling |
| Ships a very large dependency tree | The worker is one bundled module with a size cap (5 MB on CLI 0.3.7) | Drop server-only packages that no longer apply (ORM, auth, queue client); check the bundle size after the first build |

Secrets need the app to exist. The first deploy creates it, so deploy once (private, before
any secret-dependent route matters), then run `railcode secrets set`, then verify.

## Build, run, deploy, verify

```bash
railcode manifest validate
railcode dev                 # frontend + worker; db and files are local scratch storage
railcode deploy --private    # a new slug, beside the original
railcode logs app --app <slug>
```

Under `railcode dev`, SQL, connectors, email, `llm` and agents go to the real instance. Use
test recipients and read-only queries while porting.

Verify against the original, feature by feature, as a real signed-in user:

1. Every screen loads and shows the same data as the old app for the same person.
2. Each write (create, edit, delete) persists and is visible after a reload.
3. A second member cannot read or change the first member's records by calling `/api/*`
   directly.
4. Each cron route has been triggered once by hand and once by its schedule
   (`railcode logs app` shows the cron invocations).
5. Every item that was rebuilt differently behaves as the user agreed.

Then report as [SKILL.md](../SKILL.md#5-verify-then-report) describes, including the
`railcode agent-feedback` reports for anything the project needed that Railcode could not
host.
