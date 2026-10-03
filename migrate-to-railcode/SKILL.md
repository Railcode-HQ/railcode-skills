---
name: migrate-to-railcode
description: Migrate an existing project that was built for another host (Vercel, a Node server, a container) onto Railcode. Use when the user has a working app and wants it running on Railcode, including a Next.js app. Covers taking inventory of what the project depends on, mapping each dependency to a Railcode primitive, porting, testing with railcode dev, and deploying beside the original. Do not use for a new app from an idea, or for moving a Railcode v1 app to apps v2 — both belong to create-railcode-app.
version: 0.1.0
---

# Migrate to Railcode

A migration is a port, not a rewrite: the project already works somewhere, and the job is to
keep its behaviour while replacing what the old host provided (auth, a database, env vars,
cron, file storage) with what Railcode provides.

Framework guides:

| Source project | Guide | Status |
|---|---|---|
| Next.js (App Router) | [references/nextjs.md](references/nextjs.md) | Proven on a real app, with gaps listed in the guide |

For any other source, follow the method below and build the app with `create-railcode-app`.

## Update First

Before running a `railcode` command, update the skills and the CLI and confirm what is
published:

```bash
npx skills add Railcode-HQ/railcode-skills
npm install -g railcode@latest
railcode --version
npm view railcode version
```

If npm is unreachable, say so and do not claim this guidance is current. This version was
written against **CLI 0.3.7** and **`@railcode/sdk` 0.4.0**.

This skill does not restate the SDK, the manifest or the deploy flow. Those live in
`create-railcode-app` (`references/worker-sdk.md`, `references/cli-workflow.md`,
`references/deployment.md`); read them when a step below names an SDK surface.

## What Railcode is, for someone arriving from another host

Check these against the project before promising anything. Each one has ended a migration.

- **Every viewer is a signed-in member of the organization.** No anonymous visitors, no
  self-signup, no public marketing pages, no inbound webhooks. A project that needs any of
  those does not fit; say so before porting.
- **The backend is one worker module** on a Workers runtime (`nodejs_compat`), not a Node
  server. No filesystem, no long-lived process, no native addons, no raw TCP.
- **Outbound HTTP is an allow-list** (`egress:` in `manifest.yaml`).
- **Authentication is ambient.** The platform signs the user in before any app code runs and
  hands the worker a verified `ctx.user`. The project's own login goes away.

## Method

Work in this order. Do the inventory before touching code: most failed migrations port the UI
first and discover on day two that the data layer has no equivalent.

### 1. Inventory

Read the project and write down, with file paths:

| What | Where to look |
|---|---|
| Auth | NextAuth/Auth.js, Clerk, Supabase auth, a session cookie, a `/login` route |
| Data | An ORM (Prisma, Drizzle), a database URL, a hosted KV or blob store |
| Secrets and config | `.env*`, `process.env.*`, the old host's dashboard |
| Scheduled work | `vercel.json` crons, a queue, a `setInterval` in a server |
| Outbound calls | Every host the server code fetches |
| Inbound calls | Webhooks, public API routes, OAuth callbacks |
| Files | Uploads, generated documents, an S3 client |
| Host-specific packages | `@vercel/*`, platform SDKs, edge-only APIs |

### 2. Map each item

| The project has | On Railcode |
|---|---|
| Its own login, sessions, user table | Delete it. Read `ctx.user` (`id`, `email`, `name`, `is_admin`, `roles`). `appUsers` lists the org's members |
| Per-user rows in its own database | `db` collections — one flat store per app, so put the user id in the key (`<userId>:<id>`) and enforce access in server code |
| A company database it reads | A data connector an org admin sets up. Prefer saved queries (`query(name, params)`); direct SQL is `data(name).runSQL(...)` with `adhoc_sql:` in the manifest |
| `process.env.SECRET` | `railcode secrets set NAME`, read as `secrets.NAME` |
| Cron jobs | `crons:` in `manifest.yaml`, each calling one of the app's own routes |
| Outbound fetches | List each host under `egress:` |
| File uploads | `files` |
| An LLM provider key and client | `llm`, with `llm: true` in the manifest |
| Transactional email | `email`, with `email: true` in the manifest |
| Webhooks, public endpoints, anonymous pages | Nothing. Poll on a cron, or keep that part on the old host |

Tell the user what has no equivalent **before** porting, in one short list, and get a decision
on each item. Do not build an approximation and mention it afterwards.

### 3. Port

1. Add the Railcode files (`railcode.json`, `manifest.yaml`) and get an unchanged page
   rendering under `railcode dev`.
2. Replace auth.
3. Replace the data layer, one entity at a time.
4. Move secrets, crons and egress into the manifest and `railcode secrets`.
5. Remove the old host's packages and config.

Keep each step runnable. A migration that only works when all five are done is one you cannot
debug.

### 4. Deploy beside the original

Deploy to a **new app slug** and leave the original running. Nothing about a first deploy is
destructive, and the user can compare the two. Only move data and switch people over once the
new app has been checked.

Existing data does not move by itself. If it matters, write a one-off import (a script that
reads the old store and writes through a temporary admin-only route, or
`railcode app kv` from the CLI), run it once, and delete it.

### 5. Verify, then report

Load the deployed app as a real user and exercise each migrated feature; a green deploy says
only that the bundle uploaded. `railcode logs app --app <slug>` lists every invocation, and
`railcode logs app <invocation-id>` shows its console output and errors.

Report in this order: what works and how it was checked, what was dropped and why, what the
user must still do (secrets to set, connectors to link, data to import).

## Machine safety

Framework builds are heavy, and a migration runs many of them.

- Run one build or dev server at a time, and stop every process you start before finishing a
  turn. Check with `ps` rather than assuming.
- Never point a `package.json` `build` script at something that calls the framework's adapter
  if that adapter runs `npm run build` itself. That is an unbounded chain of builds. The
  Next.js guide has the specific rule.

## Feedback

After a migration, report concrete friction with the hidden `railcode agent-feedback` command
(see `create-railcode-app`): what the source project used, what had no equivalent, and what
broke that the guide did not predict. That is how the next framework guide gets written.
