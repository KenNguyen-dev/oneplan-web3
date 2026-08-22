-- AlterTable: fix subscription_transaction column sizes
ALTER TABLE "oneplandb"."subscription_transaction"
  ALTER COLUMN "environment" TYPE VARCHAR(50),
  ALTER COLUMN "ownership_type" TYPE VARCHAR(100);
