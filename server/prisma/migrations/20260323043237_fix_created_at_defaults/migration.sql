-- Backfill NULL created_at values with NOW() before making columns required
UPDATE "oneplandb"."trip" SET "created_at" = NOW() WHERE "created_at" IS NULL;
UPDATE "oneplandb"."trip_activity" SET "created_at" = NOW() WHERE "created_at" IS NULL;
UPDATE "oneplandb"."trip_member" SET "created_at" = NOW() WHERE "created_at" IS NULL;
UPDATE "oneplandb"."trip_photo" SET "created_at" = NOW() WHERE "created_at" IS NULL;
UPDATE "oneplandb"."trip_plan_item" SET "created_at" = NOW() WHERE "created_at" IS NULL;
UPDATE "oneplandb"."trip_plan_item_member" SET "created_at" = NOW() WHERE "created_at" IS NULL;

-- AlterTable
ALTER TABLE "oneplandb"."trip" ALTER COLUMN "created_at" SET NOT NULL,
ALTER COLUMN "created_at" SET DEFAULT CURRENT_TIMESTAMP;

-- AlterTable
ALTER TABLE "oneplandb"."trip_activity" ALTER COLUMN "created_at" SET NOT NULL,
ALTER COLUMN "created_at" SET DEFAULT CURRENT_TIMESTAMP;

-- AlterTable
ALTER TABLE "oneplandb"."trip_member" ALTER COLUMN "created_at" SET NOT NULL,
ALTER COLUMN "created_at" SET DEFAULT CURRENT_TIMESTAMP;

-- AlterTable
ALTER TABLE "oneplandb"."trip_photo" ALTER COLUMN "created_at" SET NOT NULL,
ALTER COLUMN "created_at" SET DEFAULT CURRENT_TIMESTAMP;

-- AlterTable
ALTER TABLE "oneplandb"."trip_plan_item" ALTER COLUMN "created_at" SET NOT NULL,
ALTER COLUMN "created_at" SET DEFAULT CURRENT_TIMESTAMP;

-- AlterTable
ALTER TABLE "oneplandb"."trip_plan_item_member" ALTER COLUMN "created_at" SET NOT NULL,
ALTER COLUMN "created_at" SET DEFAULT CURRENT_TIMESTAMP;
