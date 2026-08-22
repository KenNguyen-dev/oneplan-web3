-- CreateEnum
CREATE TYPE "oneplandb"."plan_reminder_delivery_type" AS ENUM ('PUSH', 'LIVE_ACTIVITY');

-- DropForeignKey
ALTER TABLE "oneplandb"."chat_message" DROP CONSTRAINT "chat_message_sender_id_fkey";

-- DropForeignKey
ALTER TABLE "oneplandb"."expense" DROP CONSTRAINT "expense_paid_by_id_fkey";

-- DropForeignKey
ALTER TABLE "oneplandb"."trip_activity" DROP CONSTRAINT "trip_activity_user_id_fkey";

-- AlterTable
ALTER TABLE "oneplandb"."chat_message" ALTER COLUMN "sender_id" DROP NOT NULL;

-- AlterTable
ALTER TABLE "oneplandb"."device_token" ADD COLUMN     "live_activities_enabled" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "live_activity_push_to_start_token" VARCHAR(200),
ADD COLUMN     "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- AlterTable
ALTER TABLE "oneplandb"."expense" ALTER COLUMN "paid_by_id" DROP NOT NULL;

-- AlterTable
ALTER TABLE "oneplandb"."marketplace_listing" ADD COLUMN     "currency" "oneplandb"."currency_type" NOT NULL DEFAULT 'VND';

-- AlterTable
ALTER TABLE "oneplandb"."trip_activity" ALTER COLUMN "user_id" DROP NOT NULL;

-- CreateTable
CREATE TABLE "oneplandb"."plan_reminder_delivery" (
    "id" SERIAL NOT NULL,
    "plan_item_id" INTEGER NOT NULL,
    "device_token_id" INTEGER NOT NULL,
    "delivery_type" "oneplandb"."plan_reminder_delivery_type" NOT NULL,
    "delivered_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "plan_reminder_delivery_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "plan_reminder_delivery_device_token_id_idx" ON "oneplandb"."plan_reminder_delivery"("device_token_id");

-- CreateIndex
CREATE INDEX "plan_reminder_delivery_plan_item_id_idx" ON "oneplandb"."plan_reminder_delivery"("plan_item_id");

-- CreateIndex
CREATE UNIQUE INDEX "plan_reminder_delivery_plan_item_id_device_token_id_key" ON "oneplandb"."plan_reminder_delivery"("plan_item_id", "device_token_id");

-- AddForeignKey
ALTER TABLE "oneplandb"."expense" ADD CONSTRAINT "expense_paid_by_id_fkey" FOREIGN KEY ("paid_by_id") REFERENCES "oneplandb"."user"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_activity" ADD CONSTRAINT "trip_activity_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."chat_message" ADD CONSTRAINT "chat_message_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "oneplandb"."user"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."plan_reminder_delivery" ADD CONSTRAINT "plan_reminder_delivery_device_token_id_fkey" FOREIGN KEY ("device_token_id") REFERENCES "oneplandb"."device_token"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."plan_reminder_delivery" ADD CONSTRAINT "plan_reminder_delivery_plan_item_id_fkey" FOREIGN KEY ("plan_item_id") REFERENCES "oneplandb"."trip_plan_item"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
