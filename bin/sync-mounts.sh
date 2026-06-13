#!/usr/bin/env bash
# Mirror the canonical skill (`display-dev/`) to the distribution mounts:
#   skills/display-dev/                     — vercel-labs/skills (`npx skills add`)
#   hermes/productivity/display.dev/        — Hermes well-known
#   pi/agent/skills/display-dev/            — Pi coding agent (and frameworks
#                                             built on Pi, e.g. OpenClaw)
#
# Thin wrapper around bin/transform.mjs; the transformer carries the
# per-mount placeholder table and the content+mode drift check. CI runs this
# with `--check` to fail the build if a mount drifts from canonical.
#
# Usage:
#   bin/sync-mounts.sh           # write resolved mounts
#   bin/sync-mounts.sh --check   # CI gate: exit 1 if any mount drifts
#
# Source of truth is `display-dev/` only. Never edit the mounts directly —
# `sync-mounts.sh --check` will catch it.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec node "$ROOT/bin/transform.mjs" "$@"
