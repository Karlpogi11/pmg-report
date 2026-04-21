#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${REPO:-Karlpogi11/pmg-report}"
GH_BIN="${GH_BIN:-gh}"
AUTH_MODE=""
API_TOKEN=""
API_KEY_ID=""
API_PUBLIC_KEY=""

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command '$command_name' is not installed." >&2
    exit 1
  fi
}

require_secret_env() {
  local secret_name="$1"
  if [[ -z "${!secret_name:-}" ]]; then
    MISSING_SECRET_NAMES+=("$secret_name")
  fi
}

set_secret_with_gh() {
  local secret_name="$1"
  local secret_value="$2"
  "$GH_BIN" secret set "$secret_name" --repo "$REPO" --body "$secret_value" >/dev/null
}

get_api_token() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    printf "%s\n" "$GITHUB_TOKEN"
    return 0
  fi

  local credential_output
  credential_output="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null || true)"
  if [[ -n "$credential_output" ]]; then
    local token
    token="$(printf "%s\n" "$credential_output" | awk -F= '/^password=/{print $2; exit}')"
    if [[ -n "$token" ]]; then
      printf "%s\n" "$token"
      return 0
    fi
  fi

  return 1
}

load_repo_public_key() {
  local response_file
  response_file="$(mktemp)"
  curl -sS \
    -H "Authorization: token $API_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$REPO/actions/secrets/public-key" > "$response_file"

  read -r API_KEY_ID API_PUBLIC_KEY < <(
    python3 - "$response_file" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
print(d.get('key_id', ''), d.get('key', ''))
PY
  )
  rm -f "$response_file"

  if [[ -z "$API_KEY_ID" || -z "$API_PUBLIC_KEY" ]]; then
    echo "Failed to read repository Actions public key for $REPO." >&2
    exit 1
  fi
}

set_secret_with_api() {
  local secret_name="$1"
  local secret_value="$2"
  local payload_file response_file status

  payload_file="$(mktemp)"
  response_file="$(mktemp)"

  python3 - "$API_PUBLIC_KEY" "$API_KEY_ID" "$secret_value" > "$payload_file" <<'PY'
import base64, json, sys
from nacl.public import PublicKey, SealedBox

public_key = sys.argv[1]
key_id = sys.argv[2]
secret_value = sys.argv[3]
sealed = SealedBox(PublicKey(base64.b64decode(public_key))).encrypt(secret_value.encode())
encrypted = base64.b64encode(sealed).decode()
print(json.dumps({"encrypted_value": encrypted, "key_id": key_id}))
PY

  status="$(
    curl -sS -o "$response_file" -w '%{http_code}' \
      -X PUT \
      -H "Authorization: token $API_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: application/json" \
      --data-binary "@$payload_file" \
      "https://api.github.com/repos/$REPO/actions/secrets/$secret_name"
  )"

  rm -f "$payload_file"
  if [[ "$status" != "201" && "$status" != "204" ]]; then
    echo "Failed to set secret '$secret_name' via GitHub API (HTTP $status)." >&2
    cat "$response_file" >&2
    rm -f "$response_file"
    exit 1
  fi

  rm -f "$response_file"
}

list_configured_secrets() {
  if [[ "$AUTH_MODE" == "gh" ]]; then
    "$GH_BIN" secret list --repo "$REPO"
    return 0
  fi

  local response_file
  response_file="$(mktemp)"
  curl -sS \
    -H "Authorization: token $API_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$REPO/actions/secrets" > "$response_file"

  python3 - "$response_file" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
for secret in d.get('secrets', []):
    print(secret.get('name', ''))
PY
  rm -f "$response_file"
}

select_auth_mode() {
  if ! command -v "$GH_BIN" >/dev/null 2>&1 && [[ -x "$HOME/.local/bin/gh" ]]; then
    GH_BIN="$HOME/.local/bin/gh"
  fi

  if command -v "$GH_BIN" >/dev/null 2>&1 && "$GH_BIN" auth status >/dev/null 2>&1; then
    AUTH_MODE="gh"
    return 0
  fi

  require_command curl
  require_command python3
  if ! python3 - <<'PY' >/dev/null 2>&1
import nacl
PY
  then
    echo "Python module 'nacl' is required for API-based secret encryption." >&2
    exit 1
  fi

  if ! API_TOKEN="$(get_api_token)"; then
    echo "No GitHub auth available." >&2
    echo "Use one of these options:" >&2
    echo "1) gh auth login" >&2
    echo "2) export GITHUB_TOKEN=<token_with_repo_actions_write>" >&2
    exit 1
  fi

  AUTH_MODE="api"
  load_repo_public_key
}

MISSING_SECRET_NAMES=()
REQUIRED_SECRET_NAMES=(
  MACOS_CERTIFICATE_P12_BASE64
  MACOS_CERTIFICATE_PASSWORD
  DEVELOPER_ID_APP_IDENTITY
  APPLE_ID
  APPLE_APP_SPECIFIC_PASSWORD
  APPLE_TEAM_ID
  SPARKLE_PRIVATE_KEY_BASE64
)

for secret_name in "${REQUIRED_SECRET_NAMES[@]}"; do
  require_secret_env "$secret_name"
done

if (( ${#MISSING_SECRET_NAMES[@]} > 0 )); then
  echo "Missing environment variables for secrets: ${MISSING_SECRET_NAMES[*]}" >&2
  echo "Export them, then rerun this script." >&2
  exit 1
fi

select_auth_mode

echo "Configuring release secrets in $REPO..."
for secret_name in "${REQUIRED_SECRET_NAMES[@]}"; do
  if [[ "$AUTH_MODE" == "gh" ]]; then
    set_secret_with_gh "$secret_name" "${!secret_name}"
  else
    set_secret_with_api "$secret_name" "${!secret_name}"
  fi
done

echo "Configured secrets:"
list_configured_secrets

echo
echo "Next:"
echo "1. Commit and push workflow/script changes."
echo "2. Create and push a new tag that matches MARKETING_VERSION."
