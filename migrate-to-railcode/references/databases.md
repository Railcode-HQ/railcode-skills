# Keeping the project's database

A project that already has a database does not have to move its data into Railcode's `db`.
It can keep using the database it has. This is often the fastest migration: the schema, the
data and the queries stay, and only the way the code connects changes.

## Contents

- [Three ways to hold data](#three-ways-to-hold-data)
- [What `db` is for, and where it stops](#what-db-is-for-and-where-it-stops)
- [Connect it as a data source](#connect-it-as-a-data-source)
- [Use it directly with a secret](#use-it-directly-with-a-secret)
- [Databases Railcode has no connector for](#databases-railcode-has-no-connector-for)
- [Schema migrations run in the build script](#schema-migrations-run-in-the-build-script)
- [Authorization when the worker holds the credentials](#authorization-when-the-worker-holds-the-credentials)

## Three ways to hold data

| Option | Reads | Writes | Who sets it up | Choose it when |
|---|---|---|---|---|
| **Move it into `db`** | Yes | Yes | Nobody; every app has it | The data belongs to this app and is simple: notes, tasks, settings, per-user records |
| **Connect the database as a data source** (a data connector) | Yes | **No** — sessions are read-only | An org admin, once | The app reads or reports on a Postgres, BigQuery or Turso database. No credentials in the app, and a private Postgres can be reached through an SSH bastion |
| **Use the database directly with a secret** | Yes | Yes | The developer: one secret, one `egress:` host | The app must write to its existing database, needs transactions, or uses a database Railcode has no connector for |

They combine. A common result is the existing database used directly for the app's writes,
a data connector for reporting screens, and `db` for small app-only state such as
preferences.

Decide per project with the user. If they already run Postgres and want to keep it, keep it.

## What `db` is for, and where it stops

Railcode's own `db` is built to be fast to start with and simple to use: no setup, no schema,
no credentials, and a new app can store and read records in its first route. It is the right
home for an app's own small data.

It is not a relational database, and it has limits a project with a lot of data or complex
queries will reach:

- **Volume.** A query returns one page (100 records by default, 500 at most), and every page
  is a subrequest out of about 100 per invocation. Reading or scanning tens of thousands of
  records in a request is not practical.
- **Queries.** Filters are single-field comparisons (`eq`, `ne`, `gt`, `gte`, `lt`, `lte`,
  `in`), a key prefix and an order. There are no joins, no aggregates (`count`, `sum`,
  `group by`), no full-text search and no SQL.
- **Guarantees.** No transactions, no unique constraints, no atomic increments; `put()`
  overwrites.

Use these signs during the inventory. If the project has more than a few thousand rows in a
table the screens list or search, relies on joins or aggregates for its main views, or needs
transactions, do not force it into `db`: keep its database (the next sections).

**If the project would be best served by a Postgres that Railcode hosts and manages** — it
needs a relational database and has none worth keeping, or the user does not want to run one
elsewhere — Railcode does not offer that today. Tell the user, pick the best option below for
now, and register the interest so the team can weigh building it:

```bash
railcode agent-feedback --category suggestion \
  --message "Interest in a managed Postgres for apps. Migrating a project with about 40 tables and 200k rows that relies on joins, aggregates and transactions; db does not fit, and the user would prefer not to host a database separately." \
  --context "Source: Rails + Postgres in a container. Went ahead by keeping the existing Postgres behind an HTTPS front." \
  --agent "<your assistant name>" --model "<your model>"
```

Describe the shape of the need (table and row counts, which query features, what was done
instead), with no credentials, customer data or source code. Send it once per project, and
tell the user you sent it.

## Connect it as a data source

An org admin registers the database once; apps then query it by name, and no app ever holds
its credentials.

```bash
railcode connections create --name warehouse --kind postgres ...   # admin; see manage-railcode-org
railcode db list
railcode db query "select count(*) from orders" --connection warehouse
```

Supported engines are Postgres, BigQuery and Turso. A Postgres that is not reachable from the
internet can be connected through an SSH bastion (`manage-railcode-org`, "Postgres through an
SSH bastion").

In the worker:

```ts
import { query, data } from "@railcode/sdk";

await query("orders_by_month", { year: 2026 });                              // a saved query an admin published
await data("warehouse").runSQL("select * from orders where id = $1", [id]);  // direct SQL
```

The manifest declares them: `saved_queries:` for the first, `adhoc_sql:` for the second.
Prefer saved queries.

**This path is read-only.** Postgres and Turso sessions are opened read-only whatever the
credentials allow. Use it for the screens that read; it cannot carry the app's inserts and
updates.

## Use it directly with a secret

The worker can talk to the project's own database with the project's own client library: put
the credential in a secret, allow the host, and query as before.

```bash
railcode secrets set DATABASE_URL        # the app must exist: deploy once first
```

```yaml
# manifest.yaml
run_as: app
egress:
  - ep-cool-name-123456.us-east-2.aws.neon.tech
```

```ts
import { neon } from "@neondatabase/serverless";
import { ctx, secrets } from "@railcode/sdk";

app.post("/api/orders", async (c) => {
  const sql = neon(secrets.DATABASE_URL);            // create per request, not at module scope
  const { item } = await c.req.json();
  const [row] = await sql`insert into orders (owner_email, item) values (${ctx.user!.email}, ${item}) returning id`;
  return c.json(row);
});
```

**The one constraint: the client must speak HTTPS.** A worker cannot open a raw TCP socket,
and listing the database host under `egress:` (even `egress: ["*"]`) does not change that. So
the classic socket drivers — `pg`, `mysql2`, `mongoose`, `ioredis` — do not connect. What
works is a client that sends queries with `fetch`:

| The database is | Use from the worker |
|---|---|
| Postgres on Neon | `@neondatabase/serverless` in HTTP mode (`neon(url)`); Drizzle has a `neon-http` driver for it |
| Postgres on Supabase | `@supabase/supabase-js`, or the project's PostgREST endpoint with `fetch` |
| Postgres anywhere else (RDS, a VM, the compose stack's own container) | It needs an HTTPS front. Options: PostgREST in front of it; the RDS Data API for Aurora; a hosted HTTP proxy for Postgres; or a small API kept on the old host. If the app only reads, skip all of this and use a data connector |
| Turso / libSQL | `@libsql/client/web` (or a data connector for reads) |
| MySQL on PlanetScale | `@planetscale/database` |

Before porting the data layer onto one of these, prove the connection: deploy a single route
that runs `select 1` and call it. These clients are the databases' own HTTP drivers and have
not each been verified on Railcode, so a one-query check costs a minute and settles it.

Things that differ from a server holding a connection pool:

- **No pool, no long-lived connection.** Create the client inside the request. Module
  variables do not survive between invocations.
- **Every query is a subrequest**, and an invocation has about 100. A page that ran forty
  queries on the old server needs fewer, larger queries. Join in SQL instead of looping.
- **Transactions must fit in one call.** HTTP drivers send a batch of statements as one
  transaction (Neon: `sql.transaction([...])`). An interactive transaction that reads, runs
  application code, then writes over a held connection is not available; rewrite it as one
  batch, or as a single statement with a CTE.
- **Watch the bundle.** A full ORM runtime can be several megabytes; the worker has a size
  cap (10 MB; 5 MB on a server without `worker_routes`). A light query builder or tagged SQL
  is the safer choice. If the project uses Prisma or another heavy ORM, build once and check
  the size before committing to keep it.
- **Secrets are read as `secrets.NAME`**, not `process.env.NAME`. Under `railcode dev` they
  come from your local environment, so local dev can point at a development database.
- **Keep the connection string out of files that get bundled or uploaded.** After
  `railcode secrets set`, remove the production value from `.env*` files in the project.

## Databases Railcode has no connector for

Railcode has connectors for Postgres, BigQuery and Turso. For anything else — MySQL, MongoDB,
DynamoDB, Firestore, Redis, ClickHouse, Elasticsearch, Snowflake, Airtable, a vendor's own
store — there is nothing to wait for: set the credentials as secrets, allow the host under
`egress:`, and use the database from the worker as the project always has, through its HTTPS
API or HTTP client.

| The database is | Reach it with |
|---|---|
| DynamoDB, or anything else in AWS with a signed HTTPS API | The AWS SDK v3 client for that service; keys in `secrets` |
| Upstash Redis | `@upstash/redis` (REST) |
| Firestore | Its REST API with a service-account token |
| ClickHouse, Elasticsearch / OpenSearch | Their HTTP interfaces with `fetch` or the official HTTP client |
| Snowflake | Its SQL REST API |
| MongoDB, self-hosted MySQL or Redis, anything that only speaks its own wire protocol | An HTTPS API in front of it: the vendor's, a small proxy, or a thin service on the old host |

The same rule applies as for Postgres: HTTPS works, a raw socket does not. Most hosted
databases offer an HTTPS interface; check the vendor's docs for "serverless", "edge", "HTTP"
or "REST" driver. When the only way in is a socket and nothing can be put in front of it,
that is a real gap: tell the user and file it with `railcode agent-feedback` as
[SKILL.md](../SKILL.md#what-railcode-cannot-host-today) describes, naming the database.

## Schema migrations run in the build script

Schema migrations (`prisma migrate deploy`, `drizzle-kit migrate`, `knex migrate:latest`,
Alembic, Rails migrations, Flyway) **never run in the worker**. The migration tools need a
socket connection and a filesystem, and a request handler is the wrong place to change a
schema. They run in the build or deploy script, on whatever machine runs it: the developer's
laptop for a manual deploy, the CI runner for an automated one. That machine can open a
normal database connection, so the project's existing migration tool keeps working unchanged
— including a Python or Ruby tool in a project whose server was rewritten in TypeScript.

Where the command goes depends on who owns the build:

| The app | Put the migration |
|---|---|
| Declares its own `"build"` in `railcode.json` (bring your own build) | At the front of that command: `"build": "npm run db:migrate && npm run build:app"`. `railcode deploy` runs it before uploading |
| Has a CLI-owned `"type"` (`hono+vite`, `hono+static`, `tanstack`, and `next` where it is available) | In a deploy script that wraps the CLI, because the CLI builds these itself and does not run `"build"`: `"deploy": "npm run db:migrate && railcode deploy"` in `package.json`, and deploy with `npm run deploy` |
| Deploys from CI | As a step before the `railcode deploy` step in the workflow, with the database URL as a CI secret |
| Is a Next.js app | Never in `package.json` `"build"`; that script must stay `next build` (see the [Next.js guide](nextjs.md)). Use the deploy script above |

Rules:

- **The migration's database URL comes from the machine running the script** (its environment
  or the CI secret store), not from `railcode secrets`. Railcode secrets are write-only and
  exist for the worker.
- **Migrate before the deploy, and keep each migration compatible with the code already
  live.** The old deploy keeps serving until the new one is activated, and a deploy can be
  reverted. Add columns and tables first, ship code that uses them, and drop the old ones in
  a later deploy.
- **A failed migration must stop the script**, so the new code is not deployed against an old
  schema. `&&` does that; do not use `;`.
- **`railcode dev` does not migrate.** Run the migration command by hand against the
  development database.
- Say in the handoff where migrations now run and which command deploys, so the next person
  does not run a bare `railcode deploy` and skip them.

## Authorization when the worker holds the credentials

With a direct connection the worker has the database's full power for every request. The old
app's protections often lived somewhere that no longer applies:

- **Row-level security tied to the old login** (Supabase RLS on `auth.uid()`, a per-user
  database role) has no caller to check: the worker connects with a service credential.
  Enforce ownership in the worker from `ctx.user`, in every route and query.
- **The credential never goes to the browser.** No public anon key in the frontend, no direct
  database calls from the page. The frontend calls `/api/*`; the worker calls the database.
- **User ids differ.** Rows keyed by the old auth system's user id need a mapping to Railcode
  members, usually by email. Add a column or a mapping table; see
  [SKILL.md](../SKILL.md#4-deploy-beside-the-original).
- **Use a least-privilege database user** for the app where the database allows it, separate
  from the one the migration script uses.
