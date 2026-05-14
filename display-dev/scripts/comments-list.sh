#!/usr/bin/env bash
source "$(dirname "$0")/_common.sh"

# One-shot list of comment threads on an artifact. Mirrors the wire
# shape of `GET /v1/artifacts/:shortId/comments` exactly — the response
# body is written to stdout as a single JSON object with `data`,
# `nextCursor`, and `totalCount` keys (see ListCommentsResponseDto on
# the server). Non-2xx exits with the error message on stderr.
#
# Usage:
#   comments-list.sh --artifact <shortId> [--since <iso>] [--status open|resolved|all]
#
# Defaults: --status open (server-side default).

ARTIFACT=""; SINCE=""; STATUS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact)
      if [[ $# -lt 2 ]]; then echo "comments-list.sh: --artifact requires a value" >&2; exit 1; fi
      ARTIFACT="$2"; shift 2 ;;
    --since)
      if [[ $# -lt 2 ]]; then echo "comments-list.sh: --since requires a value" >&2; exit 1; fi
      SINCE="$2"; shift 2 ;;
    --status)
      if [[ $# -lt 2 ]]; then echo "comments-list.sh: --status requires a value" >&2; exit 1; fi
      STATUS="$2"; shift 2 ;;
    *) echo "comments-list.sh: unrecognized arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ARTIFACT" ]]; then
  echo "comments-list.sh: --artifact is required" >&2; exit 1
fi

require_jq_or_exit

# Reject characters that don't appear in real shortIds — the value is
# interpolated into the URL path. shortIds are nanoid-shaped
# (alphanumeric + `-`, `_`), so anything outside that set is either a
# typo or an attempt to break out of the path segment.
if printf '%s' "$ARTIFACT" | LC_ALL=C grep -qE '[^A-Za-z0-9_-]'; then
  echo "comments-list.sh: --artifact contains invalid characters" >&2; exit 1
fi

TOKEN=$(resolve_token)
if [[ -z "$TOKEN" ]]; then
  echo "comments-list.sh: not signed in (no DISPLAYDEV_API_KEY env or ~/.displaydev/config.json). Run login.sh." >&2
  exit 1
fi

QS=""
if [[ -n "$SINCE" ]]; then
  # ISO-8601 charset: digits + `T`/`Z` + punctuation. The server
  # @IsISO8601() validates the actual format; this regex just rejects
  # shell/URL metacharacters so we don't ship a malformed query string.
  if printf '%s' "$SINCE" | LC_ALL=C grep -qE '[^0-9A-Za-z:.+-]'; then
    echo "comments-list.sh: --since contains invalid characters (expected ISO-8601)" >&2; exit 1
  fi
  # `+` in a URL query is decoded as space by some parsers — encode it
  # explicitly so timezone offsets like `+02:00` survive the wire.
  SINCE_ENC="${SINCE//+/%2B}"
  QS="${QS}&since=$SINCE_ENC"
fi
if [[ -n "$STATUS" ]]; then
  case "$STATUS" in
    open|resolved|all) ;;
    *) echo "comments-list.sh: --status must be open|resolved|all" >&2; exit 1 ;;
  esac
  QS="${QS}&status=$STATUS"
fi
QS="${QS#&}"

RESPONSE=$(curl_api \
  -H "Authorization: Bearer $TOKEN" \
  "$API_URL/v1/artifacts/$ARTIFACT/comments${QS:+?$QS}" \
  -w "\n%{http_code}" || true)
HTTP_CODE=$(printf '%s' "$RESPONSE" | tail -n 1)
BODY=$(printf '%s' "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" != "200" ]]; then
  MSG=$("$JQ" -r '.message // ""' <<<"$BODY" 2>/dev/null || printf '')
  echo "comments-list.sh: API returned $HTTP_CODE${MSG:+: $MSG}" >&2
  exit 1
fi

printf '%s\n' "$BODY"
