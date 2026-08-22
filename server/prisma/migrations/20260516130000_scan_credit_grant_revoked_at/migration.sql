-- Apple-refund clawback marker for scan-credit purchase grants. Nullable,
-- additive (no data migration); also the clawback idempotency guard.
ALTER TABLE "oneplandb"."scan_credit_grant" ADD COLUMN "revoked_at" TIMESTAMPTZ(6);
