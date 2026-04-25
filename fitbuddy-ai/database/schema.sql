-- FitBuddy AI — Core Schema
-- FROZEN after initial setup. Never modify this file.
-- All feature additions go in database/migrations/

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─────────────────────────────────────────
-- CORE TABLE: users
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  telegram_id           BIGINT UNIQUE NOT NULL,
  username              TEXT,
  first_name            TEXT,
  age                   INT,
  gender                TEXT CHECK (gender IN ('male','female','other')),
  weight_kg             DECIMAL(5,2),
  height_cm             DECIMAL(5,2),
  activity_level        TEXT CHECK (activity_level IN ('sedentary','light','moderate','active','very_active')),
  goal                  TEXT CHECK (goal IN ('toning','mass','maintenance')),
  daily_calorie_target  INT,
  onboarding_complete   BOOLEAN DEFAULT false,
  onboarding_step       TEXT DEFAULT 'ask_name',
  feature_prefs         JSONB DEFAULT '{}',
  created_at            TIMESTAMP DEFAULT now(),
  updated_at            TIMESTAMP DEFAULT now()
);

-- ─────────────────────────────────────────
-- CORE TABLE: daily_logs
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS daily_logs (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID REFERENCES users(id) ON DELETE CASCADE,
  log_date              DATE NOT NULL,
  calories_consumed     INT DEFAULT 0,
  protein_g             DECIMAL(6,2) DEFAULT 0,
  carbs_g               DECIMAL(6,2) DEFAULT 0,
  fat_g                 DECIMAL(6,2) DEFAULT 0,
  water_ml              INT DEFAULT 0,
  steps                 INT DEFAULT 0,
  workout_done          BOOLEAN DEFAULT false,
  workout_description   TEXT,
  sleep_hours           DECIMAL(4,2),
  energy_level          INT CHECK (energy_level BETWEEN 1 AND 10),
  mood                  TEXT,
  food_description      TEXT,
  notes                 TEXT,
  extra_data            JSONB DEFAULT '{}',
  created_at            TIMESTAMP DEFAULT now(),
  UNIQUE(user_id, log_date)
);

-- ─────────────────────────────────────────
-- CORE TABLE: ai_recommendations
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_recommendations (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID REFERENCES users(id) ON DELETE CASCADE,
  recommendation_date   DATE NOT NULL,
  full_response         TEXT,
  nutrition_plan        TEXT,
  workout_plan          TEXT,
  substitutes           TEXT,
  progress_snapshot     TEXT,
  motivational_message  TEXT,
  feature_sections      JSONB DEFAULT '{}',
  model_used            TEXT DEFAULT 'gpt-4o',
  prompt_version        TEXT,
  created_at            TIMESTAMP DEFAULT now()
);

-- ─────────────────────────────────────────
-- CORE TABLE: conversation_state
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS conversation_state (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID REFERENCES users(id) ON DELETE CASCADE,
  flow_id               TEXT NOT NULL,
  step                  TEXT NOT NULL,
  context               JSONB DEFAULT '{}',
  started_at            TIMESTAMP DEFAULT now(),
  updated_at            TIMESTAMP DEFAULT now(),
  expires_at            TIMESTAMP DEFAULT now() + INTERVAL '24 hours',
  UNIQUE(user_id, flow_id)
);

-- ─────────────────────────────────────────
-- CORE TABLE: feature_events
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS feature_events (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID REFERENCES users(id) ON DELETE CASCADE,
  feature_id            TEXT NOT NULL,
  event_type            TEXT NOT NULL,
  payload               JSONB DEFAULT '{}',
  created_at            TIMESTAMP DEFAULT now()
);

-- ─────────────────────────────────────────
-- CORE TABLE: workflow_errors
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS workflow_errors (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_name         TEXT,
  user_id               UUID,
  telegram_id           BIGINT,
  error_message         TEXT,
  error_stack           TEXT,
  input_data            JSONB,
  created_at            TIMESTAMP DEFAULT now()
);

-- ─────────────────────────────────────────
-- INDEXES
-- ─────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_users_telegram_id       ON users(telegram_id);
CREATE INDEX IF NOT EXISTS idx_daily_logs_user_date    ON daily_logs(user_id, log_date DESC);
CREATE INDEX IF NOT EXISTS idx_ai_recs_user_date       ON ai_recommendations(user_id, recommendation_date DESC);
CREATE INDEX IF NOT EXISTS idx_conv_state_user_flow    ON conversation_state(user_id, flow_id);
CREATE INDEX IF NOT EXISTS idx_feature_events_user     ON feature_events(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_feature_events_type     ON feature_events(feature_id, event_type);
CREATE INDEX IF NOT EXISTS idx_workflow_errors_created ON workflow_errors(created_at DESC);
