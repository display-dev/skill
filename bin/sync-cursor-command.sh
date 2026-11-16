#!/usr/bin/env bash
# Derive the Cursor plugin's /display-feedback command from the Claude Code
# plugin's /display-dev:feedback command, so the two cannot drift.
#
#   claude/commands/feedback.md  (source of truth, hand-edited)
#   cursor/commands/display-feedback.md  (generated, never hand-edited)
#
# Changes applied:
#   - frontmatter: Cursor commands need `name` and `description`; Claude's
#     `argument-hint` is dropped
#   - the `$ARGUMENTS` line: Cursor passes the user's text with the command,
#     so the command reads the artifact from that text
#   - client source: display-dev-claude-plugin@ -> display-dev-cursor-plugin@
#   - actor name: DISPLAYDEV_ACTOR_NAME=claude-code -> cursor
#
# Usage:
#   bin/sync-cursor-command.sh           # write the Cursor command
#   bin/sync-cursor-command.sh --check   # CI gate: exit 1 on drift

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/claude/commands/feedback.md"
DST="$ROOT/cursor/commands/display-feedback.md"

ARG_LINE='argument is optional: `$ARGUMENTS`'
grep -qF "$ARG_LINE" "$SRC" || { echo "error: $SRC no longer contains the \$ARGUMENTS line" >&2; exit 1; }
grep -q '^description: ' "$SRC" || { echo "error: $SRC has no description line" >&2; exit 1; }

render() {
  local description
  description="$(awk '/^---$/{n++; next} n==1 && /^description: /{sub(/^description: /, ""); print; exit}' "$SRC")"
  printf -- '---\nname: display-feedback\ndescription: %s\n---\n' "$description"
  awk '/^---$/ && n < 2 {n++; next} n >= 2' "$SRC" \
    | sed \
        -e 's/argument is optional: `\$ARGUMENTS`/artifact is optional: use the artifact URL or short ID the user gave with the command, if any./' \
        -e 's/display-dev-claude-plugin@/display-dev-cursor-plugin@/g' \
        -e 's/DISPLAYDEV_ACTOR_NAME=claude-code/DISPLAYDEV_ACTOR_NAME=cursor/g'
}

if [[ "${1:-}" == "--check" ]]; then
  if ! diff -u "$DST" <(render) >&2; then
    echo "Cursor command drift. Run \`bin/sync-cursor-command.sh\` to regenerate." >&2
    exit 1
  fi
  echo "OK · cursor/commands/display-feedback.md matches claude/commands/feedback.md"
elif [[ $# -eq 0 ]]; then
  mkdir -p "$(dirname "$DST")"
  render > "$DST"
  echo "✓ Cursor command → cursor/commands/display-feedback.md"
else
  echo "Unknown argument: $1" >&2
  exit 1
fi
