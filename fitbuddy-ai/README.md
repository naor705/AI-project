# FitBuddy AI

A fully functional, infinitely extensible Telegram-based fitness assistant bot powered by **n8n** and **OpenAI GPT-4o**.

FitBuddy delivers daily personalized nutrition plans, workout recommendations, and AI coaching — all through Telegram. New features can be added without touching any existing code.

---

## Features

| Feature | Command | Status |
|---|---|---|
| Daily Check-in & AI Report | `/checkin` | ✅ Core |
| Weekly Progress Dashboard | `/progress` | ✅ Core |
| Food Photo Analysis | `/analyze` | ✅ Enabled |
| Supplement Advisor | `/supplements` | ✅ Enabled |
| Restaurant Finder | `/restaurants` | ⏸ Disabled |
| Weekly Challenges | `/challenges` | ⏸ Disabled |
| Mindset Coach | `/mindset` | ⏸ Disabled |

---

## Prerequisites

- **Docker** and **Docker Compose** (v2+)
- A **Telegram Bot Token** — create a bot via [@BotFather](https://t.me/BotFather)
- An **OpenAI API key** with GPT-4o access
- A public HTTPS URL for webhooks (use [ngrok](https://ngrok.com) for local development)

---

## Quick Start

### 1. Clone and configure

```bash
git clone <your-repo-url> fitbuddy-ai
cd fitbuddy-ai

cp .env.example .env
# Edit .env with your actual values:
#   TELEGRAM_BOT_TOKEN=...
#   OPENAI_API_KEY=...
#   POSTGRES_PASSWORD=...
#   WEBHOOK_URL=https://your-public-url.com
#   N8N_ENCRYPTION_KEY=<run: openssl rand -hex 16>
```

### 2. Start the stack

```bash
docker-compose up -d
```

This starts PostgreSQL and n8n. The core database schema is applied automatically.

### 3. Set up Telegram webhook

```bash
curl -X POST "https://api.telegram.org/bot<YOUR_TOKEN>/setWebhook" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://your-public-url.com/webhook/fitbuddy-command-router"}'
```

Verify it's active:
```bash
curl "https://api.telegram.org/bot<YOUR_TOKEN>/getWebhookInfo"
```

### 4. Configure n8n credentials

Open n8n at `http://localhost:5678` and create two credentials:

**Telegram:**
- Name: `FitBuddy Telegram Bot`
- Type: Telegram API
- Token: your `TELEGRAM_BOT_TOKEN`

**OpenAI:**
- Name: `FitBuddy OpenAI`
- Type: OpenAI API
- API Key: your `OPENAI_API_KEY`

**PostgreSQL:**
- Name: `FitBuddy DB`
- Type: Postgres
- Host: `postgres`, Port: `5432`
- Database: `fitbuddy`, User/Password from `.env`

### 5. Import workflows

Import in this exact order:

```
workflows/core/01_onboarding.json
workflows/core/02_daily_checkin.json
workflows/core/03_ai_engine.json
workflows/core/04_command_router.json
workflows/core/05_scheduler.json
workflows/core/06_weekly_report.json
workflows/features/food_image_analysis.json
workflows/features/supplement_advisor.json
```

For each workflow: **Settings → Import from file → Activate**.

After import, replace all `REPLACE_WITH_CREDENTIAL_ID` placeholders with your actual n8n credential IDs.

**Your bot is now live.** Message it `/start` in Telegram.

---

## Enabling / Disabling Features

Open `config/feature-registry.json` and set `"enabled": true` or `"enabled": false`:

```json
{
  "id": "restaurant_finder",
  "enabled": true   ← change this line
}
```

That's all. The command router, AI engine, and scheduler all read this file at runtime — no workflow edits needed.

To fully enable a feature, also apply its migration:
```bash
docker exec -i fitbuddy_db psql -U fitbuddy_user -d fitbuddy \
  < database/migrations/003_restaurants.sql
```

---

## Environment Variables Reference

| Variable | Required | Description |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | ✅ | Your Telegram bot token from BotFather |
| `OPENAI_API_KEY` | ✅ | OpenAI API key with GPT-4o access |
| `POSTGRES_DB` | ✅ | Database name (default: `fitbuddy`) |
| `POSTGRES_USER` | ✅ | Database username |
| `POSTGRES_PASSWORD` | ✅ | Database password — use a strong value |
| `N8N_HOST` | ✅ | n8n hostname (default: `localhost`) |
| `N8N_PORT` | ✅ | n8n port (default: `5678`) |
| `N8N_PROTOCOL` | ✅ | `http` or `https` |
| `WEBHOOK_URL` | ✅ | Public HTTPS URL for Telegram webhooks |
| `N8N_ENCRYPTION_KEY` | ✅ | 32-character random string for n8n secrets |
| `GOOGLE_PLACES_API_KEY` | ⏸ | Required for restaurant_finder feature |
| `CLOUDINARY_CLOUD_NAME` | ⏸ | Required for food photo storage (optional) |
| `CLOUDINARY_API_KEY` | ⏸ | Required for Cloudinary integration |
| `CLOUDINARY_API_SECRET` | ⏸ | Required for Cloudinary integration |

---

## Troubleshooting

**1. Bot doesn't respond to /start**
- Check the webhook is set: `curl https://api.telegram.org/bot<TOKEN>/getWebhookInfo`
- Verify the Onboarding workflow (01) is active in n8n
- Check n8n execution logs for errors

**2. "Credential not found" errors in n8n**
- Replace all `REPLACE_WITH_CREDENTIAL_ID` placeholders in imported workflows
- Go to n8n → Credentials, find your credential's ID, paste it in the workflow node

**3. PostgreSQL connection fails**
- Verify `.env` values match your `docker-compose.yml` environment
- Wait for the health check: `docker-compose ps` — postgres should show `(healthy)`

**4. AI responses aren't generating**
- Check OpenAI API key is valid and has GPT-4o access
- Check n8n execution log for the AI Engine workflow (03)
- Verify the OpenAI credential is attached to all nodes in Workflow 03

**5. Reminders not sending**
- Verify Workflow 05 (Scheduler) is active
- Times in `reminder-schedule.json` are in UTC — adjust for your timezone
- Check n8n execution history for the scheduler workflow

**6. Food photo analysis fails**
- Ensure the Telegram bot token is correct (used for getFile API)
- GPT-4o vision requires the image to be accessible; check download step in execution log
- Verify `food_image_analysis` is `"enabled": true` in feature-registry.json

**7. Weekly report shows no charts**
- QuickChart.io is a free public service — check it's reachable from your server
- Chart configs are URL-encoded JSON; check the HTTP Request node for encoding errors

**8. Check-in conversation gets stuck**
- Old conversation state may be stale: `DELETE FROM conversation_state WHERE user_id = '<user_id>'`
- Check `expires_at` — states expire after 24 hours automatically
- Re-trigger with `/checkin`

---

## Project Structure

```
fitbuddy-ai/
├── config/
│   ├── feature-registry.json    ← Master feature on/off switch
│   ├── commands.json            ← All bot commands
│   ├── reminder-schedule.json   ← All reminder times and messages
│   ├── checkin-questions.json   ← Daily check-in questions
│   └── prompts/                 ← AI prompt files (base + feature fragments)
├── database/
│   ├── schema.sql               ← Core tables (never modified after init)
│   └── migrations/              ← Additive per-feature SQL files
├── workflows/
│   ├── core/                    ← 6 core workflows
│   └── features/                ← Feature workflows + developer guide
├── docker-compose.yml
└── .env.example
```

---

## Adding New Features

See `workflows/features/README.md` for the complete developer guide including step-by-step instructions, templates, and a worked example.

The short version: add a migration, add a workflow JSON, add entries to `feature-registry.json` and `commands.json`, import into n8n.
