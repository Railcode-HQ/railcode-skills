---
name: create-railcode-agent
description: Build, test, publish, invoke, schedule, and update Railcode managed agents with the Railcode CLI. Use when creating an org-scoped managed agent, editing an agent JSON manifest, running a draft or saved agent, investigating an agent run, or managing its cron schedule. Do not use for static Railcode apps or general organization administration.
version: 0.1.1
---

# Create Railcode Agent

## Update First

Before answering a Railcode agent or CLI question or running a `railcode` command, update
the installed Railcode skills and CLI, then confirm npm's published version:

```bash
npx skills add Railcode-HQ/railcode-skills
npm install -g railcode@latest
railcode --version
npm view railcode version
```

If the skill changes, re-read this file from the top. If npm is unreachable, state that the
latest version could not be verified and do not claim this guidance is current. This version
was checked against the published **Railcode CLI 0.1.23**. The
[manifest tools reference](references/manifest-tools.md) reflects the backend `tools.*` schema
as of 2026-07-16 (adds `app_data_write` — write access to another app's KV + file publish); the
CLI itself has no manifest schema of its own, so that reference is versioned against the
backend, not the CLI package.

## Build Workflow

### 1. Scope the agent

Clarify only choices that materially change its definition:

- the job it owns and the output expected;
- the input it accepts and whether an input schema is required;
- the model and tools it needs;
- whether it runs on demand, from an app, or on a schedule;
- what real systems, data, spend, or side effects a test may touch.

Use the narrowest useful tool set and explicit instructions. Do not invent tool identifiers,
provider names, or manifest fields; managed-agent manifests are server-defined JSON. See
[manifest tools reference](references/manifest-tools.md) for the current `tools.*` vocabulary
and `limits` — a snapshot of the server schema, not a contract; a save-time error always wins
over this file.

### 2. Authenticate and inspect

Run `railcode login` if the CLI has no usable saved token. Managed agents are org-scoped and
do not use an app directory or `railcode.json`.

For an existing agent, pull its exact stored manifest before editing:

```bash
railcode agent show <agent>
railcode agent pull <agent> --output agent.json
```

For a new agent, use the current server-supported manifest shape. The CLI sends the JSON
manifest to the API; it does not provide a local manifest-schema validator. Treat server
validation and ratification warnings as authoritative.

### 3. Test the draft

Test an unsaved manifest before creating or replacing an agent:

```bash
railcode agent test --file agent.json --input '{"key":"value"}' --trace
```

Use `--input-file` for larger or sensitive test payloads. Testing invokes real configured
models and tools, so it may incur spend, read real data, or cause tool side effects. Get any
needed authorization before running a side-effecting test.

Do not rely only on the process exit code: a request that reached the runtime can exit 0 even
when the run's printed status is failed. Check `Status:` or inspect `--json`.

A draft test run has no persistent store: write tools from `app_data_write` and `agent_kv` are
silently omitted from a test run's tool list (see
[manifest tools reference](references/manifest-tools.md)). An untouched app or KV store after
`test` is not evidence those tools are broken — verify writes with `create` + `run` instead.

### 4. Publish or update

```bash
railcode agent create --file agent.json
railcode agent update <agent> --file agent.json
```

`update` replaces the stored manifest. Preserve fields intentionally by starting from
`railcode agent pull`, and read all ratification warnings before considering the change done.

### 5. Verify the saved agent

```bash
railcode agent run <agent> --input '{"key":"value"}' --trace
railcode agent show <agent> --manifest
```

Confirm the saved manifest, run status, output, and relevant trace steps. For organization
observability logs, use `$manage-railcode-org`; its `railcode logs agent ...` workflow is an
admin capability rather than part of agent authoring.

### 6. Schedule only when requested

Each managed agent currently has at most one cron schedule. Inspect it first, then use
`schedule set` to upsert or a stricter create/update alias when that distinction matters.

```bash
railcode agent schedule show <agent>
railcode agent schedule set <agent> --cron "0 9 * * *" --timezone UTC
```

Use an IANA timezone and a five-field cron expression. Verify the stored schedule after every
mutation. `run-now` executes synchronously against real services.

## Permissions and Boundaries

- `list`, `show`, and `pull` require agent-read access.
- `run` also requires an invoke grant for that agent.
- `create`, `update`, `delete`, `test`, and schedule mutations require owner/admin authority.
- `delete` archives the agent while keeping run history and requires `--yes` outside a TTY.
- Use `$create-railcode-app` when building a static app that invokes an agent through
  `agents.invoke(name, input)`. A privileged app manifest declares `agents: [name]`.
- Use `$manage-railcode-org` for members, roles/grants, apps/access, connections, service
  connectors, analytics, and organization logs.

## Reference

Read [CLI reference](references/cli-workflow.md) for the exact agent commands, aliases,
schedule behavior, inputs, outputs, and failure semantics. Read
[manifest tools reference](references/manifest-tools.md) for the `tools.*` vocabulary,
what each grants, its permission gate, and `limits`.
