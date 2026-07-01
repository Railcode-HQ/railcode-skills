# railcode-skills

Agent skills for Railcode, extracted from the main `railcode` repo so they can be
installed and versioned on their own.

These skills ship through the open agent-skills ecosystem (the `skills` CLI), so they
work across Claude Code, Codex, Cursor, and other agents.

## Skills

| Skill | Description |
| --- | --- |
| [`create-railcode-app`](create-railcode-app/SKILL.md) | Build, modify, debug, and deploy Railcode static apps end-to-end — scaffolding with the CLI, wiring the zero-config SDK globals, configuring access policies, testing with `railcode dev`, and deploying. |

## Install

Install a single skill by name:

```bash
npx skills add yakkomajuri/railcode-skills --skill create-railcode-app
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
./onboard.sh --help     # options: --app, --dir, --api-url, --skip-*, --no-deploy
```

Signing in and the skill install are interactive by design; everything else is
automatic and idempotent (re-running skips work that's already done).
