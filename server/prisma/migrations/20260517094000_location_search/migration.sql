-- Accent- and separator-insensitive location search support.
-- Squashed from: location_search_unaccent + city_name_unaccent_index +
-- location_search_normalize (the intermediate f_unaccent-only index was
-- created then dropped, so it is omitted entirely here).
-- Self-contained so a fresh DB / Prisma shadow DB replays cleanly.

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA "oneplandb";
CREATE EXTENSION IF NOT EXISTS pg_trgm  WITH SCHEMA "oneplandb";

-- unaccent() is STABLE; this IMMUTABLE wrapper (dictionary pinned by name)
-- can be used inside an expression index.
CREATE OR REPLACE FUNCTION "oneplandb".f_unaccent(text)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE PARALLEL SAFE STRICT
  AS $$ SELECT "oneplandb".unaccent('oneplandb.unaccent', $1) $$;

-- Canonical location-name key: unaccent -> lowercase -> strip every
-- non [a-z0-9] char. "Huế"/"Hue", "Hanoi"/"Ha Noi"/"Hà Nội",
-- "Đà Nẵng"/"Da Nang" all collapse to the same value.
CREATE OR REPLACE FUNCTION "oneplandb".normalize_loc(text)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE PARALLEL SAFE STRICT
  AS $$ SELECT regexp_replace(lower("oneplandb".f_unaccent($1)), '[^a-z0-9]+', '', 'g') $$;

-- GIN trigram index on the normalized city name. Powers separator- and
-- diacritic-insensitive substring search with exactness-tier ranking.
-- Operator class schema-qualified so it resolves regardless of search_path.
CREATE INDEX "city_name_norm_trgm_idx"
  ON "oneplandb"."city"
  USING gin ("oneplandb".normalize_loc(name) "oneplandb".gin_trgm_ops);
