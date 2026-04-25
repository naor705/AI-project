-- Migration: 002_supplements
-- Feature: supplement_advisor
-- Additive only — no existing tables modified

CREATE TABLE IF NOT EXISTS supplement_recommendations (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID REFERENCES users(id) ON DELETE CASCADE,
  recommended_at        TIMESTAMP DEFAULT now(),
  goal_at_time          TEXT,
  recommendations       JSONB DEFAULT '[]',
  identified_gaps       JSONB DEFAULT '[]',
  raw_ai_response       TEXT
);

CREATE INDEX IF NOT EXISTS idx_supp_recs_user ON supplement_recommendations(user_id, recommended_at DESC);
