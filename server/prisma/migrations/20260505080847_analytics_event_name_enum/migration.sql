/*
  Warnings:

  - Changed the type of `event_name` on the `analytics_event` table. No cast exists, the column would be dropped and recreated, which cannot be done if there is data, since the column is required.

*/
-- CreateEnum
CREATE TYPE "oneplandb"."analytics_event_name" AS ENUM ('APP_OPEN', 'SIGNUP_COMPLETED', 'LOGIN_METHOD_SELECTED', 'TRIP_CREATED', 'MEMBER_INVITED', 'EXPENSE_ADDED', 'BILL_SCANNED', 'MARKET_OPENED', 'PLAN_VIEWED', 'PLAN_APPLIED', 'SUBSCRIPTION_VIEWED', 'SUBSCRIPTION_STARTED', 'RESTORE_PURCHASE_CLICKED', 'TRIP_PHOTO_UPLOADED');

-- AlterTable
ALTER TABLE "oneplandb"."analytics_event" DROP COLUMN "event_name",
ADD COLUMN     "event_name" "oneplandb"."analytics_event_name" NOT NULL;

-- CreateIndex
CREATE INDEX "analytics_event_event_name_occurred_at_idx" ON "oneplandb"."analytics_event"("event_name", "occurred_at");
