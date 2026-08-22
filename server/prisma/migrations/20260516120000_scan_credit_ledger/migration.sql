-- DropTable (replaces the old per-extraction quota counter)
DROP TABLE IF EXISTS "oneplandb"."video_extraction_usage";

-- CreateTable
CREATE TABLE "oneplandb"."scan_credit_grant" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "source" VARCHAR(32) NOT NULL,
    "product_id" VARCHAR(255),
    "amount" INTEGER NOT NULL,
    "remaining" INTEGER NOT NULL,
    "granted_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expires_at" TIMESTAMPTZ(6),
    "external_ref" VARCHAR(255),
    "period_key" VARCHAR(64),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "scan_credit_grant_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."scan_credit_consumption" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "grant_id" INTEGER NOT NULL,
    "session_id" TEXT NOT NULL,
    "amount" INTEGER NOT NULL DEFAULT 1,
    "consumed_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "refunded_at" TIMESTAMPTZ(6),

    CONSTRAINT "scan_credit_consumption_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "scan_credit_grant_user_id_granted_at_idx" ON "oneplandb"."scan_credit_grant"("user_id", "granted_at");

-- CreateIndex
CREATE INDEX "scan_credit_grant_user_id_remaining_idx" ON "oneplandb"."scan_credit_grant"("user_id", "remaining");

-- CreateIndex
CREATE UNIQUE INDEX "scan_credit_consumption_session_id_key" ON "oneplandb"."scan_credit_consumption"("session_id");

-- CreateIndex
CREATE INDEX "scan_credit_consumption_user_id_consumed_at_idx" ON "oneplandb"."scan_credit_consumption"("user_id", "consumed_at");

-- AddForeignKey
ALTER TABLE "oneplandb"."scan_credit_grant" ADD CONSTRAINT "scan_credit_grant_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."scan_credit_consumption" ADD CONSTRAINT "scan_credit_consumption_grant_id_fkey" FOREIGN KEY ("grant_id") REFERENCES "oneplandb"."scan_credit_grant"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- Hard safeguard: a grant's remaining can never go negative or exceed amount.
ALTER TABLE "oneplandb"."scan_credit_grant"
  ADD CONSTRAINT "scan_credit_grant_remaining_bounds_check"
  CHECK ("remaining" >= 0 AND "remaining" <= "amount");

-- Dedup via PARTIAL unique indexes. Prisma cannot express partial/predicate
-- unique indexes, and a plain UNIQUE over the nullable (external_ref,
-- period_key) would NOT dedupe purchases because Postgres treats NULL as
-- distinct under the default NULLS DISTINCT semantics.

-- One pro-weekly grant per (user, subscription, period index).
CREATE UNIQUE INDEX "scan_credit_grant_pro_weekly_period_uq"
  ON "oneplandb"."scan_credit_grant"("user_id", "external_ref", "period_key")
  WHERE "period_key" IS NOT NULL;

-- One grant per validated purchase/pay_once transaction id.
CREATE UNIQUE INDEX "scan_credit_grant_purchase_txn_uq"
  ON "oneplandb"."scan_credit_grant"("user_id", "external_ref")
  WHERE "source" IN ('purchase', 'pay_once');

-- At most one signup bonus per user (belt-and-suspenders; it is also created
-- exactly once inside the user-creation transaction).
CREATE UNIQUE INDEX "scan_credit_grant_signup_bonus_uq"
  ON "oneplandb"."scan_credit_grant"("user_id")
  WHERE "source" = 'signup_bonus';
