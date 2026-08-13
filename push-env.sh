#!/usr/bin/env bash
# Push secrets from .env into the running OpenClaw service on Railway.
#
# Telegram/OpenRouter credentials live in openclaw.json on the /data volume,
# not in Railway env vars, so these are applied via `openclaw config set`
# over `railway ssh` and survive redeploys.
#
# Usage: ./push-env.sh

set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "No .env file found. Copy the template and fill it in first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

changed=0

apply() {
  local path="$1" value="$2" label="$3"
  echo "Setting ${label}..."
  railway ssh -- openclaw config set "$path" "$value" >/dev/null
  changed=1
}

if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  # Validate against Telegram before writing, so a bad paste fails loudly here
  # rather than as a 401 restart loop in the deploy logs.
  resp=$(curl -sS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe")
  if ! grep -q '"ok":true' <<<"$resp"; then
    echo "Telegram rejected that token:" >&2
    echo "  $resp" >&2
    exit 1
  fi
  username=$(sed -n 's/.*"username":"\([^"]*\)".*/\1/p' <<<"$resp")
  echo "Telegram token valid — bot is @${username}"
  apply channels.telegram.botToken "$TELEGRAM_BOT_TOKEN" "Telegram bot token"
  apply channels.telegram.enabled true "Telegram channel enabled"
fi

if [[ -n "${TELEGRAM_OWNER_ID:-}" ]]; then
  # Order matters: the schema rejects dmPolicy=allowlist while allowFrom is empty,
  # so populate the allowlist first. Bracket notation avoids passing a quoted JSON
  # array through `railway ssh`, which strips the inner quotes.
  apply "channels.telegram.allowFrom[0]" "$TELEGRAM_OWNER_ID" "Telegram owner allowlist"
  apply channels.telegram.dmPolicy allowlist "Telegram DM policy"
fi

if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
  echo "Rotating OpenRouter API key..."
  railway variable set --skip-deploys "OPENROUTER_API_KEY=${OPENROUTER_API_KEY}" >/dev/null
  changed=1
fi

if [[ "$changed" -eq 0 ]]; then
  echo "Nothing to do — every value in .env is blank."
  exit 0
fi

echo "Validating config..."
if ! railway ssh -- openclaw config validate; then
  echo "Config failed validation — not restarting. Fix the above before retrying." >&2
  exit 1
fi

echo "Restarting the service so the gateway picks up the new config..."
railway redeploy --yes >/dev/null

echo
echo "Done. Watch it come up with:  railway logs -d"
