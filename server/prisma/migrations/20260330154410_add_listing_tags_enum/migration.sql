-- CreateEnum
CREATE TYPE "oneplandb"."listing_tag" AS ENUM ('SOLO', 'FRIENDS', 'COUPLES', 'FAMILY', 'COMPANY');

-- AlterTable: add new tags column
ALTER TABLE "oneplandb"."marketplace_listing" ADD COLUMN "tags" "oneplandb"."listing_tag"[] NOT NULL DEFAULT '{}';

-- Backfill: map old free-text tag to new enum array
UPDATE "oneplandb"."marketplace_listing"
SET "tags" = CASE
  WHEN lower("tag") = 'solo'                        THEN ARRAY['SOLO']::"oneplandb"."listing_tag"[]
  WHEN lower("tag") IN ('friend', 'friends')         THEN ARRAY['FRIENDS']::"oneplandb"."listing_tag"[]
  WHEN lower("tag") IN ('couple', 'couples')         THEN ARRAY['COUPLES']::"oneplandb"."listing_tag"[]
  WHEN lower("tag") = 'family'                       THEN ARRAY['FAMILY']::"oneplandb"."listing_tag"[]
  WHEN lower("tag") = 'company'                      THEN ARRAY['COMPANY']::"oneplandb"."listing_tag"[]
  ELSE                                                    ARRAY['SOLO']::"oneplandb"."listing_tag"[]
END;

-- AlterTable: drop old tag column
ALTER TABLE "oneplandb"."marketplace_listing" DROP COLUMN "tag";
