#!/usr/bin/env bash
source "$(dirname "$0")/_common.sh"

# Tier-1 hot path covers two invocations on OTP-authenticated orgs:
#   login.sh --email <email>             (preflight + request OTP)
#   login.sh --email <email> --code <c>  (preflight + verify + write ~/.displaydev/config.json)
# SSO-required orgs (auth-check returns method='sso') and any other flag
# (--api-key <key>, --list, etc.) fall through to `dsp login` — bash
# cannot drive the device-code flow.

EMAIL=""; CODE=""; EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --email)
      if [[ $# -lt 2 ]]; then echo "login.sh: --email requires a value" >&2; exit 1; fi
      EMAIL="$2"; shift 2 ;;
    --code)
      if [[ $# -lt 2 ]]; then echo "login.sh: --code requires a value" >&2; exit 1; fi
      CODE="$2"; shift 2 ;;
    *) EXTRA+=("$1"); shift ;;
  esac
done

if [[ ${#EXTRA[@]} -gt 0 ]] || [[ -z "$EMAIL" ]]; then
  require_dsp_or_exit
  exec $DSP_CMD login --client-source "$CLIENT_SOURCE" "${EXTRA[@]}" \
    ${EMAIL:+--email "$EMAIL"} ${CODE:+--code "$CODE"}
fi

require_jq_or_exit

# Auth-check preflight runs on BOTH arms (send and verify) so SSO orgs
# route to `dsp login` regardless of which arm the user invoked.
# `|| true` on every curl substitution is load-bearing: without it a
# network failure under `set -e` would abort before the explicit error
# handling. With it, curl's stderr (already unsilenced by `-sS`)
# surfaces the network error, and the HTTP_CODE check either falls
# through to OTP (preflight) or surfaces a clean "API returned <code>"
# message (send / verify).
CHECK_BODY_REQ=$("$JQ" -nc --arg email "$EMAIL" '{email: $email}')
CHECK_RESPONSE=$(curl_api -X POST "$API_URL/v1/cli/auth-check" \
  -H "Content-Type: application/json" \
  -d "$CHECK_BODY_REQ" -w "\n%{http_code}" || true)
CHECK_HTTP=$(printf '%s' "$CHECK_RESPONSE" | tail -n 1)
if [[ "$CHECK_HTTP" == "200" ]]; then
  CHECK_BODY=$(printf '%s' "$CHECK_RESPONSE" | sed '$d')
  METHOD=$("$JQ" -r '.method // ""' <<<"$CHECK_BODY" 2>/dev/null || printf '')
  if [[ "$METHOD" == "sso" ]]; then
    require_dsp_or_exit
    exec $DSP_CMD login --client-source "$CLIENT_SOURCE" \
      --email "$EMAIL" ${CODE:+--code "$CODE"}
  fi
fi
# Preflight failed (network/5xx) or returned non-sso method → continue OTP flow.

if [[ -z "$CODE" ]]; then
  # Step 1: send OTP.
  SEND_BODY=$("$JQ" -nc --arg email "$EMAIL" '{email: $email, type: "sign-in"}')
  RESPONSE=$(curl_api -X POST "$API_URL/api/auth/email-otp/send-verification-otp" \
    -H "Content-Type: application/json" \
    -d "$SEND_BODY" -w "\n%{http_code}" || true)
  HTTP_CODE=$(printf '%s' "$RESPONSE" | tail -n 1)
  if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "204" ]]; then
    BODY=$(printf '%s' "$RESPONSE" | sed '$d')
    MSG=$("$JQ" -r '.message // ""' <<<"$BODY" 2>/dev/null || printf '')
    echo "login.sh: OTP send failed ($HTTP_CODE)${MSG:+: $MSG}" >&2
    exit 1
  fi
  echo "Code sent to $EMAIL. Re-run with: login.sh --email $EMAIL --code <code>" >&2
  exit 0
fi

# Step 2: verify.
VERIFY_BODY=$("$JQ" -nc --arg email "$EMAIL" --arg otp "$CODE" '{email: $email, otp: $otp}')
RESPONSE=$(curl_api -X POST "$API_URL/api/auth/sign-in/email-otp" \
  -H "Content-Type: application/json" \
  -d "$VERIFY_BODY" -w "\n%{http_code}" || true)
HTTP_CODE=$(printf '%s' "$RESPONSE" | tail -n 1)
BODY=$(printf '%s' "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" != "200" ]]; then
  MSG=$("$JQ" -r '.message // ""' <<<"$BODY" 2>/dev/null || printf '')
  echo "login.sh: verify failed ($HTTP_CODE)${MSG:+: $MSG}" >&2
  exit 1
fi

TOKEN=$("$JQ" -r '.token // empty' <<<"$BODY" 2>/dev/null || printf '')
if [[ -z "$TOKEN" ]]; then
  echo "login.sh: verify succeeded but response missing token" >&2
  exit 1
fi

# Atomic write: tmp + rename + chmod 600 on the file, mirroring the
# CLI's config writer. The additional `chmod 700` on the parent dir is
# a bash-side defense-in-depth addition; the CLI relies on the default
# umask there. JSON encoded via jq so token/apiUrl with any character
# survive verbatim.
CONFIG_DIR="$HOME/.displaydev"
CONFIG_PATH="$CONFIG_DIR/config.json"
TMP_PATH="$CONFIG_PATH.tmp"
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
( umask 077 && "$JQ" -n --arg token "$TOKEN" --arg apiUrl "$API_URL" '{token: $token, apiUrl: $apiUrl}' > "$TMP_PATH" )
mv "$TMP_PATH" "$CONFIG_PATH"
chmod 600 "$CONFIG_PATH"

echo "Signed in as $EMAIL." >&2
