-- AlterTable
ALTER TABLE "oneplandb"."trip" ADD COLUMN     "marketplace_listing_id" INTEGER;

-- CreateTable
CREATE TABLE "oneplandb"."MarketplaceRating" (
    "id" SERIAL NOT NULL,
    "userId" INTEGER NOT NULL,
    "listingId" INTEGER NOT NULL,
    "rating" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MarketplaceRating_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "MarketplaceRating_listingId_idx" ON "oneplandb"."MarketplaceRating"("listingId");

-- CreateIndex
CREATE UNIQUE INDEX "MarketplaceRating_userId_listingId_key" ON "oneplandb"."MarketplaceRating"("userId", "listingId");

-- AddForeignKey
ALTER TABLE "oneplandb"."trip" ADD CONSTRAINT "trip_marketplace_listing_id_fkey" FOREIGN KEY ("marketplace_listing_id") REFERENCES "oneplandb"."marketplace_listing"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "oneplandb"."MarketplaceRating" ADD CONSTRAINT "MarketplaceRating_userId_fkey" FOREIGN KEY ("userId") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "oneplandb"."MarketplaceRating" ADD CONSTRAINT "MarketplaceRating_listingId_fkey" FOREIGN KEY ("listingId") REFERENCES "oneplandb"."marketplace_listing"("id") ON DELETE CASCADE ON UPDATE CASCADE;
