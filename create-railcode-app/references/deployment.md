# Deployment

Use this reference when deploying a Railcode app or setting its access. Deploys are
org-scoped: `railcode deploy` publishes your app to the Railcode instance you logged into.

## App Deploy

From the app directory:

```bash
railcode deploy
```

`railcode deploy` reads `railcode.json` (`{ app, build?, dist? }`), runs the build command
when one is configured, and uploads the resolved output directory (which must contain a root
`index.html`) over HTTP to the configured Railcode instance. It does not restart any backend
service.

- **Which server** — resolved from `--api-url`, then `RAILCODE_API_URL`, then the saved CLI
  config from `railcode login` (prompt default `http://api.127.0.0.1.nip.io`). There is no
  `deploy.apiUrl` manifest key.
- **Auth** — the saved personal API token, or `RAILCODE_API_TOKEN` for non-interactive
  deploys. On a `401` the token is cleared and you're asked to `railcode login` again.
- **Where it lands** — the app is created-or-resolved by slug in your saved org
  (`POST /api/organizations/{org}/apps/{appUuid}/deploy`, a multipart upload). The first
  **successful** deploy is what creates the app; a failed first deploy leaves no phantom app.
- **Private on deploy** — `railcode deploy --private` is a one-shot action that sets this
  app's access to `private` for that deploy only; it is never persisted (see App Access).
- **App manifest** — always write a `manifest.yaml` in the app directory. It declares app
  authority for saved queries, connector endpoints, LLM, email, and, only when explicitly
  requested, ad-hoc SQL under `run_as: app`/`user`; it is uploaded and ratified as part of the deploy.
  For pass-through apps, use a minimal `run_as: user` manifest. See
  [cli-workflow.md](cli-workflow.md#app-manifest-authority).
- **Output resolution** — `railcode.json` `dist` wins (`"."` = no-build static); else
  `build` + `dist/`; else a `package.json` build script runs `<pm> run build` (your app's
  package manager — pnpm/yarn/bun by lockfile, else `npm`) and `dist/` is uploaded; else an
  interactive root-`index.html` deploy.

After upload the CLI prints the live URL: `http://<app>.<org>.<serving-domain>/`
(e.g. `https://my-app.acme.railcode.dev/`).

## App Access

A newly created app defaults to **`organization`** access (every member of the org may open
it). The owner or an org admin sets access in the **admin UI**, with the `railcode apps`
commands (use `$manage-railcode-org` for full administration), or via the access API (the one
deploy-time exception is the one-shot `railcode deploy --private`, above):

```text
GET  /api/organizations/{org}/apps/{app}/access
PUT  /api/organizations/{org}/apps/{app}/access      { "mode": "organization" | "private" | "restricted", ... }
```

Modes:

- `organization` — every org member (default).
- `private` — owners only.
- `restricted` — owners plus explicitly-granted members.

Org admins/owners bypass per-app access (they manage every app). A user who lacks access
sees a 404, not a 403.

## Post-Deploy Verification

After an app deploy, open the printed URL `https://<app>.<org>.<BASE_DOMAIN>/` and check:

- Unauthenticated visitors are sent through the platform login (the serving gate), not a
  custom app login.
- The app loads `/_api/sdk.js` with no CORS or mixed-content errors.
- `me()` returns the expected user, app, and org.
- KV and file reads/writes succeed.
- SQL / LLM / service-connector / email features show configured, empty, or disabled states
  cleanly (never a raw error or a hang) — email also has a `403` (not granted) state.
- The app's access mode in the admin UI matches the intended audience.
