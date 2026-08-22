-- AlterTable: add nullable column first so existing rows accept it
ALTER TABLE "oneplandb"."marketplace_listing" ADD COLUMN "public_id" VARCHAR(32);

-- Backfill with 12-char tokens derived from gen_random_uuid() (built-in;
-- no pgcrypto extension required). Loops until every row has a unique
-- value (collisions on 12 chars are astronomically unlikely; the loop
-- is a safety net.)
DO $$
DECLARE
  remaining INT;
BEGIN
  LOOP
    UPDATE "oneplandb"."marketplace_listing"
    SET "public_id" = substr(replace(gen_random_uuid()::text, '-', ''), 1, 12)
    WHERE "public_id" IS NULL;

    -- Resolve any (improbable) duplicates by re-rolling them
    UPDATE "oneplandb"."marketplace_listing" m
    SET "public_id" = NULL
    WHERE EXISTS (
      SELECT 1 FROM "oneplandb"."marketplace_listing" o
      WHERE o."public_id" = m."public_id" AND o."id" <> m."id"
    );

    SELECT COUNT(*) INTO remaining FROM "oneplandb"."marketplace_listing" WHERE "public_id" IS NULL;
    EXIT WHEN remaining = 0;
  END LOOP;
END $$;

-- Enforce non-null and unique
ALTER TABLE "oneplandb"."marketplace_listing" ALTER COLUMN "public_id" SET NOT NULL;
CREATE UNIQUE INDEX "marketplace_listing_public_id_key" ON "oneplandb"."marketplace_listing"("public_id");
