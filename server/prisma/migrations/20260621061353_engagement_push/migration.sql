-- CreateEnum
CREATE TYPE "oneplandb"."engagement_locale" AS ENUM ('EN', 'VN');

-- CreateEnum
CREATE TYPE "oneplandb"."engagement_trigger" AS ENUM ('UNFINISHED_PLAN', 'WEATHER', 'DORMANT', 'NEW_PLAN_AVAILABLE');

-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "oneplandb"."analytics_event_name" ADD VALUE 'ENGAGEMENT_PUSH_SENT';
ALTER TYPE "oneplandb"."analytics_event_name" ADD VALUE 'ENGAGEMENT_PUSH_OPENED';

-- AlterTable
ALTER TABLE "oneplandb"."user" ADD COLUMN     "engagement_consented_at" TIMESTAMPTZ(6),
ADD COLUMN     "engagement_push_enabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "locale" "oneplandb"."engagement_locale" NOT NULL DEFAULT 'EN';

-- CreateTable
CREATE TABLE "oneplandb"."engagement_notification" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "trigger" "oneplandb"."engagement_trigger" NOT NULL,
    "trip_id" INTEGER,
    "listing_id" INTEGER,
    "dedupe_key" VARCHAR(160) NOT NULL,
    "title" VARCHAR(200) NOT NULL,
    "body" VARCHAR(400) NOT NULL,
    "locale" "oneplandb"."engagement_locale" NOT NULL,
    "used_llm" BOOLEAN NOT NULL DEFAULT false,
    "sent_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "opened_at" TIMESTAMPTZ(6),

    CONSTRAINT "engagement_notification_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."weather_snapshot" (
    "id" SERIAL NOT NULL,
    "city_id" INTEGER NOT NULL,
    "temp_c" DECIMAL(5,2) NOT NULL,
    "condition" VARCHAR(32) NOT NULL,
    "raw_type" VARCHAR(64),
    "payload" JSONB,
    "fetched_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "source" VARCHAR(64) NOT NULL DEFAULT 'google-weather',

    CONSTRAINT "weather_snapshot_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "engagement_notification_dedupe_key_key" ON "oneplandb"."engagement_notification"("dedupe_key");

-- CreateIndex
CREATE INDEX "engagement_notification_user_id_sent_at_idx" ON "oneplandb"."engagement_notification"("user_id", "sent_at");

-- CreateIndex
CREATE UNIQUE INDEX "weather_snapshot_city_id_key" ON "oneplandb"."weather_snapshot"("city_id");

-- CreateIndex
CREATE INDEX "weather_snapshot_fetched_at_idx" ON "oneplandb"."weather_snapshot"("fetched_at");

-- AddForeignKey
ALTER TABLE "oneplandb"."engagement_notification" ADD CONSTRAINT "engagement_notification_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
