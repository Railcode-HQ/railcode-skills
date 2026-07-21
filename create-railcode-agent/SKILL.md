---
name: create-railcode-agent
description: Build, test, publish, invoke, schedule, and update Railcode managed agents with the Railcode CLI. Use when creating an org-scoped managed agent, editing an agent manifest (JSON or YAML), running a draft or saved agent, investigating an agent run, or managing its cron schedule, or when the agent should own personal connectors (Gmail, Slack, ...) on behalf of a single owner. Do not use for static Railcode apps, in-app LLM tool loops (llm.generate({ tools }) — see create-railcode-app), or general organization administration.
version: 0.1.6
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
was checked against the published **Railcode CLI 0.1.26**. The
[manifest tools reference](references/manifest-tools.md) reflects the backend `tools.*` schema
as of 2026-07-20 (adds `app_files` selective file loading and explicit read-scope selection;
`code_exec` is now a **legacy** key — the sandbox is deployment infrastructure every agent
gets); the CLI itself has no manifest schema of its own, so that reference is versioned
against the backend, not the CLI package.

## When To Use A Managed Agent vs The In-Page LLM

A **managed agent** (this skill) runs server-side under its own ratified manifest, with a
code sandbox and durable, auditable runs. The **in-page LLM** (`llm.generate`/`llm.stream`
with `tools`, via `$create-railcode-app`) runs in the app viewer's tab with the app's SDK
authority and dies with the tab. Pick the first matching row:

| The AI feature… | Use |
|---|---|
| Summarizes / classifies / analyzes data the app already reads — user watching, done in seconds | **In-page LLM** |
| Processes, parses, or analyzes an uploaded file (PDF, XLSX, …) | **Managed agent** (`app_files` + sandbox) |
| Writes and runs code | **Managed agent** (sandbox) |
| Is triggered outside the app (Slack, cron, API) | **Managed agent** |
| Runs unattended, must survive tab close, or needs retries | **Managed agent** |
| Has effects that must not depend on who's viewing (shared writes, send as the system) | **Managed agent** |
| Needs a run history someone will audit or debug | **Managed agent** |

The planes compose: the app keeps its chat shell in the page and delegates heavy steps by
calling `agents.invoke`/`agents.start` from an LLM tool's `run` (the app manifest declares
`agents: [name]`; this agent declares `app_files: [app]` to reach uploaded files).

## Build Workflow

### 1. Scope the agent

Clarify only choices that materially change its definition:

- the job it owns and the output expected;
- the input it accepts and whether an input schema is required;
- the model and tools it needs;
- whether it runs on demand, from an app, or on a schedule;
- what real systems, data, spend, or side effects a test may touch;
- **its visibility** — `org` (the default: shared, invokable by anyone with an invoke
  grant, managed by its creator or any admin) or `personal` (owned and invoked by its
  creator alone, admins included — no grant makes it shared, and it cannot later become
  `org`). Pick `personal` only when the agent needs `tools.personal_connectors` (its
  owner's own Gmail/Slack/etc.) or should otherwise be usable by exactly one person.

Use the narrowest useful tool set and explicit instructions. Do not invent tool identifiers,
provider names, or manifest fields; managed-agent manifest fields are server-defined (author
the file in JSON or YAML — see step 2). See
[manifest tools reference](references/manifest-tools.md) for the current `tools.*` vocabulary
and `limits` — a snapshot of the server schema, not a contract; a save-time error always wins
over this file.

### 2. Authenticate and inspect

Run `railcode login` if the CLI has no usable saved token. Managed agents are org-scoped and
do not use an app directory or `railcode.json`.

**Manifest file format.** `--file` (on `create`/`update`/`test`) reads the manifest as **JSON
or YAML**; the CLI picks the parser by extension (`.yaml`/`.yml` → YAML, anything else →
JSON), and both parse to the same object the API stores. There is no local manifest-schema
validator — treat server validation and ratification warnings as authoritative.

For an existing agent, pull its exact stored manifest before editing:

```bash
railcode agent show <agent>
railcode agent pull <agent> --output agent.json
```

`pull` and `show --manifest` **emit JSON only** — there is no YAML output flag. If the user
asks to see or store an agent's definition as YAML, convert that pulled JSON to YAML yourself
and write `agent.yaml`; it round-trips back through `--file` unchanged.

For a new agent, author the manifest in the current server-supported shape. **Ask the user
whether to save the definition in the current working directory.** If yes, write it there as
YAML (`agent.yaml`) and feed that file to `test`/`create`; if no, keep it in a scratch
location outside their project.

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
railcode agent create --file agent.yaml            # or agent.json — format is picked by extension
railcode agent create --file agent.yaml --visibility personal
railcode agent update <agent> --file agent.yaml
```

`update` replaces the stored manifest. Preserve fields intentionally by starting from
`railcode agent pull`, and read all ratification warnings before considering the change done.

`--visibility <org|personal>` on `create`/`update`/`test` sets or changes who the agent
belongs to. Omit it on `create`/`test` for the default `org`; omit it on `update` to leave
the existing visibility alone (never pass it just to be explicit — an omitted flag and an
explicit `org` are different requests server-side). Creating/transitioning to `personal`
needs the `agent:create` capability; `org` needs `agent:create_org` — holding one does not
imply the other. `personal -> org` is rejected outright; `org -> personal` is allowed but
does not retroactively change past shared runs/writes.

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

A scheduled run passes **null** input — there is no per-schedule payload. An agent meant to run
on a schedule should therefore **omit `input_schema`**: a `type: object` schema rejects null and
fails every tick with a 422. See [example agents](references/examples.md) (`daily-metrics-report`).

## Permissions and Boundaries

- `list`, `show`, and `pull` only ever return **org** agents plus the caller's **own**
  personal agents — someone else's personal agent is invisible (a 404, never a 403, to
  avoid confirming it exists), admins included.
- For an **org** agent: `run` needs an invoke grant for that agent; `update`/`delete`/`test`/
  schedule mutations are allowed for **the agent's own creator, or any org owner/admin** — not
  every member. Creating (or transitioning an existing agent to) `org` additionally needs the
  `agent:create_org` capability.
- For a **personal** agent: invoke and manage are both **owner-only, with no admin
  override** — there is no break-glass, so even an org owner/admin can't reach someone else's.
  Creating one needs the broadly-grantable `agent:create` capability, not owner/admin.
- `delete` archives the agent while keeping run history and requires `--yes` outside a TTY.
- Use `$create-railcode-app` when building a static app that invokes an agent through
  `agents.invoke(name, input)`. A privileged app manifest declares `agents: [name]`.
- An app can also run its own agentic loop **in the page** with `llm.generate({ tools })` /
  `llm.stream({ tools })` — no managed agent involved. See **When To Use A Managed Agent
  vs The In-Page LLM** at the top of this skill for the split.
- Use `$manage-railcode-org` for members, roles/grants, apps/access, connections, service
  connectors, analytics, and organization logs.

## Reference

Read [CLI reference](references/cli-workflow.md) for the exact agent commands, aliases,
schedule behavior, inputs, outputs, and failure semantics. Read
[manifest tools reference](references/manifest-tools.md) for the `tools.*` vocabulary,
what each grants, its permission gate, and `limits`. Read
[example agents](references/examples.md) for worked, runnable manifests spanning the tool
vocabulary — start from the closest one and adapt it instead of authoring from scratch.
