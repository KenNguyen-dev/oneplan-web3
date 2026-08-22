-- Widen scan_credit_grant.period_key from VARCHAR(64) to VARCHAR(255) to match
-- external_ref. Google Play purchase tokens (144 chars) written into
-- period_key during the pro-grant reconcile overflowed the old VARCHAR(64),
-- causing P2000 on every pin-extraction start by an Android Pro subscriber.
-- Non-destructive: widening a VARCHAR is a metadata-only change in Postgres
-- and does not rewrite the table or affect the partial unique index on
-- (user_id, external_ref, period_key) WHERE period_key IS NOT NULL.
ALTER TABLE "oneplandb"."scan_credit_grant" ALTER COLUMN "period_key" SET DATA TYPE VARCHAR(255);
