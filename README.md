# railcode-skills

Agent skills for Railcode, extracted from the main `railcode` repo so they can be
installed and versioned on their own.

These skills ship through the open agent-skills ecosystem (the `skills` CLI), so they
work across Claude Code, Codex, Cursor, and other agents.

## Skills

| Skill | Description |
| --- | --- |
| [`create-railcode-app`](create-railcode-app/SKILL.md) | Build, modify, debug, and deploy Railcode apps end-to-end — scaffolding with the CLI, writing the backend worker with `@railcode/sdk`, configuring access policies, testing with `railcode dev`, migrating legacy v1 apps, and deploying. |
| [`create-railcode-agent`](create-railcode-agent/SKILL.md) | Build, test, publish, invoke, and schedule organization or personal Railcode managed agents. |
| [`manage-railcode-org`](manage-railcode-org/SKILL.md) | Administer apps, members, roles/grants, saved queries, connections, service connectors, analytics, and logs through the CLI. |

## Examples

Worked Railcode apps and agents live in
[`Railcode-HQ/railcode-examples`](https://github.com/Railcode-HQ/railcode-examples).

**The `apps/` examples are currently generation-1 (browser-SDK) apps.** Every app created today
is apps v2, where there is no browser SDK, so those examples must be read for product patterns
rather than copied into a new app. Porting them to v2 is tracked as follow-up work.

## Install

Install or update all Railcode skills:

```bash
npx skills add Railcode-HQ/railcode-skills
```

Or install a single skill by name:

```bash
npx skills add Railcode-HQ/railcode-skills --skill create-railcode-app
```

Update it later:

```bash
npx skills update create-railcode-app
```

## Onboarding script

[`onboard.sh`](onboard.sh) runs the full step-by-step onboarding end to end —
the same flow as the in-app "Step by step" tab: install the CLI, install the
skill, sign in, scaffold a "hello world" app, and deploy it.

```bash
./onboard.sh            # full flow (login opens your browser)
./onboard.sh --help     # options: --app, --dir, --api-url, --agent, --skip-*, --no-deploy
```

The skill is installed non-interactively to a default agent set (Claude Code,
OpenCode, Codex, Pi, Kiro, Cursor); change it with `--agent <list>` or fall back
to the interactive picker with `--prompt-agent`. Signing in is always
interactive (it opens your browser). Everything else is automatic and idempotent
— re-running skips work that's already done.
