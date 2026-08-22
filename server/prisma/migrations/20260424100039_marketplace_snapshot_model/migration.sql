-- CreateEnum
CREATE TYPE "oneplandb"."marketplace_listing_status" AS ENUM ('PENDING_REVIEW', 'APPROVED', 'REJECTED');

-- Add status + soft-delete to marketplace_listing.
-- Existing rows are grandfathered as APPROVED so the feed doesn't go dark on deploy;
-- the column default is then flipped to PENDING_REVIEW for future inserts (creation = submission).
ALTER TABLE "oneplandb"."marketplace_listing"
    ADD COLUMN "deleted_at" TIMESTAMPTZ(6),
    ADD COLUMN "status" "oneplandb"."marketplace_listing_status" NOT NULL DEFAULT 'APPROVED';

ALTER TABLE "oneplandb"."marketplace_listing"
    ALTER COLUMN "status" SET DEFAULT 'PENDING_REVIEW';

CREATE INDEX "marketplace_listing_status_idx" ON "oneplandb"."marketplace_listing"("status");

-- marketplace_acquisition: snapshot columns and listing_id cascade change.
-- Columns are added as nullable first, backfilled from the live listing, then
-- the required ones are tightened to NOT NULL.
ALTER TABLE "oneplandb"."marketplace_acquisition"
    DROP CONSTRAINT "marketplace_acquisition_listing_id_fkey";

ALTER TABLE "oneplandb"."marketplace_acquisition"
    ADD COLUMN "snapshot_name"               VARCHAR(255),
    ADD COLUMN "snapshot_description"        VARCHAR(500),
    ADD COLUMN "snapshot_cover_image_url"    VARCHAR(500),
    ADD COLUMN "snapshot_price"              DECIMAL(18,2),
    ADD COLUMN "snapshot_currency"           "oneplandb"."currency_type",
    ADD COLUMN "snapshot_duration_days"      INTEGER,
    ADD COLUMN "snapshot_tags"               "oneplandb"."listing_tag"[] DEFAULT ARRAY[]::"oneplandb"."listing_tag"[],
    ADD COLUMN "snapshot_city_id"            INTEGER,
    ADD COLUMN "snapshot_state_id"           INTEGER,
    ADD COLUMN "snapshot_country_id"         INTEGER,
    ADD COLUMN "snapshot_creator_name"       VARCHAR(100),
    ADD COLUMN "snapshot_creator_avatar_url" VARCHAR(500),
    ALTER COLUMN "listing_id" DROP NOT NULL;

-- Best-effort backfill for any pre-redesign acquisitions. Safe no-op when the
-- table is empty (e.g. after `prisma migrate reset`).
UPDATE "oneplandb"."marketplace_acquisition" a
SET
    "snapshot_name"               = l."name",
    "snapshot_description"        = l."description",
    "snapshot_cover_image_url"    = l."cover_image_url",
    "snapshot_price"              = l."price",
    "snapshot_currency"           = l."currency",
    "snapshot_duration_days"      = l."duration_days",
    "snapshot_tags"               = l."tags",
    "snapshot_city_id"            = l."city_id",
    "snapshot_state_id"           = l."state_id",
    "snapshot_country_id"         = l."country_id",
    "snapshot_creator_name"       = u."display_name",
    "snapshot_creator_avatar_url" = u."avatar_url"
FROM "oneplandb"."marketplace_listing" l
JOIN "oneplandb"."user" u ON u."id" = l."created_by_id"
WHERE a."listing_id" = l."id"
  AND a."snapshot_name" IS NULL;

ALTER TABLE "oneplandb"."marketplace_acquisition"
    ALTER COLUMN "snapshot_name"          SET NOT NULL,
    ALTER COLUMN "snapshot_price"         SET NOT NULL,
    ALTER COLUMN "snapshot_currency"      SET NOT NULL,
    ALTER COLUMN "snapshot_duration_days" SET NOT NULL,
    ALTER COLUMN "snapshot_creator_name"  SET NOT NULL;

ALTER TABLE "oneplandb"."marketplace_acquisition"
    ADD CONSTRAINT "marketplace_acquisition_listing_id_fkey"
    FOREIGN KEY ("listing_id") REFERENCES "oneplandb"."marketplace_listing"("id")
    ON DELETE SET NULL ON UPDATE NO ACTION;

-- Per-acquisition item snapshots.
CREATE TABLE "oneplandb"."acquisition_item" (
    "id"             SERIAL NOT NULL,
    "acquisition_id" INTEGER NOT NULL,
    "day_number"     INTEGER NOT NULL,
    "title"          VARCHAR(255) NOT NULL,
    "description"    VARCHAR(500),
    "location"       VARCHAR(500),
    "start_time"     VARCHAR(5),
    "category"       "oneplandb"."expense_category",
    "image_urls"     TEXT[],
    "sort_order"     INTEGER NOT NULL DEFAULT 0,
    "created_at"     TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "acquisition_item_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "acquisition_item_acquisition_id_idx"
    ON "oneplandb"."acquisition_item"("acquisition_id");
CREATE INDEX "acquisition_item_acquisition_id_day_number_sort_order_idx"
    ON "oneplandb"."acquisition_item"("acquisition_id", "day_number", "sort_order");

ALTER TABLE "oneplandb"."acquisition_item"
    ADD CONSTRAINT "acquisition_item_acquisition_id_fkey"
    FOREIGN KEY ("acquisition_id") REFERENCES "oneplandb"."marketplace_acquisition"("id")
    ON DELETE CASCADE ON UPDATE NO ACTION;

-- Backfill acquisition_item rows from the live trip_plan_market_item for any
-- pre-redesign acquisitions. Safe no-op when the table is empty.
INSERT INTO "oneplandb"."acquisition_item" (
    "acquisition_id", "day_number", "title", "description", "location",
    "start_time", "category", "image_urls", "sort_order"
)
SELECT
    a."id", mi."day_number", mi."title", mi."description", mi."location",
    mi."start_time", mi."category", mi."image_urls", mi."sort_order"
FROM "oneplandb"."marketplace_acquisition" a
JOIN "oneplandb"."trip_plan_market_item" mi ON mi."listing_id" = a."listing_id"
WHERE a."listing_id" IS NOT NULL;
