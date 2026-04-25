#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── 1. Create .env if it doesn't exist ───────────────────────────────────────
if [ ! -f .env ]; then
  cp .env.example .env
  # Generate a real encryption key
  GENERATED_KEY=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -d '=/+' | head -c 32)
  sed -i "s/change_me_run_openssl_rand_hex_16/$GENERATED_KEY/" .env
  echo "✓ Created .env with a generated N8N_ENCRYPTION_KEY"
  echo "  Edit .env to add your TELEGRAM_BOT_TOKEN before activating workflows."
else
  echo "✓ .env already exists — skipping creation"
fi

# ── 2. Pull images and start services ────────────────────────────────────────
echo ""
echo "Starting containers..."
docker compose up -d

echo ""
echo "Waiting for n8n to be ready..."
PORT=$(grep -E '^N8N_PORT=' .env | cut -d= -f2 || echo "5050")
PORT="${PORT:-5050}"

for i in $(seq 1 30); do
  if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PORT}/healthz" | grep -q "200"; then
    echo ""
    echo "────────────────────────────────────────"
    echo "  FitBuddy AI is running!"
    echo "  n8n UI → http://localhost:${PORT}"
    echo ""
    echo "  Next steps:"
    echo "  1. Open http://localhost:${PORT} and create your admin account"
    echo "  2. Add TELEGRAM_BOT_TOKEN to .env"
    echo "  3. Import workflows from workflows/core/ and workflows/features/"
    echo "  4. Add Telegram + Postgres credentials in n8n"
    echo "────────────────────────────────────────"
    exit 0
  fi
  sleep 2
done

echo "n8n did not become healthy within 60 s. Check logs:"
echo "  docker compose logs n8n"
exit 1
