# Deployment

Use this reference when deploying a Railcode app or setting up/updating a Railcode server.

## First-Time Server Install

Run the installer on the server:

```bash
curl -fsSL https://raw.githubusercontent.com/railcode/railcode/main/install.sh | bash
```

From an existing checkout:

```bash
bash install.sh
```

The installer verifies Docker, Docker Compose v2, and curl; prompts for the base domain; explains required DNS records; asks for storage, admin, and optional LLM settings; writes `.env` and `.railcode/Caddyfile`; then runs `docker compose up -d --build`.

DNS records:

```text
auth.<domain>  A  <server-ip>
admin.<domain> A  <server-ip>
*.<domain>     A  <server-ip>
```

Use `127.0.0.1.nip.io` as the base domain for local HTTP installs. Other domains are treated as production HTTPS installs with Caddy on-demand TLS, so ports 80 and 443 must be reachable from the public internet.

Production setup decisions:

- Platform DB: SQLite by default, Postgres with `STORAGE_BACKEND=postgres` and `POSTGRES_DATABASE_URL`.
- File bytes: local disk by default, S3-compatible storage with `OBJECT_STORAGE_BACKEND=s3`.
- Auth/admin: set a strong `SECRET_KEY`, change the bootstrap admin password, and avoid demo credentials.
- LLM: configure provider, API key, model, and `LLM_DAILY_TOKEN_LIMIT` before apps can use `llm`.

For env details, read the repo's `docs/service-config.md`.

## App-Only Deploy

For a single app:

```bash
railcode deploy
```

`railcode deploy` builds the current app and uploads the inferred static output
to the Railcode backend over HTTP. It does not restart backend services.

Deploy sends to the configured Railcode URL and uploads to the canonical
`api.<domain>` host. The URL resolution order is:

- `RAILCODE_API_URL`
- `railcode.json` `deploy.apiUrl`
- saved CLI config
- the local default `http://auth.127.0.0.1.nip.io:8080`

When no API token is saved, `railcode deploy` prompts for login and creates one.
For non-interactive deploys, set `RAILCODE_API_TOKEN`.

When the app has no access policy yet, deploy creates public access for
signed-in users. The CLI prints the live app URL after upload.

For root app repos, deploy publishes `dist/`. Legacy `apps/<app>` workspaces
can still publish `app-bundles/<app>/`.

## Platform Updates

Railcode platform servers are Docker Compose installs. Update a server from the
source repository with the Ansible playbook:

```bash
ansible-playbook -i deploy/ansible/inventory.ini deploy/ansible/update-railcode.yml
```

Each host sets its own `railcode_health_url` in the inventory (see
`deploy/ansible/inventory.example.ini`). The playbook backs up local
config/data, updates the checkout from GitHub, validates Compose, runs
`docker compose up -d --build --remove-orphans`, and waits for the health
check — one host at a time across the `[railcode]` group.

The repository also ships `.github/workflows/deploy-railcode.yml`, which runs
the project checks and deploys the pushed `main` commit with the same playbook.
Configure the workflow with `RAILCODE_HOSTS` (a JSON array of
`{name, host, health_url}` objects), `RAILCODE_SSH_USER`,
`RAILCODE_SSH_PRIVATE_KEY`, and `RAILCODE_SSH_KNOWN_HOSTS`.

Do not use a platform update for an app-only change unless the app change
depends on SDK/backend behavior that has also changed.

## Local Docker Flow

For a full local browser flow:

```bash
docker compose up --build
```

Open:

```text
http://notes.127.0.0.1.nip.io:8080
http://guestbook.127.0.0.1.nip.io:8080
http://auth.127.0.0.1.nip.io:8080
```

Local Compose uses `admin@example.com/admin`, SQLite at `/data/platform.db`, local files at `/data/files`, and a `railcode-data` Docker volume. Wipe local data with:

```bash
docker compose down -v
```

## Post-Deploy Verification

After an app deploy:

Open:

```text
https://my-app.<BASE_DOMAIN>/
```

Check:

- Auth redirects to `auth.<BASE_DOMAIN>` when not logged in.
- App loads `/_api/sdk.js` without CORS or mixed-content errors.
- `me()` returns the expected user and app.
- KV/files reads and writes succeed.
- SQL/LLM features show configured, empty, or disabled states cleanly.
- Access policy in the admin UI matches the intended audience.
