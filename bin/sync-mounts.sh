#!/usr/bin/env bash
# Copy the canonical skill mount (`display-dev/`) to the three compat
# mounts:
#   skills/display-dev/                     — vercel-labs/skills (`npx skills add`)
#   hermes/productivity/display.dev/        — Hermes well-known
#   pi/agent/skills/display-dev/            — Pi coding agent (and frameworks
#                                             built on Pi, e.g. OpenClaw)
# CI runs this with `--check` to fail the build if the mirrors drift;
# humans run it without `--check` after editing `display-dev/SKILL.md`
# or a script.
#
# Source of truth is `display-dev/` only. Never edit the mirrors
# directly — `sync-mounts.sh --check` will catch it.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CANONICAL="$ROOT/display-dev"
MIRRORS=(
  "$ROOT/skills/display-dev"
  "$ROOT/hermes/productivity/display.dev"
  "$ROOT/pi/agent/skills/display-dev"
)

MODE="write"
if [[ "${1:-}" == "--check" ]]; then
  MODE="check"
fi

drift=0
for mirror in "${MIRRORS[@]}"; do
  if [[ "$MODE" == "check" ]]; then
    if ! diff -r "$CANONICAL" "$mirror" >/dev/null 2>&1; then
      echo "drift detected: $CANONICAL → $mirror" >&2
      diff -r "$CANONICAL" "$mirror" >&2 || true
      drift=1
    fi
  else
    mkdir -p "$mirror"
    rsync -a --delete "$CANONICAL/" "$mirror/"
  fi
done

if [[ "$MODE" == "check" && $drift -ne 0 ]]; then
  echo "Run \`bin/sync-mounts.sh\` (no --check) to re-mirror." >&2
  exit 1
fi

if [[ "$MODE" == "write" ]]; then
  echo "Mirrored $CANONICAL → ${MIRRORS[*]}"
fi
