#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/display-dev-skill-tests.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

SYSTEM_PATH="/usr/bin:/bin"
WITH_DSP="$ROOT/tests/fixtures/with-dsp"
NO_DSP="$ROOT/tests/fixtures/no-dsp"
ANONYMOUS="$ROOT/tests/fixtures/anonymous"
WANT_VERSION="$(grep SKILL_VERSION_OVERRIDE "$ROOT/display-dev/scripts/_common.sh" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
EXPECTED_CLIENT_SOURCE="display-dev-skill@$WANT_VERSION"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$*"
}

assert_rejected_without_request() {
  local label="$1"
  local path="$2"
  rm -f "$TMP_DIR/curl-args"
  if env \
    HOME="$TMP_DIR/home" \
    PATH="$ANONYMOUS:$SYSTEM_PATH" \
    FAKE_CURL_ARGS="$TMP_DIR/curl-args" \
    "$ROOT/display-dev/scripts/publish.sh" "$path" \
    > "$TMP_DIR/rejected.out" 2> "$TMP_DIR/rejected.err"; then
    fail "$label was accepted"
  fi
  [[ ! -e "$TMP_DIR/curl-args" ]] || fail "$label sent a request"
}

mkdir -p "$TMP_DIR/home" "$TMP_DIR/files"

# A real executable wins over an exported function, and every argument reaches
# it byte-for-byte. Inherited command strings are inert, and the CLI sees the
# caller's DISPLAYDEV_API_URL unchanged.
export FAKE_DSP_FUNCTION_MARKER="$TMP_DIR/function-ran"
dsp() {
  printf 'unexpected shell-function execution\n' > "$FAKE_DSP_FUNCTION_MARKER"
  return 98
}
export -f dsp

WEIRD_ARGS=(
  'space value'
  'quote"value'
  '$HOME'
  'semi;colon'
  '*.md'
)

env \
  PATH="$WITH_DSP:$SYSTEM_PATH" \
  DSP_CMD="touch $TMP_DIR/command-string-ran" \
  DISPLAYDEV_API_URL="https://example.invalid/custom" \
  FAKE_DSP_ARGS="$TMP_DIR/dsp-args" \
  FAKE_DSP_API_URL="$TMP_DIR/dsp-api-url" \
  "$ROOT/display-dev/scripts/login.sh" "${WEIRD_ARGS[@]}"

{
  printf '%s\0' login --client-source "$EXPECTED_CLIENT_SOURCE"
  printf '%s\0' "${WEIRD_ARGS[@]}"
} > "$TMP_DIR/expected-dsp-args"

cmp "$TMP_DIR/expected-dsp-args" "$TMP_DIR/dsp-args" >/dev/null \
  || fail 'installed dsp did not receive literal argv values'
[[ "$(< "$TMP_DIR/dsp-api-url")" == 'https://example.invalid/custom' ]] \
  || fail 'DISPLAYDEV_API_URL changed before dsp execution'
[[ ! -e "$TMP_DIR/function-ran" ]] || fail 'exported dsp shell function ran'
[[ ! -e "$TMP_DIR/command-string-ran" ]] || fail 'DSP_CMD was executed'
pass 'installed dsp path and literal argv forwarding'

# A visible npx executable is deliberately ignored when dsp is unavailable.
if env \
  PATH="$NO_DSP:$SYSTEM_PATH" \
  FAKE_NPX_MARKER="$TMP_DIR/npx-ran" \
  "$ROOT/display-dev/scripts/login.sh" --email person@example.com --json \
  > "$TMP_DIR/missing.out" 2> "$TMP_DIR/missing.err"; then
  fail 'missing dsp unexpectedly succeeded'
fi
grep -q 'installed display.dev CLI' "$TMP_DIR/missing.err" \
  || fail 'missing-dsp message omitted installed CLI guidance'
grep -q 'MCP' "$TMP_DIR/missing.err" \
  || fail 'missing-dsp message omitted MCP guidance'
[[ ! -e "$TMP_DIR/npx-ran" ]] || fail 'npx ran as a fallback'
pass 'missing dsp stops without npx'

# The anonymous path accepts spaces, stays on the fixed endpoint, and sends no
# authorization header.
SAFE_FILE="$TMP_DIR/files/safe report.html"
printf '<h1>safe</h1>\n' > "$SAFE_FILE"
env \
  HOME="$TMP_DIR/home" \
  PATH="$ANONYMOUS:$SYSTEM_PATH" \
  FAKE_CURL_ARGS="$TMP_DIR/curl-args" \
  "$ROOT/display-dev/scripts/publish.sh" "$SAFE_FILE" \
  > "$TMP_DIR/publish.out" 2> "$TMP_DIR/publish.err"
grep -Fx -- 'https://api.display.dev/v1/public/artifacts' "$TMP_DIR/curl-args" >/dev/null \
  || fail 'anonymous publish did not use the fixed endpoint'
grep -Fx -- "file=@$SAFE_FILE" "$TMP_DIR/curl-args" >/dev/null \
  || fail 'safe path with spaces was not forwarded literally'
if grep -i 'authorization' "$TMP_DIR/curl-args" >/dev/null; then
  fail 'anonymous publish sent an authorization header'
fi
grep -q '"shortId":"abc12345"' "$TMP_DIR/publish.out" \
  || fail 'anonymous publish did not return the response body'
pass 'anonymous publish accepts a safe path with spaces'

# Credentials force the CLI path. The raw anonymous curl path must not run,
# and publish's full argv must still be forwarded literally.
rm -f "$TMP_DIR/tier2-curl-args"
env \
  HOME="$TMP_DIR/home" \
  PATH="$WITH_DSP:$ANONYMOUS:$SYSTEM_PATH" \
  DISPLAYDEV_API_KEY='test-only-key' \
  FAKE_DSP_ARGS="$TMP_DIR/tier2-dsp-args" \
  FAKE_DSP_API_URL="$TMP_DIR/tier2-dsp-api-url" \
  FAKE_CURL_ARGS="$TMP_DIR/tier2-curl-args" \
  "$ROOT/display-dev/scripts/publish.sh" "$SAFE_FILE" --name 'name with spaces' --visibility company
{
  printf '%s\0' publish --client-source "$EXPECTED_CLIENT_SOURCE"
  printf '%s\0' "$SAFE_FILE" --name 'name with spaces' --visibility company
} > "$TMP_DIR/expected-tier2-dsp-args"
cmp "$TMP_DIR/expected-tier2-dsp-args" "$TMP_DIR/tier2-dsp-args" >/dev/null \
  || fail 'authenticated publish did not forward literal argv to dsp'
[[ ! -e "$TMP_DIR/tier2-curl-args" ]] \
  || fail 'authenticated publish invoked the anonymous curl path'
pass 'credentialed publish routes only through installed dsp'

QUOTE_FILE="$TMP_DIR/files/quote\"name.html"
SEMICOLON_FILE="$TMP_DIR/files/semi;name.html"
COMMA_FILE="$TMP_DIR/files/comma,name.html"
CONTROL_FILE="$TMP_DIR/files/control
name.html"
printf 'x' > "$QUOTE_FILE"
printf 'x' > "$SEMICOLON_FILE"
printf 'x' > "$COMMA_FILE"
printf 'x' > "$CONTROL_FILE"

assert_rejected_without_request 'unreadable path' "$TMP_DIR/files/missing.html"
assert_rejected_without_request 'exact dash path' '-'
assert_rejected_without_request 'quote path' "$QUOTE_FILE"
assert_rejected_without_request 'semicolon path' "$SEMICOLON_FILE"
assert_rejected_without_request 'comma path' "$COMMA_FILE"
assert_rejected_without_request 'control-character path' "$CONTROL_FILE"
pass 'anonymous filename rejections send no request'

# Static trust-boundary guards.
if grep -R -n -I -F 'npx -y @displaydev/cli' "$ROOT/display-dev/scripts"; then
  fail 'runtime npx fallback remains in canonical scripts'
fi
if grep -R -n -I -F 'DSP_CMD' "$ROOT/display-dev/scripts"; then
  fail 'DSP_CMD remains in canonical scripts'
fi
if grep -R -n -I -E 'Authorization:[[:space:]]*(Bearer)?' "$ROOT/display-dev/scripts"; then
  fail 'canonical scripts construct an Authorization header'
fi

INSTALL_TREES=(
  "$ROOT/display-dev"
  "$ROOT/skills/display-dev"
  "$ROOT/hermes/productivity/display.dev"
  "$ROOT/pi/agent/skills/display-dev"
  "$ROOT/codex/display-dev/skills/display-dev"
)
if grep -R -n -I -E '\{\{[^}]*\}\}' "${INSTALL_TREES[@]}"; then
  fail 'an installable skill tree contains an unresolved placeholder'
fi

DESCRIPTION="$(awk '
  /^description:[[:space:]]*>[[:space:]]*$/ { in_description = 1; next }
  in_description && /^---[[:space:]]*$/ { exit }
  in_description { sub(/^[[:space:]]+/, ""); printf "%s ", $0 }
' "$ROOT/display-dev/SKILL.md")"
[[ -n "${DESCRIPTION//[[:space:]]/}" ]] || fail 'frontmatter description is empty'
[[ ${#DESCRIPTION} -le 1024 ]] \
  || fail "frontmatter description exceeds 1024 characters (${#DESCRIPTION})"

grep -F 'https://api.display.dev/v1/public/artifacts' "$ROOT/display-dev/SKILL.md" >/dev/null \
  || fail 'standalone skill omits the fixed anonymous endpoint'
grep -F '[[ $# -ne 1 ]]' "$ROOT/display-dev/SKILL.md" >/dev/null \
  || fail 'standalone recipe omits the exactly-one-file check'
grep -F '[[ "$file" == "-" || ! -r "$file" ]]' "$ROOT/display-dev/SKILL.md" >/dev/null \
  || fail 'standalone recipe omits readable-file or exact-dash checks'
grep -F '[[ "$file" == *'"'"'"'"'"'* || "$file" == *'"'"';'"'"'* || "$file" == *'"'"','"'"'* || "$file" =~ [[:cntrl:]] ]]' "$ROOT/display-dev/SKILL.md" >/dev/null \
  || fail 'standalone recipe omits filename character checks'
grep -F 'curl -sS -X POST' "$ROOT/display-dev/SKILL.md" >/dev/null \
  || fail 'standalone anonymous publishing still requires packaged scripts'

REQUIRED_ARTIFACT_WORKFLOW=(
  'dsp list --client-source'
  'dsp search --client-source'
  'dsp get-metadata --client-source'
  'dsp read --client-source'
  'dsp edit --client-source'
  'edit { short_id, base_version, old_text, new_text }'
  'Remote MCP intentionally has'
)
for instruction in "${REQUIRED_ARTIFACT_WORKFLOW[@]}"; do
  grep -F "$instruction" "$ROOT/display-dev/SKILL.md" >/dev/null \
    || fail "standalone skill omits artifact workflow instruction: $instruction"
done
if grep -F 'fetch/export, reconcile' "$ROOT/display-dev/SKILL.md" >/dev/null; then
  fail 'standalone skill still teaches the old export-first recovery workflow'
fi
pass 'artifact read, search, metadata, and exact-edit workflow'

SKILL_SOURCE_VERSIONS="$(grep -oE 'display-dev-skill@[0-9]+\.[0-9]+\.[0-9]+' "$ROOT/display-dev/SKILL.md" | sort -u)"
[[ "$SKILL_SOURCE_VERSIONS" == "display-dev-skill@$WANT_VERSION" ]] \
  || fail "standalone skill attribution version is '$SKILL_SOURCE_VERSIONS' (want display-dev-skill@$WANT_VERSION)"
pass 'static trust-boundary invariants'
