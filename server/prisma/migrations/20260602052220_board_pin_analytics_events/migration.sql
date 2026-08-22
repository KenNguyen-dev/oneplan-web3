-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "oneplandb"."analytics_event_name" ADD VALUE 'BOARD_OPENED';
ALTER TYPE "oneplandb"."analytics_event_name" ADD VALUE 'PIN_LINK_SUBMITTED';
ALTER TYPE "oneplandb"."analytics_event_name" ADD VALUE 'PIN_EXTRACTION_STARTED';
ALTER TYPE "oneplandb"."analytics_event_name" ADD VALUE 'PIN_EXTRACTION_FINISHED';
ALTER TYPE "oneplandb"."analytics_event_name" ADD VALUE 'PIN_QUOTA_BLOCKED';
ALTER TYPE "oneplandb"."analytics_event_name" ADD VALUE 'PINS_SAVED';
