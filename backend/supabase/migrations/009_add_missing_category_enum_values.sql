-- =============================================================================
-- Migration 009 — Add the missing category_type enum values
--
-- WHY
-- ---
-- The application's CategoryEnum (app/business/categorization/models.py) defines
-- 10 categories, and the offline categorization engine actively classifies
-- transactions into all of them. But the database `category_type` enum only
-- carried the original 5 values (GROCERIES, UTILITIES, ENTERTAINMENT, SAVINGS,
-- UNCATEGORIZED). Any transaction the engine tags as FOOD / HEALTH / TRANSPORT
-- / HOUSING / SHOPPING therefore fails to insert:
--     invalid input value for enum category_type: "HOUSING"
--
-- This aligns the enum with the code. `ADD VALUE IF NOT EXISTS` is idempotent,
-- so listing all 10 is safe even though only 5 are missing.
--
-- Run via the Supabase Dashboard → SQL editor. (PostgreSQL 12+ allows these in
-- a transaction as long as the new values aren't used in the same transaction,
-- which they aren't here.)
-- =============================================================================

ALTER TYPE category_type ADD VALUE IF NOT EXISTS 'FOOD';
ALTER TYPE category_type ADD VALUE IF NOT EXISTS 'GROCERIES';
ALTER TYPE category_type ADD VALUE IF NOT EXISTS 'UTILITIES';
ALTER TYPE category_type ADD VALUE IF NOT EXISTS 'ENTERTAINMENT';
ALTER TYPE category_type ADD VALUE IF NOT EXISTS 'HEALTH';
ALTER TYPE category_type ADD VALUE IF NOT EXISTS 'TRANSPORT';
ALTER TYPE category_type ADD VALUE IF NOT EXISTS 'HOUSING';
ALTER TYPE category_type ADD VALUE IF NOT EXISTS 'SHOPPING';
ALTER TYPE category_type ADD VALUE IF NOT EXISTS 'SAVINGS';
ALTER TYPE category_type ADD VALUE IF NOT EXISTS 'UNCATEGORIZED';
