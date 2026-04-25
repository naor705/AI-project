-- Migration: 001_food_analysis
-- Feature: food_image_analysis
-- Applied when feature is enabled
-- Safe to run multiple times (IF NOT EXISTS everywhere)

CREATE TABLE IF NOT EXISTS food_analyses (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID REFERENCES users(id) ON DELETE CASCADE,
  daily_log_id          UUID REFERENCES daily_logs(id),
  analyzed_at           TIMESTAMP DEFAULT now(),
  image_url             TEXT,
  food_items            JSONB DEFAULT '[]',
  estimated_calories    INT,
  estimated_macros      JSONB DEFAULT '{}',
  confidence            TEXT CHECK (confidence IN ('high','medium','low')),
  raw_ai_response       TEXT,
  source                TEXT DEFAULT 'telegram_photo'
);

CREATE INDEX IF NOT EXISTS idx_food_analyses_user ON food_analyses(user_id, analyzed_at DESC);
