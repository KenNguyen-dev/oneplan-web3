-- AlterTable
ALTER TABLE "oneplandb"."trip_plan_item" ADD COLUMN     "day_number" INTEGER,
ALTER COLUMN "plan_date" DROP NOT NULL;

-- CreateIndex
CREATE INDEX "trip_plan_item_trip_id_day_number_idx" ON "oneplandb"."trip_plan_item"("trip_id", "day_number");
