#!/usr/bin/env bash
source "$(dirname "$0")/_common.sh"

# Mark a comment thread resolved.
#
# Usage:
#   thread-resolve.sh --root <rootCommentId>
#
# Permission rules apply server-side: thread participant (any comment
# in the thread), artifact creator, or org admin. Anyone else → 403.

ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      if [[ $# -lt 2 ]]; then echo "thread-resolve.sh: --root requires a value" >&2; exit 1; fi
      ROOT="$2"; shift 2 ;;
    *) echo "thread-resolve.sh: unrecognized arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ROOT" ]]; then echo "thread-resolve.sh: --root is required" >&2; exit 1; fi
if printf '%s' "$ROOT" | LC_ALL=C grep -qE '[^A-Za-z0-9-]'; then
  echo "thread-resolve.sh: --root contains invalid characters" >&2; exit 1
fi

require_jq_or_exit

TOKEN=$(resolve_token)
if [[ -z "$TOKEN" ]]; then
  echo "thread-resolve.sh: not signed in (no DISPLAYDEV_API_KEY env or ~/.displaydev/config.json). Run login.sh." >&2
  exit 1
fi

RESPONSE=$(curl_api -X POST "$API_URL/v1/comments/$ROOT/resolve" \
  -H "Authorization: Bearer $TOKEN" \
  -w "\n%{http_code}" || true)
HTTP_CODE=$(printf '%s' "$RESPONSE" | tail -n 1)
BODY=$(printf '%s' "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" != "200" ]]; then
  MSG=$("$JQ" -r '.message // ""' <<<"$BODY" 2>/dev/null || printf '')
  echo "thread-resolve.sh: API returned $HTTP_CODE${MSG:+: $MSG}" >&2
  exit 1
fi

printf '%s\n' "$BODY"
