#!/usr/bin/env bash
set -e

echo "Importing workflows into n8n..."

# Import in dependency order — AI Engine must come before workflows that call it
WORKFLOWS=(
  "core/03_ai_engine.json"
  "core/01_onboarding.json"
  "core/02_daily_checkin.json"
  "core/06_weekly_report.json"
  "core/05_scheduler.json"
  "core/04_command_router.json"
)

for wf in "${WORKFLOWS[@]}"; do
  echo -n "  Importing $wf ... "
  MSYS_NO_PATHCONV=1 docker exec fitbuddy_n8n \
    n8n import:workflow --input="/home/node/fitbuddy/workflows/$wf"
  echo "done"
done

echo ""
echo "────────────────────────────────────────"
echo "  All workflows imported!"
echo "  Open http://localhost:5050 to verify"
echo "  they are listed and Active."
echo "────────────────────────────────────────"
