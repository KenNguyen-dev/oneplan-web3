/*
  Warnings:

  - The values [PLANE] on the enum `expense_category` will be removed. If these variants are still used in the database, this will fail.

*/
-- AlterEnum
BEGIN;
CREATE TYPE "oneplandb"."expense_category_new" AS ENUM ('FOOD', 'STAY', 'TICKET', 'TRANSPORT', 'OTHER');
ALTER TABLE "oneplandb"."expense" ALTER COLUMN "category" DROP DEFAULT;
ALTER TABLE "oneplandb"."expense" ALTER COLUMN "category" TYPE "oneplandb"."expense_category_new" USING ("category"::text::"oneplandb"."expense_category_new");
ALTER TABLE "oneplandb"."trip_plan_item" ALTER COLUMN "category" TYPE "oneplandb"."expense_category_new" USING ("category"::text::"oneplandb"."expense_category_new");
ALTER TYPE "oneplandb"."expense_category" RENAME TO "expense_category_old";
ALTER TYPE "oneplandb"."expense_category_new" RENAME TO "expense_category";
DROP TYPE "oneplandb"."expense_category_old";
ALTER TABLE "oneplandb"."expense" ALTER COLUMN "category" SET DEFAULT 'OTHER';
COMMIT;
