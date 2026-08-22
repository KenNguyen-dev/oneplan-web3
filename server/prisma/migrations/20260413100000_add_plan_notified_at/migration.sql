-- AlterTable
ALTER TABLE "oneplandb"."trip_plan_item" ADD COLUMN "notified_at" TIMESTAMPTZ(6);

-- CreateIndex
CREATE INDEX idx_trip_plan_item_notification ON "oneplandb"."trip_plan_item" (plan_date, start_time) WHERE notified_at IS NULL;
