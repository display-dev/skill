#!/usr/bin/env bash
# Sourced by the other scripts. Resolves jq, dsp invocation, attribution,
# and the helpers used by the Tier-1 bash hot path.

set -euo pipefail

# Consumed by publish.sh and login.sh after sourcing this file. ShellCheck
# can't follow into the sourcers, so silence its unused-variable warning
# rather than `export`-ing (we don't want API_URL leaking into child curl
# processes' environment — it's a shell-scope helper, not an env contract).
# shellcheck disable=SC2034
API_URL="${DISPLAYDEV_API_URL:-https://api.display.dev}"

# Resolve the bundled jq binary for the current platform. The skill
# ships statically-linked jq 1.7.1 binaries for the five common
# platforms (macOS/Linux on amd64/arm64 plus Windows amd64) — see
# bin/jq-* and the SHA-verified manifest at
# https://github.com/jqlang/jq/releases/tag/jq-1.7.1. Falls through to
# a system jq on PATH if no bundled binary matches the current host
# (BSD, Alpine on ARM, NixOS, etc).
SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
JQ=""
case "$(uname -s)/$(uname -m)" in
  Darwin/arm64)              JQ="$SKILL_ROOT/bin/jq-macos-arm64" ;;
  Darwin/x86_64)             JQ="$SKILL_ROOT/bin/jq-macos-amd64" ;;
  Linux/x86_64|Linux/amd64)  JQ="$SKILL_ROOT/bin/jq-linux-amd64" ;;
  Linux/aarch64|Linux/arm64) JQ="$SKILL_ROOT/bin/jq-linux-arm64" ;;
  MINGW*/*|MSYS*/*|CYGWIN*/*) JQ="$SKILL_ROOT/bin/jq-windows-amd64.exe" ;;
esac
if [[ -z "$JQ" || ! -x "$JQ" ]]; then
  JQ="$(command -v jq 2>/dev/null || true)"
fi

DSP_CMD=${DSP_CMD:-}
if [[ -z "$DSP_CMD" ]]; then
  if command -v dsp >/dev/null 2>&1; then
    DSP_CMD="dsp"
  elif command -v npx >/dev/null 2>&1; then
    DSP_CMD="npx -y @displaydev/cli"
  else
    DSP_CMD=""  # neither available — Tier-2 wrappers call require_dsp_or_exit
  fi
fi

# Skill version. Bump in lockstep with the git tag on every release —
# this value flows into `CLIENT_SOURCE` below as
# `display-dev-skill@<version>` and is read by display.dev's analytics
# to attribute publish events to a specific skill release. Set
# `SKILL_VERSION_OVERRIDE` to test attribution locally without retagging.
SKILL_VERSION="${SKILL_VERSION_OVERRIDE:-0.1.0}"

# Attribution: env var > skill default. Same value is sent as the CLI's
# `--client-source` flag (Tier 2) or the curl `X-Client-Source` header
# (Tier 1), so funnel attribution is symmetric across both invocation
# paths.
CLIENT_SOURCE="${DISPLAYDEV_CLIENT_SOURCE:-display-dev-skill@${SKILL_VERSION}}"

# Tier-2 helper: print install hint and exit if neither dsp nor npx exists.
require_dsp_or_exit() {
  if [[ -z "$DSP_CMD" ]]; then
    echo "This command needs the display.dev CLI. Install with:" >&2
    echo "  npm install -g @displaydev/cli" >&2
    echo "Or see https://display.dev/docs/skill for MCP and other options." >&2
    exit 1
  fi
}

# JSON helper: every script that touches API response bodies (or encodes
# request bodies) needs jq. The skill bundles jq for the five common
# platforms; if a script lands on an exotic uname/uname-m combination
# where the bundle doesn't match AND `jq` isn't on PATH, this surfaces
# a clear install hint instead of a cryptic "command not found".
require_jq_or_exit() {
  if [[ -z "$JQ" ]]; then
    echo "$(basename "${0:-jq}"): jq is required for this command and the bundled binary for $(uname -s)/$(uname -m) didn't apply." >&2
    echo "The skill ships jq for macOS/Linux/Windows on amd64/arm64. For other platforms:" >&2
    echo "  macOS:         brew install jq" >&2
    echo "  Debian/Ubuntu: apt-get install jq" >&2
    echo "  Alpine:        apk add jq" >&2
    echo "  Arch:          pacman -S jq" >&2
    exit 1
  fi
}

# Tier-1 helper: wrap curl to add attribution headers consistently.
# X-Actor-Name / X-Actor-Type are conditional pass-throughs from the
# matching env vars. They are part of a planned actor-attribution
# surface — today the server does not yet consume them on the comments
# path (audit rows still attribute to the credential owner). The
# helpers forward them so the wire is ready when the rollout lands;
# until then the load-bearing agent-vs-human signal is the body
# sentinel (`comment-reply.sh` + `comments-stream.sh`). X-Client-Source
# is always sent.
curl_api() {
  curl -sS \
    -H "X-Client-Type: cli" \
    -H "X-Client-Source: $CLIENT_SOURCE" \
    ${DISPLAYDEV_ACTOR_NAME:+-H "X-Actor-Name: $DISPLAYDEV_ACTOR_NAME"} \
    ${DISPLAYDEV_ACTOR_TYPE:+-H "X-Actor-Type: $DISPLAYDEV_ACTOR_TYPE"} \
    "$@"
}

# Resolve the bearer token used by authenticated endpoints. Precedence
# matches the CLI's `resolveAuth`: env var DISPLAYDEV_API_KEY wins over
# the persisted config file. Prints the token to stdout, or empty
# string if neither source is configured — callers check `[[ -z ]]` and
# surface their own "run login.sh first" hint.
resolve_token() {
  if [[ -n "${DISPLAYDEV_API_KEY:-}" ]]; then
    printf '%s' "$DISPLAYDEV_API_KEY"
    return 0
  fi
  if [[ -r "$HOME/.displaydev/config.json" ]]; then
    require_jq_or_exit
    "$JQ" -r '.token // empty' "$HOME/.displaydev/config.json" 2>/dev/null || printf ''
    return 0
  fi
  printf ''
}
