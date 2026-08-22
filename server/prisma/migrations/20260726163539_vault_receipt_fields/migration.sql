-- AlterTable
ALTER TABLE "oneplandb"."vault_transaction" ADD COLUMN     "fee_micro" BIGINT,
ADD COLUMN     "note" VARCHAR(255),
ADD COLUMN     "rate" VARCHAR(32),
ADD COLUMN     "recipient_name" VARCHAR(255);
