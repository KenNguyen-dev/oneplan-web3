-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "oneplandb"."expense_category" ADD VALUE 'COFFEE';
ALTER TYPE "oneplandb"."expense_category" ADD VALUE 'SPA';
ALTER TYPE "oneplandb"."expense_category" ADD VALUE 'GYM';
ALTER TYPE "oneplandb"."expense_category" ADD VALUE 'NIGHT_CLUB';
ALTER TYPE "oneplandb"."expense_category" ADD VALUE 'GROCERY';
ALTER TYPE "oneplandb"."expense_category" ADD VALUE 'SHOPPING';
ALTER TYPE "oneplandb"."expense_category" ADD VALUE 'CINEMA';
ALTER TYPE "oneplandb"."expense_category" ADD VALUE 'PHARMACY';
ALTER TYPE "oneplandb"."expense_category" ADD VALUE 'PARK';
