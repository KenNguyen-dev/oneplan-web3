/*
  Warnings:

  - Made the column `created_at` on table `budget` required. This step will fail if there are existing NULL values in that column.
  - Made the column `created_at` on table `budget_payment` required. This step will fail if there are existing NULL values in that column.
  - Made the column `created_at` on table `expense` required. This step will fail if there are existing NULL values in that column.
  - Made the column `created_at` on table `expense_share` required. This step will fail if there are existing NULL values in that column.

*/
-- AlterTable
ALTER TABLE "oneplandb"."budget" ALTER COLUMN "created_at" SET NOT NULL,
ALTER COLUMN "created_at" SET DEFAULT CURRENT_TIMESTAMP;

-- AlterTable
ALTER TABLE "oneplandb"."budget_payment" ALTER COLUMN "created_at" SET NOT NULL,
ALTER COLUMN "created_at" SET DEFAULT CURRENT_TIMESTAMP;

-- AlterTable
ALTER TABLE "oneplandb"."expense" ALTER COLUMN "created_at" SET NOT NULL,
ALTER COLUMN "created_at" SET DEFAULT CURRENT_TIMESTAMP;

-- AlterTable
ALTER TABLE "oneplandb"."expense_share" ALTER COLUMN "created_at" SET NOT NULL,
ALTER COLUMN "created_at" SET DEFAULT CURRENT_TIMESTAMP;
