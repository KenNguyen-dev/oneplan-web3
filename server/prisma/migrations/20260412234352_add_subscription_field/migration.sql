/*
  Warnings:

  - A unique constraint covering the columns `[original_transaction_id]` on the table `user` will be added. If there are existing duplicate values, this will fail.

*/
-- CreateEnum
CREATE TYPE "oneplandb"."subscription_status" AS ENUM ('NONE', 'ACTIVE', 'GRACE_PERIOD', 'BILLING_RETRY', 'EXPIRED', 'REVOKED');

-- AlterTable
ALTER TABLE "oneplandb"."user" ADD COLUMN     "auto_renew_enabled" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "grace_period_expires_at" TIMESTAMPTZ(6),
ADD COLUMN     "original_transaction_id" VARCHAR(255),
ADD COLUMN     "subscription_expires_at" TIMESTAMPTZ(6),
ADD COLUMN     "subscription_product_id" VARCHAR(255),
ADD COLUMN     "subscription_status" "oneplandb"."subscription_status" NOT NULL DEFAULT 'NONE';

-- CreateTable
CREATE TABLE "oneplandb"."subscription_transaction" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "transaction_id" VARCHAR(255) NOT NULL,
    "original_transaction_id" VARCHAR(255) NOT NULL,
    "product_id" VARCHAR(255) NOT NULL,
    "purchase_date" TIMESTAMPTZ(6) NOT NULL,
    "expires_date" TIMESTAMPTZ(6),
    "revocation_date" TIMESTAMPTZ(6),
    "notification_type" VARCHAR(100),
    "notification_uuid" VARCHAR(255),
    "signed_date" TIMESTAMPTZ(6),
    "environment" VARCHAR(20),
    "ownership_type" VARCHAR(20),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "subscription_transaction_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "subscription_transaction_transaction_id_key" ON "oneplandb"."subscription_transaction"("transaction_id");

-- CreateIndex
CREATE UNIQUE INDEX "subscription_transaction_notification_uuid_key" ON "oneplandb"."subscription_transaction"("notification_uuid");

-- CreateIndex
CREATE INDEX "subscription_transaction_user_id_idx" ON "oneplandb"."subscription_transaction"("user_id");

-- CreateIndex
CREATE INDEX "subscription_transaction_original_transaction_id_idx" ON "oneplandb"."subscription_transaction"("original_transaction_id");

-- CreateIndex
CREATE UNIQUE INDEX "user_original_transaction_id_key" ON "oneplandb"."user"("original_transaction_id");

-- AddForeignKey
ALTER TABLE "oneplandb"."subscription_transaction" ADD CONSTRAINT "subscription_transaction_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
