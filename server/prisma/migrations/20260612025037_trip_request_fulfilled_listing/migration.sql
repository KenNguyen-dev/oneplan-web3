-- AlterTable
ALTER TABLE "oneplandb"."trip_request" ADD COLUMN     "fulfilled_by_listing_id" INTEGER;

-- CreateIndex
CREATE INDEX "trip_request_fulfilled_by_listing_id_idx" ON "oneplandb"."trip_request"("fulfilled_by_listing_id");

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_request" ADD CONSTRAINT "trip_request_fulfilled_by_listing_id_fkey" FOREIGN KEY ("fulfilled_by_listing_id") REFERENCES "oneplandb"."marketplace_listing"("id") ON DELETE SET NULL ON UPDATE CASCADE;
