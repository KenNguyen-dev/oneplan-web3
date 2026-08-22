-- AlterTable
ALTER TABLE "oneplandb"."subscription_notification" ADD COLUMN     "raw_payload" JSONB,
ADD COLUMN     "store" VARCHAR(16) NOT NULL DEFAULT 'APPLE';

-- CreateIndex
CREATE INDEX "subscription_notification_store_outcome_idx" ON "oneplandb"."subscription_notification"("store", "outcome");
