# FitBuddy AI — Developer Guide

## Architecture Overview

FitBuddy AI is built around one core idea: **the core never changes, features extend it**.

### Why this architecture?

Traditional bot architectures break down as features grow. You edit the main dispatch loop to add a command. You edit the AI prompt to add a feature. You add triggers to the scheduler. Every change is a risk — breaking existing behavior.

FitBuddy flips this: the core is frozen after initial setup. Features self-register through config files. The core reads those files at runtime.

### The four contracts

Every feature communicates with the core through four contracts:

| Contract | File | What it does |
|---|---|---|
| **Registry** | `config/feature-registry.json` | Declares the feature exists, which workflow runs it, if it's on |
| **Commands** | `config/commands.json` | Maps `/commands` → workflow files |
| **Database** | `database/migrations/NNN_*.sql` | Adds tables/columns without touching core schema |
| **AI Prompt** | `config/prompts/feature-*.txt` | Appends sections to the daily report |

Add entries to all four and your feature is fully wired in.

---

## How the Core Workflows Connect

```
Telegram message
      │
      ▼
04_command_router  ──reads──► commands.json
      │                       feature-registry.json
      │
      ├──► core/01_onboarding.json      (/start)
      ├──► core/02_daily_checkin.json   (/checkin)
      ├──► core/06_weekly_report.json   (/progress)
      └──► features/*.json              (any feature command)
                │
                └──► core/03_ai_engine.json
                           │──reads──► feature-registry.json
                           │──reads──► config/prompts/*.txt
                           └──► Telegram (sends report)

05_scheduler (hourly)
      │──reads──► reminder-schedule.json
      │──reads──► feature-registry.json
      └──► Telegram (sends reminders to all users)
```

---

## Full Walkthrough: Progress Photo Comparison

This section builds a complete new feature from scratch. Follow each step exactly.

### Feature goal

Users can send a weekly progress photo. The bot stores it, and on the 4th+ photo, uses GPT-4o vision to compare the latest with the earliest and generate a progress assessment.

### Step 1: Write the migration

`database/migrations/006_progress_photos.sql`:

```sql
-- Migration: 006_progress_photos
-- Feature: progress_photos
-- Safe to run multiple times

CREATE TABLE IF NOT EXISTS progress_photos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
  photo_date      DATE NOT NULL DEFAULT CURRENT_DATE,
  telegram_file_id TEXT,
  weight_kg       DECIMAL(5,2),
  notes           TEXT,
  photo_number    INT,           -- 1st, 2nd, 3rd... photo
  ai_assessment   TEXT,          -- only populated on comparison
  created_at      TIMESTAMP DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_progress_photos_user
  ON progress_photos(user_id, photo_date DESC);
```

Apply it:
```bash
docker exec -i fitbuddy_db psql -U fitbuddy_user -d fitbuddy \
  < database/migrations/006_progress_photos.sql
```

### Step 2: Register the feature

Add to `config/feature-registry.json` features array:

```json
{
  "id": "progress_photos",
  "name": "Progress Photo Tracker",
  "enabled": true,
  "workflow": "features/progress_photos.json",
  "commands": ["/photo"],
  "prompt_fragment": null,
  "migrations": ["006_progress_photos.sql"],
  "description": "Track visual body composition changes with weekly photos"
}
```

### Step 3: Register the command

Add to `config/commands.json` commands array:

```json
{
  "command": "/photo",
  "description": "Log a weekly progress photo",
  "workflow": "features/progress_photos.json",
  "feature_id": "progress_photos"
}
```

### Step 4: Write the workflow

`workflows/features/progress_photos.json` — key nodes:

**Node 1: Webhook Trigger**
- Type: `n8n-nodes-base.webhook`
- Path: `progress-photos`
- Receives: `{ telegram_id, user_id }` from command router

**Node 2: Get User**
- Query: `SELECT id, telegram_id, first_name FROM users WHERE telegram_id = $1`

**Node 3: Count Existing Photos**
- Query: `SELECT COUNT(*) as count FROM progress_photos WHERE user_id = $1`

**Node 4: Send Request**
- Telegram: `"📸 Send me your progress photo! Include your current weight if you know it (e.g. just type '78kg' with your photo caption)."`

**Node 5: Wait for Photo**
- Wait node, webhook suffix: `progress-photo-{{ $json.telegramId }}`

**Node 6: Extract Photo Data** (Code node)
```javascript
const message = $json.body?.message || {};
const photos = message.photo || [];
if (!photos.length) {
  return [{ json: { noPhoto: true, telegramId: message.from.id } }];
}
// Telegram sends multiple sizes — get the largest
const fileId = photos[photos.length - 1].file_id;
const caption = message.caption || '';
const weightMatch = caption.match(/(\d+\.?\d*)\s*kg/i);
const weightKg = weightMatch ? parseFloat(weightMatch[1]) : null;

return [{ json: {
  fileId,
  weightKg,
  telegramId: message.from.id,
  userId: $('Get User').item.json.id,
  photoCount: parseInt($('Count Existing Photos').item.json.count) + 1
} }];
```

**Node 7: Save Photo** (Postgres)
```sql
INSERT INTO progress_photos (user_id, telegram_file_id, weight_kg, photo_number)
VALUES ($1, $2, $3, $4)
RETURNING id
```

**Node 8: IF — Has 4+ Photos?**
- Check: `photoCount >= 4`

**Node 9: Get First & Latest Photos** (Postgres, only if 4+ photos)
```sql
SELECT telegram_file_id, photo_date, weight_kg, photo_number
FROM progress_photos
WHERE user_id = $1
ORDER BY photo_date ASC
LIMIT 1
```

**Node 10: GPT-4o Vision Comparison** (only if 4+ photos)
- System: "You are a fitness coach analyzing body composition progress photos."
- User: include both images (first + latest)
- Prompt: "Compare these two photos taken [X] weeks apart. Note observable changes in muscle definition, body composition, and overall physical progress. Be specific, honest, and encouraging."

**Node 11: Log Event** (Postgres)
```sql
INSERT INTO feature_events (user_id, feature_id, event_type, payload)
VALUES ($1, 'progress_photos', 'photo_logged', $2::jsonb)
```

**Node 12: Send Confirmation** (Telegram)
- Message includes photo count and AI comparison if available

### Step 5: Import and test

1. Import JSON into n8n
2. Attach credentials to all Telegram, Postgres, and OpenAI nodes
3. Set workflow to Active
4. Test: send `/photo` to your bot

---

## The `conversation_state` Pattern — Deep Dive

This pattern powers all multi-step flows: onboarding, check-in, and any feature that needs to ask users multiple questions.

### Why one table for all flows?

Each flow has a unique `flow_id`. This means:
- A user can be mid-onboarding AND mid-checkin simultaneously (different `flow_id`)
- Features don't need their own state mechanism
- States expire automatically via `expires_at`

### The complete state machine pattern

```javascript
// 1. Initialize state when flow starts
const initQuery = `
  INSERT INTO conversation_state (user_id, flow_id, step, context)
  VALUES ($1, $2, $3, $4::jsonb)
  ON CONFLICT (user_id, flow_id) DO UPDATE
    SET step = EXCLUDED.step,
        context = EXCLUDED.context,
        updated_at = now()
  RETURNING id, step, context
`;

// 2. Read current state at each step
const stateQuery = `
  SELECT step, context FROM conversation_state
  WHERE user_id = $1 AND flow_id = $2
`;

// 3. Update state after each answer
const updateQuery = `
  UPDATE conversation_state
  SET step = $1, context = $2::jsonb, updated_at = now()
  WHERE user_id = $3 AND flow_id = $4
`;

// 4. Clean up when complete
const deleteQuery = `
  DELETE FROM conversation_state WHERE user_id = $1 AND flow_id = $2
`;
```

### Context accumulation pattern

```javascript
// Each step adds to context without overwriting previous data
let context = {};
try {
  context = typeof convState.context === 'string'
    ? JSON.parse(convState.context)
    : (convState.context || {});
} catch(e) {
  context = {};
}

// Add new answer to existing context
context.current_step_answer = userInput;

// Pass accumulated context forward
return [{ json: { context, nextStep: 'next_step_name' } }];
```

### Handling concurrent flows

If a user types a feature command while mid-check-in, both states coexist:

```
conversation_state rows for user:
  flow_id: 'checkin'          step: 'q_3'
  flow_id: 'my_feature_flow'  step: 'step_one'
```

Your feature's Wait node only resumes on its specific webhook path, so there's no cross-contamination.

---

## The `feature_events` Contract — Deep Dive

### Payload conventions

Keep payloads small and queryable. The weekly report and analytics read these.

```javascript
// Good: specific, typed values
{ calories: 450, confidence: 'high', food_count: 3 }

// Good: counts and booleans
{ restaurants_found: 5, used_location: true }

// Avoid: large text blobs (use your feature's own table for those)
{ full_response: '... 2000 characters ...' } // DON'T do this
```

### Using events for cross-feature triggers

Features can react to other features' events. Example: challenge_system reacts to `food_analyzed` events:

```sql
-- In challenge_system workflow: check if food logging challenge is met
SELECT COUNT(*) as count
FROM feature_events
WHERE user_id = $1
  AND feature_id = 'food_image_analysis'
  AND event_type = 'food_analyzed'
  AND created_at >= CURRENT_DATE
```

This is the intended communication mechanism — features talk through the event log, not through direct workflow calls.

---

## Writing Composable AI Prompt Fragments

### The anatomy of a good fragment

A prompt fragment has three parts:
1. **Section header** — emoji + ALLCAPS name (matches what GPT outputs)
2. **Context line** — what data to use (always reference `{goal}` or logged data)
3. **Bullet instructions** — 3-5 specific instructions, not vague goals

```
🧬 RECOVERY OPTIMIZATION
Based on the user's sleep ({sleep_hours}h), energy ({energy_level}/10), and workout data:
- Identify the single biggest recovery gap from today's data
- Recommend one specific recovery technique with timing (e.g., "10 min cold exposure at 6pm")
- Flag if the user is showing overtraining signals based on 7-day trend
- Keep all advice actionable for today or tomorrow — no long-term plans
```

### Available substitution tokens in fragments

These tokens are guaranteed to be substituted before the AI sees the prompt:

| Token | Value |
|---|---|
| `{name}` | User's first name |
| `{goal}` | `toning`, `mass`, or `maintenance` |
| `{energy_level}` | Integer 1-10 |
| `{mood}` | Text from check-in |
| `{daily_calorie_target}` | Integer kcal |

Do NOT use tokens like `{sleep_hours}` or `{protein_g}` in fragments — those are only available in the base analysis template, not in fragments.

### Testing your fragment

1. Set `"enabled": true` for your feature in `feature-registry.json`
2. Set your `prompt_fragment` path in the registry entry
3. Trigger a check-in: `/checkin`
4. Complete the check-in questions
5. Check the daily report — your section should appear after the base sections

If the section is missing:
- Verify the fragment file exists at the path specified in the registry
- Check the AI Engine (Workflow 03) execution log for fragment loading errors
- Ensure GPT-4o didn't skip the section (try making the instruction more explicit)

---

## Migration File Rules

### The complete rule set

**Allowed:**
```sql
CREATE TABLE IF NOT EXISTS ...
CREATE INDEX IF NOT EXISTS ...
ALTER TABLE existing_table ADD COLUMN IF NOT EXISTS col TYPE DEFAULT value;
CREATE EXTENSION IF NOT EXISTS ...
```

**Never use:**
```sql
DROP TABLE           -- can destroy data in production
DROP COLUMN          -- same
ALTER TABLE RENAME   -- breaks existing workflows
ALTER COLUMN TYPE    -- can corrupt data
TRUNCATE             -- destroys all rows
DELETE FROM          -- destroys data
UPDATE               -- changes existing data (use DEFAULT on new columns instead)
```

### The DEFAULT rule

Every column you add must have a DEFAULT value. This ensures existing rows are never invalid:

```sql
-- CORRECT: existing rows get a default value
ALTER TABLE users ADD COLUMN IF NOT EXISTS feature_score INT DEFAULT 0;

-- WRONG: existing rows get NULL, breaking NOT NULL constraints elsewhere
ALTER TABLE users ADD COLUMN IF NOT EXISTS feature_score INT NOT NULL;
```

### Migration idempotency

Every migration must be safe to run twice. Use `IF NOT EXISTS` everywhere. This protects against accidental re-runs.

---

## Testing a New Feature Locally

### 1. Start fresh if needed

```bash
docker-compose down -v   # removes all data
docker-compose up -d     # fresh start, schema re-applied
```

### 2. Apply your migration

```bash
docker exec -i fitbuddy_db psql -U fitbuddy_user -d fitbuddy \
  < database/migrations/006_my_feature.sql
```

### 3. Import workflow

In n8n: Settings (gear icon) → Import Workflow → select your JSON file.

### 4. Attach credentials

For every Telegram, Postgres, and OpenAI node in your workflow: click the node, open the credential dropdown, select the right credential.

### 5. Activate the workflow

Toggle the workflow to **Active** in the top-right of the workflow editor.

### 6. Test the happy path

```bash
# In Telegram, talk to your bot
/mycommand
# Follow the conversation flow
```

### 7. Check the database

```sql
-- Verify your feature table got rows
SELECT * FROM my_feature_table ORDER BY created_at DESC LIMIT 5;

-- Verify events were logged
SELECT * FROM feature_events WHERE feature_id = 'my_feature' ORDER BY created_at DESC LIMIT 5;
```

### 8. Check n8n execution log

In n8n: open your workflow → click **Executions** tab → inspect the last run. Each node shows its input/output data.

---

## Pre-Production Checklist

Before shipping a new feature, verify every item:

**Database:**
- [ ] Migration uses `IF NOT EXISTS` everywhere
- [ ] All new columns have `DEFAULT` values
- [ ] Migration runs cleanly from scratch (test with `docker-compose down -v && up -d`)
- [ ] All new tables have `user_id UUID REFERENCES users(id) ON DELETE CASCADE`
- [ ] Index created on `(user_id, created_at DESC)` for all new tables

**Workflow JSON:**
- [ ] All Postgres queries use `$1, $2` parameterized placeholders
- [ ] No credential values hardcoded (only `REPLACE_WITH_CREDENTIAL_ID` placeholders)
- [ ] Error handling path sends user a Telegram message
- [ ] `feature_events` INSERT on success
- [ ] JSON is valid (run through a JSON validator)

**Config files:**
- [ ] Entry added to `feature-registry.json` with correct paths
- [ ] Command added to `commands.json`
- [ ] `feature_id` in `commands.json` matches `id` in `feature-registry.json`
- [ ] If `prompt_fragment` set: file exists at that path

**Testing:**
- [ ] Happy path works end-to-end
- [ ] Error path tested (e.g., send invalid input)
- [ ] Feature disabled (`"enabled": false`) shows "feature not available" message
- [ ] Weekly report still generates correctly with feature enabled
- [ ] No changes made to any core workflow, core table, or existing config entries
