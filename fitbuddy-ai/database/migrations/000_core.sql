-- Migration: 000_core
-- Applied once at initial setup.
-- This migration simply references the core schema file.
-- Run: psql -U fitbuddy_user -d fitbuddy -f database/schema.sql

-- This file exists as a placeholder in the migration sequence
-- to preserve the NNN_ naming convention starting from 000.
-- The actual core schema is in database/schema.sql and is applied
-- automatically by docker-compose via the initdb volume mount.

SELECT 'Core schema applied via schema.sql' AS migration_note;
