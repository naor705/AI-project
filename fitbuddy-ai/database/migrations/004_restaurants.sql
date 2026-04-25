-- Migration: 004_restaurants
-- Feature: restaurant_finder
-- Additive only — no existing tables modified

CREATE TABLE IF NOT EXISTS restaurant_searches (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID REFERENCES users(id) ON DELETE CASCADE,
  searched_at           TIMESTAMP DEFAULT now(),
  latitude              DECIMAL(9,6),
  longitude             DECIMAL(9,6),
  results               JSONB DEFAULT '[]',
  result_count          INT DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_restaurant_searches_user ON restaurant_searches(user_id, searched_at DESC);
