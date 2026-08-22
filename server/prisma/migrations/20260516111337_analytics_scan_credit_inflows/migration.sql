-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "oneplandb"."analytics_event_name" ADD VALUE 'SCAN_PACK_PURCHASED';
ALTER TYPE "oneplandb"."analytics_event_name" ADD VALUE 'SCAN_CREDITS_GRANTED';
ALTER TYPE "oneplandb"."analytics_event_name" ADD VALUE 'SCAN_CREDITS_PAYWALL_VIEWED';
