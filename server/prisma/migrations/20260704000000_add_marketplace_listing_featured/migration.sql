-- Admin-curated featured marketplace listings (Home "Popular plans").
ALTER TABLE "marketplace_listing"
  ADD COLUMN "featured_at" TIMESTAMPTZ(6),
  ADD COLUMN "featured_order" INTEGER;

CREATE INDEX "marketplace_listing_featured_order_idx"
  ON "marketplace_listing"("featured_order");
