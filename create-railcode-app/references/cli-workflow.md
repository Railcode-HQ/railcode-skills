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

Run from the workspace root:

```bash
railcode init my-tool
```

Behavior:

- Validate tool names against `^[a-z0-9][a-z0-9-]{0,62}$`.
- Create `apps/<tool>` from `cli/railcode-templates/railcode-react`.
- Create `tools/<tool>` for build output.
- Replace `__RAILCODE_APP__` and `__RAILCODE_TITLE__` placeholders.
- Refuse to overwrite existing source or build output unless `--force` is passed.

The starter uses React, Vite, Zustand, Tailwind, lucide-react, TypeScript, and exact package pins. Keep direct dependency versions exact unless there is a reason to upgrade.

The starter's `vite.config.ts` builds to `../../tools/<tool>` and serves the asset dev server on `127.0.0.1:5173`.

## Local Dev

Run from `apps/<tool>`:

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

App detection order:

- `--app` option or positional app argument.
- `railcode.json` `app` or `tool`.
- App name inferred from an `apps/<tool>` or `tools/<tool>` path.
- The only app under `apps/` if exactly one exists.
- `notes` for legacy/demo workspaces when present.
- Current directory basename if it matches the tool-name regex.

Root and asset server detection:

- If `railcode.json` has `dev.root`, use it relative to the manifest.
- Otherwise infer from `apps/<tool>` or `tools/<tool>`.
- If the root has `package.json` with a `dev` script, run it.
- Prefer `pnpm`, then `yarn`, otherwise `npm`.
- Run `npm ci` when a package-lock exists and dependencies are missing; otherwise run the package manager's normal install.

Local API behavior:

- `/_api/sdk.js`: serve the bundled SDK from the CLI package or source checkout.
- `/_api/me`: return `{ user: "local-dev", tool, app }`.
- `/_api/tool-users`: return local mode with an empty complete roster.
- `/_api/kv/*`: store JSON in `~/.railcode/dev/<tool>/kv.json`.
- `/_api/files/*`: store files in `~/.railcode/dev/<tool>/files/` and metadata in `files.json`.
- `/_api/connections`: return `[]` unless a saved API token exists.
- Other `/_api/*`: forward to `<api-url>/v1/apps/<tool>/*` with bearer auth when logged in.

If the remote backend rejects forwarded local-dev calls with `401` or `403`, `connections()` becomes `[]`; other backend-backed calls return a `502` explaining that local identity/KV/files still work.

## Deploy A Tool With The CLI

```bash
cd apps/my-tool
railcode deploy
```

Deploy behavior:

- Infers the app from `railcode.json` `app`/`tool`, or from the `apps/<tool>` path.
- Runs the app's `build` script when one exists, installing dependencies first when missing.
- Publishes `tools/<tool>/` for workspace apps, falling back to `dist/` for standalone app repos.
- Uploads the static files over HTTP to `api.<domain>/v1/apps/<tool>/deploy`.
- Uses a saved API token, prompts for login when needed, or reads `RAILCODE_API_TOKEN` for non-interactive runs.
- On first deploy from an interactive terminal, asks whether the tool should be private, public to signed-in users, or restricted to specific emails.
- Defaults first deploys to private in non-interactive runs.
- Prints the live tool URL after a successful upload.

The deploy API accepts admins for any app, existing app owners for apps where
the access policy grants them `owner`, and any authenticated user for an
unclaimed app with no access policy.

Optional `railcode.json` URL:

```json
{
  "app": "my-tool",
  "deploy": {
    "apiUrl": "https://api.tools.example.com"
  }
}
```
