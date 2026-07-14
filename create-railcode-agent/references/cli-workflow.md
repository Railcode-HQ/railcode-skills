# Managed-Agent CLI Reference

## Setup

Install or update the regular npm package, verify it against npm, then log in:

```bash
npm install -g railcode@latest
railcode --version
npm view railcode version
railcode login [--api-url <url>]
```

The CLI stores its selected instance, organization, and personal token at
`${RAILCODE_HOME:-~/.railcode}/config.json`. Resolution is `--api-url`, then
`RAILCODE_API_URL`, then saved config. `RAILCODE_API_TOKEN` overrides the saved token for CI.
On a `401`, the saved token is cleared and the CLI asks for login again.

`railcode login` uses browser authorization. `railcode login --setup-token <token>` is the
one-time, non-browser onboarding path. Managed-agent commands are org-scoped and work from any
directory after login.

## Agents

```bash
railcode agent list
railcode agent show <agent> [--manifest]
railcode agent pull <agent> [--output agent.json]
railcode agent create --file agent.json
railcode agent update <agent> --file agent.json
railcode agent delete <agent> [--yes]
railcode agent test --file agent.json --input '{"k":"v"}' [--trace]
railcode agent run <agent> --input '{"k":"v"}' [--trace]
```

- `<agent>` is a name or UUID. Aliases: `list`=`ls`, `show`=`get`, `pull`=`export`,
  `update`=`edit`, `delete`=`rm`, `run`=`invoke`, and `agent`=`agents`.
- Manifests are JSON in the exact shape stored under `agent.manifest`. They are distinct from
  app authority manifests, which are YAML. `pull` writes only the current manifest;
  `show --manifest` prints it.
- `create` and `update` print the agent name, UUID, and ratification warnings. `--json` prints
  the raw response. `update` replaces the stored manifest.
- `delete` archives the agent and keeps run history. It prompts on a TTY; `--yes` is required
  non-interactively.
- `run` and `test` accept either `--input '<json>'` or `--input-file <path>`, never both. The
  default input is `null`. `test` runs an unsaved manifest; `run` invokes a saved agent.
- Human output includes `Status:`, request ID, and output JSON. `--trace` appends a table of
  model/tool steps; `--json` prints the raw run detail.
- A runtime failure can still exit 0 when the invocation request itself succeeded. Invalid
  input against the agent's input schema returns non-zero `422`. Automation must inspect the
  run status, not only `$?`.

Permissions: `list`/`show`/`pull` require agent-read; `run` also requires agent-invoke for the
specific agent; `create`/`update`/`delete`/`test` require owner/admin authority.

## Schedules

Each agent currently has at most one schedule. The schedule is a resource under the agent,
not part of its JSON manifest.

```bash
railcode agent schedule show <agent>
railcode agent schedule set <agent> --cron "0 9 * * *" --timezone UTC
railcode agent schedule add <agent> --cron "0 9 * * *" --timezone UTC
railcode agent schedule update <agent> --cron "30 9 * * 1-5"
railcode agent schedule pause <agent>
railcode agent schedule resume <agent>
railcode agent schedule run-now <agent> [--trace]
railcode agent schedule delete <agent> [--yes]
```

- `set` upserts: create requires `--cron`; creation defaults `--name` to `default`, timezone
  to `UTC`, and enabled to true. Updating accepts any of `--name`, `--cron`, `--timezone`,
  `--enabled`, or `--disabled`.
- `add`/`create` is create-only and errors if a schedule exists. `update` is update-only and
  errors when none exists.
- `--cron` (alias `--schedule`) takes a five-field cron expression. `--timezone` takes an IANA
  zone.
- `pause` and `resume` toggle `enabled`. `run-now` (alias `run`) executes synchronously and
  prints run detail. `delete` (alias `rm`) prompts unless `--yes` is passed.
- Every schedule mutation requires owner/admin authority.

## Related Commands

```bash
railcode llm providers
railcode llm models
```

These show callable provider/model names without revealing keys. For agent run logs, use
`railcode logs agent [--agent <uuid>] [--status <value>]`, documented in
`$manage-railcode-org`.
