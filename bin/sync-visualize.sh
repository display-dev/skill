#!/usr/bin/env bash
# Copy the pinned Visualize release into the Claude Code plugin.
#
# The Visualize skill is maintained in github.com/display-dev/visualize.
# The Claude Code plugin in this repo bundles one pinned release of it at
# claude/skills/visualize/. Never edit that copy by hand.
#
# Usage:
#   bin/sync-visualize.sh           # replace the copy with the pinned release
#   bin/sync-visualize.sh --check   # exit non-zero when the copy has drifted
#
# The copy comes from the release's `skills/visualize/` mount, which has its
# placeholders resolved for the vercel-labs/skills channel.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$ROOT/claude/visualize.lock"
DEST="$ROOT/claude/skills/visualize"

MODE="sync"
case "${1:-}" in
  "") ;;
  --check) MODE="check" ;;
  *) echo "usage: bin/sync-visualize.sh [--check]" >&2; exit 2 ;;
esac

read_lock() {
  grep -E "^$1=" "$LOCK" | head -n 1 | cut -d= -f2-
}
REPO="$(read_lock repo)"
TAG="$(read_lock tag)"
if [[ -z "$REPO" || -z "$TAG" ]]; then
  echo "sync-visualize: $LOCK must set repo= and tag=" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TAG" "$REPO" "$WORK/visualize"
SRC="$WORK/visualize/skills/visualize"
if [[ ! -f "$SRC/SKILL.md" ]]; then
  echo "sync-visualize: $TAG has no skills/visualize/SKILL.md" >&2
  exit 1
fi

if [[ "$MODE" == "check" ]]; then
  if ! diff -r "$SRC" "$DEST" >/dev/null 2>&1; then
    echo "sync-visualize: claude/skills/visualize/ does not match visualize $TAG." >&2
    echo "Run bin/sync-visualize.sh and commit the result." >&2
    exit 1
  fi
  echo "sync-visualize: claude/skills/visualize/ matches visualize $TAG."
  exit 0
fi

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
cp -R "$SRC" "$DEST"
echo "sync-visualize: copied visualize $TAG to claude/skills/visualize/."
