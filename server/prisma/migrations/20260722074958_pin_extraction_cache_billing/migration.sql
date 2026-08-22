-- #194: pin-extraction cache hits skipped the credit charge for every user,
-- not just the payer, because the row carried no expiry. Every cache row now
-- gets an explicit TTL; the app logic (PinExtractionService) enforces the
-- per-user billing rule and refreshes this column on every re-extraction.
--
-- Existing rows predate the TTL column and have no per-payer billing history
-- attached to them in the app's new model, so they're backfilled to their
-- creation time + 7 days (matching PIN_EXTRACTION_CACHE_TTL_DAYS' default).
-- Most will already be older than that and therefore immediately expired,
-- which is the safe direction to err in: a stale row forces a real
-- re-extraction (correctly billed) instead of silently staying "free".

-- AlterTable
ALTER TABLE "oneplandb"."pin_extraction_cache" ADD COLUMN     "expires_at" TIMESTAMPTZ(6);

-- Backfill
UPDATE "oneplandb"."pin_extraction_cache" SET "expires_at" = "created_at" + INTERVAL '7 days';

-- Enforce NOT NULL now that every row has a value
ALTER TABLE "oneplandb"."pin_extraction_cache" ALTER COLUMN "expires_at" SET NOT NULL;

-- CreateIndex
CREATE INDEX "pin_extraction_cache_expires_at_idx" ON "oneplandb"."pin_extraction_cache"("expires_at");
