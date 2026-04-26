#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Read values from .env ─────────────────────────────────────────────────────
get_env() {
  grep -E "^$1=" .env 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "$2"
}

TELEGRAM_TOKEN=$(get_env TELEGRAM_BOT_TOKEN "")
POSTGRES_PASSWORD=$(get_env POSTGRES_PASSWORD "fitbuddy_local")
POSTGRES_USER=$(get_env POSTGRES_USER "fitbuddy_user")
POSTGRES_DB=$(get_env POSTGRES_DB "fitbuddy")

# ── Validate ──────────────────────────────────────────────────────────────────
if [ -z "$TELEGRAM_TOKEN" ] || [ "$TELEGRAM_TOKEN" = "your_bot_token_here" ]; then
  echo "Error: TELEGRAM_BOT_TOKEN is not set in .env"
  echo ""
  echo "  1. Open Telegram → search @BotFather → send /newbot"
  echo "  2. Copy the token it gives you"
  echo "  3. Paste it into .env:  TELEGRAM_BOT_TOKEN=123456:ABC-xyz..."
  echo "  4. Re-run this script"
  exit 1
fi

if ! docker inspect fitbuddy_n8n > /dev/null 2>&1; then
  echo "Error: fitbuddy_n8n container is not running."
  echo "  Run: docker compose up -d"
  exit 1
fi

echo "Injecting credentials into n8n..."

# ── Write a temp credentials file ────────────────────────────────────────────
TMPFILE="./fitbuddy_creds_tmp.json"
cat > "$TMPFILE" <<CREDJSON
[
  {
    "name": "Telegram Bot",
    "type": "telegramApi",
    "data": {
      "accessToken": "$TELEGRAM_TOKEN"
    }
  },
  {
    "name": "FitBuddy DB",
    "type": "postgres",
    "data": {
      "host": "postgres",
      "port": 5432,
      "database": "$POSTGRES_DB",
      "user": "$POSTGRES_USER",
      "password": "$POSTGRES_PASSWORD",
      "ssl": false,
      "sshTunnel": false
    }
  }
]
CREDJSON

# ── Import via n8n CLI inside the container ───────────────────────────────────
# MSYS_NO_PATHCONV=1 prevents Git Bash on Windows from translating /tmp/... to a Windows path
MSYS_NO_PATHCONV=1 docker cp "$TMPFILE" fitbuddy_n8n:/tmp/fitbuddy_creds.json
MSYS_NO_PATHCONV=1 docker exec fitbuddy_n8n n8n import:credentials --input=/tmp/fitbuddy_creds.json
MSYS_NO_PATHCONV=1 docker exec fitbuddy_n8n rm /tmp/fitbuddy_creds.json
rm -f "$TMPFILE"

echo ""
echo "────────────────────────────────────────────"
echo "  Done! Two credentials are now in n8n:"
echo "    • Telegram Bot"
echo "    • FitBuddy DB"
echo ""
echo "  Next: open http://localhost:5050"
echo "  → Import workflows from workflows/core/"
echo "  → Each Telegram/Postgres node will have"
echo "    these credentials in its dropdown"
echo "────────────────────────────────────────────"
