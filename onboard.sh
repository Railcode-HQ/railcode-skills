#!/usr/bin/env bash
#
# onboard.sh — run through Railcode's step-by-step onboarding, end to end.
#
# Mirrors the "Step by step" tab of the in-app onboarding modal:
#
#   1. Install the Railcode CLI               (npm install -g railcode@latest)
#   2. Install the create-railcode-app skill  (npx skills add …)
#   3. Sign in                                (railcode login — opens your browser)
#   4. Scaffold a "hello world" app           (railcode init … + a me() greeting)
#   5. Deploy it                              (railcode deploy — prints the live URL)
#
# By default the skill is installed non-interactively (globally) to a fixed set
# of agents: Claude Code, OpenCode, Codex, Pi, Kiro, Cursor. Login (step 3) is
# always interactive — it prints a link you approve in the browser while logged
# into Railcode. Everything else is automatic.
#
# Usage:
#   ./onboard.sh [options]
#
# Options:
#   --app <name>      App slug to scaffold + deploy (default: hello)
#   --dir <path>      Directory to scaffold the app into (default: current dir)
#   --api-url <url>   Railcode server to log in to (default: the CLI's default)
#   --agent <list>    Comma-separated agents to install the skill to (default:
#                     claude-code,opencode,codex,pi,kiro-cli,cursor). Values must
#                     be valid `skills` agent ids — note kiro's id is kiro-cli.
#   --prompt-agent    Don't pass agents; let the installer prompt (or auto-detect
#                     when it's itself run by an agent).
#   --skill-project   Install the skill per-project (into the cwd) not globally
#   --skip-skill      Skip the skill install (step 2)
#   --skip-login      Skip login even if not logged in (step 3)
#   --force-login     Re-run login even if already logged in
#   --no-deploy       Do everything except the final deploy (step 5)
#   -h, --help        Show this help and exit
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Config + defaults
# ---------------------------------------------------------------------------
APP="hello"
DIR="$PWD"
API_URL=""
AGENTS="claude-code,opencode,codex,pi,kiro-cli,cursor"
SKILL_GLOBAL=1
SKIP_SKILL=0
SKIP_LOGIN=0
FORCE_LOGIN=0
NO_DEPLOY=0

SKILL_REPO="yakkomajuri/railcode-skills"
SKILL_NAME="create-railcode-app"
CONFIG_PATH="$HOME/.railcode/config.json"

# ---------------------------------------------------------------------------
# Pretty output
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  BLUE=$'\033[34m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'
else
  BOLD=""; DIM=""; RESET=""; BLUE=""; GREEN=""; YELLOW=""; RED=""
fi

step()  { printf '\n%s%s==>%s %s%s\n' "$BOLD" "$BLUE" "$RESET" "$BOLD" "$1$RESET"; }
info()  { printf '    %s\n' "$1"; }
run()   { printf '    %s$ %s%s\n' "$DIM" "$*" "$RESET"; "$@"; }
ok()    { printf '    %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
warn()  { printf '    %s!%s %s\n' "$YELLOW" "$RESET" "$1"; }
die()   { printf '\n%s✗%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }
have()  { command -v "$1" >/dev/null 2>&1; }

# Print the leading comment block (everything from line 2 up to the first
# non-comment line), stripping the "# " prefix.
usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --app)         APP="${2:?--app needs a value}"; shift 2 ;;
    --dir)         DIR="${2:?--dir needs a value}"; shift 2 ;;
    --api-url)     API_URL="${2:?--api-url needs a value}"; shift 2 ;;
    --agent)       AGENTS="${2:?--agent needs a value}"; shift 2 ;;
    --prompt-agent) AGENTS=""; shift ;;
    --skill-project) SKILL_GLOBAL=0; shift ;;
    --skip-skill)  SKIP_SKILL=1; shift ;;
    --skip-login)  SKIP_LOGIN=1; shift ;;
    --force-login) FORCE_LOGIN=1; shift ;;
    --no-deploy)   NO_DEPLOY=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "Unknown option: $1 (see --help)" ;;
  esac
done

# App slug must be a DNS label (matches the CLI's own assertAppName).
case "$APP" in
  [a-z0-9] | [a-z0-9][a-z0-9-]*[a-z0-9]) : ;;
  *) die "Invalid app name '$APP' — use lowercase letters, digits and dashes (a DNS label)." ;;
esac

logged_in() {
  [ -f "$CONFIG_PATH" ] \
    && grep -q '"apiToken"' "$CONFIG_PATH" \
    && grep -q '"orgUuid"'  "$CONFIG_PATH"
}

printf '%sRailcode onboarding%s — CLI + skill + login + hello world + deploy\n' "$BOLD" "$RESET"
info "app: ${BOLD}${APP}${RESET}   dir: ${DIM}${DIR}${RESET}"

# ---------------------------------------------------------------------------
# 0. Prerequisites
# ---------------------------------------------------------------------------
step "Checking prerequisites"
have node || die "node is required (https://nodejs.org). Install Node 20+ and re-run."
have npm  || die "npm is required (ships with Node). Install Node 20+ and re-run."
have npx  || die "npx is required (ships with npm). Update npm and re-run."
ok "node $(node --version), npm $(npm --version)"

# ---------------------------------------------------------------------------
# 1. Install the Railcode CLI
# ---------------------------------------------------------------------------
step "1/5 · Install the Railcode CLI"
latest="$(npm view railcode version 2>/dev/null || true)"
current="$(railcode --version 2>/dev/null || true)"
if have railcode && [ -n "$latest" ] && [ "$current" = "$latest" ]; then
  ok "railcode $current already installed (latest)"
else
  if [ -n "$current" ]; then
    info "railcode $current installed; latest is ${latest:-unknown} — updating"
  fi
  run npm install -g railcode@latest
  ok "railcode $(railcode --version) installed"
fi

# ---------------------------------------------------------------------------
# 2. Install the create-railcode-app skill (interactive)
# ---------------------------------------------------------------------------
step "2/5 · Install the Railcode skill for your coding agent"
if [ "$SKIP_SKILL" -eq 1 ]; then
  warn "skipped (--skip-skill)"
else
  # `npx --yes` auto-confirms npx's own package-fetch prompt. The `skills` CLI
  # stays interactive only for the agent-selection + confirmation prompts, which
  # a `--agent` per target plus `--yes` remove. The CLI takes one --agent flag
  # per agent (a comma-joined string is rejected), so expand the list here.
  skill_cmd=(npx --yes skills add "$SKILL_REPO" --skill "$SKILL_NAME")
  if [ -n "$AGENTS" ]; then
    IFS=',' read -r -a agent_list <<< "$AGENTS" || true
    for a in "${agent_list[@]}"; do
      a="${a//[[:space:]]/}"
      [ -n "$a" ] && skill_cmd+=(--agent "$a")
    done
    skill_cmd+=(--yes)
    [ "$SKILL_GLOBAL" -eq 1 ] && skill_cmd+=(--global)
    info "Installing non-interactively → ${AGENTS}$([ "$SKILL_GLOBAL" -eq 1 ] && printf ' (global)')"
  else
    info "The installer will ask which agent / where to install it — that's expected."
    info "(--prompt-agent chosen; the default installs to a fixed agent set non-interactively.)"
  fi
  run "${skill_cmd[@]}"
  ok "skill installed"
fi

# ---------------------------------------------------------------------------
# 3. Sign in (interactive — opens your browser)
# ---------------------------------------------------------------------------
step "3/5 · Sign in"
if [ "$SKIP_LOGIN" -eq 1 ]; then
  warn "skipped (--skip-login)"
  logged_in || warn "not logged in — steps 4/5 will fail without a login"
elif logged_in && [ "$FORCE_LOGIN" -eq 0 ]; then
  ok "already logged in (pass --force-login to sign in again)"
else
  info "A link will be printed — open it in the browser where you're logged into Railcode."
  login_cmd=(railcode login)
  [ -n "$API_URL" ] && login_cmd+=(--api-url "$API_URL")
  printf '    %s$ %s%s\n' "$DIM" "${login_cmd[*]}" "$RESET"
  # `curl … | bash` leaves our stdin on the download pipe, not the terminal, and
  # `railcode login` refuses to run without a TTY. Hand it the controlling
  # terminal explicitly when we can actually open one (test the open, not just
  # -r: /dev/tty can stat readable yet fail to open with no controlling tty).
  if { : < /dev/tty; } 2>/dev/null; then
    "${login_cmd[@]}" < /dev/tty
  else
    "${login_cmd[@]}"
  fi
  logged_in || die "Login did not complete (no org on file). Finish onboarding in the web app, then re-run."
  ok "signed in"
fi

# ---------------------------------------------------------------------------
# 4. Scaffold a "hello world" app
# ---------------------------------------------------------------------------
step "4/5 · Create a hello-world app"
mkdir -p "$DIR"
APP_DIR="$DIR/$APP"
if [ -f "$APP_DIR/railcode.json" ]; then
  warn "$APP_DIR already scaffolded — reusing it"
elif [ -d "$APP_DIR" ] && [ -n "$(ls -A "$APP_DIR" 2>/dev/null)" ]; then
  die "$APP_DIR exists and is not a Railcode app. Remove it or pass --app <other-name>."
else
  ( cd "$DIR" && run railcode init "$APP" --template static )
fi

# Replace the starter index.html with the welcome app: a me() greeting that
# proves same-origin auth with zero auth code written. Mirrors the in-app
# onboarding's HELLO_INDEX_HTML exactly.
cat > "$APP_DIR/index.html" <<'HTML'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Hello</title>
    <script src="/_api/sdk.js"></script>
  </head>
  <body>
    <main style="font-family: system-ui; display: grid; place-items: center; min-height: 100dvh">
      <h1 id="greeting">Hello…</h1>
    </main>
    <script>
      me().then(({ user }) => {
        document.getElementById("greeting").textContent = `Hello, ${user.name} 👋`;
      });
    </script>
  </body>
</html>
HTML
ok "wrote $APP_DIR/index.html (me() greeting)"

# ---------------------------------------------------------------------------
# 5. Deploy
# ---------------------------------------------------------------------------
step "5/5 · Deploy"
if [ "$NO_DEPLOY" -eq 1 ]; then
  warn "skipped (--no-deploy) — deploy later with: cd \"$APP_DIR\" && railcode deploy"
else
  logged_in || die "Not logged in — can't deploy. Re-run without --skip-login."
  ( cd "$APP_DIR" && run railcode deploy )
  printf '\n%s%s✓ Done!%s Open the URL above in the browser where you'\''re logged into Railcode —\n' "$BOLD" "$GREEN" "$RESET"
  info "it should greet you by name. Next: tell your coding agent \"build me a todo app with Railcode\"."
fi
