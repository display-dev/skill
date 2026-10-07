#!/usr/bin/env bash
# PreToolUse hook: scan display.dev publishes for secrets before they run.
#
# Handles two tool shapes:
#   - Bash commands that run `dsp publish` or the skill's publish.sh: scans
#     each existing file argument.
#   - The display.dev MCP `publish` tool: scans the inline `content` field.
#     An `upload_id` publish cannot be scanned and is allowed.
#
# Decision when a secret is found:
#   - deny  when the publish is public, or could be public (publish.sh with
#           no --visibility can publish anonymously; an MCP update with no
#           visibility keeps the current one, which can be public);
#   - ask   for every other publish.
# No secret, or anything the guard cannot parse: no output, publish proceeds.
# The guard never prints the matched value.
#
# Output contract: Claude Code PreToolUse hookSpecificOutput JSON on stdout.

set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Reuse the skill's bundled-jq resolution. _common.sh enables `set -e`;
# turn it off again so a parse failure cannot block the user's tool call.
# shellcheck source=../../display-dev/scripts/_common.sh
source "$PLUGIN_ROOT/display-dev/scripts/_common.sh"
set +e
[[ -n "$JQ" ]] || exit 0

INPUT="$(cat)"
TOOL="$(printf '%s' "$INPUT" | "$JQ" -r '.tool_name // empty' 2>/dev/null)"
CWD="$(printf '%s' "$INPUT" | "$JQ" -r '.cwd // empty' 2>/dev/null)"
[[ -n "$CWD" && -d "$CWD" ]] || CWD="$PWD"

# Label|extended regex. Narrow, high-confidence token shapes only.
SECRET_PATTERNS=(
  'a private key|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----'
  'an AWS access key|(AKIA|ASIA)[0-9A-Z]{16}'
  'a GitHub token|(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,})'
  'a GitLab token|glpat-[A-Za-z0-9_-]{20,}'
  'a Slack token|xox[abprs]-[A-Za-z0-9-]{10,}'
  'a live Stripe or display.dev key|(sk|rk)_live_[A-Za-z0-9]{16,}'
  'an Anthropic API key|sk-ant-[A-Za-z0-9_-]{20,}'
  'an OpenAI API key|(sk-proj-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{48})'
  'a Google API key|AIza[0-9A-Za-z_-]{35}'
)

# Print the label of the first secret pattern found on stdin, if any.
find_secret() {
  local data entry
  data="$(cat)"
  for entry in "${SECRET_PATTERNS[@]}"; do
    if printf '%s' "$data" | LC_ALL=C grep -qE -- "${entry#*|}"; then
      printf '%s' "${entry%%|*}"
      return 0
    fi
  done
  return 1
}

decide() {
  # $1 = deny|ask, $2 = reason
  "$JQ" -n --arg d "$1" --arg r "$2" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: $d,
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# Split a shell command into words without expanding anything. Handles
# single quotes, double quotes, and backslash escapes. Never evaluates.
split_words() {
  local s="$1" word="" in_word=0 quote="" c i
  WORDS=()
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    if [[ -n "$quote" ]]; then
      if [[ "$c" == "$quote" ]]; then
        quote=""
      elif [[ "$quote" == '"' && "$c" == '\' && $((i + 1)) -lt ${#s} ]]; then
        i=$((i + 1)); word+="${s:i:1}"
      else
        word+="$c"
      fi
      continue
    fi
    case "$c" in
      "'"|'"') quote="$c"; in_word=1 ;;
      '\')
        if (( i + 1 < ${#s} )); then i=$((i + 1)); word+="${s:i:1}"; in_word=1; fi ;;
      ' '|$'\t'|$'\n'|';'|'&'|'|'|'('|')')
        if (( in_word )); then WORDS+=("$word"); word=""; in_word=0; fi ;;
      *) word+="$c"; in_word=1 ;;
    esac
  done
  if (( in_word )); then WORDS+=("$word"); fi
}

guard_bash() {
  local cmd w i path label visibility="" helper=0 is_publish=0 prev=""
  cmd="$(printf '%s' "$INPUT" | "$JQ" -r '.tool_input.command // empty' 2>/dev/null)"
  [[ -n "$cmd" ]] || exit 0
  split_words "$cmd"

  for (( i = 0; i < ${#WORDS[@]}; i++ )); do
    w="${WORDS[i]}"
    if [[ "$w" == */publish.sh || "$w" == publish.sh ]]; then
      is_publish=1; helper=1
    elif [[ "$w" == publish && "$prev" == dsp ]]; then
      is_publish=1
    elif [[ "$w" == publish && $is_publish -eq 0 ]]; then
      # `dsp --client-source x publish`: dsp appears earlier in the words.
      for (( j = 0; j < i; j++ )); do
        [[ "${WORDS[j]}" == dsp || "${WORDS[j]}" == */dsp ]] && is_publish=1
      done
    fi
    if [[ "$w" == --visibility=* ]]; then
      visibility="${w#--visibility=}"
    elif [[ "$prev" == --visibility ]]; then
      visibility="$w"
    fi
    prev="$w"
  done
  (( is_publish )) || exit 0

  for w in "${WORDS[@]}"; do
    [[ "$w" == -* ]] && continue
    if [[ "$w" == /* ]]; then path="$w"; else path="$CWD/$w"; fi
    [[ -f "$path" && -r "$path" ]] || continue
    case "$path" in
      *.html|*.htm|*.md|*.markdown|*.txt|*.json|*.csv|*.svg) ;;
      *) continue ;;
    esac
    if label="$(find_secret < "$path")"; then
      if [[ "$visibility" == public ]]; then
        decide deny "display.dev publish guard: $w contains what looks like $label, and this publish is public. Remove the secret before you publish."
      elif [[ $helper -eq 1 && -z "$visibility" ]]; then
        decide deny "display.dev publish guard: $w contains what looks like $label. publish.sh without --visibility can create a public anonymous artifact. Remove the secret, or publish with --visibility private."
      else
        decide ask "display.dev publish guard: $w contains what looks like $label. Publish it anyway?"
      fi
    fi
  done
  exit 0
}

guard_mcp() {
  local visibility short_id label
  visibility="$(printf '%s' "$INPUT" | "$JQ" -r '.tool_input.visibility // empty' 2>/dev/null)"
  short_id="$(printf '%s' "$INPUT" | "$JQ" -r '.tool_input.short_id // empty' 2>/dev/null)"
  label="$(printf '%s' "$INPUT" | "$JQ" -r '.tool_input.content // empty' 2>/dev/null | find_secret)" || exit 0
  if [[ "$visibility" == public ]]; then
    decide deny "display.dev publish guard: the content contains what looks like $label, and this publish is public. Remove the secret before you publish."
  elif [[ -n "$short_id" && -z "$visibility" ]]; then
    decide deny "display.dev publish guard: the content contains what looks like $label. This update keeps the artifact's current visibility, which can be public. Remove the secret, or set visibility to private."
  else
    decide ask "display.dev publish guard: the content contains what looks like $label. Publish it anyway?"
  fi
}

case "$TOOL" in
  Bash) guard_bash ;;
  mcp__*__publish) guard_mcp ;;
esac
exit 0
