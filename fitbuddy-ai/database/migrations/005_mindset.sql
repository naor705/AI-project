-- Migration: 005_mindset
-- Feature: mindset_coach
-- Additive only — no existing tables modified

CREATE TABLE IF NOT EXISTS mindset_sessions (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID REFERENCES users(id) ON DELETE CASCADE,
  session_date          DATE NOT NULL,
  mood_at_time          TEXT,
  energy_at_time        INT,
  coaching_response     TEXT,
  habit_suggested       TEXT,
  created_at            TIMESTAMP DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mindset_sessions_user ON mindset_sessions(user_id, session_date DESC);
