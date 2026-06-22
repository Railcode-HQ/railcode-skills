# CLI Workflow

Use this reference when an agent needs exact Railcode CLI behavior, local dev behavior, or app deploy behavior.

## Install Or Link The CLI

In a Railcode source checkout:

```bash
cd cli
npm install
npm run build
npm link
```

The CLI stores config under `${RAILCODE_HOME:-~/.railcode}/config.json`. The default API URL is `http://auth.127.0.0.1.nip.io:8080`. For deploy, set `RAILCODE_API_URL`, put `deploy.apiUrl` in `railcode.json`, or rely on the saved CLI config.

## Create An App

Run from an empty app repo root:

```bash
mkdir my-app
cd my-app
railcode init my-app
```

Behavior:

- Validate app names against `^[a-z0-9][a-z0-9-]{0,62}$`.
- Copy `cli/railcode-templates/railcode-react` into the current app root.
- Replace `__RAILCODE_APP__` and `__RAILCODE_TITLE__` placeholders.
- Refuse to initialize a non-empty app root unless `--force` is passed. Existing `.git` and `.DS_Store` are ignored for this check.

The starter uses React, Vite, Zustand, Tailwind, lucide-react, TypeScript, and exact package pins. Keep direct dependency versions exact unless there is a reason to upgrade.

The starter's `vite.config.ts` builds to `dist/` and uses `127.0.0.1:5173` as the starting asset dev server port.

## Local Dev

Run from the app root:

```bash
railcode dev
```

Useful options:

```bash
railcode dev --verbose
railcode dev --reset
railcode dev --port 7332
railcode dev --asset-port 5174
railcode dev --command "npm run dev -- --host 127.0.0.1 --port 5173"
```

`--port` is the starting Railcode proxy port. `railcode dev` tries that port first, then moves upward until it finds an available local port, and prints the URL to open. `--asset-port` and `railcode.json` `dev.port` are starting asset-server ports for inferred Vite apps; the CLI reserves the selected port and passes it to Vite. Custom `--command` / `dev.command` values are not rewritten, so keep their target port aligned with `--asset-port`.

App detection order:

- `--app` option or positional app argument.
- `railcode.json` `app`.
- App name inferred from an `apps/<app>` or `app-bundles/<app>` path for legacy workspaces.
- The only app under `apps/` if exactly one exists.
- `notes` for legacy/demo workspaces when present.
- Current directory basename if it matches the app-name regex.

Root and asset server detection:

- If `railcode.json` has `dev.root`, use it relative to the manifest.
- Otherwise infer from `apps/<app>` or `app-bundles/<app>` for legacy workspaces.
- If the root has `package.json` with a `dev` script, run it.
- Prefer `pnpm`, then `yarn`, otherwise `npm`.
- Run `npm ci` when a package-lock exists and dependencies are missing; otherwise run the package manager's normal install.
- Multiple `railcode dev` processes can run at once; each uses its own printed proxy URL and inferred Vite asset port. Concurrent sessions for the same app share the same local KV/files directory.

Local API behavior:

- `/_api/sdk.js`: serve the bundled SDK from the CLI package or source checkout.
- `/_api/me`: return `{ user: "local-dev", display_name: "Local Dev", app }`.
- `/_api/app-users`: return local mode with an empty complete roster.
- `/_api/kv/*`: store JSON in `~/.railcode/dev/<app>/kv.json`.
- `/_api/files/*`: store files in `~/.railcode/dev/<app>/files/` and metadata in `files.json`.
- `/_api/connections`: return `[]` unless a saved API token exists.
- Other `/_api/*`: forward to `<api-url>/v1/apps/<app>/*` with bearer auth when logged in.

If the remote backend rejects forwarded local-dev calls with `401` or `403`, `dataConnectors()` becomes `[]`; other backend-backed calls return a `502` explaining that local identity/KV/files still work.

## Read The Design System

```bash
railcode get design-system
```

The command prints the configured platform design-system markdown directly to stdout.
It accepts `--api-url`, otherwise it uses the saved CLI config, `railcode.json`
`deploy.apiUrl`, or `RAILCODE_API_URL`.

## Deploy An App With The CLI

```bash
railcode deploy
```

Deploy behavior:

- Infers the app from `railcode.json` `app`, or from the current directory.
- Runs the app's `build` script when one exists, installing dependencies first when missing.
- Publishes `dist/` for root app repos. Legacy workspace apps can still publish `app-bundles/<app>/`.
- Uploads the static files over HTTP to `api.<domain>/v1/apps/<app>/deploy`.
- Uses a saved API token, prompts for login when needed, or reads `RAILCODE_API_TOKEN` for non-interactive runs.
- On first deploy, creates public access for signed-in users.
- Prints the live app URL after a successful upload.

The deploy API accepts admins for any app, existing app owners for apps where
the access policy grants them `owner`, and any authenticated user for an
unclaimed app with no access policy. First deploy gives that unclaimed app a
workspace policy and an owner grant for the deployer.

Optional `railcode.json` URL:

```json
{
  "app": "my-app",
  "deploy": {
    "apiUrl": "https://api.apps.example.com"
  }
}
```
