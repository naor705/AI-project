# FitBuddy AI — Migration Guide

## Naming Convention

```
NNN_feature_name.sql
```

- `NNN` — zero-padded sequence number (e.g., `006`, `007`)
- `feature_name` — snake_case name matching the feature ID in `feature-registry.json`

Examples: `006_progress_photos.sql`, `007_leaderboard.sql`

---

## The Golden Rule: Additive Only

Every migration file must use **only** these SQL operations:

```sql
CREATE TABLE IF NOT EXISTS ...
CREATE INDEX IF NOT EXISTS ...
ALTER TABLE existing_table ADD COLUMN IF NOT EXISTS new_col TYPE DEFAULT value;
```

**Never use:**
- `DROP TABLE` / `DROP COLUMN`
- `ALTER TABLE RENAME`
- `ALTER COLUMN TYPE`
- `DELETE FROM` / `TRUNCATE`
- Any statement that modifies existing data or structure

Every migration must be safe to run multiple times (`IF NOT EXISTS` everywhere).

---

## Referencing Core Tables

All feature tables must link back to the core schema via foreign keys:

```sql
-- Always reference users.id for user-scoped data
user_id UUID REFERENCES users(id) ON DELETE CASCADE,

-- Reference daily_logs.id when attaching to a specific day's entry
daily_log_id UUID REFERENCES daily_logs(id),
```

---

## Required Indexes

Every new table that has a `user_id` column must have at minimum:

```sql
CREATE INDEX IF NOT EXISTS idx_mytable_user ON my_table(user_id, created_at DESC);
```

---

## Using `feature_events` as a Cross-Feature Bus

Instead of creating complex cross-table joins, features communicate through the `feature_events` table. Any feature can write events; any feature can read them.

**Writing an event (from an n8n Code node):**
```javascript
// Log that this feature did something meaningful
return [{
  json: {
    query: `INSERT INTO feature_events (user_id, feature_id, event_type, payload)
            VALUES ($1, $2, $3, $4)`,
    params: [userId, 'my_feature', 'action_completed', JSON.stringify({ key: 'value' })]
  }
}];
```

**Standard event types:**
| Event Type | Used By |
|---|---|
| `food_analyzed` | food_image_analysis |
| `supplement_recommended` | supplement_advisor |
| `restaurants_found` | restaurant_finder |
| `challenge_completed` | challenge_system |
| `mindset_session` | mindset_coach |
| `weekly_report_sent` | core |
| `checkin_complete` | core |

The weekly report (Workflow 06) reads the last 7 days of `feature_events` to build the activity summary section. Your events appear automatically.

---

## Using `extra_data JSONB` on Core Tables

The `daily_logs.extra_data` and `ai_recommendations.feature_sections` columns are escape hatches for small amounts of feature data that don't need a dedicated table.

**Use `extra_data` when:**
- The data is small (< 5 fields)
- It is only ever read in context of that specific log entry
- You don't need to query/filter by it

```sql
-- In a Code node: append feature data to today's log without a new table
UPDATE daily_logs
SET extra_data = extra_data || $1::jsonb
WHERE id = $2
```

**Create a new table when:**
- You have more than 5 fields
- You need to query across multiple rows
- You need your own indexes for performance
- The data has its own lifecycle (e.g., supplement history independent of daily logs)

---

## Full Migration Template

```sql
-- Migration: NNN_feature_name
-- Feature: feature_id (must match feature-registry.json)
-- Description: One line explaining what this adds
-- Applied when: feature is enabled in feature-registry.json
-- Safe to run multiple times: YES (IF NOT EXISTS everywhere)

CREATE TABLE IF NOT EXISTS my_feature_table (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
  -- your columns here, ALL with DEFAULT values
  my_column   TEXT DEFAULT '',
  extra_data  JSONB DEFAULT '{}',
  created_at  TIMESTAMP DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_my_feature_table_user
  ON my_feature_table(user_id, created_at DESC);
```

---

## Applying a Migration

```bash
# Apply a single migration
psql -U fitbuddy_user -d fitbuddy -f database/migrations/NNN_feature_name.sql

# Apply all migrations in order
for f in database/migrations/*.sql; do
  echo "Applying $f..."
  psql -U fitbuddy_user -d fitbuddy -f "$f"
done
```

Or via Docker Compose:
```bash
docker exec -i fitbuddy_db psql -U fitbuddy_user -d fitbuddy \
  < database/migrations/006_my_feature.sql
```
