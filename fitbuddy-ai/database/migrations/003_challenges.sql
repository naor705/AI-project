-- Migration: 003_challenges
-- Feature: challenge_system
-- Additive only — no existing tables modified

CREATE TABLE IF NOT EXISTS challenges (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title                 TEXT NOT NULL,
  description           TEXT,
  challenge_type        TEXT,
  target_value          DECIMAL,
  target_unit           TEXT,
  week_start            DATE,
  week_end              DATE,
  is_active             BOOLEAN DEFAULT true,
  created_at            TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_challenges (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID REFERENCES users(id) ON DELETE CASCADE,
  challenge_id          UUID REFERENCES challenges(id),
  joined_at             TIMESTAMP DEFAULT now(),
  current_value         DECIMAL DEFAULT 0,
  completed             BOOLEAN DEFAULT false,
  completed_at          TIMESTAMP,
  streak_count          INT DEFAULT 0,
  UNIQUE(user_id, challenge_id)
);

CREATE INDEX IF NOT EXISTS idx_user_challenges_user     ON user_challenges(user_id);
CREATE INDEX IF NOT EXISTS idx_challenges_active        ON challenges(is_active, week_start DESC);
