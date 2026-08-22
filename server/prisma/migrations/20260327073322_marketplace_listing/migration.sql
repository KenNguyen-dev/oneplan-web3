/*
  Warnings:

  - You are about to drop the column `notes` on the `trip_plan_item` table. All the data in the column will be lost.
  - You are about to drop the column `created_by_id` on the `trip_plan_market_item` table. All the data in the column will be lost.
  - You are about to drop the column `plan_date` on the `trip_plan_market_item` table. All the data in the column will be lost.
  - Added the required column `day_number` to the `trip_plan_market_item` table without a default value. This is not possible if the table is not empty.
  - Added the required column `listing_id` to the `trip_plan_market_item` table without a default value. This is not possible if the table is not empty.

*/
-- DropForeignKey
ALTER TABLE "oneplandb"."trip_plan_market_item" DROP CONSTRAINT "trip_plan_market_item_created_by_id_fkey";

-- DropIndex
DROP INDEX "oneplandb"."trip_plan_market_item_created_by_id_idx";

-- AlterTable
ALTER TABLE "oneplandb"."trip_plan_item" DROP COLUMN "notes";

-- AlterTable
ALTER TABLE "oneplandb"."trip_plan_market_item" DROP COLUMN "created_by_id",
DROP COLUMN "plan_date",
ADD COLUMN     "day_number" INTEGER NOT NULL,
ADD COLUMN     "listing_id" INTEGER NOT NULL;

-- CreateTable
CREATE TABLE "oneplandb"."marketplace_listing" (
    "id" SERIAL NOT NULL,
    "created_by_id" INTEGER NOT NULL,
    "name" VARCHAR(255) NOT NULL,
    "description" VARCHAR(500),
    "cover_image_url" VARCHAR(500),
    "city_id" INTEGER,
    "state_id" INTEGER,
    "country_id" INTEGER,
    "price" DECIMAL(18,2) NOT NULL,
    "duration_days" INTEGER NOT NULL,
    "tag" VARCHAR(50),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "marketplace_listing_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "marketplace_listing_created_by_id_idx" ON "oneplandb"."marketplace_listing"("created_by_id");

-- CreateIndex
CREATE INDEX "marketplace_listing_city_id_idx" ON "oneplandb"."marketplace_listing"("city_id");

-- CreateIndex
CREATE INDEX "marketplace_listing_state_id_idx" ON "oneplandb"."marketplace_listing"("state_id");

-- CreateIndex
CREATE INDEX "marketplace_listing_country_id_idx" ON "oneplandb"."marketplace_listing"("country_id");

-- CreateIndex
CREATE INDEX "trip_plan_market_item_listing_id_idx" ON "oneplandb"."trip_plan_market_item"("listing_id");

-- AddForeignKey
ALTER TABLE "oneplandb"."marketplace_listing" ADD CONSTRAINT "marketplace_listing_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "oneplandb"."user"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."marketplace_listing" ADD CONSTRAINT "marketplace_listing_city_id_fkey" FOREIGN KEY ("city_id") REFERENCES "oneplandb"."city"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."marketplace_listing" ADD CONSTRAINT "marketplace_listing_state_id_fkey" FOREIGN KEY ("state_id") REFERENCES "oneplandb"."state"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."marketplace_listing" ADD CONSTRAINT "marketplace_listing_country_id_fkey" FOREIGN KEY ("country_id") REFERENCES "oneplandb"."country"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_plan_market_item" ADD CONSTRAINT "trip_plan_market_item_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "oneplandb"."marketplace_listing"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
