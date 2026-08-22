-- AlterEnum
-- New server-emitted analytics events for the Telegram offer-code bot. The
-- values are not referenced within this migration, so adding them alongside
-- the table creation is safe on PostgreSQL 12+.
ALTER TYPE "oneplandb"."analytics_event_name" ADD VALUE 'TELEGRAM_CODE_REQUESTED';
ALTER TYPE "oneplandb"."analytics_event_name" ADD VALUE 'TELEGRAM_CODE_ISSUED';
ALTER TYPE "oneplandb"."analytics_event_name" ADD VALUE 'TELEGRAM_CODE_DENIED';

-- CreateTable
CREATE TABLE "oneplandb"."telegram_offer_code" (
    "id" SERIAL NOT NULL,
    "code" VARCHAR(255) NOT NULL,
    "batch_label" VARCHAR(100),
    "assigned_telegram_user_id" BIGINT,
    "assigned_telegram_username" VARCHAR(64),
    "assigned_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "telegram_offer_code_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."telegram_setting" (
    "key" VARCHAR(64) NOT NULL,
    "value" TEXT NOT NULL,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "telegram_setting_pkey" PRIMARY KEY ("key")
);

-- CreateIndex
CREATE UNIQUE INDEX "telegram_offer_code_code_key" ON "oneplandb"."telegram_offer_code"("code");

-- CreateIndex
CREATE INDEX "telegram_offer_code_assigned_telegram_user_id_idx" ON "oneplandb"."telegram_offer_code"("assigned_telegram_user_id");

-- Partial unique index: one code per Telegram user. Prisma cannot express a
-- WHERE-filtered unique index, so it is added by hand here (mirrors the
-- scan_credit_grant partial indexes). Postgres treats NULLs as distinct, so
-- this only constrains rows that have actually been assigned.
CREATE UNIQUE INDEX "telegram_offer_code_assignee_uq"
  ON "oneplandb"."telegram_offer_code"("assigned_telegram_user_id")
  WHERE "assigned_telegram_user_id" IS NOT NULL;
