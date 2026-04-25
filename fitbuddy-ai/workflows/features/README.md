# FitBuddy AI — Feature Workflow Guide

## The Checklist: Adding Any New Feature

Follow these steps **in order** for every new feature.

- [ ] **1.** Create `database/migrations/NNN_featurename.sql` (additive SQL only)
- [ ] **2.** Create `workflows/features/my_feature.json` (copy the template below)
- [ ] **3.** Add a prompt fragment to `config/prompts/feature-myfeature.txt` (if AI is used)
- [ ] **4.** Add one entry to `config/feature-registry.json`
- [ ] **5.** Add command(s) to `config/commands.json`
- [ ] **6.** Add any reminders to `config/reminder-schedule.json` (optional)
- [ ] **7.** Apply the migration: `psql -U fitbuddy_user -d fitbuddy -f database/migrations/NNN_featurename.sql`
- [ ] **8.** Import the workflow JSON into n8n (Settings → Import Workflow)
- [ ] **9.** Set `"active": true` on the workflow in n8n
- [ ] **10.** Test end-to-end with `/mycommand` in Telegram

---

## Minimal Feature Workflow Template

Every feature workflow is a self-contained n8n JSON file. Here's the minimal structure:

```json
{
  "name": "Feature — My Feature Name",
  "nodes": [
    {
      "parameters": {
        "httpMethod": "POST",
        "path": "my-feature",
        "responseMode": "responseNode"
      },
      "id": "node-webhook",
      "name": "Webhook Trigger",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 1,
      "position": [100, 300],
      "webhookId": "fitbuddy-my-feature"
    }
  ],
  "connections": {},
  "active": false,
  "settings": { "executionOrder": "v1" },
  "id": "NNN",
  "meta": { "instanceId": "fitbuddy" }
}
```

Every feature workflow **must**:
1. Start with a **Webhook Trigger** (called by the Command Router)
2. Use `telegram_id` from `$json.body.telegram_id` to identify the user
3. Write at least one row to `feature_events` when it completes
4. Handle errors gracefully — send the user a message if anything goes wrong

---

## The `conversation_state` Pattern

Use this for any multi-step interaction (asking the user 2+ questions in sequence).

### How it works

1. Create a `conversation_state` row when the flow starts
2. Send the first question; use a **Wait** node to pause execution
3. When the user replies, a webhook resumes the workflow
4. Read the state, validate input, advance the step, update the state
5. When the last step is done, delete the state row

### Database contract

```sql
-- All feature flows use the same table with a unique flow_id
INSERT INTO conversation_state (user_id, flow_id, step, context)
VALUES ($1, 'my_feature_flow', 'step_one', '{"accumulated": "data"}'::jsonb)
ON CONFLICT (user_id, flow_id) DO UPDATE
  SET step = EXCLUDED.step,
      context = EXCLUDED.context,
      updated_at = now();

-- Read current state
SELECT step, context FROM conversation_state
WHERE user_id = $1 AND flow_id = 'my_feature_flow';

-- Cleanup when complete
DELETE FROM conversation_state
WHERE user_id = $1 AND flow_id = 'my_feature_flow';
```

### Code node pattern for multi-step flows

```javascript
// In a Code node that processes a user's reply
const convState = $('Get Conv State').item.json;
let context = typeof convState.context === 'string'
  ? JSON.parse(convState.context)
  : (convState.context || {});

const currentStep = convState.step;
const userInput = $json.body?.message?.text?.trim() || '';

// Validate and store input
if (currentStep === 'step_one') {
  if (!userInput) {
    return [{ json: { valid: false, errorMsg: 'Please provide a valid response.' } }];
  }
  context.step_one_answer = userInput;
}

const nextStep = currentStep === 'step_one' ? 'step_two' : 'complete';
const isComplete = nextStep === 'complete';

return [{ json: { valid: true, nextStep, context, isComplete } }];
```

### Wait node configuration

The **Wait** node resumes when your feature's webhook receives a POST. Name your webhooks consistently:

```
fitbuddy-{feature_id}-step-{step_name}
```

Example webhook suffix: `my-feature-answer-{{ $json.telegramId }}`

---

## The `feature_events` Contract

Every feature **must** write to `feature_events` when it completes a meaningful action. This is how the weekly report picks up your feature's activity.

### Required fields

| Field | Type | Rules |
|---|---|---|
| `user_id` | UUID | Must reference `users.id` |
| `feature_id` | TEXT | Must match your feature's `id` in `feature-registry.json` |
| `event_type` | TEXT | Snake_case, descriptive (see conventions below) |
| `payload` | JSONB | Any relevant data for analytics |

### Event type naming conventions

```
{noun}_{past_tense_verb}

Examples:
  food_analyzed
  supplement_recommended
  restaurant_found
  challenge_completed
  photo_compared
  mindset_session_sent
```

### Code node example

```javascript
// Always log an event when your feature delivers value
return [{ json: {
  query: `INSERT INTO feature_events (user_id, feature_id, event_type, payload)
          VALUES ($1, $2, $3, $4::jsonb)`,
  params: [
    userId,
    'my_feature',         // must match feature-registry.json id
    'action_completed',
    JSON.stringify({ key: 'value', count: 5 })
  ]
} }];
```

### Reading events in the weekly report

Workflow 06 automatically reads `feature_events` for all users. Your events appear in the feature activity summary without any changes to the weekly report workflow.

---

## The `extra_data` JSONB Pattern

For small, one-off data points that don't need a full table.

### When to use it

Use `daily_logs.extra_data` or `ai_recommendations.feature_sections` when:
- You have fewer than 5 data fields
- The data is only meaningful in context of that specific log
- You won't need to query or filter by this field

```javascript
// Append small feature data to today's log — no new table needed
const extraUpdate = {
  my_feature_score: 87,
  my_feature_flag: true
};

// In a Postgres node:
// UPDATE daily_logs SET extra_data = extra_data || $1::jsonb
// WHERE user_id = $2 AND log_date = CURRENT_DATE
```

### When to create a new table

Create a migration with a new table when:
- You have 5+ structured fields
- You need to query across multiple rows (e.g., show history)
- You need your own indexes for performance

---

## Prompt Fragment Format

If your feature adds AI content to the daily report, write a fragment file in `config/prompts/`.

### Rules

1. **Start with the section header** — use the same emoji that will appear in the output
2. **Describe exactly what to generate** — be specific, not vague
3. **Use only `{goal}`, `{name}`, `{energy_level}`, `{mood}`** as substitution tokens — these are guaranteed to exist
4. **Keep it under 200 words** — fragments are appended to a large prompt; stay focused
5. **Don't duplicate base prompt content** — the base already covers nutrition, workout, and substitutes

### Good fragment example

```
🧪 LAB RESULT ANALYSIS
Based on the user's goal ({goal}) and this week's energy patterns:
- Identify one biomarker category worth monitoring given their data
- Suggest one simple self-test they can do at home
- Recommend when to consult a professional
```

### Bad fragment example (what NOT to do)

```
Please also analyze the user's nutrition like you did above and give more advice
about their diet and workout because they need help with their goal of {goal}.
Also mention their name {name} and be encouraging.
```

The bad example duplicates base content, is vague, and doesn't define clear sections.

---

## Full Walkthrough: Progress Photo Comparison Feature

This is a worked example showing exactly how to add a new feature.

### Step 1: Migration (`database/migrations/006_progress_photos.sql`)

```sql
CREATE TABLE IF NOT EXISTS progress_photos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
  photo_date      DATE NOT NULL,
  file_id         TEXT,
  weight_kg       DECIMAL(5,2),
  notes           TEXT,
  ai_assessment   TEXT,
  created_at      TIMESTAMP DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_progress_photos_user
  ON progress_photos(user_id, photo_date DESC);
```

### Step 2: Feature Registry (`config/feature-registry.json`)

Add one entry:

```json
{
  "id": "progress_photos",
  "name": "Progress Photo Comparison",
  "enabled": true,
  "workflow": "features/progress_photos.json",
  "commands": ["/photo"],
  "prompt_fragment": null,
  "migrations": ["006_progress_photos.sql"],
  "description": "Track visual progress with weekly photo comparisons"
}
```

### Step 3: Command Registry (`config/commands.json`)

Add one entry:

```json
{
  "command": "/photo",
  "description": "Log a progress photo",
  "workflow": "features/progress_photos.json",
  "feature_id": "progress_photos"
}
```

### Step 4: Workflow (`workflows/features/progress_photos.json`)

1. **Webhook Trigger** — receives `telegram_id` from router
2. **Get User** (Postgres) — fetch user profile
3. **Send Message** (Telegram) — "📸 Send me your progress photo!"
4. **Wait** — webhook resumes on photo message
5. **Code** — extract `file_id` from `message.photo` array
6. **Get File** (HTTP) — Telegram getFile API
7. **Code** — build comparison prompt if previous photo exists
8. **OpenAI** (optional) — GPT-4o vision comparison analysis
9. **Insert** (Postgres) — `progress_photos` table
10. **Insert** (Postgres) — `feature_events`: `photo_logged`
11. **Send** (Telegram) — confirmation + optional AI feedback

### Step 5: Test

```
/photo → sends the command
Bot: "📸 Send me your progress photo!"
[Send photo]
Bot: "✅ Progress photo logged for [date]!"
```

---

## Testing a Feature Locally

1. Start the stack: `docker-compose up -d`
2. Open n8n at `http://localhost:5678`
3. Import your workflow JSON (Settings → Import)
4. Set the workflow to Active
5. Open @BotFather, send your bot a test command
6. Check n8n execution log for errors
7. Verify database rows were created:
   ```sql
   SELECT * FROM feature_events ORDER BY created_at DESC LIMIT 5;
   ```

## Checklist Before Shipping

- [ ] Migration runs cleanly: `psql -f migrations/NNN_*.sql` with no errors
- [ ] Workflow imports without validation errors in n8n
- [ ] All Postgres queries use `$1, $2` placeholders (no string concatenation)
- [ ] Error path sends the user a message (no silent failures)
- [ ] At least one `feature_events` row is written on success
- [ ] `enabled: false` tested — command router shows "feature disabled" message
- [ ] Feature registry entry has correct `id`, `workflow`, `migrations` paths
- [ ] Prompt fragment (if any) tested end-to-end through Workflow 03
